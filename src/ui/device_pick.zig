//! Contas do menu rápido de dispositivos (ui/device_menu.zig), sem ImGui nem
//! SDL, para os testes.
const std = @import("std");

/// Quantas linhas mostrar de uma lista com `total` linhas quando cabem `cap`:
/// sem espaço para todas, a última vira "+N em Configurações → Voz".
pub fn visibleRows(total: usize, cap: usize) struct { shown: usize, more: usize } {
    const room = @max(cap, 2);
    if (total <= room) return .{ .shown = total, .more = 0 };
    return .{ .shown = room - 1, .more = total - (room - 1) };
}

/// Posição do mouse no trilho para o volume guardado (0 a 200%).
pub fn gainAt(mouse_x: f32, track_x: f32, track_w: f32) u8 {
    if (track_w <= 0) return 100;
    return @intFromFloat(@round(std.math.clamp((mouse_x - track_x) / track_w, 0, 1) * 200));
}

/// O escolhido não está ligado agora (`list` tem `n` e `slice(i)`): ele aparece
/// na lista assim mesmo, marcado, para não parecer que nada está escolhido.
pub fn missing(list: anytype, saved: []const u8) bool {
    if (saved.len == 0) return false;
    for (0..list.n) |i| if (std.mem.eql(u8, list.slice(i), saved)) return false;
    return true;
}

test "linhas visíveis: cabe tudo ou a última vira o link" {
    const a = visibleRows(4, 10);
    try std.testing.expectEqual(@as(usize, 4), a.shown);
    try std.testing.expectEqual(@as(usize, 0), a.more);
    const b = visibleRows(17, 6);
    try std.testing.expectEqual(@as(usize, 5), b.shown);
    try std.testing.expectEqual(@as(usize, 12), b.more);
    try std.testing.expectEqual(@as(usize, 17), b.shown + b.more);
    // Mesmo sem espaço nenhum, sobra o padrão do sistema e o link.
    const z = visibleRows(17, 0);
    try std.testing.expectEqual(@as(usize, 1), z.shown);
    try std.testing.expectEqual(@as(usize, 16), z.more);
}

test "volume pela posição no trilho" {
    try std.testing.expectEqual(@as(u8, 0), gainAt(-50, 0, 100));
    try std.testing.expectEqual(@as(u8, 100), gainAt(50, 0, 100));
    try std.testing.expectEqual(@as(u8, 200), gainAt(500, 0, 100));
    try std.testing.expectEqual(@as(u8, 151), gainAt(75.4, 0, 100));
    try std.testing.expectEqual(@as(u8, 100), gainAt(10, 0, 0));
}

test "escolhido que sumiu continua na lista" {
    const L = struct {
        names: []const []const u8,
        n: usize,
        fn slice(l: *const @This(), i: usize) []const u8 {
            return l.names[i];
        }
    };
    const l: L = .{ .names = &.{"Fone USB"}, .n = 1 };
    try std.testing.expect(!missing(&l, ""));
    try std.testing.expect(!missing(&l, "Fone USB"));
    try std.testing.expect(missing(&l, "Saída HDMI"));
}
