//! QA da conta no Discord: bloquear, ignorar pela conta (e os de antes, só
//! locais), pedido de amizade (um por clique, captcha explicado) e pelo nome de
//! usuário na página Amigos, silenciar e notificações nos dois sentidos,
//! status personalizado e perfil. O
//! servidor de mentira (net/fake_conta.zig) responde como o Discord.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const types = @import("core/types.zig");
const gw = @import("net/fake_gateway.zig");
const fc = @import("net/fake_conta.zig");
const status_proto = @import("net/status_proto.zig");
const jsonx = @import("net/jsonx.zig");
const app_conta = @import("app_conta.zig");
const platform = @import("platform/window.zig");
const Id = types.Id;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 5000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

const guild0: Id = 500_000;
const geral: Id = 500_005;
const memes: Id = 500_006;
const mari: Id = 1007;
const bruno: Id = 1002;
const lulu: Id = 1004;
const gustavo: Id = 1008;
const ana: Id = 1001;
const kaique: Id = 1003;

fn load(a: anytype) u64 {
    return a.load(.acquire);
}
fn body() []const u8 {
    return fc.sent.body();
}
fn has(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}
fn userMenu(app: *App, uid: Id) void {
    app.st.popup = .{ .menu = .{ .kind = .user, .id = uid, .x = 420, .y = 260 } };
}
fn dmOf(app: *App, uid: Id) Id {
    for (app.store.channelsOf(0)) |ch| if (app.store.channel(ch)) |cs| {
        if (!cs.info.group and cs.info.recipient == uid) return ch;
    };
    return 0;
}

// --- Bloquear ---------------------------------------------------------------------

fn menuMari(app: *App) void {
    userMenu(app, mari);
}
fn confirmOpen(app: *App) bool {
    return app.st.popup == .menu and app.st.popup.menu.kind == .block_confirm and load(&fc.sent.blocks) == 0;
}
fn mariBlocked(app: *App) bool {
    // Pelo menu de contexto: o X-Context-Properties diz "ContextMenu".
    return app.store.relationship(mari) == .blocked and load(&fc.sent.blocks) == 1 and load(&fc.sent.block_user) == mari and app.st.popup == .none and
        fc.lastFrom() == .context_menu;
}
fn mariFree(app: *App) bool {
    return app.store.relationship(mari) == .none and load(&fc.sent.blocks) == 1 and load(&fc.sent.rel_user) == mari and fc.lastFrom() == .context_menu;
}
fn fullBruno(app: *App) void {
    app.handle(.{ .open_full_profile = .{ .user = bruno } });
}
fn profileBlockAsks(app: *App) bool {
    return app.st.popup == .menu and app.st.popup.menu.kind == .block_confirm and app.st.popup.menu.id == bruno;
}
fn cancelKept(app: *App) bool {
    return app.st.popup == .none and app.store.relationship(bruno) == .friend and load(&fc.sent.blocks) == 1;
}

// --- Ignorar ----------------------------------------------------------------------

fn menuBruno(app: *App) void {
    userMenu(app, bruno);
}
fn brunoIgnored(app: *App) bool {
    const f = &app.st.filtros;
    return f.account.contains(bruno) and !f.ignored.contains(bruno) and load(&fc.sent.ignores) == 1;
}
fn legacyLulu(app: *App) void {
    app.st.filtros.setIgnored(app.gpa, lulu, true);
}
fn bothListed(_: *App) bool {
    return qa.find("unignore:1002") != null and qa.find("unignore:1004") != null;
}
fn brunoBack(app: *App) bool {
    return !app.st.filtros.isIgnored(bruno) and load(&fc.sent.ignores) == 2 and qa.find("unignore:1002") == null;
}
fn luluBack(app: *App) bool {
    // O antigo sai só daqui: nada vai para o Discord.
    return !app.st.filtros.isIgnored(lulu) and load(&fc.sent.ignores) == 2;
}

// --- Amizade ----------------------------------------------------------------------

fn unfriendGustavo(app: *App) void {
    app.handle(.{ .remove_relationship = .{ .user = gustavo, .from = .context_menu } });
}
fn gustavoNone(app: *App) bool {
    return app.store.relationship(gustavo) == .none;
}
fn fullGustavo(app: *App) void {
    app.handle(.{ .open_full_profile = .{ .user = gustavo } });
}
fn addShown(_: *App) bool {
    return qa.find("profile-btn:add") != null;
}
fn requestSent(app: *App) bool {
    // Pelo perfil: o lugar vai como "user profile modal v2".
    return load(&fc.sent.friend_requests) == 1 and app.store.relationship(gustavo) == .outgoing and qa.find("profile-btn:sent") != null and qa.find("profile-btn:add") == null and
        load(&fc.sent.rel_user) == gustavo and fc.lastFrom() == .profile;
}
fn stillOne(_: *App) bool {
    return load(&fc.sent.friend_requests) == 1;
}
fn unfriendPedro(app: *App) void {
    app.handle(.{ .remove_relationship = .{ .user = fc.captcha_user, .from = .context_menu } });
}
fn pedroNone(app: *App) bool {
    return app.store.relationship(fc.captcha_user) == .none;
}
fn fullPedro(app: *App) void {
    app.handle(.{ .open_full_profile = .{ .user = fc.captcha_user } });
}
var rels0: u64 = 0;
var tab0: u8 = 0;
fn toFriends(app: *App) void {
    rels0 = load(&fc.sent.relationships);
    tab0 = app.st.friends_tab;
    app.handle(.open_friends);
    app.st.friends_tab = 2;
}
/// A aba de antes: o resto da bateria geral espera os amigos na página.
fn restoreTab(app: *App) void {
    app.st.friends_tab = tab0;
}
fn gustavoPending(_: *App) bool {
    return qa.find("friend-remove:1008") != null;
}
fn gustavoCancelled(app: *App) bool {
    // Cancelar na aba Pendentes: um DELETE, com o lugar "Friends".
    return app.store.relationship(gustavo) == .none and load(&fc.sent.relationships) == rels0 + 1 and load(&fc.sent.rel_user) == gustavo and
        fc.lastFrom() == .friends and qa.find("friend-remove:1008") == null;
}
fn captchaExplained(app: *App) bool {
    const st = app.st.conta.friends.get(fc.captcha_user) orelse return false;
    // Sem repetir sozinho: um pedido, e o botão volta para a pessoa decidir.
    return st == .captcha and load(&fc.sent.friend_requests) == 2 and qa.find("profile-btn:add") != null and app.st.toast.is_error;
}

fn cardPedro(app: *App) void {
    app.st.popup = .{ .profile = .{ .user = fc.captcha_user, .x = 420, .y = 260 } };
}
fn cardOffersAdd(_: *App) bool {
    return qa.find("profile-add") != null;
}
fn cardRequested(app: *App) bool {
    // Um clique, um pedido (o captcha de novo devolve o botão para a pessoa).
    const st = app.st.conta.friends.get(fc.captcha_user) orelse return false;
    return load(&fc.sent.friend_requests) == 3 and st == .captcha;
}

// --- Adicionar amigo pelo nome --------------------------------------------------------

fn openFriends(app: *App) void {
    app.handle(.open_friends);
}
fn addTab(app: *App) bool {
    return app.st.friends and qa.find("add-friend-input") != null and qa.find("add-friend-send") != null;
}
fn noneByName(app: *App) bool {
    return load(&fc.sent.friend_names) == 0 and app.st.conta.name_status == null;
}
fn unknownShown(app: *App) bool {
    return load(&fc.sent.friend_names) == 1 and app.st.conta.name_status == .unknown and !app.st.conta.name_busy and
        qa.find("add-friend-result:unknown") != null;
}
fn unfriendKaique(app: *App) void {
    app.handle(.{ .remove_relationship = .{ .user = kaique, .from = .context_menu } });
}
fn kaiqueNone(app: *App) bool {
    return app.store.relationship(kaique) == .none;
}
fn kaiqueSent(app: *App) bool {
    // Um pedido, com o nome em minúsculas e sem o "@"; a pessoa vai para os pendentes.
    return load(&fc.sent.friend_names) == 2 and std.mem.eql(u8, body(), "{\"username\":\"kaique\",\"discriminator\":null}") and
        app.st.conta.name_status == .sent and app.store.relationship(kaique) == .outgoing and qa.find("add-friend-result:sent") != null;
}
fn alreadyShown(app: *App) bool {
    return load(&fc.sent.friend_names) == 3 and app.st.conta.name_status == .already and qa.find("add-friend-result:already") != null;
}

// --- Notificações -----------------------------------------------------------------

fn toGeral(app: *App) void {
    app.handle(.{ .open_message = .{ .channel = geral, .id = 0 } });
}
fn guildMuted(app: *App) bool {
    return load(&fc.sent.settings_patches) == 1 and load(&fc.sent.settings_guild) == guild0 and has(body(), "\"muted\":true") and
        app.st.conta.guildMuted(guild0, gw.nowMs()) and app.st.muted_channels.contains(memes);
}
var notified0: u32 = 0;
var seq: u64 = 0;
fn injectMention(app: *App) void {
    notified0 = app.st.filtros.notified;
    seq += 1;
    const ca = std.heap.c_allocator;
    var b: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&b, "<@{d}> olha isso", .{app.store.me}) catch return;
    const id = types.makeSnowflake(gw.nowMs(), 0x3c000 + seq);
    app.events.push(.{ .message_create = .{ .id = id, .channel = memes, .author = ana, .timestamp = @divTrunc(gw.nowMs(), 1000), .content = ca.dupe(u8, text) catch return } });
    platform.Window.wake(app.win.wake_type, .gateway);
}
var injected_at: i64 = 0;
fn markInject(app: *App) void {
    injectMention(app);
    injected_at = gw.nowMs();
}
fn silentWhileMuted(app: *App) bool {
    // A menção chega, mas o servidor silenciado na conta não notifica.
    return gw.nowMs() - injected_at > 400 and app.st.filtros.notified == notified0;
}
/// O que outro aparelho mudou chega como USER_GUILD_SETTINGS_UPDATE.
fn remote(app: *App) void {
    const json =
        \\{"guild_id":"500000","muted":false,"mute_config":null,"message_notifications":2,"suppress_everyone":true,"suppress_roles":false,
        \\ "channel_overrides":[{"channel_id":"500005","muted":true,"mute_config":null,"message_notifications":3,"collapsed":false}],"version":7}
    ;
    const e = fc.remoteEvent(json) orelse return;
    app.events.push(e);
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn remoteApplied(app: *App) bool {
    const gs = app.st.conta.settings(guild0) orelse return false;
    return !app.st.conta.guildMuted(guild0, gw.nowMs()) and gs.level == .nothing and gs.suppress_everyone and
        app.st.muted_channels.contains(geral) and !app.st.muted_channels.contains(memes) and load(&fc.sent.settings_patches) == 1;
}
fn silentNothing(app: *App) bool {
    // "Nada" no servidor: nem a menção notifica.
    return gw.nowMs() - injected_at > 400 and app.st.filtros.notified == notified0;
}
fn notifMarked(_: *App) bool {
    return qa.find("menu-on:Nada") != null and qa.find("menu-on:Suprimir @everyone e @here") != null and qa.find("menu-on:Todas as mensagens") == null;
}
fn levelAll(app: *App) bool {
    const gs = app.st.conta.settings(guild0) orelse return false;
    return load(&fc.sent.settings_patches) == 2 and std.mem.eql(u8, body(), "{\"message_notifications\":0}") and gs.level == .all;
}
fn notifiedAll(app: *App) bool {
    return app.st.filtros.notified == notified0 + 1;
}
fn memesMuted(app: *App) bool {
    return load(&fc.sent.settings_patches) == 3 and has(body(), "\"channel_overrides\":{\"500006\":{\"muted\":true") and
        app.st.conta.channelMuted(guild0, memes, gw.nowMs()) and app.st.muted_channels.contains(memes);
}
fn channelLevel(app: *App) bool {
    const gs = app.st.conta.settings(guild0) orelse return false;
    const o = gs.override(memes) orelse return false;
    // O silêncio que já valia vai junto (o Discord não troca o resto).
    return load(&fc.sent.settings_patches) == 4 and has(body(), "\"500006\":{\"muted\":true") and has(body(), "\"message_notifications\":1") and o.level == .mentions and o.muted;
}
fn menuAna(app: *App) void {
    userMenu(app, ana);
}
fn dmMuted(app: *App) bool {
    const dm = dmOf(app, ana);
    return dm != 0 and load(&fc.sent.settings_patches) == 5 and load(&fc.sent.settings_guild) == 0 and app.st.conta.channelMuted(0, dm, gw.nowMs()) and app.st.muted_channels.contains(dm);
}
/// No fim, outro aparelho volta o servidor e as DMs ao padrão (sem silêncio nem exceções): o
/// resto da bateria geral conta notificações no #geral, no #memes e nas DMs.
const reset_guild =
    \\{"guild_id":"500000","muted":false,"mute_config":null,"message_notifications":3,"suppress_everyone":false,"suppress_roles":false,"channel_overrides":[],"version":8}
;
const reset_dms =
    \\{"guild_id":null,"muted":false,"mute_config":null,"message_notifications":3,"suppress_everyone":false,"suppress_roles":false,"channel_overrides":[],"version":9}
;
fn remoteReset(app: *App) void {
    for ([_][]const u8{ reset_guild, reset_dms }) |json| {
        const e = fc.remoteEvent(json) orelse continue;
        app.events.push(e);
    }
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn resetApplied(app: *App) bool {
    const gs = app.st.conta.settings(guild0) orelse return false;
    const dms = app.st.conta.settings(0) orelse return false;
    const dm = dmOf(app, ana);
    return gs.level == null and gs.overrides.len == 0 and !gs.suppress_everyone and !app.st.conta.guildMuted(guild0, gw.nowMs()) and
        dms.overrides.len == 0 and dm != 0 and !app.st.muted_channels.contains(dm) and
        !app.st.muted_channels.contains(geral) and !app.st.muted_channels.contains(memes);
}

// --- Status personalizado ---------------------------------------------------------

fn statusPopup(app: *App) bool {
    return app.st.popup == .custom_status and qa.find("custom-status-save") != null;
}
fn statusSaved(app: *App) bool {
    const cs = app.st.conta.custom;
    const left = cs.expires_ms - gw.nowMs();
    return load(&fc.sent.statuses) == 1 and std.mem.eql(u8, cs.text, "no ar") and std.mem.eql(u8, cs.emoji_name, "🎧") and
        left > 50 * 60_000 and left <= 60 * 60_000 and app.st.popup == .none and qa.find("me-custom-status") != null;
}
fn statusCleared(app: *App) bool {
    return load(&fc.sent.statuses) == 2 and app.st.conta.custom.empty() and qa.find("me-custom-status") == null;
}

// --- Status da conta --------------------------------------------------------------

var statuses0: u64 = 0;
fn markStatuses(_: *App) void {
    statuses0 = load(&fc.sent.account_statuses);
}
/// O status que foi no último PATCH das configurações (o proto do corpo).
fn sentStatus() ?status_proto.Stored {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const ar = arena.allocator();
    const v = std.json.parseFromSliceLeaky(std.json.Value, ar, fc.sent.statusBody(), .{}) catch return null;
    const bytes = status_proto.decodeBase64(ar, jsonx.str(jsonx.get(v, "settings")) orelse return null) catch return null;
    // Só o campo 11 vai, e a versão das configurações lidas junto.
    if (bytes.len == 0 or bytes[0] != 0x5a or jsonx.int(jsonx.get(v, "required_data_version")) == null) return null;
    return (status_proto.readStatus(bytes) catch return null) orelse null;
}
fn meUser(app: *App) ?*const types.User {
    return app.store.user(app.store.me);
}
fn subShown(_: *App) bool {
    return qa.find("menu:Por 1 hora") != null and qa.find("menu:Até eu mudar") != null;
}
fn dndHour(app: *App) bool {
    const u = meUser(app) orelse return false;
    const until = app.st.conta.status_expires_ms;
    const left = until - gw.nowMs();
    if (load(&fc.sent.account_statuses) != statuses0 + 1 or u.status != .dnd or app.st.settings.my_status != 2) return false;
    if (left <= 59 * 60_000 or left > 60 * 60_000 or app.st.popup != .none) return false;
    const ss = sentStatus() orelse return false;
    // Não perturbe, o prazo, e o "mostrar a atividade" que já estava ligado continua ligado.
    // O painel mostra até quando, se não estiver mostrando uma atividade.
    return ss.status == .dnd and ss.expires_ms == until and ss.show_game == true and (u.activity != null or qa.find("me-status-until") != null);
}
fn dndUntilShown(_: *App) bool {
    return qa.find("menu-until:⊘  Não perturbe") != null and qa.find("menu-on:●  Online") == null;
}
/// Outro aparelho deixou ausente, até mudar (o USER_SETTINGS_PROTO_UPDATE).
fn remoteIdle(app: *App) void {
    var b: [64]u8 = undefined;
    const proto = [_]u8{ 0x5a, 0x08, 0x0a, 0x06, 0x0a, 0x04, 'i', 'd', 'l', 'e' };
    const b64 = std.base64.standard.Encoder.encode(&b, &proto);
    const e = fc.remoteStatus(b64) orelse return;
    app.events.push(e);
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn remoteIdleApplied(app: *App) bool {
    const u = meUser(app) orelse return false;
    // Só chegou: nada é gravado de volta.
    return u.status == .idle and app.st.settings.my_status == 1 and app.st.conta.status_expires_ms == 0 and
        qa.find("me-status-until") == null and load(&fc.sent.account_statuses) == statuses0 + 1;
}
fn idleMarked(_: *App) bool {
    return qa.find("menu-on:◐  Ausente") != null and qa.find("menu-on:⊘  Não perturbe") == null;
}
fn backOnline(app: *App) bool {
    const u = meUser(app) orelse return false;
    if (load(&fc.sent.account_statuses) != statuses0 + 2 or u.status != .online or app.st.conta.status_expires_ms != 0) return false;
    const ss = sentStatus() orelse return false;
    return ss.status == .online and ss.expires_ms == 0 and ss.show_game == true;
}
/// Invisível por pouco mais de um segundo: o prazo passa durante o QA.
fn shortInvisible(app: *App) void {
    app_conta.setStatus(app, .offline, gw.nowMs() + 1200, false);
}
fn invisibleUntil(app: *App) bool {
    const u = meUser(app) orelse return false;
    const ss = sentStatus() orelse return false;
    return u.status == .offline and load(&fc.sent.account_statuses) == statuses0 + 3 and ss.status == .offline and ss.expires_ms != 0;
}
fn expiredOnline(app: *App) bool {
    const u = meUser(app) orelse return false;
    const ss = sentStatus() orelse return false;
    // O prazo passou: volta a online e grava na conta, sozinho.
    return u.status == .online and app.st.settings.my_status == 0 and app.st.conta.status_expires_ms == 0 and
        load(&fc.sent.account_statuses) == statuses0 + 4 and ss.status == .online and ss.expires_ms == 0;
}

// --- Perfil -----------------------------------------------------------------------

fn profileFields(_: *App) bool {
    return qa.find("account-name") != null and qa.find("account-pronouns") != null and qa.find("account-bio") != null;
}
fn profileSaved(app: *App) bool {
    const me = app.store.user(app.store.me) orelse return false;
    return load(&fc.sent.profiles) == 1 and std.mem.eql(u8, me.name, "rsha QA") and has(body(), "\"pronouns\":\"ela/dela\"") and !app.st.conta.profile_busy;
}

pub const ops = [_]Op{
    s("conta: bloquear"),
    run(toGeral),
    .{ .wait = 300 },
    run(menuMari),
    click("menu:Bloquear…"),
    expect("bloquear pede confirmação antes", confirmOpen),
    .{ .shot = "conta-bloquear" },
    click("menu:Bloquear mari"),
    expect("confirmar bloqueia na conta (PUT type 2)", mariBlocked),
    run(menuMari),
    click("menu:Desbloquear"),
    expect("desbloquear pelo mesmo menu", mariFree),
    run(fullBruno),
    click("profile-btn:block"),
    expect("o perfil também bloqueia, com confirmação", profileBlockAsks),
    click("menu:Cancelar"),
    expect("cancelar não manda nada", cancelKept),

    s("conta: ignorar"),
    run(menuBruno),
    click("menu:Ignorar"),
    expect("ignorar vai para a conta, não para a lista local", brunoIgnored),
    run(legacyLulu),
    .{ .click = .{ .mark = "user-btn:2" } },
    click("settings:Alertas e filtros"),
    expect("a página mostra os da conta e os antigos", bothListed),
    .{ .shot = "conta-ignorados" },
    click("unignore:1002"),
    expect("deixar de ignorar o da conta avisa o Discord", brunoBack),
    click("unignore:1004"),
    expect("o antigo sai só daqui", luluBack),
    click("settings-close"),

    s("conta: pedido de amizade"),
    run(unfriendGustavo),
    expect("(prepara alguém sem amizade)", gustavoNone),
    run(fullGustavo),
    expect("o perfil oferece adicionar", addShown),
    click("profile-btn:add"),
    expect("um pedido e o botão desliga", requestSent),
    .{ .shot = "conta-pedido" },
    click("profile-btn:sent"),
    .{ .wait = 300 },
    expect("clicar de novo não manda outro", stillOne),
    click("profile-full-close"),
    run(unfriendPedro),
    expect("(prepara quem pede captcha)", pedroNone),
    run(fullPedro),
    click("profile-btn:add"),
    expect("captcha é explicado, sem repetir sozinho", captchaExplained),
    click("profile-full-close"),
    run(cardPedro),
    expect("o cartão pequeno também oferece adicionar", cardOffersAdd),
    click("profile-add"),
    expect("pelo cartão é o mesmo pedido, um por clique", cardRequested),
    .{ .key = .{ .key = c.ImGuiKey_Escape } },

    s("conta: adicionar amigo pelo nome"),
    run(openFriends),
    click("friends-tab:add"),
    expect("a aba tem a caixa do nome e o botão", addTab),
    click("add-friend-send"),
    .{ .wait = 300 },
    expect("sem nome, o botão não manda nada", noneByName),
    click("add-friend-input"),
    .{ .text = "ninguem.existe" },
    click("add-friend-send"),
    expect("nome que ninguém tem explica o erro", unknownShown),
    run(unfriendKaique),
    expect("(prepara alguém sem amizade)", kaiqueNone),
    click("add-friend-input"),
    .{ .key = .{ .key = c.ImGuiKey_A, .ctrl = true } },
    .{ .text = "@Kaique" },
    .{ .key = .{ .key = c.ImGuiKey_Enter } },
    expect("um pedido por vez e a pessoa vai para os pendentes", kaiqueSent),
    .{ .shot = "conta-adicionar-amigo" },
    click("add-friend-input"),
    .{ .text = "ana.exe" },
    click("add-friend-send"),
    expect("quem já é amigo é explicado", alreadyShown),
    // A bateria geral segue daqui: a página de amigos volta para a lista.
    click("friends-tab:online"),

    s("conta: cancelar pedido de amizade"),
    run(toFriends),
    expect("o pedido enviado aparece em Pendentes", gustavoPending),
    .{ .shot = "conta-pendentes" },
    click("friend-remove:1008"),
    expect("cancelar tira o pedido, com o lugar da página Amigos", gustavoCancelled),
    run(restoreTab),

    s("conta: silenciar e notificações"),
    run(toGeral),
    .{ .wait = 300 },
    .{ .rclick = .{ .mark = "guild:500000" } },
    click("menu:Silenciar servidor"),
    expect("silenciar o servidor grava na conta", guildMuted),
    run(markInject),
    .{ .wait = 500 },
    expect("servidor silenciado não notifica nem com menção", silentWhileMuted),
    run(remote),
    expect("mudança feita em outro aparelho chega na hora", remoteApplied),
    run(markInject),
    .{ .wait = 500 },
    expect("\"nada\" não notifica", silentNothing),
    .{ .rclick = .{ .mark = "guild:500000" } },
    click("menu:Notificações…"),
    expect("o menu marca o que vale", notifMarked),
    .{ .shot = "conta-notificacoes" },
    click("menu:Todas as mensagens"),
    expect("trocar o nível grava na conta", levelAll),
    run(injectMention),
    expect("\"todas\" notifica", notifiedAll),
    .{ .rclick = .{ .mark = "channel:500006" } },
    click("menu:Silenciar canal"),
    expect("silenciar um canal grava a exceção dele", memesMuted),
    .{ .rclick = .{ .mark = "channel:500006" } },
    click("menu:Notificações do canal…"),
    click("menu:Só @menções"),
    expect("o nível do canal mantém o silêncio", channelLevel),
    run(menuAna),
    click("menu:Silenciar conversa"),
    expect("silenciar a DM vai para \"@me\"", dmMuted),
    run(remoteReset),
    expect("voltar ao padrão em outro aparelho tira os silêncios daqui", resetApplied),

    s("conta: status personalizado"),
    click("me"),
    click("menu:Definir status personalizado…"),
    expect("abre o status personalizado", statusPopup),
    .{ .text = "no ar" },
    click("custom-status-quick:1"),
    click("custom-status-expiry:2"),
    .{ .shot = "conta-status" },
    click("custom-status-save"),
    expect("salvar grava texto, emoji e prazo, e aparece no painel", statusSaved),
    click("me"),
    click("menu:Limpar status personalizado"),
    expect("limpar tira o status", statusCleared),

    s("conta: status da conta"),
    run(markStatuses),
    click("me"),
    .{ .hover = .{ .mark = "menu:⊘  Não perturbe" } },
    expect("passar o mouse no não perturbe abre o prazo", subShown),
    .{ .shot = "conta-status-prazo" },
    click("menu:Por 1 hora"),
    expect("o prazo grava o status na conta", dndHour),
    click("me"),
    expect("o menu mostra até quando vale", dndUntilShown),
    .{ .shot = "conta-status-ate" },
    .{ .key = .{ .key = c.ImGuiKey_Escape } },
    run(remoteIdle),
    expect("o status mudado em outro aparelho vale aqui", remoteIdleApplied),
    click("me"),
    expect("o menu marca o status de agora", idleMarked),
    click("menu:●  Online"),
    expect("online grava na conta, sem prazo e sem desligar a atividade", backOnline),
    run(shortInvisible),
    expect("(invisível por um segundo)", invisibleUntil),
    expect("o prazo passa e volta a online, gravando na conta", expiredOnline),

    s("conta: perfil"),
    .{ .click = .{ .mark = "user-btn:2" } },
    click("settings:Minha conta"),
    expect("a conta tem nome, pronomes e sobre mim", profileFields),
    click("account-name"),
    .{ .key = .{ .key = c.ImGuiKey_End } },
    .{ .text = " QA" },
    click("account-pronouns"),
    .{ .key = .{ .key = c.ImGuiKey_A, .ctrl = true } },
    .{ .text = "ela/dela" },
    .{ .shot = "conta-perfil" },
    click("account-save"),
    expect("salvar manda o nome e o perfil", profileSaved),
    click("settings-close"),
};
