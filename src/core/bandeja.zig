//! O recado entre o app e o processo do ícone da bandeja (Linux) e a imagem que o
//! ícone mostra, sem SDL nem D-Bus (testados em `zig build test`). O processo do
//! ícone escreve na saída padrão; o app lê numa thread (platform/tray.zig).
const std = @import("std");

/// Um byte por recado; a ficha de ativação vem com o tamanho na frente.
pub const msg_ready = 'r';
pub const msg_failed = 'x';
pub const msg_open = 'o';
pub const msg_quit = 'q';
/// Clique no ícone: alterna a janela, como o esquerdo no Windows.
pub const msg_toggle = 't';
/// 'a', um byte com o tamanho e a ficha do xdg-activation que o painel mandou
/// antes do clique (com ela o compositor Wayland deixa a janela vir com o foco).
pub const msg_token = 'a';

pub const token_max = 255;

pub const Recado = union(enum) {
    ready,
    failed,
    open,
    quit,
    toggle,
    token: []const u8,
};

/// Monta o recado da ficha. Nulo: vazia ou grande demais para um byte de tamanho
/// (aí o clique segue sem ela, como num painel que não manda ficha).
pub fn tokenMsg(buf: *[2 + token_max]u8, token: []const u8) ?[]const u8 {
    if (token.len == 0 or token.len > token_max) return null;
    buf[0] = msg_token;
    buf[1] = @intCast(token.len);
    @memcpy(buf[2..][0..token.len], token);
    return buf[0 .. 2 + token.len];
}

/// Lê o que chega do processo do ícone, um byte de cada vez (a leitura pode parar
/// no meio da ficha e continuar na próxima volta).
pub const Leitor = struct {
    estado: enum { recado, tamanho, ficha } = .recado,
    falta: u8 = 0,
    len: u8 = 0,
    buf: [token_max]u8 = undefined,

    pub fn feed(l: *Leitor, b: u8) ?Recado {
        switch (l.estado) {
            .recado => return switch (b) {
                msg_ready => .ready,
                msg_failed => .failed,
                msg_open => .open,
                msg_quit => .quit,
                msg_toggle => .toggle,
                msg_token => {
                    l.estado = .tamanho;
                    return null;
                },
                else => null,
            },
            .tamanho => {
                if (b == 0) {
                    l.estado = .recado;
                    return null;
                }
                l.falta = b;
                l.len = 0;
                l.estado = .ficha;
                return null;
            },
            .ficha => {
                l.buf[l.len] = b;
                l.len += 1;
                l.falta -= 1;
                if (l.falta > 0) return null;
                l.estado = .recado;
                return .{ .token = l.buf[0..l.len] };
            },
        }
    }
};

/// RGBA (como o stb_image entrega) para o ARGB32 em ordem de rede do
/// StatusNotifierItem (IconPixmap): A, R, G, B em cada pixel, sem pré-multiplicar.
/// `out` pode ser o próprio `rgba` (o ícone é convertido no lugar): o pixel é lido
/// inteiro antes de ser escrito.
pub fn argb(rgba: []const u8, out: []u8) void {
    std.debug.assert(rgba.len == out.len and rgba.len % 4 == 0);
    var i: usize = 0;
    while (i < rgba.len) : (i += 4) {
        const r = rgba[i];
        const g = rgba[i + 1];
        const b = rgba[i + 2];
        const a = rgba[i + 3];
        out[i] = a;
        out[i + 1] = r;
        out[i + 2] = g;
        out[i + 3] = b;
    }
}

/// Os itens do menu (com.canonical.dbusmenu): 0 é a raiz, 1 abre e 2 sai.
pub const menu_open: i32 = 1;
pub const menu_quit: i32 = 2;

/// O que um "clicked" no item do menu manda para o app.
pub fn menuClick(id: i32) ?u8 {
    return switch (id) {
        menu_open => msg_open,
        menu_quit => msg_quit,
        else => null,
    };
}

/// A propriedade entra na resposta? Lista vazia é "todas" (GetLayout,
/// GetGroupProperties).
pub fn wanted(names: []const []const u8, name: []const u8) bool {
    if (names.len == 0) return true;
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

test "recados de um byte e a ficha, mesmo partidos no meio" {
    var l: Leitor = .{};
    try std.testing.expectEqual(Recado.ready, l.feed('r').?);
    try std.testing.expectEqual(Recado.toggle, l.feed('t').?);
    try std.testing.expectEqual(Recado.open, l.feed('o').?);
    try std.testing.expectEqual(Recado.quit, l.feed('q').?);
    try std.testing.expectEqual(Recado.failed, l.feed('x').?);
    // Byte desconhecido: ignora e segue.
    try std.testing.expect(l.feed('?') == null);

    var buf: [2 + token_max]u8 = undefined;
    const msg = tokenMsg(&buf, "kwin-42_TIME1234").?;
    var got: ?Recado = null;
    for (msg, 0..) |b, i| {
        got = l.feed(b);
        if (i + 1 < msg.len) try std.testing.expect(got == null);
    }
    try std.testing.expectEqualStrings("kwin-42_TIME1234", got.?.token);
    // Depois da ficha, os de um byte de novo ('r' dentro da ficha não contou).
    try std.testing.expectEqual(Recado.toggle, l.feed('t').?);
}

test "ficha vazia ou grande demais não vai" {
    var buf: [2 + token_max]u8 = undefined;
    try std.testing.expect(tokenMsg(&buf, "") == null);
    const big: [token_max + 1]u8 = @splat('x');
    try std.testing.expect(tokenMsg(&buf, &big) == null);
    const max: [token_max]u8 = @splat('y');
    const m = tokenMsg(&buf, &max).?;
    try std.testing.expectEqual(@as(usize, 2 + token_max), m.len);
    var l: Leitor = .{};
    var got: ?Recado = null;
    for (m) |b| got = l.feed(b);
    try std.testing.expectEqual(@as(usize, token_max), got.?.token.len);
    // Tamanho 0 (não sai daqui, mas não pode travar a leitura).
    try std.testing.expect(l.feed(msg_token) == null);
    try std.testing.expect(l.feed(0) == null);
    try std.testing.expectEqual(Recado.open, l.feed('o').?);
}

test "RGBA para ARGB em ordem de rede" {
    const rgba = [_]u8{ 1, 2, 3, 4, 10, 20, 30, 0 };
    var out: [8]u8 = undefined;
    argb(&rgba, &out);
    try std.testing.expectEqualSlices(u8, &.{ 4, 1, 2, 3, 0, 10, 20, 30 }, &out);
    // No lugar, como o ícone é convertido: cada cor fica onde deve (um quadrado
    // branco no painel era o pixel sobrescrito antes de ser lido).
    var px = [_]u8{ 10, 20, 30, 255, 200, 100, 50, 128 };
    argb(&px, &px);
    try std.testing.expectEqualSlices(u8, &.{ 255, 10, 20, 30, 128, 200, 100, 50 }, &px);
}

test "menu: Abrir, Sair e o filtro de propriedades" {
    try std.testing.expectEqual(@as(?u8, msg_open), menuClick(menu_open));
    try std.testing.expectEqual(@as(?u8, msg_quit), menuClick(menu_quit));
    try std.testing.expect(menuClick(0) == null);
    try std.testing.expect(menuClick(3) == null);
    try std.testing.expect(wanted(&.{}, "label"));
    try std.testing.expect(wanted(&.{ "type", "label" }, "label"));
    try std.testing.expect(!wanted(&.{"type"}, "label"));
}
