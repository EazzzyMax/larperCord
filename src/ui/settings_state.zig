//! Valores das configurações. Todas têm efeito de verdade (o que ainda não
//! existe não aparece aqui até existir).
//! São salvos em ~/.config/larpercord/settings.kdl.
const std = @import("std");
const L = @import("../core/lsp.zig");
const sons = @import("../core/sons.zig");

pub const Page = enum {
    conta,
    privacidade,
    filtros,
    aparencia,
    acessibilidade,
    chat,
    voz,
    notificacoes,
    atalhos,
    idioma,
    rede,
    avancado,
    desempenho,
    lsp,
    plugins,
    atualizacoes,
    novidades,
    sobre,
};

/// Texto curto salvo nas configurações (o proxy). Tamanho fixo: as
/// configurações são copiadas e comparadas byte a byte.
pub const Text = struct {
    len: u8 = 0,
    buf: [255]u8 = @splat(0),

    pub fn slice(t: *const Text) []const u8 {
        return t.buf[0..t.len];
    }

    pub fn set(t: *Text, s: []const u8) void {
        const n = @min(s.len, t.buf.len);
        // `s` pode ser o próprio texto (o nome guardado de um dispositivo que sumiu):
        // zerar antes de copiar apagaria a origem.
        var tmp: [255]u8 = undefined;
        @memcpy(tmp[0..n], s[0..n]);
        t.* = .{};
        @memcpy(t.buf[0..n], tmp[0..n]);
        t.len = @intCast(n);
    }
};

pub const split_two_default: i16 = 500;
pub const split_three_a_default: i16 = 333;
pub const split_three_b_default: i16 = 667;

pub const Settings = struct {
    open: bool = false,
    page: Page = .aparencia,

    // Aparência / acessibilidade
    font_scale: f32 = 1.0,
    /// Tamanho de toda a interface, por cima da escala do sistema.
    ui_scale: f32 = 1.0,
    /// Traço e encaixe das letras nos pixels (ui/fonts.zig).
    text_weight: f32 = 1,
    text_hinting: u8 = 0,
    /// Limites de memória, em Desempenho: imagens e cada GIF (MB), e mensagens somando os canais.
    image_cache_mb: f32 = 32,
    gif_limit_mb: f32 = 32,
    message_budget: f32 = 2000,
    /// Revisão dos limites no arquivo: sem ela, ele é de antes da 0.6.2 (ver `migrateLimits`).
    limits_rev: u8 = 1,
    compact: bool = false,
    show_avatars: bool = true,
    reduce_motion: bool = false,
    clock_24h: bool = true,
    show_member_list: bool = true,
    show_status_bar: bool = true,
    underline_links: bool = true,
    role_colors: bool = true,
    /// Status como um anel em volta da foto (em vez da bolinha).
    status_ring: bool = false,
    /// Cor de destaque: 0 = a do tema, 1..8 = as da paleta.
    accent: u8 = 0,
    /// Cantos: 0 = os do tema, 1 = retos, 2 = suaves, 3 = redondos.
    corners: u8 = 0,

    // Chat
    show_spoilers: bool = false,
    autoplay_gifs: bool = true,
    /// Imagens e GIFs que vêm de links (embeds).
    show_embeds: bool = true,
    /// Modo economia: imagens, avatares e anexos só baixam ao clicar.
    data_saver: bool = false,
    /// Prévia do markdown acima da caixa de texto, quando tem formatação.
    md_preview: bool = true,
    /// Canal com não lidas abre na primeira delas, como no Discord (senão, no fim).
    open_at_unread: bool = true,
    /// Pasta com as bibliotecas do FFmpeg escolhida à mão (vazia = procurar sozinho;
    /// platform/ffmpeg.zig). Só entra uma pasta conferida.
    ffmpeg_dir: Text = .{},

    // Largura dos painéis (ui/resize.zig): quanto a pessoa alargou em relação ao
    // que o tema pede, em pixels, e as divisas da tela dividida, em milésimos.
    width_channels: i16 = 0,
    width_members: i16 = 0,
    split_two: i16 = split_two_default,
    split_three_a: i16 = split_three_a_default,
    split_three_b: i16 = split_three_b_default,

    /// Pergunta ao GitHub se há versão nova ao abrir o app.
    check_updates: bool = true,

    // Privacidade (o proxy fica na página Rede)
    send_typing: bool = true,
    /// Mensagens apagadas ficam na tela (marcadas) e as editadas guardam o
    /// texto original. Só neste computador.
    message_log: bool = false,
    /// GIFs do Tenor/Giphy direto do site deles (eles veem o IP).
    gif_hosts: bool = false,
    /// Esconde o e-mail e o @usuário na conta.
    streamer_mode: bool = false,
    /// Aviso antes de entrar num servidor por convite (ui/entrada.zig).
    join_warning: bool = true,
    /// Proxy (socks5h://127.0.0.1:9050…): vazio = conexão direta. Só a mídia
    /// de fora passa por ele, ou tudo com `proxy_all` (net/proxy.zig).
    proxy: Text = .{},
    proxy_all: bool = false,
    /// Emojis usados há pouco, do mais novo para o mais velho (ui/emoji_picker.zig).
    emoji_recent: Text = .{},
    /// Últimas mensagens de cada canal em disco (abrir na hora, busca offline).
    message_cache: bool = true,
    /// Rich Presence: jogos e apps mostram a atividade pelo discord-ipc
    /// (net/rpc_ipc.zig). Desligado, nada escuta.
    rich_presence: bool = false,

    /// Nosso status: 0 online, 1 ausente, 2 não perturbe, 3 invisível.
    /// Reaplicado ao conectar.
    my_status: u8 = 0,

    // Notificações (DMs e menções)
    desktop_notifs: bool = true,
    taskbar_flash: bool = true,

    // Voz (net/voz_audio.zig, core/voz.zig)
    /// Nome do microfone e da saída; vazio = padrão do sistema. Se o dispositivo
    /// sumiu, usa o padrão e o nome fica guardado para quando ele voltar.
    voice_mic: Text = .{},
    voice_out: Text = .{},
    /// Volumes em % (0..200).
    voice_in_gain: u8 = 100,
    voice_out_gain: u8 = 100,
    /// Limiar da detecção de voz: posição na barra (0..100; -80..0 dB).
    voice_sens: u8 = 39,
    /// O limiar segue o ruído de fundo em vez de `voice_sens`.
    voice_auto: bool = false,
    /// Aperte para falar, com a tecla ou o botão em `voice_key` ("k:44", "m:4").
    voice_ptt: bool = false,
    voice_key: Text = .{},
    voice_highpass: bool = true,
    voice_gate: bool = false,
    /// Supressão de ruído: o número de `core/ruido.zig` Mode (0 desligada, 1 RNNoise).
    voice_denoise: u8 = 1,
    /// Liga os avisos da call (o toque de chamada tem a escolha dele, abaixo).
    voice_sounds: bool = true,
    /// Cada som (core/sons.zig Event): a variante (Variant: 0 desligado,
    /// 1 clássico, 2..4 embutidos, 5 o arquivo da pessoa), o volume em %
    /// (0..200) e o arquivo copiado para <config>/larpercord/sons (só o nome).
    /// Os padrões são o que tocava antes de dar para escolher.
    sound_join: u8 = 1,
    sound_join_vol: u8 = 100,
    sound_join_file: Text = .{},
    sound_leave: u8 = 1,
    sound_leave_vol: u8 = 100,
    sound_leave_file: Text = .{},
    sound_user_join: u8 = 0,
    sound_user_join_vol: u8 = 100,
    sound_user_join_file: Text = .{},
    sound_user_leave: u8 = 0,
    sound_user_leave_vol: u8 = 100,
    sound_user_leave_file: Text = .{},
    sound_mute: u8 = 1,
    sound_mute_vol: u8 = 100,
    sound_mute_file: Text = .{},
    sound_unmute: u8 = 1,
    sound_unmute_vol: u8 = 100,
    sound_unmute_file: Text = .{},
    sound_deafen: u8 = 1,
    sound_deafen_vol: u8 = 100,
    sound_deafen_file: Text = .{},
    sound_undeafen: u8 = 1,
    sound_undeafen_vol: u8 = 100,
    sound_undeafen_file: Text = .{},
    sound_ring: u8 = 1,
    sound_ring_vol: u8 = 100,
    sound_ring_file: Text = .{},

    /// Volume dos vídeos em % (0..100; 0 = mudo).
    video_volume: u8 = 100,

    // Erros no código (ui/settings_lsp.zig): uma linguagem de core/lsp.zig `known`
    // em cada par. Tudo desligado por padrão; ligar é sempre a pessoa quem faz.
    lsp_on_zig: bool = false,
    lsp_cmd_zig: Text = .{},
    lsp_on_python: bool = false,
    lsp_cmd_python: Text = .{},
    lsp_on_rust: bool = false,
    lsp_cmd_rust: Text = .{},
    lsp_on_cpp: bool = false,
    lsp_cmd_cpp: Text = .{},
    lsp_on_go: bool = false,
    lsp_cmd_go: Text = .{},
    lsp_on_typescript: bool = false,
    lsp_cmd_typescript: Text = .{},
    lsp_on_lua: bool = false,
    lsp_cmd_lua: Text = .{},
    /// Servidores propostos por plugins que a pessoa liberou (ver `approvalKey`).
    lsp_plugins_ok: Text = .{},

    // Atalhos
    /// Navegação estilo vim com a caixa de texto sem foco (ui/vim.zig).
    vim_keys: bool = false,

    // Avançado
    developer_mode: bool = false,
    hot_reload: bool = true,
    /// O ícone fica na bandeja da abertura até sair, como no Discord (Abrir e Sair no
    /// menu, até com a janela aberta), e fechar a janela deixa o app lá. Desligado:
    /// nenhum ícone nem processo dele, e fechar sai. Sem bandeja, fechar sai igual.
    /// (O `tray_always` de um build de desenvolvimento da 0.6.2 virou esta opção: num
    /// arquivo que ainda o tenha, ele é ignorado.)
    close_to_tray: bool = true,
    /// 0 = seguir o sistema, 1 = português, 2 = inglês, 3 = japonês.
    language: u8 = 0,
    /// 0 = escuro, 1 = claro, 2 = seguir o sistema.
    color_mode: u8 = 0,

    /// Os painéis estão como o tema pede?
    pub fn panelsAtDefault(s: *const Settings) bool {
        return s.width_channels == 0 and s.width_members == 0 and s.split_two == split_two_default and
            s.split_three_a == split_three_a_default and s.split_three_b == split_three_b_default;
    }

    pub fn resetPanels(s: *Settings) void {
        s.width_channels = 0;
        s.width_members = 0;
        s.split_two = split_two_default;
        s.split_three_a = split_three_a_default;
        s.split_three_b = split_three_b_default;
    }

    /// Muda quando algo que afeta o layout das mensagens muda.
    pub fn layoutKey(s: *const Settings) u32 {
        var h: u32 = @intFromFloat(s.font_scale * 100);
        h = h *% 31 +% @intFromBool(s.compact);
        h = h *% 31 +% @intFromBool(s.show_avatars);
        h = h *% 31 +% @intFromBool(s.show_embeds);
        // No modo economia, emoji personalizado vira `:nome:` (ui/rich.zig).
        h = h *% 31 +% @intFromBool(s.data_saver);
        return h;
    }
};

/// Volume do slider para o ganho do som. O ouvido é logarítmico: ao quadrado, o
/// meio da barra soa como metade do volume, e não quase igual ao máximo.
pub fn videoGain(volume: u8) f32 {
    const k = @as(f32, @floatFromInt(@min(volume, 100))) / 100;
    return k * k;
}

pub fn lspOn(s: *Settings, i: usize) *bool {
    return switch (i) {
        inline 0...L.known.len - 1 => |k| &@field(s, "lsp_on_" ++ L.known[k].key),
        else => unreachable,
    };
}
pub fn lspOnC(s: *const Settings, i: usize) *const bool {
    return switch (i) {
        inline 0...L.known.len - 1 => |k| &@field(s, "lsp_on_" ++ L.known[k].key),
        else => unreachable,
    };
}
pub fn lspCmd(s: *Settings, i: usize) *Text {
    return switch (i) {
        inline 0...L.known.len - 1 => |k| &@field(s, "lsp_cmd_" ++ L.known[k].key),
        else => unreachable,
    };
}
pub fn lspCmdC(s: *const Settings, i: usize) *const Text {
    return switch (i) {
        inline 0...L.known.len - 1 => |k| &@field(s, "lsp_cmd_" ++ L.known[k].key),
        else => unreachable,
    };
}

/// Os campos de cada som (sound_<evento>, _vol e _file).
pub fn soundVariant(s: *Settings, e: sons.Event) *u8 {
    return switch (e) {
        inline else => |k| &@field(s, "sound_" ++ @tagName(k)),
    };
}
pub fn soundVariantC(s: *const Settings, e: sons.Event) u8 {
    return switch (e) {
        inline else => |k| @field(s, "sound_" ++ @tagName(k)),
    };
}
pub fn soundVolume(s: *Settings, e: sons.Event) *u8 {
    return switch (e) {
        inline else => |k| &@field(s, "sound_" ++ @tagName(k) ++ "_vol"),
    };
}
pub fn soundVolumeC(s: *const Settings, e: sons.Event) u8 {
    return switch (e) {
        inline else => |k| @field(s, "sound_" ++ @tagName(k) ++ "_vol"),
    };
}
pub fn soundFile(s: *Settings, e: sons.Event) *Text {
    return switch (e) {
        inline else => |k| &@field(s, "sound_" ++ @tagName(k) ++ "_file"),
    };
}
pub fn soundFileC(s: *const Settings, e: sons.Event) *const Text {
    return switch (e) {
        inline else => |k| &@field(s, "sound_" ++ @tagName(k) ++ "_file"),
    };
}

/// Todos os sons como vêm de fábrica (as cópias continuam na pasta).
pub fn resetSounds(s: *Settings) void {
    for (std.enums.values(sons.Event)) |e| {
        soundVariant(s, e).* = @backingInt(e.defaultVariant());
        soundVolume(s, e).* = 100;
        soundFile(s, e).* = .{};
    }
}

/// Alguma linguagem ligada? Falso é o caso comum: o caminho de quem não usa.
pub fn lspAnyOn(s: *const Settings) bool {
    if (s.lsp_plugins_ok.len > 0) return true;
    for (0..L.known.len) |i| if (lspOnC(s, i).*) return true;
    return false;
}

pub const Field = struct { name: []const u8, kind: enum { boolean, float, byte, int, text }, offset: usize };

/// Campos persistidos (todos menos `open` e `page`).
pub fn fields() []const Field {
    const S = struct {
        const list = blk: {
            const info = @typeInfo(Settings).@"struct";
            var out: [info.field_names.len]Field = undefined;
            var n: usize = 0;
            for (info.field_names, info.field_types) |fname, ftype| {
                if (std.mem.eql(u8, fname, "open") or std.mem.eql(u8, fname, "page")) continue;
                // Só estes tipos são salvos byte a byte; outro tipo aqui
                // corromperia o arquivo (ou a memória) ao ler.
                if (ftype != bool and ftype != f32 and ftype != u8 and ftype != i16 and ftype != Text) @compileError("configuração com tipo não suportado: " ++ fname);
                out[n] = .{
                    .name = fname,
                    .kind = if (ftype == bool) .boolean else if (ftype == f32) .float else if (ftype == Text) .text else if (ftype == i16) .int else .byte,
                    .offset = @offsetOf(Settings, fname),
                };
                n += 1;
            }
            const final = out[0..n].*;
            break :blk final;
        };
    };
    return &S.list;
}

/// Lê um campo booleano ou de um byte pelo índice em `fields()` (para a
/// paleta de comandos). Número quebrado ou maior que um byte não tem como ler
/// assim: null.
pub fn getByte(s: *const Settings, index: usize) ?u8 {
    const fs = fields();
    if (index >= fs.len or fs[index].kind == .float or fs[index].kind == .int or fs[index].kind == .text) return null;
    return (@as([*]const u8, @ptrCast(s)) + fs[index].offset)[0];
}

/// Muda um campo booleano (0/1) ou de um byte pelo índice em `fields()`.
pub fn setByte(s: *Settings, index: usize, value: u8) bool {
    const fs = fields();
    if (index >= fs.len) return false;
    const p = @as([*]u8, @ptrCast(s)) + fs[index].offset;
    switch (fs[index].kind) {
        .boolean => @as(*bool, @ptrCast(p)).* = value != 0,
        .byte => p[0] = value,
        .float, .int, .text => return false,
    }
    return true;
}

/// Índice do campo em `fields()` (para tabelas montadas em tempo de compilação).
pub fn fieldIndex(comptime name: []const u8) usize {
    @setEvalBranchQuota(20_000);
    if (!@hasField(Settings, name)) @compileError("configuração inexistente: " ++ name);
    @setEvalBranchQuota(20_000);
    for (fields(), 0..) |f, i| if (std.mem.eql(u8, f.name, name)) return i;
    unreachable;
}

/// Serializa em KDL: `settings theme="vidro" compact=#true font_scale=1.1 …`
pub fn write(s: *const Settings, theme_name: []const u8, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    try out.print(gpa, "// gerado pelo larperCord\nsettings theme=\"{s}\"", .{theme_name});
    const base: [*]const u8 = @ptrCast(s);
    for (fields()) |f| {
        switch (f.kind) {
            .boolean => try out.print(gpa, " {s}={s}", .{ f.name, if (@as(*const bool, @ptrCast(base + f.offset)).*) "#true" else "#false" }),
            .float => try out.print(gpa, " {s}={d:.3}", .{ f.name, @as(*const f32, @ptrCast(@alignCast(base + f.offset))).* }),
            .byte => try out.print(gpa, " {s}={d}", .{ f.name, (base + f.offset)[0] }),
            .int => try out.print(gpa, " {s}={d}", .{ f.name, @as(*const i16, @ptrCast(@alignCast(base + f.offset))).* }),
            .text => {
                // Comandos têm aspas, e caminhos do Windows têm barras.
                try out.print(gpa, " {s}=\"", .{f.name});
                for (@as(*const Text, @ptrCast(@alignCast(base + f.offset))).slice()) |ch| {
                    if (ch == '"' or ch == '\\') try out.append(gpa, '\\');
                    if (ch >= 0x20) try out.append(gpa, ch);
                }
                try out.append(gpa, '"');
            },
        }
    }
    try out.append(gpa, '\n');
}

/// Faixa aceita ao ler cada número quebrado. Escalas e pesos ficam entre 0,5 e 3; os
/// limites de memória (MB, mensagens) não são escala (o app ainda aperta cada um no uso).
fn floatRange(name: []const u8) [2]f64 {
    if (std.mem.endsWith(u8, name, "_mb") or std.mem.eql(u8, name, "message_budget")) return .{ 0, 100_000 };
    return .{ 0.5, 3 };
}

/// Arquivo de antes da 0.6.2. A 0.6.1 baixou o limite de cada GIF de 32 para 12 MB (as
/// animações longas pulavam quadros) e, ao ler, apertava todo número quebrado entre 0,5
/// e 3: reabrindo o app, os limites viravam o mínimo de cada um (4 MB por GIF, 16 MB de
/// imagens, 500 mensagens). O padrão antigo e o que ficou estragado voltam ao padrão.
fn migrateLimits(s: *Settings) void {
    const defaults: Settings = .{};
    if (s.gif_limit_mb == 12 or s.gif_limit_mb < 4) s.gif_limit_mb = defaults.gif_limit_mb;
    if (s.image_cache_mb < 16) s.image_cache_mb = defaults.image_cache_mb;
    if (s.message_budget < 500) s.message_budget = defaults.message_budget;
    s.limits_rev = defaults.limits_rev;
}

pub fn apply(s: *Settings, node: anytype) void {
    const base: [*]u8 = @ptrCast(s);
    for (fields()) |f| {
        switch (f.kind) {
            .boolean => if (node.flag(f.name)) |v| {
                @as(*bool, @ptrCast(base + f.offset)).* = v;
            },
            .float => if (node.num(f.name)) |v| {
                const range = floatRange(f.name);
                @as(*f32, @ptrCast(@alignCast(base + f.offset))).* = @floatCast(std.math.clamp(v, range[0], range[1]));
            },
            .byte => if (node.num(f.name)) |v| {
                (base + f.offset)[0] = @intFromFloat(std.math.clamp(v, 0, 255));
            },
            .int => if (node.num(f.name)) |v| {
                @as(*i16, @ptrCast(@alignCast(base + f.offset))).* = @intFromFloat(std.math.clamp(v, -32768, 32767));
            },
            .text => if (node.str(f.name)) |v| {
                @as(*Text, @ptrCast(@alignCast(base + f.offset))).set(v);
            },
        }
    }
    if (node.num("limits_rev") == null) migrateLimits(s);
}

test "limites de memória voltam do arquivo como estavam e o arquivo da 0.6.1 é corrigido" {
    const kdl = @import("../theme/kdl.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var s: Settings = .{};
    s.gif_limit_mb = 20;
    s.image_cache_mb = 64;
    s.message_budget = 3000;
    s.font_scale = 1.2;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expectEqual(@as(f32, 20), back.gif_limit_mb);
    try std.testing.expectEqual(@as(f32, 64), back.image_cache_mb);
    try std.testing.expectEqual(@as(f32, 3000), back.message_budget);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), back.font_scale, 0.001);
    // 0.6.1: o padrão antigo de cada GIF e os limites que o arredondamento estragou.
    const old = try kdl.parse(arena.allocator(), "settings gif_limit_mb=12.000 image_cache_mb=3.000 message_budget=3.000 font_scale=9\n", null);
    var fixed: Settings = .{};
    apply(&fixed, &old[0]);
    try std.testing.expectEqual(@as(f32, 32), fixed.gif_limit_mb);
    try std.testing.expectEqual(@as(f32, 32), fixed.image_cache_mb);
    try std.testing.expectEqual(@as(f32, 2000), fixed.message_budget);
    try std.testing.expectEqual(@as(f32, 3), fixed.font_scale);
    // 0.6.1 com escolhas que não são o padrão nem estragadas: ficam.
    const chosen = try kdl.parse(arena.allocator(), "settings gif_limit_mb=24.000 image_cache_mb=96.000\n", null);
    var kept: Settings = .{};
    apply(&kept, &chosen[0]);
    try std.testing.expectEqual(@as(f32, 24), kept.gif_limit_mb);
    try std.testing.expectEqual(@as(f32, 96), kept.image_cache_mb);
    // Depois da migração, 12 escolhido de propósito fica 12.
    const now = try kdl.parse(arena.allocator(), "settings gif_limit_mb=12.000 limits_rev=1\n", null);
    var later: Settings = .{};
    apply(&later, &now[0]);
    try std.testing.expectEqual(@as(f32, 12), later.gif_limit_mb);
}

test "configurações vão e voltam pelo KDL" {
    const kdl = @import("../theme/kdl.zig");
    var s: Settings = .{};
    s.compact = true;
    s.font_scale = 1.2;
    s.language = 2;
    s.proxy.set("socks5h://127.0.0.1:9050");
    s.emoji_recent.set("😀 ❤️ pepe:12");
    s.ffmpeg_dir.set("C:\\Program Files\\ffmpeg \"shared\"\\bin");
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expect(back.compact);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), back.font_scale, 0.001);
    try std.testing.expectEqual(@as(u8, 2), back.language);
    try std.testing.expectEqualStrings("socks5h://127.0.0.1:9050", back.proxy.slice());
    try std.testing.expectEqualStrings("😀 ❤️ pepe:12", back.emoji_recent.slice());
    try std.testing.expectEqualStrings("C:\\Program Files\\ffmpeg \"shared\"\\bin", back.ffmpeg_dir.slice());
    try std.testing.expectEqualStrings("vidro", nodes[0].str("theme").?);
}

test "configurações de voz vão e voltam (volume acima de 3x e nome com acento)" {
    const kdl = @import("../theme/kdl.zig");
    var s: Settings = .{};
    s.voice_mic.set("Microfone do headset (USB) ção");
    s.voice_out.set("Saída HDMI");
    s.voice_in_gain = 180;
    s.voice_out_gain = 0;
    s.voice_sens = 12;
    s.voice_auto = true;
    s.voice_ptt = true;
    s.voice_key.set("k:44");
    s.voice_highpass = false;
    s.voice_gate = true;
    s.voice_denoise = 0;
    s.voice_sounds = false;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expectEqualStrings("Microfone do headset (USB) ção", back.voice_mic.slice());
    try std.testing.expectEqualStrings("Saída HDMI", back.voice_out.slice());
    try std.testing.expectEqual(@as(u8, 180), back.voice_in_gain);
    try std.testing.expectEqual(@as(u8, 0), back.voice_out_gain);
    try std.testing.expectEqual(@as(u8, 12), back.voice_sens);
    try std.testing.expect(back.voice_auto and back.voice_ptt and back.voice_gate);
    try std.testing.expect(!back.voice_highpass and !back.voice_sounds);
    try std.testing.expectEqualStrings("k:44", back.voice_key.slice());
    try std.testing.expectEqual(@as(u8, 0), back.voice_denoise);
    // Arquivo antigo, sem nada disso: os padrões.
    const old = try kdl.parse(arena.allocator(), "settings compact=#true\n", null);
    var fresh: Settings = .{};
    apply(&fresh, &old[0]);
    try std.testing.expectEqual(@as(u8, 100), fresh.voice_in_gain);
    try std.testing.expectEqual(@as(usize, 0), fresh.voice_mic.slice().len);
    try std.testing.expect(fresh.voice_highpass and fresh.voice_sounds and !fresh.voice_ptt);
    try std.testing.expectEqual(@as(u8, 1), fresh.voice_denoise);
}

test "texto copiado dele mesmo não se apaga" {
    var t: Text = .{};
    t.set("Fone USB (sumiu)");
    t.set(t.slice());
    try std.testing.expectEqualStrings("Fone USB (sumiu)", t.slice());
    // Um pedaço do próprio texto também vale.
    t.set(t.slice()[5..8]);
    try std.testing.expectEqualStrings("USB", t.slice());
}

test "sons por evento vão e voltam, e o arquivo antigo toca o de antes" {
    const kdl = @import("../theme/kdl.zig");
    // De fábrica: o que tocava antes de dar para escolher.
    var fresh: Settings = .{};
    for (std.enums.values(sons.Event)) |e| {
        try std.testing.expectEqual(@backingInt(e.defaultVariant()), soundVariantC(&fresh, e));
        try std.testing.expectEqual(@as(u8, 100), soundVolumeC(&fresh, e));
        try std.testing.expectEqual(@as(usize, 0), soundFileC(&fresh, e).len);
    }
    var s: Settings = .{};
    soundVariant(&s, .join).* = @backingInt(sons.Variant.glass);
    soundVolume(&s, .join).* = 35;
    soundVariant(&s, .ring).* = @backingInt(sons.Variant.custom);
    soundFile(&s, .ring).set("ring-meu \"toque\".ogg");
    soundVariant(&s, .user_leave).* = @backingInt(sons.Variant.retro);
    soundVolume(&s, .mute).* = 200;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expectEqual(@as(u8, 3), back.sound_join);
    try std.testing.expectEqual(@as(u8, 35), back.sound_join_vol);
    try std.testing.expectEqual(@as(u8, 5), back.sound_ring);
    try std.testing.expectEqualStrings("ring-meu \"toque\".ogg", back.sound_ring_file.slice());
    try std.testing.expectEqual(@as(u8, 4), back.sound_user_leave);
    try std.testing.expectEqual(@as(u8, 200), back.sound_mute_vol);
    try std.testing.expectEqual(@as(u8, 1), back.sound_leave);
    // Arquivo de antes dos sons: os padrões.
    const old = try kdl.parse(arena.allocator(), "settings voice_sounds=#true\n", null);
    var older: Settings = .{};
    apply(&older, &old[0]);
    try std.testing.expectEqual(@as(u8, 1), older.sound_join);
    try std.testing.expectEqual(@as(u8, 0), older.sound_user_join);
    resetSounds(&back);
    try std.testing.expectEqual(@as(u8, 1), back.sound_join);
    try std.testing.expectEqual(@as(usize, 0), back.sound_ring_file.len);
}

test "volume dos vídeos e fechar para a bandeja vão e voltam" {
    const kdl = @import("../theme/kdl.zig");
    var s: Settings = .{};
    try std.testing.expect(s.close_to_tray);
    try std.testing.expectEqual(@as(u8, 100), s.video_volume);
    s.video_volume = 35;
    s.close_to_tray = false;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expectEqual(@as(u8, 35), back.video_volume);
    try std.testing.expect(!back.close_to_tray);
    // Arquivo antigo: os padrões. Volta para a bandeja ligada e som cheio.
    const old = try kdl.parse(arena.allocator(), "settings compact=#true\n", null);
    var fresh: Settings = .{};
    apply(&fresh, &old[0]);
    try std.testing.expect(fresh.close_to_tray);
    try std.testing.expectEqual(@as(u8, 100), fresh.video_volume);
}

test "o tray_always de antes é ignorado e sai do arquivo ao salvar" {
    const kdl = @import("../theme/kdl.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // As duas combinações: quem manda é só o close_to_tray.
    for ([_]bool{ true, false }) |ctt| {
        const text = if (ctt) "settings tray_always=#false close_to_tray=#true\n" else "settings close_to_tray=#false tray_always=#true\n";
        const nodes = try kdl.parse(arena.allocator(), text, null);
        var s: Settings = .{};
        apply(&s, &nodes[0]);
        try std.testing.expectEqual(ctt, s.close_to_tray);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.testing.allocator);
        try write(&s, "classico", &out, std.testing.allocator);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "tray_always") == null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, if (ctt) "close_to_tray=#true" else "close_to_tray=#false") != null);
    }
}

test "largura dos painéis vai e volta, e um arquivo editado à mão não estoura" {
    const kdl = @import("../theme/kdl.zig");
    var s: Settings = .{};
    s.width_channels = 90;
    s.width_members = -40;
    s.split_two = 620;
    s.split_three_a = 250;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expectEqual(@as(i16, 90), back.width_channels);
    try std.testing.expectEqual(@as(i16, -40), back.width_members);
    try std.testing.expectEqual(@as(i16, 620), back.split_two);
    try std.testing.expectEqual(@as(i16, 250), back.split_three_a);
    try std.testing.expectEqual(split_three_b_default, back.split_three_b);
    // Número fora do que cabe vira o maior que cabe (a tela limita depois).
    const big = try kdl.parse(arena.allocator(), "settings width_channels=999999 width_members=-999999\n", null);
    var fresh: Settings = .{};
    apply(&fresh, &big[0]);
    try std.testing.expectEqual(@as(i16, 32767), fresh.width_channels);
    try std.testing.expectEqual(@as(i16, -32768), fresh.width_members);
    // Arquivo antigo: como o tema pede.
    const old = try kdl.parse(arena.allocator(), "settings compact=#true\n", null);
    var older: Settings = .{};
    apply(&older, &old[0]);
    try std.testing.expectEqual(@as(i16, 0), older.width_channels);
    try std.testing.expectEqual(split_two_default, older.split_two);
}

test "ganho do vídeo: mudo em 0, cheio em 100, e um arquivo editado à mão não estoura" {
    try std.testing.expectEqual(@as(f32, 0), videoGain(0));
    try std.testing.expectEqual(@as(f32, 1), videoGain(100));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), videoGain(50), 0.001);
    try std.testing.expectEqual(@as(f32, 1), videoGain(255));
}

test "comandos de LSP vão e voltam, com aspas e barras" {
    const kdl = @import("../theme/kdl.zig");
    var s: Settings = .{};
    try std.testing.expect(!lspAnyOn(&s));
    s.lsp_on_python = true;
    s.lsp_cmd_python.set("\"/opt/meu servidor/ruff\" server");
    s.lsp_cmd_zig.set("C:\\tools\\zls.exe --flag");
    s.lsp_plugins_ok.set("0123456789abcdef");
    try std.testing.expect(lspAnyOn(&s));
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try write(&s, "vidro", &out, std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes = try kdl.parse(arena.allocator(), out.items, null);
    var back: Settings = .{};
    apply(&back, &nodes[0]);
    try std.testing.expect(back.lsp_on_python and !back.lsp_on_zig);
    try std.testing.expectEqualStrings("\"/opt/meu servidor/ruff\" server", back.lsp_cmd_python.slice());
    try std.testing.expectEqualStrings("C:\\tools\\zls.exe --flag", back.lsp_cmd_zig.slice());
    try std.testing.expectEqualStrings("0123456789abcdef", back.lsp_plugins_ok.slice());
    // Cada linguagem conhecida tem o seu par de campos, e o padrão é desligado.
    var fresh: Settings = .{};
    for (0..L.known.len) |i| {
        try std.testing.expect(!lspOn(&fresh, i).*);
        try std.testing.expectEqual(@as(usize, 0), lspCmd(&fresh, i).slice().len);
    }
}

test "campos pelo índice (paleta de comandos)" {
    var s: Settings = .{};
    const i = fieldIndex("compact");
    try std.testing.expectEqual(@as(?u8, 0), getByte(&s, i));
    try std.testing.expect(setByte(&s, i, 1));
    try std.testing.expect(s.compact);
    try std.testing.expect(setByte(&s, fieldIndex("color_mode"), 2));
    try std.testing.expectEqual(@as(u8, 2), s.color_mode);
    try std.testing.expect(!setByte(&s, fieldIndex("font_scale"), 1));
    try std.testing.expect(!s.vim_keys and s.md_preview);
}
