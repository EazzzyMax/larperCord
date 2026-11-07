//! O JSON do Discord para core/conta.zig: `user_guild_settings` (READY, com
//! ou sem o formato versionado `{entries}`, e USER_GUILD_SETTINGS_UPDATE) e
//! o `user_ignored` das relações. Separado do gateway para testar sem rede.
const std = @import("std");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const j = @import("jsonx.zig");
const Value = std.json.Value;
const Id = types.Id;

fn boolOf(v: ?Value) bool {
    const x = v orelse return false;
    return x == .bool and x.bool;
}

/// `mute_config.end_time` em ms (0 = sem prazo) e `selected_time_window`.
fn muteConfig(v: Value) struct { end_ms: i64, window: i32 } {
    const cfg = j.get(v, "mute_config") orelse return .{ .end_ms = 0, .window = -1 };
    if (cfg != .object) return .{ .end_ms = 0, .window = -1 };
    const end = if (j.str(j.get(cfg, "end_time"))) |t| j.isoTime(t) * 1000 else 0;
    const win = std.math.clamp(j.int(j.get(cfg, "selected_time_window")) orelse -1, -1, std.math.maxInt(i32));
    return .{ .end_ms = @max(end, 0), .window = @intCast(win) };
}

fn level(v: ?Value) ?conta.Level {
    const n = j.int(v) orelse return null;
    return switch (n) {
        0 => .all,
        1 => .mentions,
        2 => .nothing,
        3 => .inherit,
        else => null,
    };
}

/// Limite de exceções por servidor (uma conta normal tem dezenas).
const max_overrides = 4096;

/// Um objeto de configurações de servidor. `overrides` com `gpa`.
pub fn one(gpa: std.mem.Allocator, v: Value) !?conta.GuildSettings {
    if (v != .object) return null;
    const mc = muteConfig(v);
    const lv = level(j.get(v, "message_notifications"));
    var gs: conta.GuildSettings = .{
        // `guild_id` null = as mensagens diretas.
        .guild = j.id(j.get(v, "guild_id")) orelse 0,
        .muted = boolOf(j.get(v, "muted")),
        .mute_end_ms = mc.end_ms,
        .mute_window = mc.window,
        .level = if (lv) |l| (if (l == .inherit) null else l) else null,
        .suppress_everyone = boolOf(j.get(v, "suppress_everyone")),
        .suppress_roles = boolOf(j.get(v, "suppress_roles")),
    };
    // No objeto completo é uma lista; aceita também o mapa da forma parcial.
    const ov = j.get(v, "channel_overrides");
    var ovs: std.ArrayList(conta.Override) = .empty;
    errdefer ovs.deinit(gpa);
    if (ov) |o| switch (o) {
        .array => |arr| for (arr.items) |e| {
            if (ovs.items.len >= max_overrides) break;
            if (override(e, null)) |x| try ovs.append(gpa, x);
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |kv| {
                if (ovs.items.len >= max_overrides) break;
                const key = std.fmt.parseInt(Id, kv.key_ptr.*, 10) catch continue;
                if (override(kv.value_ptr.*, key)) |x| try ovs.append(gpa, x);
            }
        },
        else => {},
    };
    gs.overrides = try ovs.toOwnedSlice(gpa);
    return gs;
}

fn override(e: Value, key: ?Id) ?conta.Override {
    if (e != .object) return null;
    const ch = j.id(j.get(e, "channel_id")) orelse key orelse return null;
    const mc = muteConfig(e);
    return .{
        .channel = ch,
        .muted = boolOf(j.get(e, "muted")),
        .mute_end_ms = mc.end_ms,
        .mute_window = mc.window,
        .level = level(j.get(e, "message_notifications")) orelse .inherit,
        .collapsed = boolOf(j.get(e, "collapsed")),
    };
}

/// `user_guild_settings` inteiro (lista ou `{entries}`).
pub fn list(gpa: std.mem.Allocator, ugs: Value) ![]conta.GuildSettings {
    var out: std.ArrayList(conta.GuildSettings) = .empty;
    errdefer {
        for (out.items) |gs| gpa.free(gs.overrides);
        out.deinit(gpa);
    }
    const items = if (ugs == .array) j.array(ugs) else j.array(j.get(ugs, "entries"));
    try out.ensureTotalCapacity(gpa, items.len);
    for (items) |e| if (try one(gpa, e)) |gs| out.appendAssumeCapacity(gs);
    return out.toOwnedSlice(gpa);
}

/// `user_ignored` de uma relação (null = o campo não veio).
pub fn ignored(rv: Value) ?bool {
    const v = j.get(rv, "user_ignored") orelse return null;
    return v == .bool and v.bool;
}

/// Quem está ignorado nas relações do READY.
pub fn ignoredIds(gpa: std.mem.Allocator, rels: []const Value) ![]Id {
    var out: std.ArrayList(Id) = .empty;
    errdefer out.deinit(gpa);
    for (rels) |rv| {
        if (!(ignored(rv) orelse false)) continue;
        const uid = j.id(j.get(rv, "user_id")) orelse j.id(j.get(rv, "id")) orelse continue;
        try out.append(gpa, uid);
    }
    return out.toOwnedSlice(gpa);
}

fn parse(arena: std.mem.Allocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, arena, text, .{});
}

test "user_guild_settings: servidor, DMs, prazos e exceções" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    const l = try list(ar, try parse(ar,
        \\{"version":3,"partial":false,"entries":[
        \\ {"guild_id":"1","muted":true,"mute_config":{"end_time":"2030-01-01T00:00:00+00:00","selected_time_window":3600},
        \\  "message_notifications":1,"suppress_everyone":true,"suppress_roles":false,"channel_overrides":[
        \\   {"channel_id":"10","muted":true,"mute_config":null,"message_notifications":3,"collapsed":true},
        \\   {"channel_id":"11","muted":false,"message_notifications":2}]},
        \\ {"guild_id":null,"muted":false,"message_notifications":3,"channel_overrides":[{"channel_id":"40","muted":true}]},
        \\ "lixo",
        \\ {"guild_id":"2","message_notifications":9}
        \\]}
    ));
    try std.testing.expectEqual(@as(usize, 3), l.len);
    try std.testing.expectEqual(@as(Id, 1), l[0].guild);
    try std.testing.expect(l[0].muted and l[0].suppress_everyone and !l[0].suppress_roles);
    try std.testing.expectEqual(@as(i64, 1893456000000), l[0].mute_end_ms);
    try std.testing.expectEqual(@as(i32, 3600), l[0].mute_window);
    try std.testing.expectEqual(@as(?conta.Level, .mentions), l[0].level);
    try std.testing.expectEqual(@as(usize, 2), l[0].overrides.len);
    try std.testing.expect(l[0].overrides[0].muted and l[0].overrides[0].collapsed and l[0].overrides[0].level == .inherit);
    try std.testing.expectEqual(conta.Level.nothing, l[0].overrides[1].level);
    try std.testing.expectEqual(@as(Id, 0), l[1].guild);
    try std.testing.expectEqual(@as(?conta.Level, null), l[1].level);
    try std.testing.expectEqual(@as(Id, 40), l[1].overrides[0].channel);
    try std.testing.expectEqual(@as(?conta.Level, null), l[2].level);
    // Forma antiga: lista direta; e a parcial com mapa de exceções.
    const old = try list(ar, try parse(ar,
        \\[{"guild_id":"5","muted":false,"channel_overrides":{"50":{"muted":true}}}]
    ));
    try std.testing.expectEqual(@as(Id, 50), old[0].overrides[0].channel);
    try std.testing.expect(old[0].overrides[0].muted);
}

test "user_ignored nas relações" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    const v = try parse(ar,
        \\[{"id":"1","type":1,"user_ignored":false},{"id":"2","type":0,"user_ignored":true},{"user_id":"3","type":2,"user_ignored":true},{"id":"4","type":1}]
    );
    const ids = try ignoredIds(ar, j.array(v));
    try std.testing.expectEqualSlices(Id, &.{ 2, 3 }, ids);
    try std.testing.expectEqual(@as(?bool, null), ignored(j.array(v)[3]));
    try std.testing.expectEqual(@as(?bool, false), ignored(j.array(v)[0]));
}
