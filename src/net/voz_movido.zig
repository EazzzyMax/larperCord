//! Alguém nos moveu de canal de voz: o VOICE_STATE_UPDATE da própria conta
//! chega com outro canal sem um op 4 nosso. A conexão de voz segue, ou cai
//! com 4014/4022 e volta pelo VOICE_SERVER_UPDATE. Se em vez disso ela
//! terminar de vez logo depois (servidor trocado, sessão que não vale no
//! canal novo), o gateway pede o canal novo de novo, uma vez, em vez de sair
//! da call. Lógica pura: quem usa é net/discord.zig.
const std = @import("std");

/// Até quanto tempo depois de sermos movidos uma queda conta como parte da troca.
pub const grace_ms: i64 = 20_000;

pub const Movido = struct {
    at: ?i64 = null,
    rejoined: bool = false,

    /// O Discord nos moveu agora.
    pub fn moved(m: *Movido, now: i64) void {
        m.* = .{ .at = now };
    }

    /// Entrar ou sair por conta própria encerra a troca.
    pub fn clear(m: *Movido) void {
        m.* = .{};
    }

    /// A voz terminou de vez: true = pedir o canal de novo (uma vez por troca).
    pub fn takeRejoin(m: *Movido, now: i64) bool {
        const at = m.at orelse return false;
        if (m.rejoined or now - at > grace_ms) return false;
        m.rejoined = true;
        return true;
    }
};

const t = std.testing;

test "queda logo depois de ser movido: pede o canal de novo, uma vez só" {
    var m: Movido = .{};
    m.moved(1000);
    try t.expect(m.takeRejoin(1500));
    try t.expect(!m.takeRejoin(1600));
}

test "sem troca, ou passado o prazo, a queda é queda" {
    var m: Movido = .{};
    try t.expect(!m.takeRejoin(1000));
    m.moved(1000);
    try t.expect(!m.takeRejoin(1000 + grace_ms + 1));
}

test "entrar ou sair por conta própria encerra a troca; ser movido de novo reabre" {
    var m: Movido = .{};
    m.moved(1000);
    m.clear();
    try t.expect(!m.takeRejoin(1100));
    m.moved(2000);
    try t.expect(m.takeRejoin(2100));
    m.moved(3000);
    try t.expect(m.takeRejoin(3100));
}
