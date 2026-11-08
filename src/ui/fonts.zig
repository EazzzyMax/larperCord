//! Fontes: resolve famílias pelo fontconfig, mapeia cada arquivo uma única
//! vez na memória (compartilhado entre pesos e famílias) e mescla o emoji
//! colorido em todas. Famílias novas podem ser carregadas a qualquer momento
//! (troca de tema), fora do intervalo NewFrame/Render.
const std = @import("std");
const sys = @import("../platform/sys.zig");
const plain_letters = @import("../core/plain_letters.zig");
const c = @import("c");

pub const Weight = enum(u3) { regular, medium, semibold, bold, italic };

pub const Family = struct {
    name: []const u8,
    faces: [5]*c.ImFont,

    pub fn get(f: *const Family, w: Weight) *c.ImFont {
        return f.faces[@intFromEnum(w)];
    }
};

const load_color: c_uint = 1 << 8; // ImGuiFreeTypeLoaderFlags_LoadColor
const load_bitmap: c_uint = 1 << 9; // ImGuiFreeTypeLoaderFlags_Bitmap (emoji CBDT)
const light_hinting: c_uint = 1 << 3; // ImGuiFreeTypeLoaderFlags_LightHinting
/// Natural, hastes alinhadas (ForceAutoHint) e encaixe total (ForceAutoHint + MonoHinting).
const hint_modes = [_]c_uint{ light_hinting, 1 << 2, (1 << 2) | (1 << 4) };

extern fn larper_font_style(font: *c.ImFont, multiply: f32, hint_flags: c_uint) void;
const match_em: c_uint = 1 << 10; // ImGuiFreeTypeLoaderFlags_LarperMatchEm

/// O ImGui avisa quando nenhuma fonte tem uma letra (imgui_draw.cpp), enquanto as fontes reserva
/// não entraram. Fontes não entram no meio do quadro: aqui só marca, e `loadWanted` carrega.
extern var larper_glyph_missing: ?*const fn (c_uint) callconv(.c) void;
extern fn larper_font_source_to(font: *c.ImFont, data: *const anyopaque, font_no: c_int, pos: c_int) void;
extern var larper_glyph_plain: ?*const fn (c_uint) callconv(.c) c_uint;
var wanted: [groups]bool = @splat(false);
var tried_once: [groups]bool = @splat(false);
var missing_buf: [32]u32 = undefined;
var missing_n: usize = 0;

fn onGlyphMissing(cp: c_uint) callconv(.c) void {
    // Invisível (o U+FEFF cai na faixa do árabe) não pede fonte nenhuma.
    if (plain_letters.invisible(cp)) return;
    if (groupOf(cp)) |g| if (!tried_once[@intFromEnum(g)]) {
        wanted[@intFromEnum(g)] = true;
        return;
    };
    for (missing_buf[0..missing_n]) |m| if (m == cp) return;
    if (missing_n < missing_buf.len) {
        missing_buf[missing_n] = cp;
        missing_n += 1;
    }
}

/// Nenhuma fonte tem esta letra: a estilizada (𝐫𝐞𝐠𝐫𝐚𝐬) vira a comum, em vez de "?".
fn onGlyphPlain(cp: c_uint) callconv(.c) c_uint {
    return plain_letters.of(cp) orelse 0;
}

/// As letras que continuam sem fonte, para as Configurações dizerem quais escritas são.
pub fn missingLetters() []const u32 {
    return missing_buf[0..missing_n];
}

/// O quadro que acabou pediu fontes: precisa de outro, mesmo sem evento nenhum.
pub fn scriptsWanted() bool {
    return std.mem.indexOfScalar(bool, &wanted, true) != null;
}

/// Os grupos de fontes reserva. Cada um só entra quando um texto pede uma letra das faixas dele
/// (ver `onGlyphMissing`): quem nunca vê árabe não carrega a fonte do árabe.
pub const Group = enum { cjk, arabic, hebrew };
const groups = @typeInfo(Group).@"enum".field_names.len;

fn rangesOf(g: Group) [*]const c.ImWchar {
    return switch (g) {
        .cjk => &cjk_ranges,
        .arabic => &arabic_ranges,
        .hebrew => &hebrew_ranges,
    };
}

pub fn groupOf(cp: u32) ?Group {
    for (0..groups) |gi| {
        const g: Group = @enumFromInt(gi);
        const r = rangesOf(g);
        var i: usize = 0;
        while (r[i] != 0) : (i += 2) if (cp >= r[i] and cp <= r[i + 1]) return g;
    }
    return null;
}

/// Uma fonte reserva mesclada em todas as faces, só com as letras do grupo dela.
const Reserve = struct { data: []u8, index: c_int, ranges: [*]const c.ImWchar };

pub const Fonts = struct {
    gpa: std.mem.Allocator,
    atlas: *c.ImFontAtlas,
    families: std.ArrayList(*Family) = .empty,
    maps: std.StringHashMapUnmanaged([]u8) = .empty,
    faces: std.ArrayList(struct { data: [*]u8, index: c_int, font: *c.ImFont }) = .empty,
    emoji: ?[]u8 = null,
    text_weight: f32 = 1,
    text_mode: u8 = 0,
    text_hint: c_uint = light_hinting,
    /// Fonte reserva para símbolos que a fonte principal não tem (⌁ ▣ ◐ ♪ …).
    symbols: ?struct { data: []u8, index: c_int } = null,
    /// Fontes reserva para as outras escritas (ver `scripts`), mescladas em todas as famílias.
    /// Só entram quando um texto pede uma letra delas (ver `loadWanted`), grupo por grupo:
    /// quem não vê CJK nem árabe não paga por elas. Um arquivo só, se ele cobrir mais de uma.
    cjk: [scripts.len]Reserve = undefined,
    cjk_n: usize = 0,
    /// Já procurou as fontes reserva de cada grupo (pode não ter achado nenhuma).
    tried: [groups]bool = @splat(false),
    /// A escrita do idioma da interface: vence a do sistema (ver `preferLanguage`).
    script_pref: ?usize = null,

    pub fn init(gpa: std.mem.Allocator, atlas: *c.ImFontAtlas) Fonts {
        var f: Fonts = .{ .gpa = gpa, .atlas = atlas };
        larper_glyph_missing = onGlyphMissing;
        larper_glyph_plain = onGlyphPlain;
        if (resolve("emoji", 80, 0)) |m| {
            defer std.heap.c_allocator.free(m.path);
            f.emoji = f.mapPath(m.path) catch null;
        }
        if (resolve("DejaVu Sans", 80, 0)) |m| {
            defer std.heap.c_allocator.free(m.path);
            if (f.mapPath(m.path)) |data| {
                f.symbols = .{ .data = data, .index = m.index };
            } else |_| {}
        }
        return f;
    }

    /// Peso e encaixe do texto em todas as fontes. Fora do intervalo NewFrame/Render.
    pub fn setStyle(f: *Fonts, weight: f32, mode: u8) void {
        f.text_weight = weight;
        f.text_mode = mode;
        f.text_hint = hint_modes[@min(mode, hint_modes.len - 1)];
        for (f.faces.items) |e| larper_font_style(e.font, f.text_weight, f.text_hint);
    }

    /// Pixels por ponto, a cada quadro. O ImGui só atualiza a fonte "atual", e o texto aqui sai
    /// direto com a fonte que pedir: sem isto, tudo seria rasterizado em 100% e esticado.
    pub fn setDensity(f: *Fonts, density: f32) void {
        for (f.faces.items) |e| e.font.*.CurrentRasterizerDensity = density;
    }

    /// Um texto pediu uma letra de outra escrita (ver `onGlyphMissing`): as fontes reserva entram
    /// em tudo o que já está no atlas. Fora do intervalo NewFrame/Render. Verdadeiro se procurou
    /// agora: as medidas feitas com o quadradinho deixam de valer.
    pub fn loadWanted(f: *Fonts) bool {
        if (!scriptsWanted()) return false;
        const first_new = f.cjk_n;
        for (&wanted, 0..) |*w, gi| {
            if (!w.*) continue;
            w.* = false;
            tried_once[gi] = true;
            f.tried[gi] = true;
            const ranges = rangesOf(@enumFromInt(gi));
            for (scriptOrder(f.script_pref)) |i| {
                if (@intFromEnum(scripts[i].group) != gi) continue;
                const m = f.resolveScript(scripts[i]) orelse continue;
                defer std.heap.c_allocator.free(m.path);
                const data = f.mapPath(m.path) catch continue;
                // A mesma dos símbolos (DejaVu Sans): já está inteira em todas as faces.
                if (f.symbols) |sym| if (sym.data.ptr == data.ptr and sym.index == m.index) continue;
                const seen = for (f.cjk[0..f.cjk_n]) |o| {
                    if (o.data.ptr == data.ptr and o.ranges == ranges) break true;
                } else false;
                if (seen or f.cjk_n == f.cjk.len) continue;
                f.cjk[f.cjk_n] = .{ .data = data, .index = m.index, .ranges = ranges };
                f.cjk_n += 1;
            }
        }
        // Como na abertura: o cache de fontes do sistema não precisa ficar na memória.
        if (!sys.windows) c.FcFini();
        for (f.faces.items) |e| for (f.cjk[first_new..f.cjk_n]) |j| f.mergeOne(e.font, j);
        return true;
    }

    /// Já procurou as fontes reserva deste grupo (pode não ter achado nenhuma).
    pub fn triedGroup(f: *const Fonts, g: Group) bool {
        return f.tried[@intFromEnum(g)];
    }

    /// Alguma fonte reserva deste grupo entrou.
    pub fn hasGroup(f: *const Fonts, g: Group) bool {
        for (f.cjk[0..f.cjk_n]) |o| if (o.ranges == rangesOf(g)) return true;
        return false;
    }

    /// O idioma da interface escolhe o desenho: o mesmo ideograma muda de forma entre japonês
    /// e chinês, e um sistema em chinês com o app em japonês quer ver o japonês. Com as reservas
    /// já no atlas (trocou de idioma com o app aberto), a fonte certa passa para a frente.
    pub fn preferLanguage(f: *Fonts, code: []const u8) void {
        const pref: ?usize = for (scripts, 0..) |sc, i| {
            if (sc.group == .cjk and std.mem.startsWith(u8, code, sc.locale)) break i;
        } else null;
        if (pref == f.script_pref) return;
        f.script_pref = pref;
        if (f.triedGroup(.cjk)) if (pref) |i| f.raiseScript(i);
    }

    fn raiseScript(f: *Fonts, i: usize) void {
        const m = f.resolveScript(scripts[i]) orelse return;
        defer std.heap.c_allocator.free(m.path);
        if (!sys.windows) c.FcFini();
        const data = f.mapPath(m.path) catch return;
        const at = for (f.cjk[0..f.cjk_n], 0..) |o, n| {
            if (o.data.ptr == data.ptr and o.index == m.index and o.ranges == rangesOf(.cjk)) break n;
        } else blk: {
            if (f.cjk_n == f.cjk.len) return;
            // Um arquivo com todas as escritas (Noto Sans CJK): é outra face dele.
            f.cjk[f.cjk_n] = .{ .data = data, .index = m.index, .ranges = &cjk_ranges };
            f.cjk_n += 1;
            for (f.faces.items) |e| f.mergeOne(e.font, f.cjk[f.cjk_n - 1]);
            break :blk f.cjk_n - 1;
        };
        if (at == 0) return;
        const raised = f.cjk[at];
        std.mem.copyBackwards(@TypeOf(raised), f.cjk[1 .. at + 1], f.cjk[0..at]);
        f.cjk[0] = raised;
        // Antes das reservas ficam a fonte principal, o emoji e os símbolos (ver `add`).
        const pos: c_int = 1 + @as(c_int, @intFromBool(f.emoji != null)) + @as(c_int, @intFromBool(f.symbols != null));
        for (f.faces.items) |e| larper_font_source_to(e.font, raised.data.ptr, raised.index, pos);
    }

    /// O arquivo de fonte para a escrita `sc`, ou null se o sistema não tem um que sirva.
    fn resolveScript(f: *Fonts, sc: Script) ?Match {
        // Navegador: só as fontes que a página traz (latim); as outras escritas ficam de fora.
        if (sys.web) return null;
        if (!sys.windows) return matchScript(sc, false) orelse matchScript(sc, true);
        const windir = if (c.SDL_getenv("WINDIR")) |w| std.mem.span(w) else "C:/Windows";
        var pb: [300]u8 = undefined;
        for (sc.windows) |file| {
            const p2 = std.fmt.bufPrintSentinel(&pb, "{s}/Fonts/{s}", .{ windir, file }, 0) catch continue;
            if (!sys.exists(p2.ptr)) continue;
            // Nem toda versão do arquivo traz as letras (as formas ligadas do árabe): confere antes.
            const data = f.mapPath(p2) catch continue;
            if (!fileHas(data, 0, sc.probes)) continue;
            return .{ .path = std.heap.c_allocator.dupeSentinel(u8, p2, 0) catch return null, .index = 0 };
        }
        return null;
    }

    /// Família já carregada (não carrega nada: seguro no meio do quadro).
    pub fn find(f: *const Fonts, name: []const u8) ?*Family {
        for (f.families.items) |fam| if (std.mem.eql(u8, fam.name, name)) return fam;
        return null;
    }

    /// Família pelo nome ("Inter", "JetBrains Mono"...). Carrega se preciso.
    pub fn family(f: *Fonts, name: []const u8) !*Family {
        for (f.families.items) |fam| if (std.mem.eql(u8, fam.name, name)) return fam;

        const fam = try f.gpa.create(Family);
        fam.name = try f.gpa.dupe(u8, name);
        const specs = [_]struct { w: c_int, slant: c_int }{
            .{ .w = 80, .slant = 0 }, // regular
            .{ .w = 100, .slant = 0 }, // medium
            .{ .w = 180, .slant = 0 }, // semibold
            .{ .w = 200, .slant = 0 }, // bold
            .{ .w = 80, .slant = 100 }, // itálico
        };
        for (specs, 0..) |s, i| {
            const m = resolve(name, s.w, s.slant) orelse return error.FontNotFound;
            defer std.heap.c_allocator.free(m.path);
            const data = try f.mapPath(m.path);
            fam.faces[i] = try f.faceFor(data, m.index);
        }
        try f.families.append(f.gpa, fam);
        return fam;
    }

    /// O mesmo arquivo pode atender vários pesos e famílias (a família não tem
    /// aquele peso, ou "monospace" é a fonte de outro nome): uma fonte só no atlas.
    fn faceFor(f: *Fonts, data: []u8, index: c_int) !*c.ImFont {
        for (f.faces.items) |e| if (e.data == data.ptr and e.index == index) return e.font;
        const font = try f.add(data, index);
        try f.faces.append(f.gpa, .{ .data = data.ptr, .index = index, .font = font });
        return font;
    }

    fn add(f: *Fonts, data: []u8, index: c_int) !*c.ImFont {
        var cfg = defaultConfig();
        cfg.FontNo = @intCast(index);
        cfg.PixelSnapH = true;
        // Por padrão, hinting leve: encaixa só na vertical (como o ClearType), sem mudar o desenho
        // da letra. E o traço como a fonte desenhou: multiplicar a cobertura engrossa, mas corta
        // os tons da borda e serrilha. Configurações → Avançado muda os dois.
        cfg.FontLoaderFlags = f.text_hint;
        cfg.RasterizerMultiply = f.text_weight;
        cfg.FontDataOwnedByAtlas = false;
        if (f.emoji != null) cfg.GlyphExcludeRanges = &emoji_ranges;
        const font = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, data.ptr, @intCast(data.len), 16, &cfg, null) orelse return error.FontLoad;
        if (f.emoji) |e| {
            var ecfg = defaultConfig();
            ecfg.MergeMode = true;
            ecfg.FontLoaderFlags = load_color | load_bitmap;
            ecfg.FontDataOwnedByAtlas = false;
            _ = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, e.ptr, @intCast(e.len), 16, &ecfg, null);
        }
        if (f.symbols) |sym| {
            var scfg = defaultConfig();
            scfg.MergeMode = true;
            scfg.FontNo = @intCast(sym.index);
            scfg.FontDataOwnedByAtlas = false;
            scfg.FontLoaderFlags = f.text_hint;
            scfg.RasterizerMultiply = f.text_weight;
            _ = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, sym.data.ptr, @intCast(sym.data.len), 16, &scfg, null);
        }
        f.mergeScripts(font);
        return font;
    }

    /// As fontes reserva numa fonte do atlas: o resto das letras vem da fonte do tema, e estas
    /// saem do mesmo tamanho e com o mesmo traço do texto ao lado (ver `add`).
    fn mergeScripts(f: *Fonts, font: *c.ImFont) void {
        for (f.cjk[0..f.cjk_n]) |j| f.mergeOne(font, j);
    }

    fn mergeOne(f: *Fonts, font: *c.ImFont, j: Reserve) void {
        var jcfg = defaultConfig();
        jcfg.MergeMode = true;
        jcfg.DstFont = font;
        jcfg.FontNo = @intCast(j.index);
        jcfg.FontDataOwnedByAtlas = false;
        jcfg.GlyphRanges = j.ranges;
        jcfg.PixelSnapH = true;
        jcfg.FontLoaderFlags = f.text_hint | match_em;
        jcfg.RasterizerMultiply = f.text_weight;
        _ = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, j.data.ptr, @intCast(j.data.len), 16, &jcfg, null);
    }

    /// Mapeia o arquivo (somente leitura); só as páginas lidas ficam na RAM.
    fn mapPath(f: *Fonts, path: [:0]const u8) ![]u8 {
        if (f.maps.get(path)) |m| return m;
        const data = sys.mapFile(path.ptr) orelse return error.FontLoad;
        try f.maps.put(f.gpa, try f.gpa.dupe(u8, path), data);
        return data;
    }
};

/// Faixas que o emoji colorido deve fornecer mesmo que a fonte do texto tenha
/// uma versão em preto e branco (❤ ☀ ✨ …).
const emoji_ranges = [_]c.ImWchar{ 0x2600, 0x27BF, 0x2B00, 0x2BFF, 0x1F000, 0x1FAFF, 0 };

/// As letras que trazem as fontes reserva do CJK: quem vê outra letra sem fonte (tailandês,
/// por exemplo) não carrega nada à toa.
const cjk_ranges = [_]c.ImWchar{
    0x1100, 0x11FF, // hangul jamo
    0x2E80, 0x2FDF, // radicais
    0x3000, 0x9FFF, // sinais CJK, hiragana, katakana, bopomofo, hangul compatibilidade, ideogramas
    0xA960, 0xA97F, // hangul jamo estendido
    0xAC00, 0xD7FF, // hangul
    0xF900, 0xFAFF, // ideogramas de compatibilidade
    0xFE30, 0xFE4F, // formas de compatibilidade
    0xFF00, 0xFFEF, // meia-largura e largura cheia
    0x20000, 0x3FFFF, // ideogramas, extensões
    0,
};

/// Árabe: as letras e as formas de apresentação, que é o que o texto moldado desenha (ui/bidi.zig).
const arabic_ranges = [_]c.ImWchar{
    0x0600, 0x06FF, // árabe
    0x0750, 0x077F, // suplemento
    0x08A0, 0x08FF, // estendido A
    0xFB50, 0xFDFF, // formas de apresentação A
    0xFE70, 0xFEFF, // formas de apresentação B
    0,
};

const hebrew_ranges = [_]c.ImWchar{
    0x0590, 0x05FF, // hebraico
    0xFB1D, 0xFB4F, // formas de apresentação
    0,
};

fn defaultConfig() c.ImFontConfig {
    var cfg = std.mem.zeroes(c.ImFontConfig);
    cfg.FontDataOwnedByAtlas = true;
    cfg.ExtraSizeScale = 1.0;
    cfg.GlyphMaxAdvanceX = std.math.floatMax(f32);
    cfg.RasterizerMultiply = 1.0;
    cfg.RasterizerDensity = 1.0;
    return cfg;
}

const Match = struct { path: [:0]u8, index: c_int };

/// Sem fontconfig: procura em C:\\Windows\\Fonts. Primeiro um arquivo com o nome
/// da família; senão a fonte do sistema do mesmo tipo (Segoe UI, Georgia, Consolas).
fn resolveWindows(name: []const u8, weight: c_int, slant: c_int) ?Match {
    const windir = if (c.SDL_getenv("WINDIR")) |w| std.mem.span(w) else "C:/Windows";
    const italic = slant != 0;
    const bold = weight >= 200;
    const semi = weight >= 180 and !bold;
    var lower: [64]u8 = undefined;
    var n: usize = 0;
    for (name) |ch| {
        if (ch == ' ' or n == lower.len) continue;
        lower[n] = std.ascii.toLower(ch);
        n += 1;
    }
    const low = lower[0..n];
    const has = struct {
        fn f(s: []const u8, words: []const []const u8) bool {
            for (words) |w| if (std.mem.indexOf(u8, s, w) != null) return true;
            return false;
        }
    }.f;
    const emoji: []const []const u8 = &.{ "seguiemj", "seguisym" };
    const symbols: []const []const u8 = &.{ "seguisym", "arial" };
    const mono: []const []const u8 = if (bold) &.{ "consolab", "courbd" } else if (italic) &.{ "consolai", "couri" } else &.{ "consola", "cour" };
    const serif: []const []const u8 = if (bold) &.{ "georgiab", "timesbd" } else if (italic) &.{ "georgiai", "timesi" } else &.{ "georgia", "times" };
    const sans: []const []const u8 = if (bold) &.{ "segoeuib", "arialbd", "tahomabd", "tahoma" } else if (semi) &.{ "seguisb", "segoeuib", "arialbd", "tahoma" } else if (italic) &.{ "segoeuii", "ariali", "tahoma" } else &.{ "segoeui", "arial", "tahoma" };
    const family = if (std.mem.eql(u8, low, "emoji")) emoji else if (has(low, &.{"dejavusans"})) symbols else if (has(low, &.{ "mono", "code", "consol", "courier", "term" })) mono else if (has(low, &.{ "serif", "georgia", "times", "garamond", "playfair" }) and !has(low, &.{"sans"})) serif else sans;
    var pb: [300]u8 = undefined;
    const exact = std.fmt.bufPrintSentinel(&pb, "{s}/Fonts/{s}.ttf", .{ windir, low }, 0) catch return null;
    if (sys.exists(exact.ptr)) return .{ .path = std.heap.c_allocator.dupeSentinel(u8, exact, 0) catch return null, .index = 0 };
    for (family) |file| {
        const p = std.fmt.bufPrintSentinel(&pb, "{s}/Fonts/{s}.ttf", .{ windir, file }, 0) catch continue;
        if (sys.exists(p.ptr)) return .{ .path = std.heap.c_allocator.dupeSentinel(u8, p, 0) catch return null, .index = 0 };
    }
    return null;
}

/// Navegador: as poucas fontes que a página traz (tools/web/fonts.py), na pasta que a
/// raiz diz (src/web_main.zig). Toda família vira a do texto ou a monoespaçada, no peso
/// mais perto que existir; emoji e símbolos só se a pasta tiver.
fn resolveWeb(name: []const u8, weight: c_int, slant: c_int) ?Match {
    var lower: [64]u8 = undefined;
    const low = std.ascii.lowerString(lower[0..@min(name.len, lower.len)], name[0..@min(name.len, lower.len)]);
    const has = struct {
        fn f(s: []const u8, words: []const []const u8) bool {
            for (words) |w| if (std.mem.indexOf(u8, s, w) != null) return true;
            return false;
        }
    }.f;
    const files: []const []const u8 = if (std.mem.eql(u8, low, "emoji"))
        &.{"emoji.ttf"}
    else if (has(low, &.{"dejavu"}))
        &.{"symbols.ttf"}
    else if (has(low, &.{ "mono", "code", "consol", "courier", "term" }))
        (if (weight >= 180) &.{ "mono-bold.ttf", "mono.ttf" } else &.{"mono.ttf"})
    else if (slant != 0)
        &.{ "ui-italic.ttf", "ui-regular.ttf" }
    else if (weight >= 200)
        &.{ "ui-bold.ttf", "ui-semibold.ttf", "ui-regular.ttf" }
    else if (weight >= 180)
        &.{ "ui-semibold.ttf", "ui-bold.ttf", "ui-regular.ttf" }
    else if (weight >= 100)
        &.{ "ui-medium.ttf", "ui-regular.ttf" }
    else
        &.{"ui-regular.ttf"};
    const dir = @import("root").fonts_dir;
    var pb: [300]u8 = undefined;
    for (files) |file| {
        const p = std.fmt.bufPrintSentinel(&pb, "{s}/{s}", .{ dir, file }, 0) catch continue;
        if (sys.exists(p.ptr)) return .{ .path = std.heap.c_allocator.dupeSentinel(u8, p, 0) catch return null, .index = 0 };
    }
    return null;
}

/// As escritas que as fontes dos temas não cobrem. Uma linha nova basta para somar outra (e,
/// se for de um grupo novo, as faixas dele em `rangesOf`): `probes` são letras que a fonte
/// precisa ter, e `windows`, os arquivos a procurar.
const Script = struct { lang: [*:0]const u8, locale: []const u8, group: Group, probes: []const u32, windows: []const []const u8 };
const scripts = [_]Script{
    .{ .lang = "ja", .locale = "ja", .group = .cjk, .probes = &.{0x3042}, .windows = &.{ "YuGothM.ttc", "YuGothR.ttc", "meiryo.ttc", "msgothic.ttc" } },
    .{ .lang = "ko", .locale = "ko", .group = .cjk, .probes = &.{0xD55C}, .windows = &.{ "malgun.ttf", "gulim.ttc" } },
    .{ .lang = "zh-cn", .locale = "zh", .group = .cjk, .probes = &.{0x4E2D}, .windows = &.{ "msyh.ttc", "simsun.ttc", "simhei.ttf" } },
    // O árabe vai para a tela já moldado: a fonte precisa das formas ligadas (lam inicial e
    // lam-alef), não só das letras soltas.
    .{ .lang = "ar", .locale = "ar", .group = .arabic, .probes = &.{ 0x0627, 0xFEDF, 0xFEFB }, .windows = &.{ "segoeui.ttf", "arial.ttf", "tahoma.ttf", "times.ttf", "cour.ttf" } },
    .{ .lang = "he", .locale = "he", .group = .hebrew, .probes = &.{ 0x05D0, 0x05E9 }, .windows = &.{ "segoeui.ttf", "arial.ttf", "tahoma.ttf", "cour.ttf" } },
};

/// A escrita do idioma da interface vem primeiro; sem ela, a da língua do sistema: o mesmo
/// ideograma muda de forma entre japonês e chinês, e cada um quer ver o seu.
fn scriptOrder(pref: ?usize) [scripts.len]usize {
    var order: [scripts.len]usize = undefined;
    for (&order, 0..) |*o, i| o.* = i;
    if (pref orelse systemScript()) |i| {
        std.mem.swap(usize, &order[0], &order[i]);
        // Quem desceu da frente mantém a ordem da tabela.
        std.mem.sort(usize, order[1..], {}, std.sort.asc(usize));
    }
    return order;
}

fn systemScript() ?usize {
    var count: c_int = 0;
    const list = c.SDL_GetPreferredLocales(&count) orelse return null;
    defer c.SDL_free(@ptrCast(list));
    if (count == 0) return null;
    const loc = list[0] orelse return null;
    const lang = std.mem.span(loc.*.language orelse return null);
    for (scripts, 0..) |sc, i| if (sc.group == .cjk and std.mem.startsWith(u8, lang, sc.locale)) return i;
    return null;
}

// FreeType (o mesmo do ImGui): no Windows não há fontconfig para dizer se um arquivo tem a letra.
extern fn FT_Init_FreeType(lib: *?*anyopaque) c_int;
extern fn FT_Done_FreeType(lib: ?*anyopaque) c_int;
extern fn FT_New_Memory_Face(lib: ?*anyopaque, base: [*]const u8, size: c_long, index: c_long, face: *?*anyopaque) c_int;
extern fn FT_Done_Face(face: ?*anyopaque) c_int;
extern fn FT_Get_Char_Index(face: ?*anyopaque, charcode: c_ulong) c_uint;

/// O arquivo tem todas as letras de prova? Lê só o cabeçalho e a tabela de caracteres.
fn fileHas(data: []const u8, index: c_int, probes: []const u32) bool {
    var lib: ?*anyopaque = null;
    if (FT_Init_FreeType(&lib) != 0) return false;
    defer _ = FT_Done_FreeType(lib);
    var face: ?*anyopaque = null;
    if (FT_New_Memory_Face(lib, data.ptr, @intCast(data.len), index, &face) != 0) return false;
    defer _ = FT_Done_Face(face);
    for (probes) |p| if (FT_Get_Char_Index(face, p) == 0) return false;
    return true;
}

/// O fontconfig responde pelo idioma (o desenho certo do ideograma). Se a fonte que vier não
/// tiver as letras de prova, pergunta de novo, agora pelas letras: um sistema sem fonte própria
/// para árabe ainda pode ter uma que cubra (DejaVu Sans, FreeSerif).
fn matchScript(sc: Script, by_chars: bool) ?Match {
    const pat = c.FcPatternCreate() orelse return null;
    defer c.FcPatternDestroy(pat);
    _ = c.FcPatternAddString(pat, c.FC_LANG, sc.lang);
    _ = c.FcPatternAddString(pat, c.FC_FAMILY, "sans-serif");
    if (by_chars) {
        const want = c.FcCharSetCreate() orelse return null;
        defer c.FcCharSetDestroy(want);
        for (sc.probes) |p| _ = c.FcCharSetAddChar(want, p);
        _ = c.FcPatternAddCharSet(pat, c.FC_CHARSET, want);
    }
    _ = c.FcConfigSubstitute(null, pat, c.FcMatchPattern);
    c.FcDefaultSubstitute(pat);
    var result: c.FcResult = undefined;
    const m = c.FcFontMatch(null, pat, &result) orelse return null;
    defer c.FcPatternDestroy(m);
    // Sem fonte para essa escrita, o fontconfig responde com outra qualquer: essa não serve.
    var chars: ?*c.FcCharSet = null;
    if (c.FcPatternGetCharSet(m, c.FC_CHARSET, 0, &chars) != c.FcResultMatch) return null;
    for (sc.probes) |p| if (c.FcCharSetHasChar(chars, p) == 0) return null;
    var file: [*c]c.FcChar8 = null;
    if (c.FcPatternGetString(m, c.FC_FILE, 0, &file) != c.FcResultMatch) return null;
    var index: c_int = 0;
    _ = c.FcPatternGetInteger(m, c.FC_INDEX, 0, &index);
    const path = std.heap.c_allocator.dupeSentinel(u8, std.mem.span(@as([*:0]const u8, @ptrCast(file))), 0) catch return null;
    return .{ .path = path, .index = index };
}

/// Pergunta ao fontconfig qual arquivo atende família + peso + inclinação.
fn resolve(name: []const u8, weight: c_int, slant: c_int) ?Match {
    if (sys.web) return resolveWeb(name, weight, slant);
    if (sys.windows) return resolveWindows(name, weight, slant);
    var buf: [128]u8 = undefined;
    const zname = std.fmt.bufPrintSentinel(&buf, "{s}", .{name}, 0) catch return null;
    const pat = c.FcPatternCreate() orelse return null;
    defer c.FcPatternDestroy(pat);
    _ = c.FcPatternAddString(pat, c.FC_FAMILY, zname.ptr);
    _ = c.FcPatternAddInteger(pat, c.FC_WEIGHT, weight);
    _ = c.FcPatternAddInteger(pat, c.FC_SLANT, slant);
    if (std.mem.eql(u8, name, "emoji")) _ = c.FcPatternAddBool(pat, c.FC_COLOR, c.FcTrue);
    _ = c.FcConfigSubstitute(null, pat, c.FcMatchPattern);
    c.FcDefaultSubstitute(pat);
    var result: c.FcResult = undefined;
    const m = c.FcFontMatch(null, pat, &result) orelse return null;
    defer c.FcPatternDestroy(m);
    var file: [*c]c.FcChar8 = null;
    if (c.FcPatternGetString(m, c.FC_FILE, 0, &file) != c.FcResultMatch) return null;
    var index: c_int = 0;
    _ = c.FcPatternGetInteger(m, c.FC_INDEX, 0, &index);
    const path = std.heap.c_allocator.dupeSentinel(u8, std.mem.span(@as([*:0]const u8, @ptrCast(file))), 0) catch return null;
    return .{ .path = path, .index = index };
}
