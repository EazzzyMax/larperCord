//! Espera a escolha parar de mudar: só o último valor sai, `delay_ms` depois da
//! última troca (Ctrl+Tab segurado, cliques em sequência na lista de canais).
//! Sem relógio próprio: quem usa passa a hora e acorda em `due()`.
const std = @import("std");

pub fn Debounce(comptime T: type) type {
    return struct {
        const Self = @This();
        value: ?T = null,
        due_ms: i64 = std.math.maxInt(i64),

        /// Troca o que vai sair e recomeça a espera.
        pub fn set(d: *Self, v: T, now_ms: i64, delay_ms: i64) void {
            d.value = v;
            d.due_ms = now_ms + delay_ms;
        }

        /// O valor, se a espera já venceu (e esquece dele).
        pub fn take(d: *Self, now_ms: i64) ?T {
            if (d.value == null or now_ms < d.due_ms) return null;
            const v = d.value;
            d.cancel();
            return v;
        }

        /// Quando acordar para `take` (maxInt = nada esperando).
        pub fn due(d: *const Self) i64 {
            return d.due_ms;
        }

        pub fn cancel(d: *Self) void {
            d.value = null;
            d.due_ms = std.math.maxInt(i64);
        }
    };
}

test "só o último sai, depois da espera" {
    var d: Debounce(u32) = .{};
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    try std.testing.expectEqual(@as(?u32, null), d.take(0));
    d.set(1, 0, 250);
    d.set(2, 100, 250);
    d.set(3, 200, 250);
    try std.testing.expectEqual(@as(i64, 450), d.due());
    try std.testing.expectEqual(@as(?u32, null), d.take(449));
    try std.testing.expectEqual(@as(?u32, 3), d.take(450));
    // Saiu uma vez só.
    try std.testing.expectEqual(@as(?u32, null), d.take(10_000));
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    d.set(4, 0, 250);
    d.cancel();
    try std.testing.expectEqual(@as(?u32, null), d.take(10_000));
}
