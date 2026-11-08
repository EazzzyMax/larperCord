//! A conta no Discord de verdade (core/conta.zig): bloquear, ignorar, pedido
//! de amizade, notificações, status personalizado e perfil, mais o que chega
//! pelo gateway sobre eles. Roda na thread da rede, chamado pelo gateway de
//! net/discord.zig (`g` é o `Gateway` de lá). Cada comando é um clique da
//! pessoa: um pedido só, sem repetir sozinho.
const std = @import("std");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const conta_json = @import("conta_json.zig");
const status_proto = @import("status_proto.zig");
const j = @import("jsonx.zig");
const i18n = @import("../ui/i18n.zig");
const nowMs = @import("fake_gateway.zig").nowMs;
const Value = std.json.Value;
const Id = types.Id;

const alloc = std.heap.c_allocator;

/// O que o gateway guarda da conta (o status personalizado vai no op 3).
pub const NetState = struct {
    /// Textos alocados com o c_allocator.
    custom: conta.CustomStatus = .{},

    pub fn setCustom(s: *NetState, cs: conta.CustomStatus) void {
        const copy = cs.dupe(alloc) catch return;
        s.custom.deinit(alloc);
        s.custom = copy;
    }

    pub fn deinit(s: *NetState) void {
        s.custom.deinit(alloc);
        s.custom = .{};
    }
};

fn emit(g: anytype, e: conta.Event) void {
    g.emit(.{ .conta = e });
}

/// Manda o status personalizado para quem estiver vendo.
fn emitCustom(g: anytype) void {
    const copy = g.conta.custom.dupe(alloc) catch return;
    emit(g, .{ .custom_status = copy });
}

/// Pede o op 3: entra na fila do teto de envio do gateway (net/gw_budget.zig;
/// pedidos seguidos viram um só) e sai montado por `writePresence` quando
/// tiver vez, com o status, o status personalizado e a atividade do Rich
/// Presence daquele momento.
pub fn sendPresence(g: anytype) void {
    g.queueOp(.presence);
}

/// O op 3 inteiro do gateway de verdade (`g.presence`: net/rpc_proto.zig).
pub fn writePresence(g: anytype, status_name: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    writeOp3(&out, status_name, g.conta.custom, g.presence.current) catch return;
    g.writeWs(out.items);
}

/// O op 3: o status escolhido mais o status personalizado (tipo 4), se vale
/// agora, e a atividade do Rich Presence (`rich`, já em JSON), se houver.
/// Único lugar que monta a lista de atividades da presença (a demonstração
/// usa o mesmo).
pub fn writeOp3(out: *std.ArrayList(u8), status_name: []const u8, custom: conta.CustomStatus, rich: ?[]const u8) !void {
    try out.print(alloc, "{{\"op\":3,\"d\":{{\"status\":\"{s}\",\"since\":0,\"activities\":", .{status_name});
    try conta.writeActivitiesWith(out, alloc, custom, nowMs(), rich);
    try out.appendSlice(alloc, ",\"afk\":false}}");
}

/// `"activities":[…]` do IDENTIFY: a mesma lista do op 3.
pub fn writeActivities(g: anytype, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(alloc, "\"activities\":");
    try conta.writeActivitiesWith(out, alloc, g.conta.custom, nowMs(), g.presence.current);
}

/// O status personalizado venceu: some da presença (chamado no heartbeat,
/// que já acorda sozinho; nenhum relógio a mais).
pub fn tick(g: anytype) void {
    const cs = g.conta.custom;
    if (cs.empty() or cs.expires_ms == 0 or cs.expires_ms > nowMs()) return;
    g.conta.deinit();
    if (g.ws_ready) sendPresence(g);
    emitCustom(g);
}

/// O que o READY traz da conta. Chamado antes do `status = ready`: a presença
/// pedida aqui espera na fila e sai assim que o gateway aceitar.
pub fn onReady(g: anytype, d: Value) void {
    if (j.get(d, "user_guild_settings")) |ugs| {
        if (conta_json.list(alloc, ugs)) |l| emit(g, .{ .guild_settings = l }) else |_| {}
    }
    if (conta_json.ignoredIds(alloc, j.array(j.get(d, "relationships")))) |ids| emit(g, .{ .ignored_list = ids }) else |_| {}
    if (j.str(j.get(d, "user_settings_proto"))) |b64| {
        if (customFrom(b64)) |got| {
            defer if (got) |x| x.deinit(alloc);
            g.conta.setCustom(got orelse .{});
            emitCustom(g);
            // A sessão nova abriu sem atividades: o status personalizado volta.
            if (g.conta.custom.active(nowMs())) sendPresence(g);
        } else |_| {}
    }
}

/// O status personalizado do protobuf, duplicado com o c_allocator.
fn customFrom(b64: []const u8) !?conta.CustomStatus {
    const bytes = try status_proto.decodeBase64(alloc, b64);
    defer alloc.free(bytes);
    const cs = try status_proto.read(bytes) orelse return null;
    // As fatias apontam para `bytes`, que vai embora aqui.
    return try cs.dupe(alloc);
}

/// RELATIONSHIP_ADD/UPDATE/REMOVE: o `user_ignored` (ignorar pela conta).
pub fn onRelationship(g: anytype, d: Value, removed: bool) void {
    const uid = j.id(j.get(d, "id")) orelse j.id(j.get(d, "user_id")) orelse return;
    const ig = conta_json.ignored(d) orelse (if (removed) false else return);
    emit(g, .{ .ignored = .{ .user = uid, .on = ig } });
}

pub fn onGuildSettingsUpdate(g: anytype, d: Value) void {
    const gs = (conta_json.one(alloc, d) catch return) orelse return;
    emit(g, .{ .guild_settings_one = gs });
}

/// USER_SETTINGS_PROTO_UPDATE (tipo 1): o status personalizado mudou em
/// outro aparelho? Parcial sem o campo 11 = não mexeu nele.
pub fn onProtoUpdate(g: anytype, b64: []const u8, partial: bool) void {
    const bytes = status_proto.decodeBase64(alloc, b64) catch return;
    defer alloc.free(bytes);
    const has_status = blk: {
        const only = status_proto.statusOnly(alloc, bytes) catch return;
        defer alloc.free(only);
        break :blk only.len > 0;
    };
    if (partial and !has_status) return;
    const cs = (status_proto.read(bytes) catch return) orelse conta.CustomStatus{};
    const same = std.mem.eql(u8, cs.text, g.conta.custom.text) and std.mem.eql(u8, cs.emoji_name, g.conta.custom.emoji_name) and
        cs.emoji_id == g.conta.custom.emoji_id and cs.expires_ms == g.conta.custom.expires_ms;
    if (same) return;
    g.conta.setCustom(cs);
    emitCustom(g);
    if (g.ws_ready) sendPresence(g);
}

fn userPath(buf: []u8, comptime fmt: []const u8, id: Id) ?[]const u8 {
    return std.fmt.bufPrint(buf, fmt, .{id}) catch null;
}

/// Executa um comando da conta (o gateway libera o comando depois).
pub fn execute(g: anytype, cmd: conta.Cmd) void {
    var pb: [160]u8 = undefined;
    switch (cmd) {
        .block => |uid| {
            const path = userPath(&pb, "/users/@me/relationships/{d}", uid) orelse return;
            var resp = g.request("PUT", path, conta.block_body) orelse return;
            defer resp.body.deinit(alloc);
            if (resp.status >= 300) return g.noticeHttp(i18n.tr("não deu para bloquear", "couldn't block"), &resp);
            // O RELATIONSHIP_ADD também vem; já mostra.
            g.emit(.{ .relationship = .{ .user = uid, .kind = .blocked } });
        },
        .ignore => |ig| {
            const path = userPath(&pb, "/users/@me/relationships/{d}/ignore", ig.user) orelse return;
            var resp = g.request(if (ig.on) "PUT" else "DELETE", path, null) orelse return;
            defer resp.body.deinit(alloc);
            if (resp.status >= 300) return g.noticeHttp(if (ig.on) i18n.tr("não deu para ignorar", "couldn't ignore") else i18n.tr("não deu para deixar de ignorar", "couldn't unignore"), &resp);
            emit(g, .{ .ignored = .{ .user = ig.user, .on = ig.on } });
        },
        .friend_request => |uid| {
            const path = userPath(&pb, "/users/@me/relationships/{d}", uid) orelse return;
            // Um pedido só: nem o rate limit faz repetir sozinho.
            g.no_retry = true;
            defer g.no_retry = false;
            var resp = g.request("PUT", path, conta.friend_body) orelse return emit(g, .{ .friend_request = .{ .user = uid, .status = .failed } });
            defer resp.body.deinit(alloc);
            const status: conta.FriendStatus = if (resp.status < 300) .sent else if (resp.status == 429) .rate_limited else if (hasCaptcha(resp.body.items)) .captcha else .failed;
            if (status == .failed) g.noticeHttp(i18n.tr("pedido de amizade recusado", "friend request refused"), &resp);
            emit(g, .{ .friend_request = .{ .user = uid, .status = status } });
        },
        .friend_by_name => |body| {
            // Um pedido só, como o de cima.
            g.no_retry = true;
            defer g.no_retry = false;
            var resp = g.request("POST", conta.friend_name_path, body) orelse return emit(g, .{ .friend_by_name = .failed });
            defer resp.body.deinit(alloc);
            const status = conta.nameStatus(resp.status, errorCode(resp.body.items), hasCaptcha(resp.body.items));
            // O que a página não sabe explicar vai para o aviso, com o motivo do Discord.
            if (status == .failed) g.noticeHttp(i18n.tr("pedido de amizade recusado", "friend request refused"), &resp);
            emit(g, .{ .friend_by_name = status });
        },
        .guild_settings => |gs| {
            const path = (if (gs.guild == 0)
                std.fmt.bufPrint(&pb, "/users/@me/guilds/@me/settings", .{})
            else
                std.fmt.bufPrint(&pb, "/users/@me/guilds/{d}/settings", .{gs.guild})) catch return;
            var resp = g.request("PATCH", path, gs.body) orelse return;
            defer resp.body.deinit(alloc);
            if (resp.status >= 300) return g.noticeHttp(i18n.tr("não deu para mudar as notificações", "couldn't change notifications"), &resp);
            // A resposta são as configurações inteiras do servidor.
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();
            const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), resp.body.items, .{}) catch return;
            onGuildSettingsUpdate(g, v);
        },
        .custom_status => |cs| customStatus(g, cs),
        .profile => |p| {
            var ok = true;
            if (p.user_body) |b| {
                var resp = g.request("PATCH", "/users/@me", b) orelse return emit(g, .{ .profile_saved = false });
                defer resp.body.deinit(alloc);
                if (resp.status >= 300) {
                    ok = false;
                    g.noticeHttp(i18n.tr("não deu para mudar o nome", "couldn't change the name"), &resp);
                }
            }
            if (p.profile_body) |b| {
                var resp = g.request("PATCH", "/users/@me/profile", b) orelse return emit(g, .{ .profile_saved = false });
                defer resp.body.deinit(alloc);
                if (resp.status >= 300) {
                    ok = false;
                    g.noticeHttp(i18n.tr("não deu para salvar o perfil", "couldn't save the profile"), &resp);
                }
            }
            emit(g, .{ .profile_saved = ok });
        },
    }
}

/// O `code` de um erro da API (null = não veio).
pub fn errorCode(body: []const u8) ?i64 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return null;
    return j.int(j.get(v, "code"));
}

/// O Discord pediu captcha (não dá para resolver aqui: a pessoa usa o app oficial).
pub fn hasCaptcha(body: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return false;
    return j.get(v, "captcha_key") != null;
}

/// Lê as configurações atuais, troca só o status personalizado e grava.
fn customStatus(g: anytype, cs: conta.CustomStatus) void {
    const failed = conta.Event.custom_status_failed;
    var resp = g.request("GET", "/users/@me/settings-proto/1", null) orelse return emit(g, failed);
    defer resp.body.deinit(alloc);
    if (resp.status != 200) {
        g.noticeHttp(i18n.tr("não deu para ler as configurações", "couldn't read the settings"), &resp);
        return emit(g, failed);
    }
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const ar = arena.allocator();
    const v = std.json.parseFromSliceLeaky(Value, ar, resp.body.items, .{}) catch return emit(g, failed);
    const b64 = j.str(j.get(v, "settings")) orelse return emit(g, failed);
    const body = status_proto.patchBody(ar, b64, cs, nowMs()) catch {
        // Não deu para ler tudo: não grava nada.
        g.notice("as configurações vieram num formato que o app não entende: nada foi mudado", "the settings came in a format the app doesn't understand: nothing was changed", .{});
        return emit(g, failed);
    };
    var presp = g.request("PATCH", "/users/@me/settings-proto/1", body) orelse return emit(g, failed);
    defer presp.body.deinit(alloc);
    if (presp.status >= 300) {
        g.noticeHttp(i18n.tr("não deu para salvar o status", "couldn't save the status"), &presp);
        return emit(g, failed);
    }
    const pv = std.json.parseFromSliceLeaky(Value, ar, presp.body.items, .{}) catch Value{ .null = {} };
    if (j.get(pv, "out_of_date")) |o| if (o == .bool and o.bool) {
        g.notice("as configurações mudaram em outro aparelho: tente de novo", "the settings changed on another device: try again", .{});
        return emit(g, failed);
    };
    g.conta.setCustom(cs);
    emitCustom(g);
    if (g.ws_ready) sendPresence(g);
}
