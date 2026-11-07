//! Configurações da conta que moram no Discord: silenciar e notificações
//! (user guild settings), status personalizado, ignorar, bloquear, pedido de
//! amizade e o perfil. Aqui ficam os tipos, a lógica pura e os textos JSON
//! que vão para a API (testados no `zig build test`). A rede fica em
//! net/conta_net.zig, o lado do app em app_conta.zig e as telas em ui/.
//!
//! Tudo aqui sai de um clique: nada roda sozinho nem em lote.
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;

/// `message_notifications` do Discord. `inherit` só vale num canal (segue o
/// servidor); no servidor, o 3 quer dizer "o padrão do servidor".
pub const Level = enum(u8) { all = 0, mentions = 1, nothing = 2, inherit = 3 };

/// Exceção de um canal (ou de uma DM, dentro das configurações "@me").
pub const Override = struct {
    channel: Id,
    muted: bool = false,
    /// Fim do silêncio (ms desde 1970); 0 = até reativar.
    mute_end_ms: i64 = 0,
    /// `selected_time_window` (s; -1 = até reativar).
    mute_window: i32 = -1,
    level: Level = .inherit,
    collapsed: bool = false,
};

/// As configurações de notificação de um servidor (ou das DMs, `guild` 0).
pub const GuildSettings = struct {
    /// 0 = mensagens diretas (`guild_id` null; "@me" na API).
    guild: Id,
    muted: bool = false,
    mute_end_ms: i64 = 0,
    mute_window: i32 = -1,
    /// null: o padrão do servidor (o Discord manda 3 ou nada).
    level: ?Level = null,
    suppress_everyone: bool = false,
    suppress_roles: bool = false,
    /// Alocado com o alocador de quem montou (ver `freeList`).
    overrides: []Override = &.{},

    pub fn override(gs: *const GuildSettings, channel: Id) ?*const Override {
        for (gs.overrides) |*o| if (o.channel == channel) return o;
        return null;
    }
};

pub fn freeList(gpa: std.mem.Allocator, list: []const GuildSettings) void {
    for (list) |gs| if (gs.overrides.len > 0) gpa.free(gs.overrides);
    gpa.free(list);
}

/// Silenciado agora (o prazo, se tem, ainda não venceu).
pub fn mutedAt(muted: bool, end_ms: i64, now_ms: i64) bool {
    return muted and (end_ms == 0 or end_ms > now_ms);
}

/// Servidores e canais silenciados agora (o app expande servidor e
/// categoria em canais) e quando o primeiro prazo vence (0 = nenhum).
pub fn mutedIds(list: []const GuildSettings, now_ms: i64, out: *std.ArrayList(Id), gpa: std.mem.Allocator) !i64 {
    var next: i64 = 0;
    const keep = struct {
        fn f(n: *i64, end: i64, now: i64) void {
            if (end > now and (n.* == 0 or end < n.*)) n.* = end;
        }
    }.f;
    for (list) |gs| {
        if (gs.guild != 0 and mutedAt(gs.muted, gs.mute_end_ms, now_ms)) {
            try out.append(gpa, gs.guild);
            keep(&next, gs.mute_end_ms, now_ms);
        }
        for (gs.overrides) |o| if (mutedAt(o.muted, o.mute_end_ms, now_ms)) {
            try out.append(gpa, o.channel);
            keep(&next, o.mute_end_ms, now_ms);
        };
    }
    return next;
}

// --- Quem notifica -------------------------------------------------------------

/// O que a mensagem chama: DM, menção direta, @everyone/@here, cargo nosso,
/// palavra de alerta (core/filtros.zig).
pub const Ping = struct { dm: bool = false, me: bool = false, everyone: bool = false, role: bool = false, alert: bool = false };

/// O nível que vale num canal: o do canal, senão o do servidor. null = o
/// padrão do app (DMs e menções notificam, o resto não).
pub fn effectiveLevel(gs: ?*const GuildSettings, channel: Id, parent: Id) ?Level {
    const s = gs orelse return null;
    for ([_]Id{ channel, parent }) |id| {
        if (id == 0) continue;
        if (s.override(id)) |o| if (o.level != .inherit) return o.level;
    }
    return s.level;
}

/// Notifica? (silenciado o app já tirou antes.) `nothing` cala até menção;
/// `all` escolhido de propósito notifica tudo; senão DM, menção e alerta,
/// com @everyone e cargos respeitando "suprimir".
pub fn shouldNotify(level: ?Level, suppress_everyone: bool, suppress_roles: bool, p: Ping) bool {
    if (level) |l| switch (l) {
        .nothing => return false,
        .all => return true,
        .mentions, .inherit => {},
    };
    if (p.dm or p.me or p.alert) return true;
    if (p.everyone and !suppress_everyone) return true;
    return p.role and !suppress_roles;
}

// --- Textos para a API ------------------------------------------------------------

/// String JSON com aspas (o que o Discord aceita, sem mexer em UTF-8).
pub fn writeString(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    try out.append(gpa, '"');
    for (s) |ch| switch (ch) {
        '"' => try out.appendSlice(gpa, "\\\""),
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '\n' => try out.appendSlice(gpa, "\\n"),
        '\r' => try out.appendSlice(gpa, "\\r"),
        '\t' => try out.appendSlice(gpa, "\\t"),
        0...8, 11, 12, 14...0x1f => try out.print(gpa, "\\u{x:0>4}", .{ch}),
        else => try out.append(gpa, ch),
    };
    try out.append(gpa, '"');
}

/// ms desde 1970 -> "2026-11-07T15:04:05.000Z".
pub fn isoUtc(buf: []u8, ms: i64) []const u8 {
    const secs: u64 = @intCast(@max(@divFloor(ms, 1000), 0));
    const es: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{ yd.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute() }) catch "";
}

fn writeMuteConfig(out: *std.ArrayList(u8), gpa: std.mem.Allocator, muted: bool, end_ms: i64, window: i32) !void {
    if (!muted) return out.appendSlice(gpa, "null");
    if (end_ms == 0) return out.print(gpa, "{{\"end_time\":null,\"selected_time_window\":-1}}", .{});
    var ib: [40]u8 = undefined;
    try out.print(gpa, "{{\"end_time\":\"{s}\",\"selected_time_window\":{d}}}", .{ isoUtc(&ib, end_ms), window });
}

/// Uma mudança de notificação escolhida pela pessoa.
pub const Change = union(enum) {
    /// Silenciar/reativar o servidor inteiro (não vale para as DMs).
    mute: bool,
    level: Level,
    suppress_everyone: bool,
    suppress_roles: bool,
    channel_mute: struct { channel: Id, on: bool },
    channel_level: struct { channel: Id, level: Level },
};

/// Corpo do PATCH /users/@me/guilds/{guild}/settings. Exceção de canal vai
/// inteira (silêncio, prazo, nível, recolhido), com o que já valia, para o
/// Discord não trocar por padrão o que não mudou. Alocado com `gpa`.
pub fn settingsBody(gpa: std.mem.Allocator, cur: ?*const GuildSettings, change: Change) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    switch (change) {
        .mute => |on| {
            try out.print(gpa, "{{\"muted\":{},\"mute_config\":", .{on});
            try writeMuteConfig(&out, gpa, on, 0, -1);
            try out.append(gpa, '}');
        },
        .level => |l| try out.print(gpa, "{{\"message_notifications\":{d}}}", .{@intFromEnum(if (l == .inherit) Level.mentions else l)}),
        .suppress_everyone => |on| try out.print(gpa, "{{\"suppress_everyone\":{}}}", .{on}),
        .suppress_roles => |on| try out.print(gpa, "{{\"suppress_roles\":{}}}", .{on}),
        .channel_mute, .channel_level => {
            const ch = switch (change) {
                .channel_mute => |m| m.channel,
                .channel_level => |m| m.channel,
                else => unreachable,
            };
            var o: Override = if (cur) |s| (if (s.override(ch)) |x| x.* else .{ .channel = ch }) else .{ .channel = ch };
            switch (change) {
                .channel_mute => |m| {
                    o.muted = m.on;
                    o.mute_end_ms = 0;
                    o.mute_window = -1;
                },
                .channel_level => |m| o.level = m.level,
                else => unreachable,
            }
            try out.print(gpa, "{{\"channel_overrides\":{{\"{d}\":{{\"muted\":{},\"mute_config\":", .{ ch, o.muted });
            try writeMuteConfig(&out, gpa, o.muted, o.mute_end_ms, o.mute_window);
            try out.print(gpa, ",\"message_notifications\":{d},\"collapsed\":{}}}}}}}", .{ @intFromEnum(o.level), o.collapsed });
        },
    }
    return out.toOwnedSlice(gpa);
}

/// As configurações depois da mudança, como o Discord vai devolver (a
/// demonstração usa; o app de verdade espera a resposta).
pub fn applied(gpa: std.mem.Allocator, cur: ?*const GuildSettings, guild: Id, change: Change) !GuildSettings {
    var gs: GuildSettings = if (cur) |s| s.* else .{ .guild = guild };
    gs.guild = guild;
    var list: std.ArrayList(Override) = .empty;
    errdefer list.deinit(gpa);
    try list.appendSlice(gpa, gs.overrides);
    switch (change) {
        .mute => |on| {
            gs.muted = on;
            gs.mute_end_ms = 0;
            gs.mute_window = -1;
        },
        .level => |l| gs.level = l,
        .suppress_everyone => |on| gs.suppress_everyone = on,
        .suppress_roles => |on| gs.suppress_roles = on,
        .channel_mute, .channel_level => {
            const ch = switch (change) {
                .channel_mute => |m| m.channel,
                .channel_level => |m| m.channel,
                else => unreachable,
            };
            const o = for (list.items) |*x| {
                if (x.channel == ch) break x;
            } else blk: {
                try list.append(gpa, .{ .channel = ch });
                break :blk &list.items[list.items.len - 1];
            };
            switch (change) {
                .channel_mute => |m| {
                    o.muted = m.on;
                    o.mute_end_ms = 0;
                    o.mute_window = -1;
                },
                .channel_level => |m| o.level = m.level,
                else => unreachable,
            }
        },
    }
    gs.overrides = try list.toOwnedSlice(gpa);
    return gs;
}

/// Bloquear: PUT /users/@me/relationships/{id}.
pub const block_body = "{\"type\":2}";
/// Pedido de amizade (ou aceitar o que veio): o `type` fica no padrão.
pub const friend_body = "{}";

pub const max_global_name = 32;
pub const max_pronouns = 40;
pub const max_bio = 190;
/// Texto do status personalizado (o Discord corta em 128).
pub const max_status_text = 128;

fn chars(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

pub const ProfileError = error{ TooLong, InvalidUtf8, OutOfMemory };

/// PATCH /users/@me: só o nome que aparece. Vazio volta para o nome de
/// usuário (`null`).
pub fn globalNameBody(gpa: std.mem.Allocator, name: []const u8) ProfileError![]u8 {
    const t = std.mem.trim(u8, name, " \t\r\n");
    if (!std.unicode.utf8ValidateSlice(t)) return error.InvalidUtf8;
    if (chars(t) > max_global_name) return error.TooLong;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"global_name\":");
    if (t.len == 0) try out.appendSlice(gpa, "null") else try writeString(&out, gpa, t);
    try out.append(gpa, '}');
    return out.toOwnedSlice(gpa);
}

/// PATCH /users/@me/profile: pronomes e "sobre mim".
pub fn profileBody(gpa: std.mem.Allocator, pronouns: []const u8, bio: []const u8) ProfileError![]u8 {
    const p = std.mem.trim(u8, pronouns, " \t\r\n");
    const b = std.mem.trimEnd(u8, bio, " \t\r\n");
    if (!std.unicode.utf8ValidateSlice(p) or !std.unicode.utf8ValidateSlice(b)) return error.InvalidUtf8;
    if (chars(p) > max_pronouns or chars(b) > max_bio) return error.TooLong;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"pronouns\":");
    try writeString(&out, gpa, p);
    try out.appendSlice(gpa, ",\"bio\":");
    try writeString(&out, gpa, b);
    try out.append(gpa, '}');
    return out.toOwnedSlice(gpa);
}

// --- Status personalizado ------------------------------------------------------------

/// Textos alocados com o alocador de quem montou (`deinit`). Vazio = sem.
pub const CustomStatus = struct {
    text: []const u8 = "",
    /// Emoji Unicode, ou o nome de um personalizado (com `emoji_id`).
    emoji_name: []const u8 = "",
    emoji_id: u64 = 0,
    /// Quando some (ms desde 1970); 0 = não some.
    expires_ms: i64 = 0,

    pub fn empty(s: CustomStatus) bool {
        return s.text.len == 0 and s.emoji_name.len == 0 and s.emoji_id == 0;
    }

    /// Vale agora (tem algo e não venceu).
    pub fn active(s: CustomStatus, now_ms: i64) bool {
        return !s.empty() and (s.expires_ms == 0 or s.expires_ms > now_ms);
    }

    pub fn dupe(s: CustomStatus, gpa: std.mem.Allocator) !CustomStatus {
        const t = try gpa.dupe(u8, s.text);
        errdefer gpa.free(t);
        return .{ .text = t, .emoji_name = try gpa.dupe(u8, s.emoji_name), .emoji_id = s.emoji_id, .expires_ms = s.expires_ms };
    }

    pub fn deinit(s: CustomStatus, gpa: std.mem.Allocator) void {
        gpa.free(s.text);
        gpa.free(s.emoji_name);
    }
};

/// Até quando, a partir da escolha do menu: 0 não some, 1 30 min, 2 1 h,
/// 3 4 h, 4 hoje (meia-noite local; `utc_offset_s` = hora local - UTC).
pub fn expiryFor(choice: u8, now_ms: i64, utc_offset_s: i64) i64 {
    return switch (choice) {
        1 => now_ms + 30 * 60_000,
        2 => now_ms + 60 * 60_000,
        3 => now_ms + 4 * 60 * 60_000,
        4 => blk: {
            const local_s = @divFloor(now_ms, 1000) + utc_offset_s;
            const day = @divFloor(local_s, 86400);
            break :blk ((day + 1) * 86400 - utc_offset_s) * 1000;
        },
        else => 0,
    };
}

/// A atividade "Custom Status" (tipo 4) para o op 3, ou nada se não vale.
/// `out` recebe `[...]` inteiro.
pub fn writeActivities(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: CustomStatus, now_ms: i64) !void {
    return writeActivitiesWith(out, gpa, s, now_ms, null);
}

/// Igual a `writeActivities`, mais `extra` depois do status personalizado: outra
/// atividade já em JSON (a do Rich Presence, net/rpc_proto.zig), que vai mesmo
/// sem status personalizado.
pub fn writeActivitiesWith(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: CustomStatus, now_ms: i64, extra: ?[]const u8) !void {
    try out.append(gpa, '[');
    if (s.active(now_ms)) {
        try out.appendSlice(gpa, "{\"type\":4,\"name\":\"Custom Status\"");
        if (s.text.len > 0) {
            try out.appendSlice(gpa, ",\"state\":");
            try writeString(out, gpa, s.text);
        }
        if (s.emoji_name.len > 0 or s.emoji_id != 0) {
            try out.appendSlice(gpa, ",\"emoji\":{\"name\":");
            try writeString(out, gpa, s.emoji_name);
            if (s.emoji_id != 0) try out.print(gpa, ",\"id\":\"{d}\"", .{s.emoji_id});
            try out.append(gpa, '}');
        }
        try out.append(gpa, '}');
        if (extra != null) try out.append(gpa, ',');
    }
    if (extra) |e| try out.appendSlice(gpa, e);
    try out.append(gpa, ']');
}

// --- Comandos, eventos e ações ---------------------------------------------------------

/// Pedido para a rede (textos alocados com o c_allocator; quem executa libera).
pub const Cmd = union(enum) {
    block: Id,
    /// Ignorar pela conta (true) ou deixar de ignorar.
    ignore: struct { user: Id, on: bool },
    friend_request: Id,
    /// `guild` 0 = DMs ("@me"). `body` é o JSON de `settingsBody`.
    /// `demo`: só na demonstração, o que o Discord devolveria (`applied`).
    guild_settings: struct { guild: Id, body: []const u8, demo: ?GuildSettings = null },
    custom_status: CustomStatus,
    /// Corpos de `globalNameBody` e `profileBody` (null = não muda).
    profile: struct { user_body: ?[]const u8 = null, profile_body: ?[]const u8 = null },

    pub fn deinit(cmd: Cmd, gpa: std.mem.Allocator) void {
        switch (cmd) {
            .guild_settings => |g| {
                gpa.free(g.body);
                if (g.demo) |x| if (x.overrides.len > 0) gpa.free(x.overrides);
            },
            .custom_status => |s| s.deinit(gpa),
            .profile => |p| {
                if (p.user_body) |b| gpa.free(b);
                if (p.profile_body) |b| gpa.free(b);
            },
            else => {},
        }
    }
};

pub const FriendStatus = enum { sent, captcha, rate_limited, failed };

/// O que a rede devolve (alocado com o c_allocator; quem recebe libera).
pub const Event = union(enum) {
    /// Todas as configurações (READY): trocam as que havia.
    guild_settings: []GuildSettings,
    /// As de um servidor (USER_GUILD_SETTINGS_UPDATE ou a resposta do PATCH).
    guild_settings_one: GuildSettings,
    /// Ignorados pela conta (READY): troca a lista.
    ignored_list: []Id,
    ignored: struct { user: Id, on: bool },
    custom_status: CustomStatus,
    /// O status personalizado não foi salvo (o motivo vai num aviso).
    custom_status_failed,
    friend_request: struct { user: Id, status: FriendStatus },
    /// Perfil salvo (`ok`) ou não.
    profile_saved: bool,

    pub fn deinit(e: Event, gpa: std.mem.Allocator) void {
        switch (e) {
            .guild_settings => |l| freeList(gpa, l),
            .guild_settings_one => |g| if (g.overrides.len > 0) gpa.free(g.overrides),
            .ignored_list => |l| gpa.free(l),
            .custom_status => |s| s.deinit(gpa),
            else => {},
        }
    }
};

/// Pedidos da interface para o app (textos alocados com o gpa da interface).
pub const Action = union(enum) {
    block: Id,
    /// Desbloquear é o "remover relação" que já existe.
    ignore: struct { user: Id, on: bool },
    friend_request: Id,
    /// `target`: servidor, canal ou DM; o app descobre de onde é.
    notif: struct { target: Id, change: Change },
    /// `choice` como em `expiryFor`.
    custom_status: struct { text: []const u8, emoji: []const u8, choice: u8 },
    clear_custom_status,
    save_profile: struct { name: []const u8, pronouns: []const u8, bio: []const u8 },
};

// --- Estado do lado da interface -------------------------------------------------------

/// Pedido de amizade desta sessão, para o botão do perfil.
pub const FriendState = enum { sending, sent, captcha, rate_limited, failed };

/// O que a interface sabe da conta. Tudo com o c_allocator (o mesmo dos
/// eventos, que entregam a posse).
pub const State = struct {
    /// Por servidor (0 = DMs).
    guilds: std.AutoHashMapUnmanaged(Id, GuildSettings) = .empty,
    /// Quando o primeiro silêncio com prazo vence (0 = nenhum).
    next_expiry_ms: i64 = 0,
    custom: CustomStatus = .{},
    /// Salvando o status personalizado / o perfil.
    status_busy: bool = false,
    profile_busy: bool = false,
    /// Pedidos de amizade feitos nesta sessão.
    friends: std.AutoHashMapUnmanaged(Id, FriendState) = .empty,

    const ca = std.heap.c_allocator;

    pub fn settings(s: *const State, guild: Id) ?*const GuildSettings {
        return s.guilds.getPtr(guild);
    }

    /// Fica com as exceções de `gs`.
    pub fn put(s: *State, gs: GuildSettings) void {
        const gop = s.guilds.getOrPut(ca, gs.guild) catch {
            if (gs.overrides.len > 0) ca.free(gs.overrides);
            return;
        };
        if (gop.found_existing and gop.value_ptr.overrides.len > 0) ca.free(gop.value_ptr.overrides);
        gop.value_ptr.* = gs;
    }

    /// Troca tudo (READY). Fica com a lista e as exceções.
    pub fn replaceAll(s: *State, list: []GuildSettings) void {
        s.clearGuilds();
        for (list) |gs| s.put(gs);
        ca.free(list);
    }

    fn clearGuilds(s: *State) void {
        var it = s.guilds.valueIterator();
        while (it.next()) |gs| if (gs.overrides.len > 0) ca.free(gs.overrides);
        s.guilds.clearRetainingCapacity();
    }

    /// Fica com os textos de `cs`.
    pub fn setCustom(s: *State, cs: CustomStatus) void {
        s.custom.deinit(ca);
        s.custom = cs;
    }

    /// Silenciado agora (servidor inteiro, ou só o canal/categoria/DM).
    pub fn guildMuted(s: *const State, guild: Id, now_ms: i64) bool {
        const gs = s.settings(guild) orelse return false;
        return guild != 0 and mutedAt(gs.muted, gs.mute_end_ms, now_ms);
    }

    pub fn channelMuted(s: *const State, guild: Id, channel: Id, now_ms: i64) bool {
        const gs = s.settings(guild) orelse return false;
        const o = gs.override(channel) orelse return false;
        return mutedAt(o.muted, o.mute_end_ms, now_ms);
    }

    /// Outra conta: nada daqui vale mais.
    pub fn reset(s: *State) void {
        s.clearGuilds();
        s.next_expiry_ms = 0;
        s.custom.deinit(ca);
        s.custom = .{};
        s.status_busy = false;
        s.profile_busy = false;
        s.friends.clearRetainingCapacity();
    }

    pub fn deinit(s: *State) void {
        s.reset();
        s.guilds.deinit(ca);
        s.friends.deinit(ca);
    }
};

// --- Testes -----------------------------------------------------------------------

test "estado: trocar, substituir e silenciar" {
    var s: State = .{};
    defer s.deinit();
    const ca = std.heap.c_allocator;
    const l = try ca.alloc(GuildSettings, 2);
    const ov = try ca.alloc(Override, 1);
    ov[0] = .{ .channel = 10, .muted = true };
    l[0] = .{ .guild = 1, .overrides = ov };
    l[1] = .{ .guild = 2, .muted = true, .mute_end_ms = 50 };
    s.replaceAll(l);
    try std.testing.expect(s.channelMuted(1, 10, 0) and !s.channelMuted(1, 11, 0));
    try std.testing.expect(s.guildMuted(2, 10) and !s.guildMuted(2, 60));
    s.put(.{ .guild = 1, .muted = true });
    try std.testing.expect(s.guildMuted(1, 0) and !s.channelMuted(1, 10, 0));
    s.setCustom(try (CustomStatus{ .text = "oi" }).dupe(ca));
    try std.testing.expectEqualStrings("oi", s.custom.text);
}


test "silêncio com e sem prazo e o próximo vencimento" {
    const gpa = std.testing.allocator;
    var ov = [_]Override{ .{ .channel = 10, .muted = true, .mute_end_ms = 5_000 }, .{ .channel = 11, .muted = true }, .{ .channel = 12, .muted = false } };
    var dm = [_]Override{.{ .channel = 40, .muted = true, .mute_end_ms = 900 }};
    const list = [_]GuildSettings{
        .{ .guild = 1, .muted = true, .mute_end_ms = 3_000 },
        .{ .guild = 2, .overrides = &ov },
        .{ .guild = 0, .muted = true, .overrides = &dm },
    };
    var out: std.ArrayList(Id) = .empty;
    defer out.deinit(gpa);
    const next = try mutedIds(&list, 1_000, &out, gpa);
    // As DMs inteiras não têm um id para silenciar; o canal 40 já venceu.
    try std.testing.expectEqualSlices(Id, &.{ 1, 10, 11 }, out.items);
    try std.testing.expectEqual(@as(i64, 3_000), next);
}

test "nível do canal, do pai e do servidor; quem notifica" {
    var ov = [_]Override{ .{ .channel = 10, .level = .nothing }, .{ .channel = 20, .level = .all }, .{ .channel = 11 } };
    const gs: GuildSettings = .{ .guild = 1, .level = .mentions, .suppress_everyone = true, .overrides = &ov };
    try std.testing.expectEqual(@as(?Level, .nothing), effectiveLevel(&gs, 10, 0));
    // Canal sem nível próprio segue a categoria, depois o servidor.
    try std.testing.expectEqual(@as(?Level, .all), effectiveLevel(&gs, 11, 20));
    try std.testing.expectEqual(@as(?Level, .mentions), effectiveLevel(&gs, 99, 0));
    try std.testing.expectEqual(@as(?Level, null), effectiveLevel(null, 99, 0));

    try std.testing.expect(!shouldNotify(.nothing, false, false, .{ .me = true }));
    try std.testing.expect(shouldNotify(.all, false, false, .{}));
    try std.testing.expect(!shouldNotify(.mentions, false, false, .{}));
    try std.testing.expect(shouldNotify(null, false, false, .{ .dm = true }));
    try std.testing.expect(!shouldNotify(.mentions, true, false, .{ .everyone = true }));
    try std.testing.expect(shouldNotify(.mentions, false, false, .{ .everyone = true }));
    try std.testing.expect(!shouldNotify(null, false, true, .{ .role = true }));
    try std.testing.expect(shouldNotify(null, true, true, .{ .everyone = true, .me = true }));
}

test "corpos do PATCH de notificações" {
    const gpa = std.testing.allocator;
    const cases = [_]struct { change: Change, want: []const u8 }{
        .{ .change = .{ .mute = true }, .want = "{\"muted\":true,\"mute_config\":{\"end_time\":null,\"selected_time_window\":-1}}" },
        .{ .change = .{ .mute = false }, .want = "{\"muted\":false,\"mute_config\":null}" },
        .{ .change = .{ .level = .nothing }, .want = "{\"message_notifications\":2}" },
        .{ .change = .{ .suppress_everyone = true }, .want = "{\"suppress_everyone\":true}" },
        .{ .change = .{ .suppress_roles = false }, .want = "{\"suppress_roles\":false}" },
    };
    for (cases) |cs| {
        const b = try settingsBody(gpa, null, cs.change);
        defer gpa.free(b);
        try std.testing.expectEqualStrings(cs.want, b);
    }
    // A exceção do canal leva o que já valia (nível e recolhido).
    var ov = [_]Override{.{ .channel = 7, .level = .all, .collapsed = true }};
    const gs: GuildSettings = .{ .guild = 1, .overrides = &ov };
    const b1 = try settingsBody(gpa, &gs, .{ .channel_mute = .{ .channel = 7, .on = true } });
    defer gpa.free(b1);
    try std.testing.expectEqualStrings("{\"channel_overrides\":{\"7\":{\"muted\":true,\"mute_config\":{\"end_time\":null,\"selected_time_window\":-1},\"message_notifications\":0,\"collapsed\":true}}}", b1);
    // Nível com um silêncio com prazo: o prazo continua.
    var ov2 = [_]Override{.{ .channel = 8, .muted = true, .mute_end_ms = 1_700_000_000_000, .mute_window = 3600 }};
    const gs2: GuildSettings = .{ .guild = 1, .overrides = &ov2 };
    const b2 = try settingsBody(gpa, &gs2, .{ .channel_level = .{ .channel = 8, .level = .mentions } });
    defer gpa.free(b2);
    try std.testing.expectEqualStrings("{\"channel_overrides\":{\"8\":{\"muted\":true,\"mute_config\":{\"end_time\":\"2023-11-14T22:13:20.000Z\",\"selected_time_window\":3600},\"message_notifications\":1,\"collapsed\":false}}}", b2);
    const b3 = try settingsBody(gpa, null, .{ .channel_level = .{ .channel = 9, .level = .inherit } });
    defer gpa.free(b3);
    try std.testing.expectEqualStrings("{\"channel_overrides\":{\"9\":{\"muted\":false,\"mute_config\":null,\"message_notifications\":3,\"collapsed\":false}}}", b3);
}

test "aplicar uma mudança cria a exceção que faltava" {
    const gpa = std.testing.allocator;
    const a = try applied(gpa, null, 5, .{ .channel_mute = .{ .channel = 50, .on = true } });
    defer gpa.free(a.overrides);
    try std.testing.expectEqual(@as(usize, 1), a.overrides.len);
    try std.testing.expect(a.overrides[0].muted);
    const b = try applied(gpa, &a, 5, .{ .channel_level = .{ .channel = 50, .level = .nothing } });
    defer gpa.free(b.overrides);
    try std.testing.expect(b.overrides[0].muted and b.overrides[0].level == .nothing);
    const c2 = try applied(gpa, &b, 5, .{ .mute = true });
    defer gpa.free(c2.overrides);
    try std.testing.expect(c2.muted and c2.overrides.len == 1);
}

/// `s` repetido `n` vezes (nos testes).
fn repeat(buf: []u8, s: []const u8, n: usize) []const u8 {
    for (0..n) |i| @memcpy(buf[i * s.len ..][0..s.len], s);
    return buf[0 .. n * s.len];
}

test "corpos do perfil: limites, aspas e nome vazio" {
    const gpa = std.testing.allocator;
    var rb: [512]u8 = undefined;
    const n = try globalNameBody(gpa, "  Ana \"A\"  ");
    defer gpa.free(n);
    try std.testing.expectEqualStrings("{\"global_name\":\"Ana \\\"A\\\"\"}", n);
    const e = try globalNameBody(gpa, "   ");
    defer gpa.free(e);
    try std.testing.expectEqualStrings("{\"global_name\":null}", e);
    try std.testing.expectError(error.TooLong, globalNameBody(gpa, repeat(&rb, "a", 33)));
    // 32 letras acentuadas cabem (o limite é em caracteres, não bytes).
    const acc = try globalNameBody(gpa, repeat(&rb, "é", 32));
    gpa.free(acc);
    try std.testing.expectError(error.InvalidUtf8, globalNameBody(gpa, "\xff"));
    const p = try profileBody(gpa, "ela/dela", "linha 1\nlinha 2");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("{\"pronouns\":\"ela/dela\",\"bio\":\"linha 1\\nlinha 2\"}", p);
    try std.testing.expectError(error.TooLong, profileBody(gpa, repeat(&rb, "x", 41), ""));
    try std.testing.expectError(error.TooLong, profileBody(gpa, "", repeat(&rb, "x", 191)));
}

test "prazo do status e a atividade do op 3" {
    try std.testing.expectEqual(@as(i64, 0), expiryFor(0, 1000, 0));
    try std.testing.expectEqual(@as(i64, 1000 + 1_800_000), expiryFor(1, 1000, 0));
    try std.testing.expectEqual(@as(i64, 1000 + 14_400_000), expiryFor(3, 1000, 0));
    // 2023-11-14 22:13:20 UTC, fuso -03:00: hoje acaba à meia-noite local (03:00 UTC do dia 15).
    try std.testing.expectEqual(@as(i64, 1_700_017_200_000), expiryFor(4, 1_700_000_000_000, -3 * 3600));
    try std.testing.expectEqual(@as(i64, 1_700_006_400_000), expiryFor(4, 1_700_000_000_000, 0));

    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try writeActivities(&out, gpa, .{ .text = "no \"ar\"", .emoji_name = "🎧" }, 0);
    try std.testing.expectEqualStrings("[{\"type\":4,\"name\":\"Custom Status\",\"state\":\"no \\\"ar\\\"\",\"emoji\":{\"name\":\"🎧\"}}]", out.items);
    out.clearRetainingCapacity();
    try writeActivities(&out, gpa, .{ .emoji_name = "blob", .emoji_id = 99 }, 0);
    try std.testing.expectEqualStrings("[{\"type\":4,\"name\":\"Custom Status\",\"emoji\":{\"name\":\"blob\",\"id\":\"99\"}}]", out.items);
    out.clearRetainingCapacity();
    // Vencido: nada vai para os outros.
    try writeActivities(&out, gpa, .{ .text = "x", .expires_ms = 10 }, 20);
    try std.testing.expectEqualStrings("[]", out.items);
    // Com o Rich Presence: o status personalizado primeiro, a atividade do jogo depois;
    // sem status personalizado (ou vencido), só a do jogo.
    const game = "{\"type\":0,\"name\":\"Jogo\"}";
    out.clearRetainingCapacity();
    try writeActivitiesWith(&out, gpa, .{ .text = "ar" }, 0, game);
    try std.testing.expectEqualStrings("[{\"type\":4,\"name\":\"Custom Status\",\"state\":\"ar\"}," ++ game ++ "]", out.items);
    out.clearRetainingCapacity();
    try writeActivitiesWith(&out, gpa, .{ .text = "x", .expires_ms = 10 }, 20, game);
    try std.testing.expectEqualStrings("[" ++ game ++ "]", out.items);
    out.clearRetainingCapacity();
    try writeActivitiesWith(&out, gpa, .{}, 0, null);
    try std.testing.expectEqualStrings("[]", out.items);
}
