//! Editar uma thread (PATCH /channels/{id}): quem pode o quê e o que muda.
//! Sem rede e sem interface, para dar para testar.
//!
//! Regras (docs.discord.food, "Threads" e "Modify Channel"):
//! - nome, arquivar e auto-arquivar: quem criou a thread ou MANAGE_THREADS;
//! - desarquivar: quem está na thread e pode responder nela; trancada, só
//!   MANAGE_THREADS;
//! - trancar e destrancar: MANAGE_THREADS;
//! - tags de um post: quem criou ou MANAGE_THREADS; as moderadas, só MANAGE_THREADS;
//! - arquivada, qualquer outra mudança precisa desarquivar no mesmo pedido.
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;
const perm = types.perm;

/// Um post leva no máximo 5 tags.
pub const max_tags = 5;
/// Minutos sem atividade até arquivar: os únicos valores que o Discord aceita.
pub const durations = [_]u16{ 60, 1440, 4320, 10080 };
/// Nome de canal: de 1 a 100 caracteres.
pub const max_name_chars = 100;

pub const Tags = struct {
    ids: [max_tags]Id = @splat(0),
    n: u8 = 0,

    pub fn slice(t: *const Tags) []const Id {
        return t.ids[0..t.n];
    }

    pub fn from(list: []const Id) Tags {
        var t: Tags = .{};
        for (list) |id| {
            if (t.n == max_tags) break;
            if (std.mem.indexOfScalar(Id, t.slice(), id) != null) continue;
            t.ids[t.n] = id;
            t.n += 1;
        }
        return t;
    }

    pub fn has(t: *const Tags, id: Id) bool {
        return std.mem.indexOfScalar(Id, t.slice(), id) != null;
    }

    /// Liga ou desliga uma tag. Cheia, não entra (devolve false).
    pub fn toggle(t: *Tags, id: Id) bool {
        if (std.mem.indexOfScalar(Id, t.slice(), id)) |i| {
            std.mem.copyForwards(Id, t.ids[i .. t.n - 1], t.ids[i + 1 .. t.n]);
            t.n -= 1;
            return true;
        }
        if (t.n == max_tags) return false;
        t.ids[t.n] = id;
        t.n += 1;
        return true;
    }

    /// As mesmas tags, em qualquer ordem.
    pub fn same(t: *const Tags, other: []const Id) bool {
        const o = from(other);
        if (o.n != t.n) return false;
        for (t.slice()) |id| if (!o.has(id)) return false;
        return true;
    }
};

/// O que muda (null = fica como está). `name` é alocado por quem monta (o
/// comando e o evento levam a posse junto).
pub const Edit = struct {
    thread: Id,
    name: ?[]const u8 = null,
    tags: ?Tags = null,
    archived: ?bool = null,
    locked: ?bool = null,
    auto_archive: ?u16 = null,

    pub fn empty(e: *const Edit) bool {
        return e.name == null and e.tags == null and e.archived == null and e.locked == null and e.auto_archive == null;
    }
};

/// O que dá para fazer numa thread.
pub const Rights = struct {
    /// Nome e auto-arquivar.
    rename: bool = false,
    archive: bool = false,
    unarchive: bool = false,
    lock: bool = false,
    /// Tags de um post (só em fórum); as moderadas pedem `moderated_tags`.
    tags: bool = false,
    moderated_tags: bool = false,

    /// Dá para abrir "Editar thread".
    pub fn edit(r: Rights) bool {
        return r.rename or r.tags;
    }
};

/// `perms`: as nossas no canal pai (thread não tem exceções próprias).
/// `forum`: o pai é um fórum ou canal de mídia (é onde há tags).
pub fn rights(t: types.ThreadInfo, perms: u64, me: Id, forum: bool) Rights {
    if (perms & perm.view_channel == 0) return .{};
    const manage = perms & perm.manage_threads != 0;
    const owner = me != 0 and t.owner == me;
    const send = perms & perm.send_messages_in_threads != 0;
    const unarchive = manage or (!t.locked and send and (t.joined or owner));
    var r: Rights = .{
        .rename = manage or owner,
        .archive = manage or owner,
        .unarchive = unarchive,
        .lock = manage,
        .tags = forum and (manage or owner),
        .moderated_tags = forum and manage,
    };
    // Arquivada, o resto só junto com desarquivar; e trancar fica para depois.
    if (t.archived) {
        if (!unarchive) {
            r.rename = false;
            r.tags = false;
            r.moderated_tags = false;
        }
        r.lock = false;
        r.archive = false;
    } else r.unarchive = false;
    return r;
}

/// Nome que dá para mandar: sem espaço nas pontas, de 1 a 100 caracteres.
pub fn nameOk(name: []const u8) bool {
    const n = std.unicode.utf8CountCodepoints(name) catch return false;
    return n >= 1 and n <= max_name_chars;
}

/// O formulário de "Editar thread" virou o quê. `name` já sem espaços nas
/// pontas; `tags` null = o formulário não tem tags; `duration` 0 = não mexeu.
/// O `name` devolvido aponta para o de entrada (quem manda copia).
pub fn fromForm(thread: Id, cur_name: []const u8, t: types.ThreadInfo, name: []const u8, tags: ?Tags, duration: u16) Edit {
    var e: Edit = .{ .thread = thread };
    if (nameOk(name) and !std.mem.eql(u8, name, cur_name)) e.name = name;
    if (tags) |tg| if (!tg.same(t.tags)) {
        e.tags = tg;
    };
    if (duration != 0 and duration != t.auto_archive) e.auto_archive = duration;
    if (!e.empty() and t.archived) e.archived = false;
    return e;
}

test "regras: dono, quem gerencia e quem só participa" {
    const me: Id = 7;
    const base = perm.view_channel | perm.send_messages_in_threads;
    const mine: types.ThreadInfo = .{ .owner = me, .joined = true };
    const other: types.ThreadInfo = .{ .owner = 9, .joined = true };
    // Quem criou: nome, arquivar e tags; trancar não.
    const r1 = rights(mine, base, me, true);
    try std.testing.expect(r1.rename and r1.archive and r1.tags and !r1.lock and !r1.moderated_tags and !r1.unarchive);
    // Só participa: nada além de desarquivar (e só se arquivada).
    const r2 = rights(other, base, me, true);
    try std.testing.expect(!r2.edit() and !r2.archive and !r2.lock);
    try std.testing.expect(rights(.{ .owner = 9, .joined = true, .archived = true }, base, me, false).unarchive);
    try std.testing.expect(!rights(.{ .owner = 9, .joined = false, .archived = true }, base, me, false).unarchive);
    // Gerencia threads: tudo, inclusive tags moderadas.
    const r3 = rights(other, base | perm.manage_threads, me, true);
    try std.testing.expect(r3.rename and r3.archive and r3.lock and r3.tags and r3.moderated_tags);
    // Fora de fórum não há tags.
    try std.testing.expect(!rights(mine, base, me, false).tags);
    // Sem ver o canal, nada.
    try std.testing.expect(!rights(mine, perm.manage_threads, me, true).edit());
    // Sem saber quem somos (me = 0), dono 0 não vira dono.
    try std.testing.expect(!rights(.{}, base, 0, false).rename);
}

test "regras: arquivada e trancada" {
    const me: Id = 7;
    const base = perm.view_channel | perm.send_messages_in_threads;
    // Arquivada e trancada: o dono não desarquiva, nem edita.
    const locked: types.ThreadInfo = .{ .owner = me, .joined = true, .archived = true, .locked = true };
    const r1 = rights(locked, base, me, true);
    try std.testing.expect(!r1.unarchive and !r1.edit() and !r1.archive);
    // Quem gerencia desarquiva e edita (junto), mas não tranca arquivada.
    const r2 = rights(locked, base | perm.manage_threads, me, true);
    try std.testing.expect(r2.unarchive and r2.edit() and !r2.lock);
    // Arquivada, sem trava: o dono desarquiva e edita.
    const r3 = rights(.{ .owner = me, .joined = true, .archived = true }, base, me, false);
    try std.testing.expect(r3.unarchive and r3.rename and !r3.archive);
    // Sem poder responder em threads, quem não gerencia não desarquiva.
    try std.testing.expect(!rights(.{ .owner = me, .joined = true, .archived = true }, perm.view_channel, me, false).unarchive);
}

test "formulário: só o que mudou, e desarquiva junto" {
    const t: types.ThreadInfo = .{ .owner = 1, .auto_archive = 1440, .tags = &.{ 5, 6 } };
    // Nada mudou: pedido vazio.
    try std.testing.expect(fromForm(3, "nome", t, "nome", Tags.from(&.{ 6, 5 }), 1440).empty());
    // Nome vazio não vale.
    try std.testing.expect(fromForm(3, "nome", t, "", null, 0).empty());
    const e = fromForm(3, "nome", t, "outro", Tags.from(&.{5}), 4320);
    try std.testing.expectEqualStrings("outro", e.name.?);
    try std.testing.expectEqual(@as(u8, 1), e.tags.?.n);
    try std.testing.expectEqual(@as(u16, 4320), e.auto_archive.?);
    try std.testing.expect(e.archived == null);
    var ta = t;
    ta.archived = true;
    try std.testing.expectEqual(false, fromForm(3, "nome", ta, "outro", null, 0).archived.?);
    try std.testing.expect(fromForm(3, "nome", ta, "nome", null, 0).archived == null);
}

test "tags: liga, desliga, teto de 5 e ordem não importa" {
    var t: Tags = .{};
    for (1..6) |i| try std.testing.expect(t.toggle(@intCast(i)));
    try std.testing.expect(!t.toggle(9));
    try std.testing.expect(t.toggle(3));
    try std.testing.expectEqualSlices(Id, &.{ 1, 2, 4, 5 }, t.slice());
    try std.testing.expect(t.same(&.{ 5, 4, 2, 1 }));
    try std.testing.expect(!t.same(&.{ 1, 2, 4 }));
    try std.testing.expectEqual(@as(u8, 2), Tags.from(&.{ 8, 8, 9 }).n);
}

test "nome: de 1 a 100 caracteres" {
    try std.testing.expect(nameOk("a"));
    try std.testing.expect(!nameOk(""));
    // 100 "é" (200 bytes) cabem; 101 letras não.
    var e100: [200]u8 = undefined;
    for (0..100) |i| @memcpy(e100[i * 2 ..][0..2], "\xc3\xa9");
    try std.testing.expect(nameOk(&e100));
    const a101: [101]u8 = @splat('a');
    try std.testing.expect(!nameOk(&a101));
    try std.testing.expect(!nameOk("\xff"));
}
