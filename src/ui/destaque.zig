//! Cores do destaque de uma mensagem que chama a gente (core/mencao.zig) ou
//! que tem palavra de alerta: a faixa à esquerda e o fundo claro da linha,
//! como no Discord. A cor vem do tema (o `idle`, o dourado do Discord; no
//! estilo terminal, o `mention` do tema) e é acertada contra o fundo da
//! conversa, escuro ou claro: a faixa fica com contraste de pelo menos 3:1
//! (o mínimo da WCAG para um elemento da interface) e o fundo muda pelo menos
//! um canal de cor o bastante para se ver. Calculado por tema, não por quadro.
const std = @import("std");
const Rgba = @import("../theme/color.zig").Rgba;

pub const Cores = struct { faixa: Rgba, fundo: Rgba };

/// Contraste mínimo da faixa contra cada fundo.
pub const contraste_faixa: f32 = 3;
/// O quanto o fundo da linha muda, no canal que mais muda (0..1).
pub const diferenca_fundo: f32 = 0.085;

fn menorContraste(c: Rgba, fundos: []const Rgba) f32 {
    var m: f32 = 21;
    for (fundos) |f| m = @min(m, c.contrast(opaco(f)));
    return m;
}

fn opaco(c: Rgba) Rgba {
    return .{ .r = c.r, .g = c.g, .b = c.b };
}

/// O canal que mais muda entre duas cores.
pub fn maiorCanal(a: Rgba, b: Rgba) f32 {
    return @max(@abs(a.r - b.r), @max(@abs(a.g - b.g), @abs(a.b - b.b)));
}

/// `base`: a cor do tema; `fundos`: onde a linha pode estar (o fundo e a
/// superfície da conversa).
pub fn cores(base: Rgba, fundos: []const Rgba) Cores {
    var faixa = opaco(base);
    if (fundos.len == 0) return .{ .faixa = faixa, .fundo = faixa.alpha(0.08) };
    // Fundo escuro: a faixa clareia até aparecer; claro: escurece.
    var luz: f32 = 0;
    for (fundos) |f| luz += opaco(f).luminance();
    const rumo = if (luz / @as(f32, @floatFromInt(fundos.len)) < 0.3) Rgba.white else Rgba.black;
    var i: usize = 0;
    while (i < 12 and menorContraste(faixa, fundos) < contraste_faixa) : (i += 1) faixa = faixa.mix(rumo, 0.18);
    var dif: f32 = 1;
    for (fundos) |f| dif = @min(dif, maiorCanal(faixa, opaco(f)));
    const a = std.math.clamp(diferenca_fundo / @max(dif, 0.01), 0.08, 0.26);
    return .{ .faixa = faixa, .fundo = faixa.alpha(a) };
}

/// A cor que fica na tela com o fundo da linha por cima de `f`.
pub fn composto(c: Cores, f: Rgba) Rgba {
    return opaco(f).mix(opaco(c.fundo), c.fundo.a);
}

test "destaque aparece em fundo escuro e claro" {
    const dourado = Rgba.hex(0xe5a83b);
    for ([_]Rgba{ Rgba.hex(0x1e1f22), Rgba.hex(0x313338), Rgba.hex(0xffffff), Rgba.hex(0xf2f3f5) }) |f| {
        const c = cores(dourado, &.{f});
        try std.testing.expect(c.faixa.contrast(f) >= contraste_faixa);
        try std.testing.expect(maiorCanal(composto(c, f), f) >= diferenca_fundo - 0.005);
    }
    // No escuro, o dourado já aparece: fica a cor do tema e o fundo de antes.
    const e = cores(dourado, &.{Rgba.hex(0x1e1f22)});
    try std.testing.expectEqual(dourado.r, e.faixa.r);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), e.fundo.a, 0.02);
}

test "cor do tema parecida com o fundo é acertada" {
    // Amarelo-claro num fundo branco: a faixa escurece até ter contraste.
    const f = Rgba.hex(0xfafafa);
    const c = cores(Rgba.hex(0xffe680), &.{f});
    try std.testing.expect(c.faixa.contrast(f) >= contraste_faixa);
    try std.testing.expect(c.faixa.luminance() < Rgba.hex(0xffe680).luminance());
    // Azul-escuro num fundo quase preto: clareia.
    const g = Rgba.hex(0x0d0f14);
    const d = cores(Rgba.hex(0x1a2a6c), &.{g});
    try std.testing.expect(d.faixa.contrast(g) >= contraste_faixa);
}
