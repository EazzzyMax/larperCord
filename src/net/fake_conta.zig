//! A conta na demonstração (core/conta.zig): responde como o Discord, e
//! guarda o que "foi mandado" para o QA conferir. Roda na thread do gateway
//! falso; os contadores são atômicos porque o QA lê da thread da interface.
const std = @import("std");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const conta_json = @import("conta_json.zig");
const conta_net = @import("conta_net.zig");
const status_proto = @import("status_proto.zig");
const ev = @import("../core/event.zig");
const gw = @import("fake_gateway.zig");
const nowMs = gw.nowMs;
const Id = types.Id;

const alloc = std.heap.c_allocator;

/// Quem pede captcha no pedido de amizade (o QA confere a mensagem).
pub const captcha_user: Id = 1010;

pub const sent = struct {
    const A = std.atomic.Value(u64);
    pub var blocks: A = .init(0);
    pub var block_user: A = .init(0);
    pub var ignores: A = .init(0);
    pub var friend_requests: A = .init(0);
    /// O último PUT/DELETE de /users/@me/relationships: quantos, com quem e de
    /// onde foi o clique (o `X-Context-Properties`, core/conta.zig `Origin`).
    pub var relationships: A = .init(0);
    pub var rel_user: A = .init(0);
    pub var rel_from: A = .init(0);
    /// Pedidos pelo nome de usuário (o corpo do último fica em `last_body`).
    pub var friend_names: A = .init(0);
    pub var settings_patches: A = .init(0);
    pub var settings_guild: A = .init(0);
    pub var statuses: A = .init(0);
    pub var profiles: A = .init(0);
    /// O último corpo de PATCH (notificações ou perfil), para o QA ler
    /// depois que o contador mudou.
    pub var last_body: [512]u8 = undefined;
    pub var last_len: std.atomic.Value(usize) = .init(0);

    pub fn body() []const u8 {
        return last_body[0..last_len.load(.acquire)];
    }

    /// O último PATCH do status da conta (o JSON inteiro, com o proto em base64).
    pub var account_statuses: A = .init(0);
    pub var status_body: [256]u8 = undefined;
    pub var status_len: std.atomic.Value(usize) = .init(0);

    pub fn statusBody() []const u8 {
        return status_body[0..status_len.load(.acquire)];
    }
};

/// As configurações (tipo 1) da demonstração: a versão e o status, com o
/// "mostrar a atividade" ligado (o PATCH do status não pode desligar).
const demo_settings = [_]u8{ 0x0a, 0x02, 0x18, 0x01, 0x5a, 0x0e, 0x0a, 0x08, 0x0a, 0x06, 'o', 'n', 'l', 'i', 'n', 'e', 0x1a, 0x02, 0x08, 0x01 };
var settings: std.ArrayList(u8) = .empty;

/// O status escolhido vai para as configurações como no Discord de verdade
/// (net/conta_net.zig `saveStatus`): o corpo do PATCH fica para o QA.
pub fn saveStatus(status: types.Status, expires_ms: i64) void {
    if (settings.items.len == 0) settings.appendSlice(alloc, &demo_settings) catch return;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const ar = arena.allocator();
    const now = nowMs();
    const b64 = status_proto.encodeBase64(ar, settings.items) catch return;
    const b = status_proto.statusPatchBody(ar, b64, status, expires_ms, now) catch return;
    const edited = status_proto.editStatus(ar, settings.items, status, expires_ms, now) catch return;
    settings.clearRetainingCapacity();
    settings.appendSlice(alloc, edited) catch return;
    const n = @min(b.len, sent.status_body.len);
    @memcpy(sent.status_body[0..n], b[0..n]);
    sent.status_len.store(n, .release);
    _ = sent.account_statuses.fetchAdd(1, .release);
}

pub fn deinit() void {
    settings.deinit(alloc);
    settings = .empty;
}

/// "Outro aparelho" mudou o status: o USER_SETTINGS_PROTO_UPDATE (o proto em
/// base64), lido pelo mesmo leitor do gateway (o QA usa).
pub fn remoteStatus(b64: []const u8) ?ev.Event {
    const bytes = status_proto.decodeBase64(alloc, b64) catch return null;
    defer alloc.free(bytes);
    const ss = conta_net.storedStatus(bytes) orelse return null;
    const st = ss.status.?;
    return .{ .conta = .{ .status = .{ .status = st, .expires_ms = if (st == .online) 0 else ss.expires_ms } } };
}

/// Anota o pedido de relação que iria para o Discord (o QA confere o lugar).
pub fn noteRelationship(user: Id, from: conta.Origin) void {
    sent.rel_user.store(user, .monotonic);
    sent.rel_from.store(@intFromEnum(from), .monotonic);
    _ = sent.relationships.fetchAdd(1, .release);
}

/// De onde foi o último pedido de relação.
pub fn lastFrom() conta.Origin {
    return @enumFromInt(sent.rel_from.load(.acquire));
}

fn keep(b: []const u8) void {
    const n = @min(b.len, sent.last_body.len);
    @memcpy(sent.last_body[0..n], b[0..n]);
    sent.last_len.store(n, .release);
}

pub fn execute(g: anytype, cmd: conta.Cmd) void {
    defer cmd.deinit(alloc);
    switch (cmd) {
        .block => |b| {
            noteRelationship(b.user, b.from);
            sent.block_user.store(b.user, .monotonic);
            _ = sent.blocks.fetchAdd(1, .release);
            g.emit(.{ .relationship = .{ .user = b.user, .kind = .blocked } });
        },
        .ignore => |ig| {
            _ = sent.ignores.fetchAdd(1, .release);
            g.emit(.{ .conta = .{ .ignored = .{ .user = ig.user, .on = ig.on } } });
        },
        .friend_request => |fr| {
            const uid = fr.user;
            noteRelationship(uid, fr.from);
            _ = sent.friend_requests.fetchAdd(1, .release);
            if (uid == captcha_user) return g.emit(.{ .conta = .{ .friend_request = .{ .user = uid, .status = .captcha } } });
            g.emit(.{ .relationship = .{ .user = uid, .kind = .outgoing } });
            g.emit(.{ .conta = .{ .friend_request = .{ .user = uid, .status = .sent } } });
        },
        .friend_by_name => |body| {
            keep(body);
            _ = sent.friend_names.fetchAdd(1, .release);
            g.emit(.{ .conta = .{ .friend_by_name = byName(g, body) } });
        },
        .guild_settings => |gs| {
            keep(gs.body);
            sent.settings_guild.store(gs.guild, .monotonic);
            _ = sent.settings_patches.fetchAdd(1, .release);
            // A resposta do PATCH: as configurações inteiras, como ficaram.
            if (gs.demo) |next| emitSettings(g, next);
        },
        .custom_status => |cs| {
            _ = sent.statuses.fetchAdd(1, .release);
            // Vai junto no próximo op 3 da demonstração (Rich Presence).
            g.conta.setCustom(cs);
            const copy = cs.dupe(alloc) catch return;
            g.emit(.{ .conta = .{ .custom_status = copy } });
        },
        .profile => |p| {
            if (p.profile_body) |b| keep(b) else if (p.user_body) |b| keep(b);
            if (p.user_body) |b| renamed(g, b);
            _ = sent.profiles.fetchAdd(1, .release);
            g.emit(.{ .conta = .{ .profile_saved = true } });
        },
    }
}

/// O que o Discord responde ao pedido pelo nome, com os códigos da API (ver
/// `conta.nameStatus`); deu certo, chega o RELATIONSHIP_ADD.
fn byName(g: anytype, body: []const u8) conta.NameStatus {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body, .{}) catch return .failed;
    const name = switch (v.object.get("username") orelse return .failed) {
        .string => |x| x,
        else => return .failed,
    };
    const u = gw.demoUserNamed(name) orelse return conta.nameStatus(400, 80004, false);
    if (u.id == gw.me_user) return conta.nameStatus(400, 80003, false);
    if (u.bot) return conta.nameStatus(400, 80002, false);
    if (u.id == captcha_user) return conta.nameStatus(400, null, true);
    const rel = g.rels.get(u.id) orelse .none;
    switch (rel) {
        .friend => return conta.nameStatus(400, 80007, false),
        .blocked => return conta.nameStatus(400, 80001, false),
        // Quem já tinha mandado pedido para a gente vira amigo.
        .incoming => g.emit(.{ .relationship = .{ .user = u.id, .kind = .friend } }),
        .none, .outgoing => g.emit(.{ .relationship = .{ .user = u.id, .kind = .outgoing } }),
    }
    return conta.nameStatus(204, null, false);
}

/// Uma cópia para a interface (que libera a dela).
fn emitSettings(g: anytype, gs: conta.GuildSettings) void {
    var copy = gs;
    copy.overrides = alloc.dupe(conta.Override, gs.overrides) catch return;
    g.emit(.{ .conta = .{ .guild_settings_one = copy } });
}

/// O nome novo chega como o USER_UPDATE do Discord.
fn renamed(g: anytype, body: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body, .{}) catch return;
    const name = switch (v.object.get("global_name") orelse return) {
        .string => |s| s,
        else => "rsha",
    };
    const owned = alloc.dupe(u8, name) catch return;
    g.emit(.{ .user_update = .{ .id = 1000, .name = owned, .status = .offline, .avatar = alloc.dupe(u8, "demo:av:1000") catch null } });
}

/// "Outro aparelho" mudou as notificações: o USER_GUILD_SETTINGS_UPDATE
/// como o Discord manda, lido pelo mesmo leitor do gateway (o QA usa).
pub fn remoteEvent(json: []const u8) ?ev.Event {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), json, .{}) catch return null;
    const gs = (conta_json.one(alloc, v) catch return null) orelse return null;
    return .{ .conta = .{ .guild_settings_one = gs } };
}
