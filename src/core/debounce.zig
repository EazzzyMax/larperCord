//! Espera a escolha parar de mudar (Ctrl+Tab segurado, cliques em sequência na
//! lista de canais), sem atrasar quem só escolheu uma vez: depois de `delay_ms`
//! parado, o valor novo sai na hora; numa rajada de trocas, só o último sai,
//! `delay_ms` depois da última. Sem relógio próprio: quem usa passa a hora e
//! acorda em `due()`.
const std = @import("std");

pub fn Debounce(comptime T: type) type {
    return struct {
        const Self = @This();
        value: ?T = null,
        due_ms: i64 = std.math.maxInt(i64),
        /// Hora da última troca (null = nenhuma ainda).
        last_ms: ?i64 = null,
        /// O que saiu por último: a rajada que volta ao mesmo valor não sai de novo.
        sent: ?T = null,

        /// Troca o valor. Depois de `delay_ms` sem troca nenhuma, devolve `v`
        /// para quem chamou mandar já; numa rajada, guarda e recomeça a espera.
        pub fn push(d: *Self, v: T, now_ms: i64, delay_ms: i64) ?T {
            const quiet = if (d.last_ms) |l| now_ms - l >= delay_ms else true;
            d.last_ms = now_ms;
            if (quiet) {
                // O que esperava já venceu e ficou para trás: vale o novo.
                d.value = null;
                d.due_ms = std.math.maxInt(i64);
                d.sent = v;
                return v;
            }
            d.value = v;
            d.due_ms = now_ms + delay_ms;
            return null;
        }

        /// O fim da rajada, se a espera já venceu (e esquece dele).
        pub fn take(d: *Self, now_ms: i64) ?T {
            const v = d.value orelse return null;
            if (now_ms < d.due_ms) return null;
            d.value = null;
            d.due_ms = std.math.maxInt(i64);
            if (d.sent) |s| if (std.meta.eql(s, v)) return null;
            d.sent = v;
            return v;
        }

        /// Quando acordar para `take` (maxInt = nada esperando).
        pub fn due(d: *const Self) i64 {
            return d.due_ms;
        }

        /// Esquece tudo (outra conta): a próxima troca sai na hora.
        pub fn cancel(d: *Self) void {
            d.* = .{};
        }
    };
}

test "parado, sai na hora; numa rajada, só o último, depois da espera" {
    var d: Debounce(u32) = .{};
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    try std.testing.expectEqual(@as(?u32, null), d.take(0));
    // A primeira escolha não espera.
    try std.testing.expectEqual(@as(?u32, 1), d.push(1, 0, 250));
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    // Trocas seguidas esperam a última parar.
    try std.testing.expectEqual(@as(?u32, null), d.push(2, 100, 250));
    try std.testing.expectEqual(@as(?u32, null), d.push(3, 200, 250));
    try std.testing.expectEqual(@as(i64, 450), d.due());
    try std.testing.expectEqual(@as(?u32, null), d.take(449));
    try std.testing.expectEqual(@as(?u32, 3), d.take(450));
    // Saiu uma vez só.
    try std.testing.expectEqual(@as(?u32, null), d.take(10_000));
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    // Parado de novo: a próxima sai na hora.
    try std.testing.expectEqual(@as(?u32, 4), d.push(4, 10_000, 250));
    d.cancel();
    try std.testing.expectEqual(@as(?u32, null), d.take(20_000));
}

test "a espera conta da última troca, não da primeira" {
    var d: Debounce(u32) = .{};
    try std.testing.expectEqual(@as(?u32, 1), d.push(1, 1000, 250));
    // Uma troca a cada 200 ms nunca fica parada 250 ms: nada sai no meio.
    var t: i64 = 1200;
    var v: u32 = 2;
    while (v < 8) : ({
        t += 200;
        v += 1;
    }) {
        try std.testing.expectEqual(@as(?u32, null), d.push(v, t, 250));
        try std.testing.expectEqual(@as(?u32, null), d.take(t + 199));
    }
    const last = t - 200;
    try std.testing.expectEqual(@as(?u32, 7), d.take(last + 250));
    // 250 ms depois da última troca, a seguinte já é escolha nova.
    try std.testing.expectEqual(@as(?u32, 9), d.push(9, last + 250, 250));
}

test "a rajada que volta ao que já saiu não manda de novo" {
    var d: Debounce(u32) = .{};
    try std.testing.expectEqual(@as(?u32, 1), d.push(1, 0, 250));
    try std.testing.expectEqual(@as(?u32, null), d.push(2, 50, 250));
    try std.testing.expectEqual(@as(?u32, null), d.push(1, 100, 250));
    try std.testing.expectEqual(@as(?u32, null), d.take(350));
    try std.testing.expectEqual(std.math.maxInt(i64), d.due());
    // Depois de outra conta, o mesmo valor sai de novo.
    d.cancel();
    try std.testing.expectEqual(@as(?u32, 1), d.push(1, 400, 250));
}

test "funciona com struct (o pedido do op 14)" {
    const Req = struct { guild: u64, channel: u64, thread: u64 };
    var d: Debounce(Req) = .{};
    const a: Req = .{ .guild = 1, .channel = 2, .thread = 0 };
    const b: Req = .{ .guild = 1, .channel = 3, .thread = 0 };
    try std.testing.expectEqual(@as(?Req, a), d.push(a, 0, 250));
    try std.testing.expectEqual(@as(?Req, null), d.push(b, 10, 250));
    try std.testing.expectEqual(@as(?Req, b), d.take(260));
}
