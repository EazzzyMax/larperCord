//! Enquetes: o que a mensagem traz (pergunta, opções, prazo, votos) e como os
//! votos mudam com MESSAGE_POLL_VOTE_ADD/REMOVE. A enquete fica à parte da
//! mensagem, por ID (como as reações do histórico), e só existe para quem tem.
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;

/// O Discord aceita até 10 opções.
pub const max_answers = 10;
/// Enquetes guardadas de uma vez: passando disso, a de ID mais antigo sai.
pub const max_kept = 256;

const ev_alloc = std.heap.c_allocator;

pub const Answer = struct {
    /// `answer_id` do Discord (começa em 1, mas não dá para contar com isso).
    id: u32 = 0,
    /// Fatia de `Poll.text_buf`.
    text: []const u8 = "",
    /// Emoji da opção (`len` 0 = nenhum).
    emoji: types.Reaction = .{},
    count: u32 = 0,
    /// Votamos nesta.
    me: bool = false,
};

pub const Poll = struct {
    question: []const u8 = "",
    answers: [max_answers]Answer = @splat(.{}),
    n: u8 = 0,
    /// Quando acaba (s desde 1970; 0 = sem prazo).
    expiry: i64 = 0,
    multi: bool = false,
    /// Os votos vieram. Sem `results`, o Discord diz que são desconhecidos (não zero).
    known: bool = false,
    /// A contagem final já foi feita (depois do fim).
    finalized: bool = false,
    /// Todos os textos numa alocação só (ev_alloc).
    text_buf: []u8 = &.{},

    pub fn slice(p: *const Poll) []const Answer {
        return p.answers[0..p.n];
    }

    pub fn find(p: *Poll, answer: u32) ?*Answer {
        for (p.answers[0..p.n]) |*a| if (a.id == answer) return a;
        return null;
    }

    /// Soma dos votos de todas as opções (numa de várias escolhas, uma
    /// pessoa conta uma vez em cada opção que marcou).
    pub fn total(p: *const Poll) u32 {
        var t: u32 = 0;
        for (p.slice()) |a| t +|= a.count;
        return t;
    }

    pub fn voted(p: *const Poll) bool {
        for (p.slice()) |a| if (a.me) return true;
        return false;
    }

    pub fn ended(p: *const Poll, now_s: i64) bool {
        return p.finalized or (p.expiry != 0 and now_s >= p.expiry);
    }

    /// Um voto chegou (ou saiu). O nosso volta do servidor também: o que já
    /// está marcado não conta duas vezes.
    pub fn vote(p: *Poll, answer: u32, add: bool, mine: bool) void {
        const a = p.find(answer) orelse return;
        if (mine and a.me == add) return;
        if (mine) a.me = add;
        if (!p.known) return;
        if (add) a.count +|= 1 else a.count -|= 1;
    }

    /// Copia a pergunta e as opções para um buffer só (os textos da enquete
    /// passam a apontar para ele). `texts.len` é o número de opções.
    pub fn setTexts(p: *Poll, question: []const u8, texts: []const []const u8) !void {
        var len = question.len;
        for (texts) |t| len += t.len;
        const buf = try ev_alloc.alloc(u8, len);
        @memcpy(buf[0..question.len], question);
        p.question = buf[0..question.len];
        var at = question.len;
        for (texts, 0..) |t, i| {
            @memcpy(buf[at .. at + t.len], t);
            p.answers[i].text = buf[at .. at + t.len];
            at += t.len;
        }
        p.text_buf = buf;
    }
};

pub fn create() !*Poll {
    const p = try ev_alloc.create(Poll);
    p.* = .{};
    return p;
}

pub fn destroy(p: *Poll) void {
    if (p.text_buf.len > 0) ev_alloc.free(p.text_buf);
    ev_alloc.destroy(p);
}

/// As enquetes conhecidas, por mensagem.
pub const Map = struct {
    items: std.AutoHashMapUnmanaged(Id, *Poll) = .empty,

    pub fn get(m: *const Map, id: Id) ?*Poll {
        return m.items.get(id);
    }

    /// Guarda (ou troca pela versão nova) a enquete da mensagem `id`.
    pub fn put(m: *Map, gpa: std.mem.Allocator, id: Id, p: *Poll) !void {
        if (m.items.getPtr(id)) |old| {
            // Sem `results` os votos são desconhecidos, não zero: os que já
            // tínhamos continuam valendo.
            if (!p.known and old.*.known) {
                for (p.answers[0..p.n]) |*a| if (old.*.find(a.id)) |o| {
                    a.count = o.count;
                    a.me = o.me;
                };
                p.known = true;
            }
            destroy(old.*);
            old.* = p;
            return;
        }
        if (m.items.count() >= max_kept) {
            var oldest: Id = std.math.maxInt(Id);
            var it = m.items.keyIterator();
            while (it.next()) |k| oldest = @min(oldest, k.*);
            m.remove(gpa, oldest);
        }
        m.items.put(gpa, id, p) catch |err| {
            destroy(p);
            return err;
        };
    }

    pub fn remove(m: *Map, gpa: std.mem.Allocator, id: Id) void {
        _ = gpa;
        if (m.items.fetchRemove(id)) |kv| destroy(kv.value);
    }

    pub fn deinit(m: *Map, gpa: std.mem.Allocator) void {
        var it = m.items.valueIterator();
        while (it.next()) |p| destroy(p.*);
        m.items.deinit(gpa);
    }
};

fn testPoll(known: bool) !*Poll {
    const p = try create();
    p.n = 3;
    for (p.answers[0..3], 0..) |*a, i| a.id = @intCast(i + 1);
    p.answers[0].count = 2;
    p.answers[1].count = 1;
    p.known = known;
    try p.setTexts("pizza ou lasanha?", &.{ "pizza", "lasanha", "os dois" });
    return p;
}

test "enquete: textos num buffer só" {
    const p = try testPoll(true);
    defer destroy(p);
    try std.testing.expectEqualStrings("pizza ou lasanha?", p.question);
    try std.testing.expectEqualStrings("lasanha", p.answers[1].text);
    try std.testing.expectEqualStrings("os dois", p.answers[2].text);
    try std.testing.expectEqual(@as(u32, 3), p.total());
}

test "enquete: votos dos outros e o nosso eco" {
    const p = try testPoll(true);
    defer destroy(p);
    p.vote(3, true, false);
    try std.testing.expectEqual(@as(u32, 1), p.answers[2].count);
    // O nosso voto volta do servidor duas vezes (outro aparelho, RESUME): conta uma.
    p.vote(2, true, true);
    p.vote(2, true, true);
    try std.testing.expectEqual(@as(u32, 2), p.answers[1].count);
    try std.testing.expect(p.answers[1].me and p.voted());
    p.vote(2, false, true);
    p.vote(2, false, true);
    try std.testing.expectEqual(@as(u32, 1), p.answers[1].count);
    try std.testing.expect(!p.voted());
    // Nunca abaixo de zero, e opção que não existe é ignorada.
    p.vote(3, false, false);
    p.vote(3, false, false);
    p.vote(99, true, false);
    try std.testing.expectEqual(@as(u32, 0), p.answers[2].count);
}

test "enquete: votos desconhecidos só marcam o nosso" {
    const p = try testPoll(false);
    defer destroy(p);
    p.vote(1, true, true);
    p.vote(1, true, false);
    try std.testing.expectEqual(@as(u32, 2), p.answers[0].count);
    try std.testing.expect(p.answers[0].me);
}

test "enquete: fim pelo prazo ou pela contagem final" {
    const p = try testPoll(true);
    defer destroy(p);
    try std.testing.expect(!p.ended(100));
    p.expiry = 50;
    try std.testing.expect(p.ended(50) and !p.ended(49));
    p.expiry = 0;
    p.finalized = true;
    try std.testing.expect(p.ended(0));
}

test "enquete: o mapa troca a versão e esquece a mais antiga" {
    const gpa = std.testing.allocator;
    var m: Map = .{};
    defer m.deinit(gpa);
    try m.put(gpa, 10, try testPoll(false));
    try std.testing.expect(!m.get(10).?.known);
    const voted = try testPoll(true);
    voted.answers[1].me = true;
    try m.put(gpa, 10, voted);
    // Atualização sem `results`: fica com os votos que já tinha.
    try m.put(gpa, 10, try testPoll(false));
    const kept = m.get(10).?;
    try std.testing.expect(kept.known and kept.answers[1].me);
    try std.testing.expectEqual(@as(u32, 2), kept.answers[0].count);
    var id: Id = 100;
    while (m.items.count() < max_kept) : (id += 1) try m.put(gpa, id, try testPoll(true));
    try m.put(gpa, 5000, try testPoll(true));
    try std.testing.expect(m.get(10) == null and m.get(5000) != null);
    m.remove(gpa, 5000);
    try std.testing.expect(m.get(5000) == null);
}
