//! Texto com árabe ou hebraico em ui/rich.zig: cada palavra se molda sozinha no `d.text` (ver
//! `bidi`), mas a ordem das palavras na linha também muda. Uma passada que só mede anota onde
//! cada pedaço caiu (a quebra é feita com as larguras moldadas) e cada linha ganha a ordem
//! visual antes de desenhar. Parágrafo da direita para a esquerda termina na borda direita da
//! coluna, como num leitor nativo. Só o x muda: seleção e cópia seguem os bytes do texto
//! original. Fica fora do rich.zig (que depende do ImGui) para os testes alcançarem as contas.
const std = @import("std");
const bidi = @import("bidi.zig");

pub const Plan = struct {
    pub const max = 1024;
    n: usize = 0,
    /// Passou de `max`: o último parágrafo fica na ordem lógica.
    full: bool = false,
    x: [max]f32 = undefined,
    y: [max]f32 = undefined,
    w: [max]f32 = undefined,
    cls: [max]bidi.Class = undefined,
    /// Começa um parágrafo (\n antes) / começa uma linha / não sai do lugar (marcador de
    /// lista e linha de bloco de código).
    para: [max]bool = undefined,
    line: [max]bool = undefined,
    fixed: [max]bool = undefined,
    /// O x de cada pedaço na ordem visual.
    vx: [max]f32 = undefined,
    /// A linha do pedaço mudou de ordem: onde ela começa e termina na tela, a direção do
    /// parágrafo, se ela foi para a borda direita e se o pedaço é o último dela no texto (a
    /// sonda do mouse usa, ver `select` no rich.zig).
    moved: [max]bool = undefined,
    lo: [max]f32 = undefined,
    hi: [max]f32 = undefined,
    rtl: [max]bool = undefined,
    right: [max]bool = undefined,
    last: [max]bool = undefined,
    /// O vão até o próximo pedaço do texto, na tela: à direita ou à esquerda, conforme a
    /// ordem (a seleção pinta o espaço entre as palavras ali).
    gap_lo: [max]f32 = undefined,
    gap_hi: [max]f32 = undefined,

    pub const Line = struct { lo: f32, hi: f32, rtl: bool, right: bool, last: bool, gap_lo: f32, gap_hi: f32 };

    pub fn reset(p: *Plan) void {
        p.n = 0;
        p.full = false;
    }

    pub fn add(p: *Plan, x: f32, y: f32, w: f32, cls: bidi.Class, para: bool, line: bool, fixed: bool) void {
        if (p.n == max) {
            p.full = true;
            return;
        }
        p.x[p.n] = x;
        p.y[p.n] = y;
        p.w[p.n] = w;
        p.cls[p.n] = cls;
        p.para[p.n] = para or p.n == 0;
        p.line[p.n] = line;
        p.fixed[p.n] = fixed;
        p.n += 1;
    }

    pub fn xAt(p: *const Plan, k: usize, x: f32) f32 {
        return if (k < p.n) p.vx[k] else x;
    }

    pub fn lineOf(p: *const Plan, k: usize) ?Line {
        if (k >= p.n or !p.moved[k]) return null;
        return .{ .lo = p.lo[k], .hi = p.hi[k], .rtl = p.rtl[k], .right = p.right[k], .last = p.last[k], .gap_lo = p.gap_lo[k], .gap_hi = p.gap_hi[k] };
    }

    /// `edge`: a borda direita da coluna, a partir do começo do texto (a largura de quebra,
    /// ou a do balão, que pode ser mais estreita).
    pub fn resolve(p: *Plan, edge: f32) void {
        var i: usize = 0;
        while (i < p.n) {
            var j = i + 1;
            while (j < p.n and !p.para[j]) j += 1;
            for (i..j) |k| {
                p.vx[k] = p.x[k];
                p.moved[k] = false;
            }
            if (!(j == p.n and p.full)) p.paragraph(i, j, edge);
            i = j;
        }
    }

    /// A ordem visual de um parágrafo, linha por linha. Parágrafo da direita para a esquerda
    /// sem recuo: cada linha termina na borda direita. O resto (da esquerda para a direita,
    /// citação, lista) começa onde começava.
    fn paragraph(p: *Plan, from: usize, to: usize, edge: f32) void {
        var idx: [max]u16 = undefined;
        var cls: [max]bidi.Class = undefined;
        var gap: [max]bool = undefined;
        var starts: [max]bool = undefined;
        var order: [max]u16 = undefined;
        var n: usize = 0;
        for (from..to) |k| {
            if (p.fixed[k]) continue;
            const prev = if (n > 0) idx[n - 1] else 0;
            idx[n] = @intCast(k);
            cls[n] = p.cls[k];
            starts[n] = n == 0 or p.line[k] or p.y[k] != p.y[prev];
            gap[n] = !starts[n] and p.x[k] > p.x[prev] + p.w[prev] + 0.5;
            n += 1;
        }
        if (!bidi.anyRtl(cls[0..n])) return;
        const rtl = bidi.orderWords(cls[0..n], gap[0..n], starts[0..n], order[0..n]) orelse return;
        var a: usize = 0;
        while (a < n) {
            var b = a + 1;
            while (b < n and !starts[b]) b += 1;
            const start = p.x[idx[a]];
            // Recuo (citação, lista) fica como estava: o marcador e a barra são da esquerda.
            const right = rtl and start == 0;
            const lo = if (right) rightStart(p.lineWidth(idx[0..n], order[a..b]), edge) else start;
            var cx = lo;
            for (a..b) |v| {
                const q = order[v];
                p.vx[idx[q]] = cx;
                cx += p.w[idx[q]];
                if (v + 1 < b) cx += p.gapBetween(idx[0..n], q, order[v + 1]);
            }
            // `idx` está na ordem do texto: o último de a..b é o fim da linha no texto.
            for (a..b) |v| {
                const k = idx[v];
                p.moved[k] = true;
                p.lo[k] = lo;
                p.hi[k] = cx;
                p.rtl[k] = rtl;
                p.right[k] = right;
                p.last[k] = v + 1 == b;
                p.gap_lo[k] = 0;
                p.gap_hi[k] = 0;
                if (v + 1 == b) continue;
                const nx = idx[v + 1];
                if (p.vx[nx] >= p.vx[k]) {
                    p.gap_lo[k] = p.vx[k] + p.w[k];
                    p.gap_hi[k] = p.vx[nx];
                } else {
                    p.gap_lo[k] = p.vx[nx] + p.w[nx];
                    p.gap_hi[k] = p.vx[k];
                }
            }
            a = b;
        }
    }

    /// A largura de uma linha na tela (`line`: os pedaços na ordem visual): as palavras e os
    /// espaços entre elas, sem o espaço do fim.
    fn lineWidth(p: *const Plan, idx: []const u16, line: []const u16) f32 {
        var lw: f32 = 0;
        for (line, 0..) |q, v| {
            lw += p.w[idx[q]];
            if (v + 1 < line.len) lw += p.gapBetween(idx, q, line[v + 1]);
        }
        return lw;
    }

    /// O espaço entre duas palavras vizinhas na tela: o que havia entre elas no texto ou, se
    /// não eram vizinhas, o da fronteira entre os trechos.
    fn gapBetween(p: *const Plan, idx: []const u16, q: u16, r: u16) f32 {
        const lo = @min(q, r);
        const hi = @max(q, r);
        const at = if (hi - lo == 1) lo else hi - 1;
        const k = idx[at];
        const next = idx[at + 1];
        return @max(0, p.x[next] - (p.x[k] + p.w[k]));
    }
};

/// Onde começa uma linha de largura `lw` que termina na borda `edge`. Mais larga que a coluna
/// (um balão que não coube, uma palavra enorme): fica no começo, sem passar para a esquerda.
pub fn rightStart(lw: f32, edge: f32) f32 {
    return @max(0, edge - lw);
}

// --- Testes -----------------------------------------------------------------------------

/// Um plano feito à mão: palavras de 50 de largura com 5 de espaço, quebrando a linha nos
/// índices de `breaks`, e um parágrafo novo nos de `paras` (as duas listas em ordem).
fn planOf(p: *Plan, cls: []const bidi.Class, breaks: []const usize, paras: []const usize, indent: f32) void {
    p.reset();
    var x: f32 = indent;
    var y: f32 = 0;
    for (cls, 0..) |c, i| {
        const para = std.mem.indexOfScalar(usize, paras, i) != null;
        const line = i == 0 or para or std.mem.indexOfScalar(usize, breaks, i) != null;
        if (i > 0 and line) {
            x = indent;
            y += 20;
        }
        p.add(x, y, 50, c, para, line, false);
        x += 55;
    }
}

fn expectNear(want: f32, got: f32) !void {
    try std.testing.expectApproxEqAbs(want, got, 0.01);
}

test "parágrafo árabe termina na borda direita" {
    var p: Plan = .{};
    // "السلام عليكم ورحمة الله": 4 palavras, 215 de largura, numa coluna de 400.
    planOf(&p, &.{ .arabic, .arabic, .arabic, .arabic }, &.{}, &.{}, 0);
    p.resolve(400);
    // A primeira palavra do texto é a da direita, encostada na borda.
    try expectNear(350, p.vx[0]);
    try expectNear(295, p.vx[1]);
    try expectNear(240, p.vx[2]);
    try expectNear(185, p.vx[3]);
    try expectNear(400, p.vx[0] + p.w[0]);
    for (0..4) |k| {
        const l = p.lineOf(k).?;
        try std.testing.expect(l.rtl and l.right);
        try expectNear(185, l.lo);
        try expectNear(400, l.hi);
        try std.testing.expectEqual(k == 3, l.last);
    }
    // O espaço entre a primeira e a segunda palavra (na tela, à esquerda da primeira).
    const g = p.lineOf(0).?;
    try expectNear(345, g.gap_lo);
    try expectNear(350, g.gap_hi);
}

test "hebraico em duas linhas: cada uma termina na borda" {
    var p: Plan = .{};
    planOf(&p, &.{ .rtl, .rtl, .rtl, .rtl, .rtl }, &.{3}, &.{}, 0);
    p.resolve(300);
    // Linha 1: palavras 0..2 (160 de largura); linha 2: 3..4 (105).
    try expectNear(250, p.vx[0]);
    try expectNear(140, p.vx[2]);
    try expectNear(250, p.vx[3]);
    try expectNear(195, p.vx[4]);
    try expectNear(140, p.lineOf(0).?.lo);
    try expectNear(195, p.lineOf(4).?.lo);
    try expectNear(300, p.lineOf(4).?.hi);
}

test "texto latino fica onde estava" {
    var p: Plan = .{};
    planOf(&p, &.{ .ltr, .ltr, .number, .ltr }, &.{}, &.{}, 0);
    p.resolve(400);
    for (0..4) |k| {
        try expectNear(p.x[k], p.vx[k]);
        try std.testing.expect(p.lineOf(k) == null);
    }
}

test "parágrafo da esquerda para a direita com hebraico no meio não vai para a direita" {
    var p: Plan = .{};
    // "abc שלום עולם def": só o trecho hebraico vira, e a linha começa no 0.
    planOf(&p, &.{ .ltr, .rtl, .rtl, .ltr }, &.{}, &.{}, 0);
    p.resolve(400);
    try expectNear(0, p.vx[0]);
    try expectNear(110, p.vx[1]);
    try expectNear(55, p.vx[2]);
    try expectNear(165, p.vx[3]);
    const l = p.lineOf(0).?;
    try std.testing.expect(!l.rtl and !l.right);
    try expectNear(0, l.lo);
    try expectNear(215, l.hi);
}

test "mensagem mista: cada parágrafo com o seu alinhamento" {
    var p: Plan = .{};
    // "lyrics and translation:\nكلمات الأغنية على https://… مع الترجمة"
    planOf(&p, &.{ .ltr, .ltr, .ltr, .arabic, .arabic, .arabic, .ltr, .arabic, .arabic }, &.{}, &.{3}, 0);
    p.resolve(600);
    for (0..3) |k| {
        try expectNear(p.x[k], p.vx[k]);
        try std.testing.expect(p.lineOf(k) == null);
    }
    // Segundo parágrafo: 6 pedaços, 325 de largura, terminando em 600; o link (6) fica entre
    // "على" (5) e "مع" (7), na ordem visual da direita para a esquerda.
    try expectNear(550, p.vx[3]);
    try expectNear(275, p.vx[8]);
    try std.testing.expect(p.vx[5] > p.vx[6] and p.vx[6] > p.vx[7]);
    const l = p.lineOf(6).?;
    try std.testing.expect(l.rtl and l.right);
    try expectNear(275, l.lo);
    try expectNear(600, l.hi);
}

test "citação e lista em árabe ficam com o recuo" {
    var p: Plan = .{};
    planOf(&p, &.{ .arabic, .arabic }, &.{}, &.{}, 16);
    p.resolve(400);
    // Ordem visual trocada, mas a linha começa no recuo.
    try expectNear(71, p.vx[0]);
    try expectNear(16, p.vx[1]);
    const l = p.lineOf(0).?;
    try std.testing.expect(l.rtl and !l.right);
    try expectNear(16, l.lo);
}

test "linha mais larga que a coluna não passa da borda esquerda" {
    var p: Plan = .{};
    planOf(&p, &.{ .arabic, .arabic, .arabic }, &.{}, &.{}, 0);
    p.resolve(100);
    try expectNear(0, p.lineOf(0).?.lo);
    try expectNear(0, p.vx[2]);
    try expectNear(0, rightStart(160, 100));
    try expectNear(240, rightStart(160, 400));
}

test "bloco de código não sai do lugar no meio do árabe" {
    var p: Plan = .{};
    p.reset();
    p.add(0, 0, 50, .arabic, true, true, false);
    p.add(55, 0, 50, .arabic, false, false, false);
    // A linha do bloco: largura toda, fixa.
    p.add(0, 20, 400, .ltr, true, true, true);
    p.add(0, 40, 50, .arabic, true, true, false);
    p.resolve(400);
    try expectNear(0, p.vx[2]);
    try std.testing.expect(p.lineOf(2) == null);
    try expectNear(350, p.vx[0]);
    try expectNear(295, p.vx[1]);
    try expectNear(350, p.vx[3]);
}
