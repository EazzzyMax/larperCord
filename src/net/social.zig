//! Pedidos de mensagem, spam e grupos de DM: o que vem no JSON do canal e o
//! pedido de cada ação (sem rede, para dar para testar). Tudo conferido no
//! recurso de canal de docs.discord.food.
const std = @import("std");
const types = @import("../core/types.zig");
const ev = @import("../core/event.zig");
const i18n = @import("../ui/i18n.zig");
const j = @import("jsonx.zig");
const Id = types.Id;
const Value = std.json.Value;

/// Flag IS_SPAM (1 << 5) no `flags` do canal.
const flag_is_spam: i64 = 1 << 5;
/// `consent_status` ACCEPTED: o único que uma conta comum pode mandar.
const consent_accepted = 2;
/// Grupo de DM comum: até 10 pessoas, contando a gente.
pub const group_max = 10;

fn flag(cv: Value, key: []const u8) bool {
    const b = j.get(cv, key) orelse return false;
    return b == .bool and b.bool;
}

/// Pedido de mensagem, spam ou conversa comum (só DMs e grupos têm esses
/// campos). A flag IS_SPAM só vale enquanto é pedido: aceita, a conversa
/// não fica presa na aba de spam.
pub fn requestOf(cv: Value) types.DmRequest {
    const req = flag(cv, "is_message_request");
    if (flag(cv, "is_spam")) return .spam;
    if (req and (j.int(j.get(cv, "flags")) orelse 0) & flag_is_spam != 0) return .spam;
    return if (req) .pending else .none;
}

/// Dono do grupo (`owner_id`); 0 fora de grupos (em thread o campo é outro).
pub fn ownerOf(cv: Value, kind_i: i64) Id {
    return if (kind_i == 3) j.id(j.get(cv, "owner_id")) orelse 0 else 0;
}

/// Só o dono tira gente do grupo, e ninguém tira a si mesmo (isso é sair).
pub fn canRemove(ch: *const types.Channel, me: Id, user: Id) bool {
    return ch.group and me != 0 and ch.owner == me and user != me and std.mem.indexOfScalar(Id, ch.recipients, user) != null;
}

/// Ainda cabe mais alguém? (`recipients` não conta a gente.)
pub fn hasRoom(ch: *const types.Channel) bool {
    return ch.group and ch.recipients.len + 1 < group_max;
}

pub fn canAdd(ch: *const types.Channel, user: Id) bool {
    return hasRoom(ch) and std.mem.indexOfScalar(Id, ch.recipients, user) == null;
}

pub const Req = struct { method: [:0]const u8, path: []const u8, body: ?[]const u8 = null };

/// Método, caminho e corpo de cada ação; `buf` guarda o caminho.
pub fn build(buf: []u8, s: ev.Social) ?Req {
    return switch (s) {
        // Update Message Request: o corpo leva o consentimento.
        .accept_request => |ch| .{
            .method = "PUT",
            .path = std.fmt.bufPrint(buf, "/channels/{d}/recipients/@me", .{ch}) catch return null,
            .body = std.fmt.comptimePrint("{{\"consent_status\":{d}}}", .{consent_accepted}),
        },
        // Reject Message Request: recusa e apaga o pedido.
        .reject_request => |ch| .{ .method = "DELETE", .path = std.fmt.bufPrint(buf, "/channels/{d}/recipients/@me", .{ch}) catch return null },
        // Add/Remove Channel Recipient (os campos do corpo são só de OAuth2).
        .add_member => |m| .{ .method = "PUT", .path = std.fmt.bufPrint(buf, "/channels/{d}/recipients/{d}", .{ m.channel, m.user }) catch return null },
        .remove_member => |m| .{ .method = "DELETE", .path = std.fmt.bufPrint(buf, "/channels/{d}/recipients/{d}", .{ m.channel, m.user }) catch return null },
        // Leave Group DM (sem `silent`: os outros veem a mensagem de saída).
        .leave_group => |ch| .{ .method = "DELETE", .path = std.fmt.bufPrint(buf, "/channels/{d}", .{ch}) catch return null },
    };
}

/// O aviso quando o Discord recusa.
pub fn failText(s: ev.Social) []const u8 {
    return switch (s) {
        .accept_request => i18n.tr("não deu para aceitar o pedido", "couldn't accept the request"),
        .reject_request => i18n.tr("não deu para recusar o pedido", "couldn't decline the request"),
        .add_member => i18n.tr("não deu para adicionar ao grupo", "couldn't add to the group"),
        .remove_member => i18n.tr("não deu para tirar do grupo", "couldn't remove from the group"),
        .leave_group => i18n.tr("não deu para sair do grupo", "couldn't leave the group"),
    };
}

fn parse(arena: *std.heap.ArenaAllocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, arena.allocator(), text, .{});
}

test "social: pedido, spam e conversa comum no JSON do canal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(types.DmRequest.pending, requestOf(try parse(&arena,
        \\{"id":"1","type":1,"is_message_request":true,"is_message_request_timestamp":"2026-11-01T10:00:00+00:00","is_spam":false}
    )));
    try std.testing.expectEqual(types.DmRequest.spam, requestOf(try parse(&arena,
        \\{"id":"1","type":1,"is_message_request":true,"is_spam":true}
    )));
    // A flag IS_SPAM conta enquanto é pedido.
    try std.testing.expectEqual(types.DmRequest.spam, requestOf(try parse(&arena,
        \\{"id":"1","type":1,"is_message_request":true,"flags":32}
    )));
    try std.testing.expectEqual(types.DmRequest.none, requestOf(try parse(&arena,
        \\{"id":"1","type":1,"is_message_request":false,"flags":32}
    )));
    try std.testing.expectEqual(types.DmRequest.none, requestOf(try parse(&arena,
        \\{"id":"1","type":1,"is_message_request":null}
    )));
    try std.testing.expectEqual(types.DmRequest.none, requestOf(try parse(&arena,
        \\{"id":"1","type":1}
    )));
    const grp = try parse(&arena,
        \\{"id":"5","type":3,"owner_id":"77"}
    );
    try std.testing.expectEqual(@as(Id, 77), ownerOf(grp, 3));
    try std.testing.expectEqual(@as(Id, 0), ownerOf(grp, 11));
}

test "social: pedidos de cada ação" {
    var buf: [96]u8 = undefined;
    const Case = struct { s: ev.Social, method: []const u8, path: []const u8, body: ?[]const u8 };
    const cases = [_]Case{
        .{ .s = .{ .accept_request = 12 }, .method = "PUT", .path = "/channels/12/recipients/@me", .body = "{\"consent_status\":2}" },
        .{ .s = .{ .reject_request = 12 }, .method = "DELETE", .path = "/channels/12/recipients/@me", .body = null },
        .{ .s = .{ .add_member = .{ .channel = 6, .user = 1007 } }, .method = "PUT", .path = "/channels/6/recipients/1007", .body = null },
        .{ .s = .{ .remove_member = .{ .channel = 6, .user = 1007 } }, .method = "DELETE", .path = "/channels/6/recipients/1007", .body = null },
        .{ .s = .{ .leave_group = 6 }, .method = "DELETE", .path = "/channels/6", .body = null },
    };
    for (cases) |cs| {
        const r = build(&buf, cs.s).?;
        try std.testing.expectEqualStrings(cs.method, r.method);
        try std.testing.expectEqualStrings(cs.path, r.path);
        if (cs.body) |b| try std.testing.expectEqualStrings(b, r.body.?) else try std.testing.expect(r.body == null);
        try std.testing.expect(failText(cs.s).len > 0);
    }
    // Snowflake de 20 dígitos cabe; buffer curto não estoura.
    var small: [8]u8 = undefined;
    try std.testing.expect(build(&small, .{ .leave_group = std.math.maxInt(u64) }) == null);
}

test "social: quem pode tirar e pôr gente no grupo" {
    const members = [_]Id{ 2, 3 };
    var g: types.Channel = .{ .id = 6, .guild = 0, .name = "g", .group = true, .owner = 1, .recipients = &members };
    try std.testing.expect(canRemove(&g, 1, 2));
    try std.testing.expect(!canRemove(&g, 1, 1));
    try std.testing.expect(!canRemove(&g, 1, 9));
    try std.testing.expect(!canRemove(&g, 2, 3));
    try std.testing.expect(canAdd(&g, 9));
    try std.testing.expect(!canAdd(&g, 3));
    const full = [_]Id{ 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    g.recipients = &full;
    try std.testing.expect(!hasRoom(&g) and !canAdd(&g, 11));
    const dm: types.Channel = .{ .id = 7, .guild = 0, .name = "d", .recipient = 2, .owner = 1 };
    try std.testing.expect(!canRemove(&dm, 1, 2) and !canAdd(&dm, 9));
}
