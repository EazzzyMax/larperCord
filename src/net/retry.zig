//! Quanto esperar para conectar de novo. Uma sessão só conta como "funcionou" depois de ficar
//! de pé um tempo: se o servidor aceita e derruba em seguida, voltar direto ao começo vira um
//! IDENTIFY atrás do outro, e o Discord limita quantos cada conta pode fazer por dia.
const std = @import("std");

pub const min_ms: u32 = 2000;
pub const cap_ms: u32 = 60_000;
/// Aceita e derruba sem parar: aí nem adianta insistir a cada minuto.
pub const flapping_cap_ms: u32 = 5 * 60_000;
pub const flapping_after: u32 = 5;
pub const stable_ms: i64 = 60_000;

pub const Retry = struct {
    wait_ms: u32 = min_ms,
    /// Quedas seguidas logo depois de conectar.
    flaps: u32 = 0,
    /// A última sessão ficou de pé (ou ainda não houve nenhuma).
    fresh: bool = true,

    /// `lived_ms`: quanto a sessão durou depois do READY/RESUMED; null se nem chegou lá.
    pub fn sessionEnded(r: *Retry, lived_ms: ?i64) void {
        if (lived_ms) |lived| {
            if (lived >= stable_ms) {
                r.* = .{};
                return;
            }
            r.flaps += 1;
        }
        r.fresh = false;
    }

    /// Acabou de passar do limite de quedas seguidas: hora de avisar a pessoa.
    pub fn justStartedFlapping(r: *const Retry) bool {
        return r.flaps == flapping_after;
    }

    /// A próxima espera, 20% para mais ou para menos, para muitos clientes caindo juntos não
    /// voltarem juntos. A seguinte dobra.
    pub fn next(r: *Retry, random: std.Random) u32 {
        const wait = r.wait_ms;
        const cap: u32 = if (r.flaps >= flapping_after) flapping_cap_ms else cap_ms;
        r.wait_ms = @min(wait * 2, cap);
        const spread = wait / 5;
        return wait - spread + random.uintLessThan(u32, spread * 2 + 1);
    }
};

const testing = std.testing;

fn prng() std.Random.DefaultPrng {
    return std.Random.DefaultPrng.init(7);
}

test "cair logo depois de conectar não zera a espera" {
    var p = prng();
    var r: Retry = .{};
    var last: u32 = 0;
    for (0..4) |_| {
        r.sessionEnded(1000);
        last = r.next(p.random());
    }
    try testing.expect(!r.fresh);
    // 2, 4, 8, 16 s: antes, cada queda dessas esperava 1 s para sempre.
    try testing.expect(last >= 16_000 * 8 / 10 and last <= 16_000 * 12 / 10);
}

test "só uma sessão estável volta ao começo" {
    var p = prng();
    var r: Retry = .{};
    for (0..3) |_| {
        r.sessionEnded(30_000);
        _ = r.next(p.random());
    }
    r.sessionEnded(stable_ms);
    try testing.expect(r.fresh);
    try testing.expectEqual(0, r.flaps);
    try testing.expectEqual(min_ms, r.wait_ms);
}

test "sem rede para em 1 minuto, para voltar logo quando a internet voltar" {
    var p = prng();
    var r: Retry = .{};
    for (0..12) |_| {
        r.sessionEnded(null);
        _ = r.next(p.random());
    }
    try testing.expectEqual(cap_ms, r.wait_ms);
    try testing.expectEqual(0, r.flaps);
}

test "aceitar e derrubar sem parar sobe até 5 minutos e avisa uma vez" {
    var p = prng();
    var r: Retry = .{};
    var warned: u32 = 0;
    for (0..12) |_| {
        r.sessionEnded(500);
        if (r.justStartedFlapping()) warned += 1;
        _ = r.next(p.random());
    }
    try testing.expectEqual(1, warned);
    try testing.expectEqual(flapping_cap_ms, r.wait_ms);
}

test "a espera varia no máximo 20%" {
    var p = prng();
    for (0..200) |_| {
        var r: Retry = .{};
        const w = r.next(p.random());
        try testing.expect(w >= 1600 and w <= 2400);
    }
}
