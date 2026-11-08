//! A conta na demonstração (core/conta.zig): responde como o Discord, e
//! guarda o que "foi mandado" para o QA conferir. Roda na thread do gateway
//! falso; os contadores são atômicos porque o QA lê da thread da interface.
const std = @import("std");
const sys = @import("../platform/sys.zig");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const conta_json = @import("conta_json.zig");
const ev = @import("../core/event.zig");
const Id = types.Id;

const alloc = std.heap.c_allocator;

/// Quem pede captcha no pedido de amizade (o QA confere a mensagem).
pub const captcha_user: Id = 1010;

pub const sent = struct {
    const A = sys.Atomic(u64);
    pub var blocks: A = .init(0);
    pub var block_user: A = .init(0);
    pub var ignores: A = .init(0);
    pub var friend_requests: A = .init(0);
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
};

fn keep(b: []const u8) void {
    const n = @min(b.len, sent.last_body.len);
    @memcpy(sent.last_body[0..n], b[0..n]);
    sent.last_len.store(n, .release);
}

pub fn execute(g: anytype, cmd: conta.Cmd) void {
    defer cmd.deinit(alloc);
    switch (cmd) {
        .block => |uid| {
            sent.block_user.store(uid, .monotonic);
            _ = sent.blocks.fetchAdd(1, .release);
            g.emit(.{ .relationship = .{ .user = uid, .kind = .blocked } });
        },
        .ignore => |ig| {
            _ = sent.ignores.fetchAdd(1, .release);
            g.emit(.{ .conta = .{ .ignored = .{ .user = ig.user, .on = ig.on } } });
        },
        .friend_request => |uid| {
            _ = sent.friend_requests.fetchAdd(1, .release);
            if (uid == captcha_user) return g.emit(.{ .conta = .{ .friend_request = .{ .user = uid, .status = .captcha } } });
            g.emit(.{ .relationship = .{ .user = uid, .kind = .outgoing } });
            g.emit(.{ .conta = .{ .friend_request = .{ .user = uid, .status = .sent } } });
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
