//! Teto de envio do gateway. O Discord aceita 120 eventos por conexão a cada
//! 60 s e derruba quem passa disso (docs.discord.food, "Rate Limiting"); o
//! op 8 tem limite próprio, mas o app não usa. A presença ainda fica em 5 a
//! cada 20 s por conta nossa (a doc não dá número; trocar de status mais que
//! isso não tem porquê). Aqui:
//!  - heartbeat (op 1), IDENTIFY (op 2) e RESUME (op 6) saem sempre e na hora:
//!    contam no teto, mas nada os segura (`Budget.note` direto, sem fila);
//!  - o resto para em 110 por janela: a folga até 120 é deles;
//!  - presença (op 3) e lista de membros (op 14) se juntam: só o último pedido
//!    de cada um (op 14: por servidor) sai quando houver vez;
//!  - estado de voz (op 4) entra numa fila e sai na ordem, sem perder nenhum.
//! Lógica pura: quem escreve no WebSocket é net/discord.zig.
const std = @import("std");
const types = @import("../core/types.zig");
const Id = types.Id;

pub const window_ms: i64 = 60_000;
/// O que não é heartbeat/IDENTIFY/RESUME: até aqui por janela.
pub const normal_limit: usize = 110;
pub const presence_limit: usize = 5;
pub const presence_window_ms: i64 = 20_000;

/// As últimas `N` vezes que algo saiu (janela deslizante).
fn Ring(comptime N: usize) type {
    return struct {
        const Self = @This();
        t: [N]i64 = undefined,
        head: usize = 0,
        len: usize = 0,

        fn prune(r: *Self, now_ms: i64, window: i64) void {
            while (r.len > 0 and now_ms - r.t[r.head] >= window) {
                r.head = (r.head + 1) % N;
                r.len -= 1;
            }
        }

        /// Cheio, esquece o mais antigo (a conta só fica mais conservadora).
        fn push(r: *Self, now_ms: i64) void {
            if (r.len == N) {
                r.head = (r.head + 1) % N;
                r.len -= 1;
            }
            r.t[(r.head + r.len) % N] = now_ms;
            r.len += 1;
        }

        fn count(r: *Self, now_ms: i64, window: i64) usize {
            r.prune(now_ms, window);
            return r.len;
        }

        /// Quando o mais antigo sai da janela.
        fn oldestExpires(r: *const Self, window: i64) i64 {
            return if (r.len == 0) 0 else r.t[r.head] + window;
        }
    };
}

pub const Budget = struct {
    /// Cabe tudo o que sai numa janela (110 comuns + os de prioridade).
    sent: Ring(128) = .{},

    /// Algo saiu agora (qualquer op, inclusive heartbeat).
    pub fn note(b: *Budget, now_ms: i64) void {
        b.sent.push(now_ms);
    }

    pub fn used(b: *Budget, now_ms: i64) usize {
        return b.sent.count(now_ms, window_ms);
    }

    /// Um op comum pode sair agora?
    pub fn allows(b: *Budget, now_ms: i64) bool {
        return b.used(now_ms) < normal_limit;
    }

    /// Quando um op comum pode sair (agora, se já pode).
    pub fn freeAt(b: *Budget, now_ms: i64) i64 {
        if (b.allows(now_ms)) return now_ms;
        // Passou de 110 só com heartbeats no meio: espera sair o bastante.
        const extra = b.sent.len - normal_limit;
        return b.sent.t[(b.sent.head + extra) % b.sent.t.len] + window_ms;
    }

    /// Conexão nova: o Discord conta do zero.
    pub fn reset(b: *Budget) void {
        b.sent = .{};
    }
};

/// Op 14: a lista de membros de um servidor vista de um canal (e de uma thread).
pub const Lazy = struct { guild: Id, channel: Id, thread: Id = 0 };
/// Op 4: entrar, sair ou mudar mudo/surdo (`channel` null = sair).
pub const Voice = struct {
    guild: Id,
    channel: ?Id,
    mute: bool = false,
    deaf: bool = false,

    /// O VOICE_STATE_UPDATE da própria conta mostra que este op 4 chegou ao Discord. Saindo,
    /// basta o canal vazio.
    pub fn confirmedBy(v: Voice, channel: ?Id, self_mute: bool, self_deaf: bool) bool {
        const want = v.channel orelse return channel == null;
        const got = channel orelse return false;
        return got == want and v.mute == self_mute and v.deaf == self_deaf;
    }
};
/// O que espera vez. A presença sai com o status do momento (só o último vale).
pub const Item = union(enum) { presence, lazy: Lazy, voice: Voice };

pub const Push = enum {
    queued,
    /// Juntou com um pedido do mesmo tipo que ainda não tinha saído.
    coalesced,
    /// A fila de voz encheu: o último estado de voz pendente virou este
    /// (o estado final é o mesmo). Quem chama registra.
    merged,
    /// Muitos servidores com op 14 pendente: o mais antigo deu lugar a este.
    replaced_oldest,
};

pub const Outbox = struct {
    budget: Budget = .{},
    presence_sent: Ring(presence_limit) = .{},
    presence: bool = false,
    /// Na ordem em que chegaram (o mesmo servidor de novo vai para o fim).
    lazy: [8]Lazy = undefined,
    lazy_n: usize = 0,
    voice: [64]Voice = undefined,
    voice_head: usize = 0,
    voice_n: usize = 0,

    pub fn push(o: *Outbox, it: Item) Push {
        switch (it) {
            .presence => {
                const was = o.presence;
                o.presence = true;
                return if (was) .coalesced else .queued;
            },
            .lazy => |l| {
                for (o.lazy[0..o.lazy_n], 0..) |x, i| if (x.guild == l.guild) {
                    std.mem.copyForwards(Lazy, o.lazy[i .. o.lazy_n - 1], o.lazy[i + 1 .. o.lazy_n]);
                    o.lazy[o.lazy_n - 1] = l;
                    return .coalesced;
                };
                if (o.lazy_n == o.lazy.len) {
                    std.mem.copyForwards(Lazy, o.lazy[0 .. o.lazy.len - 1], o.lazy[1..]);
                    o.lazy[o.lazy.len - 1] = l;
                    return .replaced_oldest;
                }
                o.lazy[o.lazy_n] = l;
                o.lazy_n += 1;
                return .queued;
            },
            .voice => |v| {
                if (o.voice_n == o.voice.len) {
                    o.voice[(o.voice_head + o.voice_n - 1) % o.voice.len] = v;
                    return .merged;
                }
                o.voice[(o.voice_head + o.voice_n) % o.voice.len] = v;
                o.voice_n += 1;
                return .queued;
            },
        }
    }

    pub fn pending(o: *const Outbox) usize {
        return o.voice_n + o.lazy_n + @intFromBool(o.presence);
    }

    fn presenceOk(o: *Outbox, now_ms: i64) bool {
        return o.presence_sent.count(now_ms, presence_window_ms) < presence_limit;
    }

    /// O próximo que pode sair agora (já contado no teto). Voz primeiro (é a
    /// pessoa esperando a call), depois presença, depois listas de membros.
    pub fn pop(o: *Outbox, now_ms: i64) ?Item {
        if (o.pending() == 0 or !o.budget.allows(now_ms)) return null;
        var it: Item = undefined;
        if (o.voice_n > 0) {
            it = .{ .voice = o.voice[o.voice_head] };
            o.voice_head = (o.voice_head + 1) % o.voice.len;
            o.voice_n -= 1;
        } else if (o.presence and o.presenceOk(now_ms)) {
            o.presence = false;
            o.presence_sent.push(now_ms);
            it = .presence;
        } else if (o.lazy_n > 0) {
            it = .{ .lazy = o.lazy[0] };
            std.mem.copyForwards(Lazy, o.lazy[0 .. o.lazy_n - 1], o.lazy[1..o.lazy_n]);
            o.lazy_n -= 1;
        } else return null;
        o.budget.note(now_ms);
        return it;
    }

    /// Devolve à frente da fila um item que `pop` tirou e que não chegou a sair (a escrita
    /// no WebSocket falhou): sai de novo depois do RESUME, na mesma ordem. O teto não é
    /// devolvido: a conexão cai e a próxima começa do zero (`newConnection`).
    pub fn unpop(o: *Outbox, it: Item) void {
        switch (it) {
            .presence => o.presence = true,
            .lazy => |l| {
                // Um pedido mais novo do mesmo servidor já está na fila: vale ele.
                for (o.lazy[0..o.lazy_n]) |x| if (x.guild == l.guild) return;
                // Cheia de pedidos mais novos: este era o mais antigo.
                if (o.lazy_n == o.lazy.len) return;
                std.mem.copyBackwards(Lazy, o.lazy[1 .. o.lazy_n + 1], o.lazy[0..o.lazy_n]);
                o.lazy[0] = l;
                o.lazy_n += 1;
            },
            .voice => |v| {
                // Logo depois de um `pop` sempre cabe; cheia, os estados mais novos valem.
                if (o.voice_n == o.voice.len) return;
                o.voice_head = (o.voice_head + o.voice.len - 1) % o.voice.len;
                o.voice[o.voice_head] = v;
                o.voice_n += 1;
            },
        }
    }

    /// Manda o que tem vez agora por `w.write(item)` (false = não saiu): para na primeira
    /// falha, com o item de volta na frente da fila e o resto esperando atrás dele.
    pub fn drainTo(o: *Outbox, now_ms: i64, w: anytype) void {
        while (o.pop(now_ms)) |it| if (!w.write(it)) {
            o.unpop(it);
            return;
        };
    }

    /// Quando acordar para `pop` (maxInt = nada esperando).
    pub fn due(o: *Outbox, now_ms: i64) i64 {
        if (o.pending() == 0) return std.math.maxInt(i64);
        const free = o.budget.freeAt(now_ms);
        if (o.voice_n > 0 or o.lazy_n > 0) return free;
        // Só a presença: espera também o limite dela.
        return if (o.presenceOk(now_ms)) free else @max(free, o.presence_sent.oldestExpires(presence_window_ms));
    }

    /// Conexão nova: os limites recomeçam; o que espera continua esperando.
    pub fn newConnection(o: *Outbox) void {
        o.budget.reset();
        o.presence_sent = .{};
    }

    /// Sessão nova (READY): o que esperava era da anterior. Quem chama manda de
    /// novo o que ainda vale (voz, lista de membros; a presença foi no IDENTIFY).
    /// Os limites ficam: a conexão é a mesma.
    pub fn forgetPending(o: *Outbox) void {
        o.presence = false;
        o.lazy_n = 0;
        o.voice_n = 0;
        o.voice_head = 0;
    }

    pub fn clear(o: *Outbox) void {
        o.* = .{};
    }
};

// --- Testes -------------------------------------------------------------------

const t = std.testing;

test "o teto para em 110 e libera quando a janela anda" {
    var b: Budget = .{};
    for (0..normal_limit) |i| {
        try t.expect(b.allows(1000 + @as(i64, @intCast(i))));
        b.note(1000 + @as(i64, @intCast(i)));
    }
    try t.expect(!b.allows(2000));
    try t.expectEqual(@as(i64, 1000 + window_ms), b.freeAt(2000));
    try t.expect(b.allows(1000 + window_ms));
    b.reset();
    try t.expectEqual(@as(usize, 0), b.used(0));
}

test "heartbeat, IDENTIFY e RESUME passam com o teto cheio e cabem nos 120" {
    var o: Outbox = .{};
    var now: i64 = 0;
    // Uma enxurrada de pedidos comuns: só 110 saem na janela.
    var sent: usize = 0;
    for (0..300) |i| {
        _ = o.push(.{ .voice = .{ .guild = 1, .channel = @intCast(i % 3) } });
        while (o.pop(now)) |_| sent += 1;
        now += 10;
    }
    try t.expectEqual(normal_limit, sent);
    // Os de prioridade não perguntam ao teto: saem na hora e são contados.
    for (0..10) |_| o.budget.note(now);
    try t.expect(o.budget.used(now) <= 120);
    // E nada comum sai até a janela andar.
    try t.expectEqual(@as(?Item, null), o.pop(now));
}

test "op 14 e presença: só o último de cada um sai" {
    var o: Outbox = .{};
    // Teto cheio: tudo espera.
    for (0..normal_limit) |_| o.budget.note(0);
    try t.expectEqual(Push.queued, o.push(.{ .lazy = .{ .guild = 1, .channel = 10 } }));
    try t.expectEqual(Push.coalesced, o.push(.{ .lazy = .{ .guild = 1, .channel = 11 } }));
    try t.expectEqual(Push.queued, o.push(.{ .lazy = .{ .guild = 2, .channel = 20 } }));
    try t.expectEqual(Push.coalesced, o.push(.{ .lazy = .{ .guild = 1, .channel = 12, .thread = 99 } }));
    try t.expectEqual(Push.queued, o.push(.presence));
    try t.expectEqual(Push.coalesced, o.push(.presence));
    try t.expectEqual(Push.coalesced, o.push(.presence));
    try t.expectEqual(@as(usize, 3), o.pending());
    try t.expectEqual(@as(?Item, null), o.pop(10));
    try t.expectEqual(window_ms, o.due(10));
    const later = window_ms;
    try t.expectEqual(Item.presence, o.pop(later).?);
    // O servidor 2 pediu antes do último pedido do 1.
    try t.expectEqual(@as(Id, 20), o.pop(later).?.lazy.channel);
    const l1 = o.pop(later).?.lazy;
    try t.expectEqual(@as(Id, 12), l1.channel);
    try t.expectEqual(@as(Id, 99), l1.thread);
    try t.expectEqual(@as(?Item, null), o.pop(later));
    try t.expectEqual(std.math.maxInt(i64), o.due(later));
}

test "presença: no máximo 5 a cada 20 s, sem segurar o resto" {
    var o: Outbox = .{};
    var now: i64 = 0;
    for (0..presence_limit) |_| {
        _ = o.push(.presence);
        try t.expectEqual(Item.presence, o.pop(now).?);
        now += 100;
    }
    _ = o.push(.presence);
    _ = o.push(.{ .lazy = .{ .guild = 3, .channel = 30 } });
    // A sexta presença espera; a lista de membros não.
    try t.expectEqual(@as(Id, 30), o.pop(now).?.lazy.channel);
    try t.expectEqual(@as(?Item, null), o.pop(now));
    try t.expectEqual(presence_window_ms, o.due(now));
    try t.expectEqual(Item.presence, o.pop(presence_window_ms).?);
}

test "op 4 nunca se perde: sai tudo, na ordem" {
    var o: Outbox = .{};
    for (0..normal_limit) |_| o.budget.note(0);
    for (0..40) |i| try t.expectEqual(Push.queued, o.push(.{ .voice = .{ .guild = 5, .channel = @intCast(i), .mute = i % 2 == 0 } }));
    try t.expectEqual(@as(?Item, null), o.pop(1));
    var got: usize = 0;
    while (o.pop(window_ms)) |it| : (got += 1) {
        try t.expectEqual(@as(?Id, got), it.voice.channel);
        try t.expectEqual(got % 2 == 0, it.voice.mute);
    }
    try t.expectEqual(@as(usize, 40), got);
}

test "op 4: fila cheia guarda o último estado no lugar do penúltimo" {
    var o: Outbox = .{};
    for (0..normal_limit) |_| o.budget.note(0);
    for (0..o.voice.len) |i| _ = o.push(.{ .voice = .{ .guild = 5, .channel = @intCast(i) } });
    try t.expectEqual(Push.merged, o.push(.{ .voice = .{ .guild = 5, .channel = null } }));
    try t.expectEqual(o.voice.len, o.pending());
    var last: ?Voice = null;
    while (o.pop(window_ms)) |it| last = it.voice;
    try t.expectEqual(@as(?Id, null), last.?.channel);
}

test "op 14 de muitos servidores: o mais antigo dá lugar" {
    var o: Outbox = .{};
    for (0..normal_limit) |_| o.budget.note(0);
    for (0..8) |i| _ = o.push(.{ .lazy = .{ .guild = @intCast(i + 1), .channel = 1 } });
    try t.expectEqual(Push.replaced_oldest, o.push(.{ .lazy = .{ .guild = 100, .channel = 1 } }));
    try t.expectEqual(@as(Id, 2), o.pop(window_ms).?.lazy.guild);
}

test "escrita que falha devolve o item: nada se perde e a ordem fica" {
    const Fake = struct {
        fail_at: usize,
        n: usize = 0,
        got: [16]Item = undefined,

        pub fn write(f: *@This(), it: Item) bool {
            if (f.n == f.fail_at) {
                f.fail_at = std.math.maxInt(usize);
                return false;
            }
            f.got[f.n] = it;
            f.n += 1;
            return true;
        }
    };
    var o: Outbox = .{};
    _ = o.push(.{ .voice = .{ .guild = 1, .channel = 10, .mute = true } });
    _ = o.push(.{ .voice = .{ .guild = 1, .channel = null } });
    _ = o.push(.presence);
    _ = o.push(.{ .lazy = .{ .guild = 7, .channel = 70 } });
    _ = o.push(.{ .lazy = .{ .guild = 8, .channel = 80 } });
    // A segunda escrita (sair da call) falha: o flush para e nada depois dela sai.
    var w: Fake = .{ .fail_at = 1 };
    o.drainTo(0, &w);
    try t.expectEqual(@as(usize, 1), w.n);
    try t.expectEqual(@as(?Id, 10), w.got[0].voice.channel);
    try t.expectEqual(@as(usize, 4), o.pending());
    // Depois do RESUME o resto sai na ordem de antes, começando pelo que falhou.
    o.newConnection();
    o.drainTo(1, &w);
    try t.expectEqual(@as(usize, 5), w.n);
    try t.expectEqual(@as(?Id, null), w.got[1].voice.channel);
    try t.expectEqual(Item.presence, w.got[2]);
    try t.expectEqual(@as(Id, 7), w.got[3].lazy.guild);
    try t.expectEqual(@as(Id, 8), w.got[4].lazy.guild);
    try t.expectEqual(@as(usize, 0), o.pending());
}

test "item devolvido: um pedido mais novo do mesmo servidor vence; voz volta para a frente" {
    var o: Outbox = .{};
    _ = o.push(.{ .lazy = .{ .guild = 1, .channel = 10 } });
    const old = o.pop(0).?;
    _ = o.push(.{ .lazy = .{ .guild = 1, .channel = 11 } });
    o.unpop(old);
    try t.expectEqual(@as(usize, 1), o.pending());
    try t.expectEqual(@as(Id, 11), o.pop(0).?.lazy.channel);
    // Voz com a fila dando a volta no anel: o devolvido sai antes dos que esperam.
    for (0..o.voice.len - 1) |_| {
        _ = o.push(.{ .voice = .{ .guild = 2, .channel = 1 } });
        _ = o.pop(0);
    }
    _ = o.push(.{ .voice = .{ .guild = 2, .channel = 20 } });
    _ = o.push(.{ .voice = .{ .guild = 2, .channel = 21 } });
    const v = o.pop(window_ms).?;
    o.unpop(v);
    try t.expectEqual(@as(?Id, 20), o.pop(window_ms).?.voice.channel);
    try t.expectEqual(@as(?Id, 21), o.pop(window_ms).?.voice.channel);
}

test "o VOICE_STATE_UPDATE da conta confirma o op 4" {
    const join: Voice = .{ .guild = 1, .channel = 5, .mute = true };
    try t.expect(join.confirmedBy(5, true, false));
    try t.expect(!join.confirmedBy(5, false, false));
    try t.expect(!join.confirmedBy(6, true, false));
    try t.expect(!join.confirmedBy(null, true, false));
    const leave: Voice = .{ .guild = 1, .channel = null };
    try t.expect(leave.confirmedBy(null, true, true));
    try t.expect(!leave.confirmedBy(5, false, false));
}

test "conexão nova zera os limites e mantém a fila" {
    var o: Outbox = .{};
    for (0..normal_limit) |_| o.budget.note(0);
    _ = o.push(.{ .voice = .{ .guild = 1, .channel = 2 } });
    try t.expectEqual(@as(?Item, null), o.pop(5));
    o.newConnection();
    try t.expectEqual(@as(?Id, 2), o.pop(5).?.voice.channel);
    _ = o.push(.presence);
    _ = o.push(.{ .lazy = .{ .guild = 1, .channel = 2 } });
    o.forgetPending();
    try t.expectEqual(@as(usize, 0), o.pending());
    try t.expectEqual(@as(usize, 1), o.budget.used(5));
    o.clear();
    try t.expectEqual(@as(usize, 0), o.pending());
}
