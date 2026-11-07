//! A conta no Discord, do lado do app (core/conta.zig): transforma os
//! cliques em pedidos para a rede, guarda o que volta e decide o que
//! silencia e o que notifica. Cada ação daqui é um clique, um pedido.
const std = @import("std");
const App = @import("app.zig").App;
const conta = @import("core/conta.zig");
const types = @import("core/types.zig");
const leitura = @import("core/leitura.zig");
const store_mod = @import("core/store.zig");
const w = @import("ui/widgets.zig");
const nowMs = @import("net/fake_gateway.zig").nowMs;
const Id = types.Id;

const ca = std.heap.c_allocator;

fn userName(app: *App, uid: Id) []const u8 {
    return if (app.store.user(uid)) |u| u.name else "?";
}

pub fn handle(app: *App, a: conta.Action) void {
    const st = &app.st;
    switch (a) {
        .block => |uid| {
            if (uid == app.store.me) return;
            app.cmd(.{ .conta = .{ .block = uid } });
        },
        .ignore => |ig| {
            if (ig.user == app.store.me) return;
            if (ig.on) return app.cmd(.{ .conta = .{ .ignore = .{ .user = ig.user, .on = true } } });
            // Deixar de ignorar: o da lista local (de antes) sai aqui mesmo; o
            // da conta vai para o Discord.
            if (st.filtros.ignored.contains(ig.user)) {
                st.filtros.setIgnored(st.gpa, ig.user, false);
                if (!st.filtros.account.contains(ig.user)) st.showToast(nowMs(), false, "{s} não é mais ignorado", "no longer ignoring {s}", .{userName(app, ig.user)});
            }
            if (st.filtros.account.contains(ig.user)) app.cmd(.{ .conta = .{ .ignore = .{ .user = ig.user, .on = false } } });
        },
        .friend_request => |uid| {
            if (uid == app.store.me) return;
            // Um clique, um pedido: enquanto vai (ou depois de ir), nada sai de novo.
            if (st.conta.friends.get(uid)) |fs| if (fs == .sending or fs == .sent) return;
            st.conta.friends.put(ca, uid, .sending) catch return;
            app.cmd(.{ .conta = .{ .friend_request = uid } });
        },
        .notif => |n| notif(app, n.target, n.change),
        .custom_status => |cs| {
            defer st.gpa.free(cs.text);
            defer st.gpa.free(cs.emoji);
            if (st.conta.status_busy) return;
            const text = std.mem.trim(u8, cs.text, " \t\r\n");
            const emoji = std.mem.trim(u8, cs.emoji, " \t\r\n");
            if (text.len == 0 and emoji.len == 0) return handle(app, .clear_custom_status);
            const now = nowMs();
            const new: conta.CustomStatus = .{
                .text = ca.dupe(u8, utf8Chars(text, conta.max_status_text)) catch return,
                .emoji_name = ca.dupe(u8, utf8Chars(emoji, 32)) catch "",
                .expires_ms = conta.expiryFor(cs.choice, now, w.utcOffset(@divFloor(now, 1000))),
            };
            st.conta.status_busy = true;
            app.cmd(.{ .conta = .{ .custom_status = new } });
        },
        .clear_custom_status => {
            if (st.conta.status_busy) return;
            st.conta.status_busy = true;
            app.cmd(.{ .conta = .{ .custom_status = .{} } });
        },
        .save_profile => |p| {
            defer st.gpa.free(p.name);
            defer st.gpa.free(p.pronouns);
            defer st.gpa.free(p.bio);
            saveProfile(app, p.name, p.pronouns, p.bio);
        },
    }
}

/// Os primeiros `max` caracteres (sem cortar um no meio).
fn utf8Chars(s: []const u8, max: usize) []const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len and n < max) : (n += 1) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i = @min(s.len, i + len);
    }
    return s[0..i];
}

/// Silenciar ou nível de notificação: vai para a conta (o celular também
/// para de tocar); a tela muda quando o Discord confirma.
fn notif(app: *App, target: Id, change: conta.Change) void {
    const guild: Id = if (app.store.guild(target) != null) target else if (app.store.channel(target)) |cs| cs.info.guild else return;
    // Servidor inteiro só se mexe pelo menu do servidor; DMs não têm "servidor".
    switch (change) {
        .mute, .level, .suppress_everyone, .suppress_roles => if (guild == 0 or guild != target) return,
        .channel_mute, .channel_level => {},
    }
    const cur = app.st.conta.settings(guild);
    const body = conta.settingsBody(ca, cur, change) catch return;
    // A demonstração não tem servidor para guardar: leva a resposta pronta.
    const demo: ?conta.GuildSettings = if (app.store.demo) conta.applied(ca, cur, guild, change) catch null else null;
    app.cmd(.{ .conta = .{ .guild_settings = .{ .guild = guild, .body = body, .demo = demo } } });
}

fn saveProfile(app: *App, name: []const u8, pronouns: []const u8, bio: []const u8) void {
    const st = &app.st;
    if (st.conta.profile_busy) return;
    const me = app.store.me;
    const cur_name = userName(app, me);
    const pf = app.store.profiles.get(me);
    const name_t = std.mem.trim(u8, name, " \t\r\n");
    const want_name = !std.mem.eql(u8, name_t, cur_name);
    const want_profile = !std.mem.eql(u8, std.mem.trim(u8, pronouns, " \t\r\n"), if (pf) |x| x.pronouns else "") or
        !std.mem.eql(u8, std.mem.trimEnd(u8, bio, " \t\r\n"), if (pf) |x| x.bio else "");
    if (!want_name and !want_profile) return st.showToast(nowMs(), false, "nada mudou", "nothing changed", .{});
    const ub: ?[]u8 = if (want_name) conta.globalNameBody(ca, name_t) catch |err| return tooLong(app, err) else null;
    const pb: ?[]u8 = if (want_profile) conta.profileBody(ca, pronouns, bio) catch |err| {
        if (ub) |b| ca.free(b);
        return tooLong(app, err);
    } else null;
    st.conta.profile_busy = true;
    app.cmd(.{ .conta = .{ .profile = .{ .user_body = ub, .profile_body = pb } } });
}

fn tooLong(app: *App, err: conta.ProfileError) void {
    switch (err) {
        error.TooLong => app.st.showToast(nowMs(), true, "texto longo demais (nome 32, pronomes 40, sobre mim 190)", "text too long (name 32, pronouns 40, about me 190)", .{}),
        else => app.st.showToast(nowMs(), true, "texto inválido", "invalid text", .{}),
    }
}

pub fn onEvent(app: *App, e: conta.Event) void {
    const st = &app.st;
    switch (e) {
        .guild_settings => |l| {
            st.conta.replaceAll(l);
            refreshMuted(app);
        },
        .guild_settings_one => |gs| {
            st.conta.put(gs);
            refreshMuted(app);
        },
        .ignored_list => |ids| {
            defer ca.free(ids);
            st.filtros.setAccountList(st.gpa, ids);
        },
        .ignored => |ig| {
            const was = st.filtros.account.contains(ig.user);
            st.filtros.setAccountIgnored(st.gpa, ig.user, ig.on);
            if (was == ig.on) return;
            if (ig.on)
                st.showToast(nowMs(), false, "{s} ignorado na conta: as mensagens ficam recolhidas", "ignoring {s} on your account: their messages are collapsed", .{userName(app, ig.user)})
            else
                st.showToast(nowMs(), false, "{s} não é mais ignorado", "no longer ignoring {s}", .{userName(app, ig.user)});
        },
        .custom_status => |cs| {
            st.conta.setCustom(cs);
            st.conta.status_busy = false;
        },
        .custom_status_failed => st.conta.status_busy = false,
        .friend_request => |fr| {
            const fs: conta.FriendState = switch (fr.status) {
                .sent => .sent,
                .captcha => .captcha,
                .rate_limited => .rate_limited,
                .failed => .failed,
            };
            st.conta.friends.put(ca, fr.user, fs) catch {};
            const name = userName(app, fr.user);
            switch (fr.status) {
                .sent => st.showToast(nowMs(), false, "pedido de amizade enviado para {s}", "friend request sent to {s}", .{name}),
                .captcha => st.showToast(nowMs(), true, "o Discord pediu um captcha: mande o pedido para {s} pelo app oficial ou pelo site", "Discord asked for a captcha: send the request to {s} from the official app or website", .{name}),
                .rate_limited => st.showToast(nowMs(), true, "muitos pedidos agora: tente mais tarde", "too many requests right now: try again later", .{}),
                // O motivo já apareceu no aviso da rede.
                .failed => {},
            }
        },
        .profile_saved => |ok| {
            st.conta.profile_busy = false;
            if (!ok) return;
            st.showToast(nowMs(), false, "perfil salvo", "profile saved", .{});
            // Pronomes e "sobre mim" novos no cartão: o perfil vem de novo.
            if (!app.store.demo) app.cmd(.{ .fetch_profile = .{ .user = app.store.me, .guild = 0 } });
        },
    }
}

/// Os canais silenciados saem das configurações da conta (servidor e
/// categoria viram os canais deles). Só quando algo muda, nunca por quadro.
pub fn refreshMuted(app: *App) void {
    const st = &app.st;
    const now = nowMs();
    var ids: std.ArrayList(Id) = .empty;
    defer ids.deinit(app.gpa);
    var next: i64 = 0;
    var it = st.conta.guilds.valueIterator();
    while (it.next()) |gs| {
        const n = conta.mutedIds(&.{gs.*}, now, &ids, app.gpa) catch return;
        if (n != 0 and (next == 0 or n < next)) next = n;
    }
    st.conta.next_expiry_ms = next;
    st.muted_channels.clearRetainingCapacity();
    leitura.applyMuted(&app.store, &st.muted_channels, app.gpa, ids.items);
    for (app.store.guilds.items) |g| app.store.refreshGuildUnread(g.id);
}

/// Servidor que chegou depois do READY: os silêncios dele valem já.
pub fn onGuild(app: *App, guild: Id) void {
    const gs = app.st.conta.settings(guild) orelse return;
    var ids: std.ArrayList(Id) = .empty;
    defer ids.deinit(app.gpa);
    _ = conta.mutedIds(&.{gs.*}, nowMs(), &ids, app.gpa) catch return;
    if (ids.items.len == 0) return;
    leitura.applyMuted(&app.store, &app.st.muted_channels, app.gpa, ids.items);
    app.store.refreshGuildUnread(guild);
}

/// Um silêncio com prazo venceu? (olhado quando chega mensagem, sem relógio.)
fn expire(app: *App) void {
    const next = app.st.conta.next_expiry_ms;
    if (next != 0 and nowMs() >= next) refreshMuted(app);
}

/// Mensagem de outra pessoa: notifica? `important` é o que já valia (DM,
/// menção, alerta). Sem configuração da conta para o lugar, fica como antes.
pub fn allowsNotify(app: *App, m: types.Message, cs: *const store_mod.ChannelState, important: bool) bool {
    expire(app);
    if (app.st.muted_channels.contains(m.channel)) return false;
    const guild = cs.info.guild;
    const gs = app.st.conta.settings(guild);
    const level = conta.effectiveLevel(gs, m.channel, cs.info.parent orelse 0);
    if (level == null and gs == null) return important;
    const ping = pingOf(app, m, guild, important);
    const s = gs orelse return conta.shouldNotify(level, false, false, ping);
    return conta.shouldNotify(level, s.suppress_everyone, s.suppress_roles, ping);
}

fn pingOf(app: *App, m: types.Message, guild: Id, important: bool) conta.Ping {
    var p: conta.Ping = .{ .dm = guild == 0, .me = m.mentions_me, .everyone = m.mention_everyone };
    var rest = m.content;
    while (std.mem.indexOf(u8, rest, "<@&")) |i| {
        rest = rest[i + 3 ..];
        const end = std.mem.indexOfScalar(u8, rest, '>') orelse break;
        const role = std.fmt.parseInt(Id, rest[0..end], 10) catch continue;
        if (app.store.hasRole(guild, role)) {
            p.role = true;
            break;
        }
    }
    // A demonstração não tem os campos do servidor (como App.mentionsMe).
    if (app.store.demo) {
        var b: [32]u8 = undefined;
        if (std.fmt.bufPrint(&b, "<@{d}>", .{app.store.me})) |a| {
            if (std.mem.indexOf(u8, m.content, a) != null) p.me = true;
        } else |_| {}
        if (std.mem.indexOf(u8, m.content, "@everyone") != null or std.mem.indexOf(u8, m.content, "@here") != null) p.everyone = true;
    }
    p.alert = important and !p.dm and !p.me and !p.everyone and !p.role;
    return p;
}

/// O canal de DM com alguém (0 = não tem).
pub fn dmWith(app: *App, uid: Id) Id {
    for (app.store.channelsOf(0)) |ch| if (app.store.channel(ch)) |cs| {
        if (!cs.info.group and cs.info.recipient == uid) return ch;
    };
    return 0;
}
