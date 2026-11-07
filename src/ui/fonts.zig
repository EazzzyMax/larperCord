//! Fontes: resolve famílias pelo fontconfig, mapeia cada arquivo uma única
//! vez na memória (compartilhado entre pesos e famílias) e mescla o emoji
//! colorido em todas. Famílias novas podem ser carregadas a qualquer momento
//! (troca de tema), fora do intervalo NewFrame/Render.
const std = @import("std");
const sys = @import("../platform/sys.zig");
const plain_letters = @import("../core/plain_letters.zig");
const font_blocks = @import("font_blocks.zig");
const c = @import("c");

pub const Weight = enum(u3) { regular, medium, semibold, bold, italic };

/// A fonte que vem dentro do ImGui: a última saída quando o sistema não tem fonte nenhuma.
pub const builtin_name = "ProggyForever";
var builtin_family: ?Family = null;
/// Marca a face embutida em `Fonts.faces` (não é um arquivo mapeado).
var builtin_tag: u8 = 0;

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
/// As letras de qualquer outra escrita: que blocos pediram fonte e quais o sistema já respondeu
/// (ver `loadBlocks`). Tamanho fixo, e nada acontece para quem nunca vê uma letra dessas.
var misses: font_blocks.Misses = .{};

fn onGlyphMissing(cp: c_uint) callconv(.c) void {
    // Invisível (o U+FEFF cai na faixa do árabe) não pede fonte nenhuma.
    if (plain_letters.invisible(cp)) return;
    if (groupOf(cp)) |g| {
        if (!tried_once[@intFromEnum(g)]) {
            wanted[@intFromEnum(g)] = true;
            return;
        }
    } else if (blockToSearch(cp)) |b| {
        if (misses.note(b, cp)) return;
    }
    noteMissing(cp);
}

fn noteMissing(cp: u32) void {
    for (missing_buf[0..missing_n]) |m| if (m == cp) return;
    if (missing_n < missing_buf.len) {
        missing_buf[missing_n] = cp;
        missing_n += 1;
    }
}

/// O bloco que uma letra sem fonte pede ao sistema, ou null se ela não pede: emoji vem da
/// fonte de emoji, uso privado não é escrita nenhuma (cada fonte põe ali os ícones dela) e a
/// letra estilizada já virou a comum (ver `onGlyphPlain`).
fn blockToSearch(cp: u32) ?font_blocks.Block {
    if (inRanges(cp, &emoji_ranges) or plain_letters.of(cp) != null) return null;
    return switch (cp) {
        // Metades de par (não chegam sozinhas ao texto) e uso privado.
        0xD800...0xF8FF, 0xF0000...0x10FFFF => null,
        else => font_blocks.of(cp),
    };
}

/// Nenhuma fonte tem esta letra: a estilizada (𝐫𝐞𝐠𝐫𝐚𝐬) vira a comum, em vez de "?".
fn onGlyphPlain(cp: c_uint) callconv(.c) c_uint {
    return plain_letters.of(cp) orelse 0;
}

/// Pede as fontes reserva da escrita de `cp` como o desenho pede quando nenhuma fonte tem a
/// letra (ver `onGlyphMissing`): entram antes do próximo quadro. Para conferir uma face que
/// nenhum texto usou ainda (no Windows, o itálico do Segoe UI não tem árabe e o normal tem:
/// desenhando só no normal, as reservas nunca são procuradas). Escrita já procurada: nada.
pub fn request(cp: u32) void {
    const g = groupOf(cp) orelse return;
    if (!tried_once[@intFromEnum(g)]) wanted[@intFromEnum(g)] = true;
}

/// As letras que continuam sem fonte, para as Configurações dizerem quais escritas são.
pub fn missingLetters() []const u32 {
    return missing_buf[0..missing_n];
}

/// O quadro que acabou pediu fontes: precisa de outro, mesmo sem evento nenhum.
pub fn scriptsWanted() bool {
    return std.mem.indexOfScalar(bool, &wanted, true) != null or misses.anyWanted();
}

/// O bloco do Unicode de uma letra (font_blocks.zig), para o QA perguntar por ele.
pub const blockOf = font_blocks.of;

/// Os grupos de fontes reserva. Cada um só entra quando um texto pede uma letra das faixas dele
/// (ver `onGlyphMissing`): quem nunca vê árabe não carrega a fonte do árabe. As outras escritas
/// não precisam de grupo: o sistema diz a fonte de cada bloco (ver `Fonts.loadBlocks`).
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
        if (inRanges(cp, rangesOf(g))) return g;
    }
    return null;
}

fn inRanges(cp: u32, r: [*]const c.ImWchar) bool {
    var i: usize = 0;
    while (r[i] != 0) : (i += 2) if (cp >= r[i] and cp <= r[i + 1]) return true;
    return false;
}

/// Uma fonte reserva mesclada em todas as faces, só com as letras do grupo dela.
const Reserve = struct { data: []u8, index: c_int, ranges: [*]const c.ImWchar };

/// Uma fonte do sistema para as letras de outras escritas, valendo só nos blocos que pediram
/// fonte a ela (em ordem crescente): o mesmo arquivo atende vários blocos sem abrir outra face.
const Extra = struct { data: []u8, index: c_int, blocks: [extra_blocks_per_file]font_blocks.Block = undefined, n: usize = 0 };
/// Tetos das outras escritas. Cada fonte entra em cada face do atlas (uma face do FreeType por
/// face), e uma conversa com escritas demais não abre fonte sem fim: o que passar disso fica
/// como letra sem fonte. Até 31 blocos separados cabem nas faixas do ImGui (font_blocks.exclude).
const extra_files = 8;
const extra_blocks = 24;
const extra_blocks_per_file = 16;
/// Blocos procurados por vez: com mais, o resto fica para o próximo intervalo entre quadros.
const blocks_per_load = 8;
/// O nome dessas fontes no atlas: é por ele que `larper_font_source_exclude` acha a certa (o
/// mesmo arquivo pode estar lá também como fonte do tema).
const extra_tag = "larper:escrita";
extern fn larper_font_source_exclude(font: *c.ImFont, data: *const anyopaque, font_no: c_int, tag: [*:0]const u8, ranges: [*]const c.ImWchar) void;
const ExtraRanges = [font_blocks.excludeLen(extra_blocks_per_file)]c.ImWchar;

/// As faixas fora dos blocos da fonte, no formato do ImGui (ver font_blocks.exclude).
fn extraRanges(x: *const Extra, out: *ExtraRanges) [*]const c.ImWchar {
    var tmp: [out.len]u32 = undefined;
    for (font_blocks.exclude(x.blocks[0..x.n], &tmp), 0..) |v, i| out[i] = @intCast(v);
    return out;
}

pub const Fonts = struct {
    gpa: std.mem.Allocator,
    atlas: *c.ImFontAtlas,
    families: std.ArrayList(*Family) = .empty,
    /// Famílias que o sistema não tem: sem perguntar de novo a cada quadro (ver `forgetMissing`).
    missing: std.ArrayList([]u8) = .empty,
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
    /// Fontes reserva de qualquer outra escrita (tailandês, devanágari, etíope...), achadas no
    /// sistema bloco a bloco quando um texto pede (ver `loadBlocks`), em todas as famílias.
    extras: [extra_files]Extra = undefined,
    extras_n: usize = 0,
    /// Os blocos que ganharam fonte do sistema.
    blocks_on: std.StaticBitSet(font_blocks.count) = .empty,
    blocks_n: usize = 0,

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
        f.loadBlocks();
        // Como na abertura: o cache de fontes do sistema não precisa ficar na memória.
        if (!sys.windows) c.FcFini();
        for (f.faces.items) |e| for (f.cjk[first_new..f.cjk_n]) |j| f.mergeOne(e.font, j);
        return true;
    }

    /// Letras de outras escritas pediram fonte (ver `onGlyphMissing`): para cada bloco, uma vez
    /// só, o sistema diz que fonte tem a letra, e ela entra em todas as faces só com esse bloco.
    /// Sem fonte no sistema, a letra entra na lista das sem fonte (para as Configurações).
    fn loadBlocks(f: *Fonts) void {
        for (0..blocks_per_load) |_| {
            const w = misses.next() orelse break;
            if (f.blocks_n < extra_blocks) if (f.resolveChar(w.cp)) |m| {
                defer std.heap.c_allocator.free(m.path);
                if (f.addBlock(w.block, m, w.cp)) {
                    // Só o nome do arquivo: o caminho pode ter o nome da pessoa (fontes da pasta dela).
                    std.log.info("fontes: U+{X:0>4} (bloco {X:0>4}-{X:0>4}) vem de {s}", .{ w.cp, font_blocks.first(w.block), font_blocks.last(w.block), std.fs.path.basename(m.path) });
                    continue;
                }
            };
            std.log.info("fontes: U+{X:0>4} (bloco {X:0>4}-{X:0>4}) sem fonte no sistema", .{ w.cp, font_blocks.first(w.block), font_blocks.last(w.block) });
            noteMissing(w.cp);
        }
    }

    /// O bloco `b` passa a vir da fonte `m` em todas as faces. Falso se ela não serve: o FreeType
    /// não acha a letra nela, ela já está inteira no atlas (e mesmo assim faltou), ou passou do teto.
    fn addBlock(f: *Fonts, b: font_blocks.Block, m: Match, cp: u32) bool {
        // Com as fontes no teto, só um arquivo que já é uma delas ainda serve: nem mapeia outro.
        if (f.extras_n == f.extras.len and f.maps.get(m.path) == null) return false;
        const data = f.mapPath(m.path) catch return false;
        if (f.whole(data, m.index) or !fileHas(data, m.index, &.{cp})) return false;
        const x = for (f.extras[0..f.extras_n]) |*x| {
            if (x.data.ptr == data.ptr and x.index == m.index) break x;
        } else blk: {
            if (f.extras_n == f.extras.len) return false;
            f.extras[f.extras_n] = .{ .data = data, .index = m.index };
            f.extras_n += 1;
            break :blk &f.extras[f.extras_n - 1];
        };
        if (x.n == x.blocks.len) return false;
        var at = x.n;
        while (at > 0 and x.blocks[at - 1] > b) : (at -= 1) x.blocks[at] = x.blocks[at - 1];
        x.blocks[at] = b;
        x.n += 1;
        f.blocks_on.set(b);
        f.blocks_n += 1;
        // A primeira vez, a fonte entra; depois, só alarga as faixas em que vale.
        var buf: ExtraRanges = undefined;
        const ranges = extraRanges(x, &buf);
        for (f.faces.items) |e| {
            if (e.data == x.data.ptr and e.index == x.index) continue;
            if (x.n == 1) f.mergeExtra(e.font, x) else larper_font_source_exclude(e.font, x.data.ptr, x.index, extra_tag, ranges);
        }
        return true;
    }

    /// A fonte já está no atlas valendo para tudo (emoji, símbolos, reserva de um grupo).
    fn whole(f: *const Fonts, data: []u8, index: c_int) bool {
        if (f.emoji) |e| if (e.ptr == data.ptr) return true;
        if (f.symbols) |sym| if (sym.data.ptr == data.ptr and sym.index == index) return true;
        for (f.cjk[0..f.cjk_n]) |o| if (o.data.ptr == data.ptr and o.index == index) return true;
        return false;
    }

    /// O arquivo de fonte do sistema que tem a letra `cp`, ou null.
    fn resolveChar(f: *Fonts, cp: u32) ?Match {
        // Navegador: só as fontes que a página traz, sem fontconfig.
        if (sys.web) return null;
        if (!sys.windows) return matchChar(cp);
        return f.windowsFile(font_blocks.windowsFiles(cp), &.{cp});
    }

    /// Já procurou fonte para este bloco (pode não ter achado nenhuma).
    pub fn triedBlock(_: *const Fonts, b: font_blocks.Block) bool {
        return misses.triedBlock(b);
    }

    /// Uma fonte do sistema entrou para este bloco.
    pub fn hasBlock(f: *const Fonts, b: font_blocks.Block) bool {
        return f.blocks_on.isSet(b);
    }

    /// A escrita desta letra ganhou fonte reserva, mesmo que falte justo esta letra nela: as
    /// Configurações só citam as escritas que continuam sem fonte nenhuma.
    pub fn scriptHasFont(f: *const Fonts, cp: u32) bool {
        if (groupOf(cp)) |g| return f.hasGroup(g);
        const b = font_blocks.of(cp) orelse return false;
        return f.hasBlock(b);
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
        return f.windowsFile(sc.windows, sc.probes);
    }

    /// O primeiro de `files` (em C:\Windows\Fonts) que existe e tem todas as letras de prova.
    fn windowsFile(f: *Fonts, files: []const []const u8, probes: []const u32) ?Match {
        const windir = if (c.SDL_getenv("WINDIR")) |w| std.mem.span(w) else "C:/Windows";
        var pb: [300]u8 = undefined;
        for (files) |file| {
            const p2 = std.fmt.bufPrintSentinel(&pb, "{s}/Fonts/{s}", .{ windir, file }, 0) catch continue;
            if (!sys.exists(p2.ptr)) continue;
            // Nem toda versão do arquivo traz as letras (as formas ligadas do árabe): confere antes.
            const data = f.mapPath(p2) catch continue;
            if (!fileHas(data, 0, probes)) continue;
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
        for (f.missing.items) |m| if (std.mem.eql(u8, m, name)) return error.FontNotFound;
        const faces = f.loadFaces(name) catch |e| {
            if (f.gpa.dupe(u8, name)) |n| f.missing.append(f.gpa, n) catch f.gpa.free(n) else |_| {}
            return e;
        };
        const fam = try f.gpa.create(Family);
        errdefer f.gpa.destroy(fam);
        fam.* = .{ .name = try f.gpa.dupe(u8, name), .faces = faces };
        errdefer f.gpa.free(fam.name);
        try f.families.append(f.gpa, fam);
        return fam;
    }

    /// Os cinco pesos da família, de onde o sistema disser.
    fn loadFaces(f: *Fonts, name: []const u8) ![5]*c.ImFont {
        const specs = [_]struct { w: c_int, slant: c_int }{
            .{ .w = 80, .slant = 0 }, // regular
            .{ .w = 100, .slant = 0 }, // medium
            .{ .w = 180, .slant = 0 }, // semibold
            .{ .w = 200, .slant = 0 }, // bold
            .{ .w = 80, .slant = 100 }, // itálico
        };
        var faces: [5]*c.ImFont = undefined;
        for (specs, 0..) |s, i| {
            const m = resolve(name, s.w, s.slant) orelse return error.FontNotFound;
            defer std.heap.c_allocator.free(m.path);
            const data = try f.mapPath(m.path);
            faces[i] = try f.faceFor(data, m.index);
        }
        return faces;
    }

    /// Tema novo (ou recarregado): as famílias que faltavam são procuradas de novo (uma
    /// fonte pode ter sido instalada com o app aberto).
    pub fn forgetMissing(f: *Fonts) void {
        for (f.missing.items) |m| f.gpa.free(m);
        f.missing.clearRetainingCapacity();
    }

    /// Nenhuma família do sistema carregou (Windows sem C:\Windows\Fonts, Linux sem fonte
    /// nenhuma no fontconfig): a fonte que vem dentro do ImGui, nos cinco pesos, para o app
    /// abrir assim mesmo. Criada uma vez, fora do intervalo NewFrame/Render (o app pede ao
    /// carregar o tema); o emoji, os símbolos e as reservas que houver entram nela também.
    pub fn builtin(f: *Fonts) *Family {
        if (builtin_family) |*fam| return fam;
        var cfg = f.baseConfig();
        // O ImGui guarda a cópia descomprimida da fonte e cuida dela.
        cfg.FontDataOwnedByAtlas = true;
        const font = c.ImFontAtlas_AddFontDefaultVector(f.atlas, &cfg) orelse @panic("nenhuma fonte, nem a embutida no ImGui");
        f.mergeExtras(font, @ptrCast(&builtin_tag), 0);
        // Na lista das faces: o peso, o encaixe e a densidade das Configurações valem para ela.
        f.faces.append(f.gpa, .{ .data = @ptrCast(&builtin_tag), .index = 0, .font = font }) catch {};
        builtin_family = .{ .name = builtin_name, .faces = @splat(font) };
        return &builtin_family.?;
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
        var cfg = f.baseConfig();
        cfg.FontNo = @intCast(index);
        const font = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, data.ptr, @intCast(data.len), 16, &cfg, null) orelse return error.FontLoad;
        f.mergeExtras(font, data.ptr, index);
        return font;
    }

    /// A configuração da fonte principal de uma face.
    fn baseConfig(f: *const Fonts) c.ImFontConfig {
        var cfg = defaultConfig();
        cfg.PixelSnapH = true;
        // Por padrão, hinting leve: encaixa só na vertical (como o ClearType), sem mudar o desenho
        // da letra. E o traço como a fonte desenhou: multiplicar a cobertura engrossa, mas corta
        // os tons da borda e serrilha. Configurações → Avançado muda os dois.
        cfg.FontLoaderFlags = f.text_hint;
        cfg.RasterizerMultiply = f.text_weight;
        cfg.FontDataOwnedByAtlas = false;
        if (f.emoji != null) cfg.GlyphExcludeRanges = &emoji_ranges;
        return cfg;
    }

    /// O emoji colorido, os símbolos e as reservas por cima da fonte principal (a de
    /// `data`/`index`, ver `mergeScripts`).
    fn mergeExtras(f: *Fonts, font: *c.ImFont, data: [*]u8, index: c_int) void {
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
        f.mergeScripts(font, data, index);
    }

    /// As fontes reserva numa fonte do atlas (a de `data`/`index`). A de outra escrita que for
    /// o mesmo arquivo dela não entra: a fonte já tem tudo dele.
    fn mergeScripts(f: *Fonts, font: *c.ImFont, data: [*]u8, index: c_int) void {
        for (f.cjk[0..f.cjk_n]) |j| f.mergeOne(font, j);
        for (f.extras[0..f.extras_n]) |*x| if (x.data.ptr != data or x.index != index) f.mergeExtra(font, x);
    }

    fn mergeOne(f: *Fonts, font: *c.ImFont, j: Reserve) void {
        var jcfg = f.reserveConfig(font, j.index);
        jcfg.GlyphRanges = j.ranges;
        _ = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, j.data.ptr, @intCast(j.data.len), 16, &jcfg, null);
    }

    /// Uma fonte de outra escrita, valendo só nos blocos dela: as faixas de fora ficam
    /// excluídas (o ImGui guarda uma cópia delas).
    fn mergeExtra(f: *Fonts, font: *c.ImFont, x: *const Extra) void {
        var cfg = f.reserveConfig(font, x.index);
        @memcpy(cfg.Name[0..extra_tag.len], extra_tag);
        var buf: ExtraRanges = undefined;
        cfg.GlyphExcludeRanges = extraRanges(x, &buf);
        _ = c.ImFontAtlas_AddFontFromMemoryTTF(f.atlas, x.data.ptr, @intCast(x.data.len), 16, &cfg, null);
    }

    /// Uma fonte reserva mesclada em `font`: o resto das letras vem da fonte do tema, e estas
    /// saem do mesmo tamanho e com o mesmo traço do texto ao lado (ver `add`).
    fn reserveConfig(f: *const Fonts, font: *c.ImFont, index: c_int) c.ImFontConfig {
        var cfg = defaultConfig();
        cfg.MergeMode = true;
        cfg.DstFont = font;
        cfg.FontNo = @intCast(index);
        cfg.FontDataOwnedByAtlas = false;
        cfg.PixelSnapH = true;
        cfg.FontLoaderFlags = f.text_hint | match_em;
        cfg.RasterizerMultiply = f.text_weight;
        return cfg;
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
/// por exemplo) não carrega a fonte do CJK à toa.
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

/// Fontes do sistema se o fontconfig não encontrar nenhuma. O fontconfig
/// continua sendo a primeira opção, para respeitar as fontes instaladas.
fn resolveMacFallback(name: []const u8, weight: c_int, slant: c_int) ?Match {
    const italic = slant != 0;
    const bold = weight >= 200;
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
    const path: [:0]const u8 = if (std.mem.eql(u8, low, "emoji"))
        "/System/Library/Fonts/Apple Color Emoji.ttc"
    else if (has(low, &.{ "mono", "code", "consol", "courier", "term" }))
        if (italic) "/System/Library/Fonts/SFNSMonoItalic.ttf" else "/System/Library/Fonts/SFNSMono.ttf"
    else if (has(low, &.{ "serif", "georgia", "times", "garamond", "playfair" }) and !has(low, &.{"sans"}))
        if (bold and italic) "/System/Library/Fonts/Supplemental/Times New Roman Bold Italic.ttf" else if (bold) "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf" else if (italic) "/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf" else "/System/Library/Fonts/Supplemental/Times New Roman.ttf"
    else if (italic)
        "/System/Library/Fonts/SFNSItalic.ttf"
    else
        "/System/Library/Fonts/SFNS.ttf";
    if (!sys.exists(path.ptr)) return null;
    return .{ .path = std.heap.c_allocator.dupeSentinel(u8, path, 0) catch return null, .index = 0 };
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

// FreeType (o mesmo do ImGui): no Windows não há fontconfig para dizer se um arquivo tem a letra,
// e nas outras escritas é ele que confirma o que o fontconfig respondeu.
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
    return fcFile(m, sc.probes);
}

/// O arquivo de uma fonte que o fontconfig respondeu, se ela tem todas as letras de prova. Sem
/// fonte para essa escrita, ele responde com outra qualquer: essa não serve.
fn fcFile(m: *c.FcPattern, probes: []const u32) ?Match {
    var chars: ?*c.FcCharSet = null;
    if (c.FcPatternGetCharSet(m, c.FC_CHARSET, 0, &chars) != c.FcResultMatch) return null;
    for (probes) |p| if (c.FcCharSetHasChar(chars, p) == 0) return null;
    var file: [*c]c.FcChar8 = null;
    if (c.FcPatternGetString(m, c.FC_FILE, 0, &file) != c.FcResultMatch) return null;
    var index: c_int = 0;
    _ = c.FcPatternGetInteger(m, c.FC_INDEX, 0, &index);
    const path = std.heap.c_allocator.dupeSentinel(u8, std.mem.span(@as([*:0]const u8, @ptrCast(file))), 0) catch return null;
    return .{ .path = path, .index = index };
}

/// A fonte do sistema que tem a letra `cp` (qualquer escrita, ver `Fonts.loadBlocks`): das que
/// o fontconfig ordena para "sans-serif" com essa letra, a primeira que tem mesmo a letra, com
/// contorno (bitmap não muda de tamanho) e sem cor (as de emoji também trazem letras).
fn matchChar(cp: u32) ?Match {
    const pat = c.FcPatternCreate() orelse return null;
    defer c.FcPatternDestroy(pat);
    _ = c.FcPatternAddString(pat, c.FC_FAMILY, "sans-serif");
    _ = c.FcPatternAddBool(pat, c.FC_SCALABLE, c.FcTrue);
    _ = c.FcPatternAddBool(pat, c.FC_COLOR, c.FcFalse);
    const want = c.FcCharSetCreate() orelse return null;
    defer c.FcCharSetDestroy(want);
    _ = c.FcCharSetAddChar(want, cp);
    _ = c.FcPatternAddCharSet(pat, c.FC_CHARSET, want);
    _ = c.FcConfigSubstitute(null, pat, c.FcMatchPattern);
    c.FcDefaultSubstitute(pat);
    var result: c.FcResult = undefined;
    // Aparadas: só fica na lista quem cobre alguma letra que as anteriores não cobrem.
    const set = c.FcFontSort(null, pat, c.FcTrue, null, &result) orelse return null;
    defer c.FcFontSetDestroy(set);
    if (set.*.nfont <= 0) return null;
    for (set.*.fonts[0..@intCast(set.*.nfont)]) |each| {
        const font = each orelse continue;
        var flag: c.FcBool = c.FcFalse;
        if (c.FcPatternGetBool(font, c.FC_SCALABLE, 0, &flag) == c.FcResultMatch and flag == c.FcFalse) continue;
        if (c.FcPatternGetBool(font, c.FC_COLOR, 0, &flag) == c.FcResultMatch and flag != c.FcFalse) continue;
        if (fcFile(font, &.{cp})) |m| return m;
    }
    return null;
}

fn resolve(name: []const u8, weight: c_int, slant: c_int) ?Match {
    if (sys.web) return resolveWeb(name, weight, slant);
    if (sys.windows) return resolveWindows(name, weight, slant);
    if (resolveFontconfig(name, weight, slant)) |m| return m;
    return if (sys.macos) resolveMacFallback(name, weight, slant) else null;
}

/// Pergunta ao fontconfig qual arquivo atende família + peso + inclinação.
fn resolveFontconfig(name: []const u8, weight: c_int, slant: c_int) ?Match {
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
