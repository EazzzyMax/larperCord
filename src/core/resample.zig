//! Redução de imagem com filtro bicúbico (Catmull-Rom), para fotos de perfil, ícones e imagens
//! paradas ficarem nítidas no tamanho em que aparecem. A placa de vídeo sozinha, sem mipmaps,
//! só olha 4 pixels por ponto: reduzindo 3 vezes, pula o resto e a imagem sai serrilhada.
const std = @import("std");

fn catmullRom(x: f32) f32 {
    const t = @abs(x);
    if (t < 1) return (1.5 * t - 2.5) * t * t + 1;
    if (t < 2) return ((-0.5 * t + 2.5) * t - 4) * t + 2;
    return 0;
}

const Taps = struct {
    first: []u32,
    count: []u32,
    start: []u32,
    weights: []f32,

    /// Quais pixels de origem entram em cada pixel de destino, e com que peso.
    fn init(gpa: std.mem.Allocator, src_n: usize, dst_n: usize) !Taps {
        const ratio = @max(@as(f32, @floatFromInt(src_n)) / @as(f32, @floatFromInt(dst_n)), 1);
        const support = 2 * ratio;
        const per_dst: usize = @intFromFloat(@ceil(support * 2) + 2);
        var t: Taps = .{
            .first = try gpa.alloc(u32, dst_n),
            .count = try gpa.alloc(u32, dst_n),
            .start = try gpa.alloc(u32, dst_n),
            .weights = try gpa.alloc(f32, dst_n * per_dst),
        };
        const scale = @as(f32, @floatFromInt(src_n)) / @as(f32, @floatFromInt(dst_n));
        var at: u32 = 0;
        for (0..dst_n) |d| {
            const center = (@as(f32, @floatFromInt(d)) + 0.5) * scale;
            const lo: usize = @intFromFloat(@max(@floor(center - support), 0));
            const hi: usize = @min(@as(usize, @intFromFloat(@ceil(center + support))), src_n);
            t.first[d] = @intCast(lo);
            t.start[d] = at;
            var total: f32 = 0;
            var n: u32 = 0;
            for (lo..hi) |i| {
                if (n == per_dst) break;
                const w = catmullRom((@as(f32, @floatFromInt(i)) + 0.5 - center) / ratio);
                t.weights[at + n] = w;
                total += w;
                n += 1;
            }
            for (t.weights[at .. at + n]) |*w| w.* /= total;
            t.count[d] = n;
            at += n;
        }
        return t;
    }

    fn deinit(t: Taps, gpa: std.mem.Allocator) void {
        gpa.free(t.first);
        gpa.free(t.count);
        gpa.free(t.start);
        gpa.free(t.weights);
    }
};

/// Reduz `src` (RGBA, sw×sh) para `dst` (dw×dh). As cores são ponderadas pelo alfa: o fundo
/// transparente de uma foto de perfil não vaza para a borda.
pub fn bicubic(gpa: std.mem.Allocator, src: []const u8, sw: usize, sh: usize, dst: []u8, dw: usize, dh: usize) !void {
    const across = try Taps.init(gpa, sw, dw);
    defer across.deinit(gpa);
    const down = try Taps.init(gpa, sh, dh);
    defer down.deinit(gpa);
    // Primeiro na horizontal, para um meio do caminho com a largura final e a altura original.
    const mid = try gpa.alloc(f32, dw * sh * 4);
    defer gpa.free(mid);
    for (0..sh) |y| {
        const row = src[y * sw * 4 ..];
        for (0..dw) |x| {
            var acc: [4]f32 = .{ 0, 0, 0, 0 };
            const first = across.first[x];
            for (across.weights[across.start[x]..][0..across.count[x]], first..) |w, i| {
                const p = row[i * 4 ..][0..4];
                const a = @as(f32, @floatFromInt(p[3])) * w;
                acc[0] += @as(f32, @floatFromInt(p[0])) * a;
                acc[1] += @as(f32, @floatFromInt(p[1])) * a;
                acc[2] += @as(f32, @floatFromInt(p[2])) * a;
                acc[3] += a;
            }
            @memcpy(mid[(y * dw + x) * 4 ..][0..4], &acc);
        }
    }
    for (0..dh) |y| {
        const first = down.first[y];
        for (0..dw) |x| {
            var acc: [4]f32 = .{ 0, 0, 0, 0 };
            for (down.weights[down.start[y]..][0..down.count[y]], first..) |w, sy| {
                const p = mid[(sy * dw + x) * 4 ..][0..4];
                for (&acc, p) |*o, v| o.* += v * w;
            }
            const o = dst[(y * dw + x) * 4 ..][0..4];
            // O filtro passa um pouco de 0 e de 255 nas bordas fortes: é o que dá a nitidez.
            const alpha = std.math.clamp(acc[3], 0, 255);
            if (alpha < 0.5) {
                o.* = .{ 0, 0, 0, 0 };
                continue;
            }
            for (0..3) |k| o[k] = @intFromFloat(std.math.clamp(acc[k] / acc[3], 0, 255) + 0.5);
            o[3] = @intFromFloat(alpha + 0.5);
        }
    }
}

test "cor lisa continua igual, em qualquer proporção" {
    const gpa = std.testing.allocator;
    var src: [128 * 128 * 4]u8 = undefined;
    for (0..128 * 128) |i| src[i * 4 ..][0..4].* = .{ 200, 100, 50, 255 };
    var dst: [40 * 25 * 4]u8 = undefined;
    try bicubic(gpa, &src, 128, 128, &dst, 40, 25);
    for (0..40 * 25) |i| try std.testing.expectEqualSlices(u8, &.{ 200, 100, 50, 255 }, dst[i * 4 ..][0..4]);
}

test "o fundo transparente não vaza cor para a borda" {
    const gpa = std.testing.allocator;
    // Metade branca opaca, metade vermelha totalmente transparente.
    var src: [64 * 64 * 4]u8 = undefined;
    for (0..64) |y| for (0..64) |x| {
        src[(y * 64 + x) * 4 ..][0..4].* = if (x < 32) .{ 255, 255, 255, 255 } else .{ 255, 0, 0, 0 };
    };
    var dst: [16 * 16 * 4]u8 = undefined;
    try bicubic(gpa, &src, 64, 64, &dst, 16, 16);
    for (0..16 * 16) |i| {
        const p = dst[i * 4 ..][0..4];
        if (p[3] == 0) continue;
        // Nenhum pixel visível pode puxar para o vermelho do fundo escondido.
        try std.testing.expect(p[1] >= 250 and p[2] >= 250);
    }
    try std.testing.expectEqual(255, dst[(8 * 16 + 1) * 4 + 3]);
    try std.testing.expectEqual(0, dst[(8 * 16 + 14) * 4 + 3]);
}

test "a borda fica mais marcada que na média simples" {
    const gpa = std.testing.allocator;
    // Linha preta de 4 pixels em fundo branco, reduzida 4 vezes.
    var src: [64 * 8 * 4]u8 = undefined;
    for (0..8) |y| for (0..64) |x| {
        const v: u8 = if (x >= 30 and x < 34) 0 else 255;
        src[(y * 64 + x) * 4 ..][0..4].* = .{ v, v, v, 255 };
    };
    var dst: [16 * 2 * 4]u8 = undefined;
    try bicubic(gpa, &src, 64, 8, &dst, 16, 2);
    var darkest: u8 = 255;
    for (0..16) |x| darkest = @min(darkest, dst[x * 4]);
    // Na média simples a linha, dividida entre dois pixels, não passaria de 128.
    try std.testing.expect(darkest < 128);
}
