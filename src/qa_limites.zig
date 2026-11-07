//! QA dos limites de envio (QA_SUITE=limites): modo lento com a contagem, o
//! 429 do servidor, quem é liberado, os motivos no lugar da caixa (sem
//! permissão, castigo, quarentena), Ctrl+Tab segurado e o op 14 que espera a
//! escolha parar. O "servidor" é a demonstração (net/fake_gateway.zig): o
//! #memes do "Rice do Hyprland" tem modo lento de 5 s, o #bugs do nosso tem
//! 30 s (somos donos), estamos de castigo em "os larpers" e em quarentena no
//! "CTF da madrugada".
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const limites = @import("core/limites.zig");
const send_limits = @import("ui/composer_limits.zig");
const platform = @import("platform/window.zig");
const Id = types.Id;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn slow(name: []const u8, f: *const fn (*App) bool, ms: u32) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = ms } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}

const memes1 = gw.channelId(1, 5);
const anuncios1 = gw.channelId(1, 2);
const bugs0 = gw.channelId(0, 11);
/// Sem DM com a gente na demonstração (as DMs são com 1001…1006 e o bot).
const no_dm_user: Id = 1007;

fn now() i64 {
    return gw.nowMs();
}

fn activeId(app: *App) Id {
    return app.st.activeChannel() orelse 0;
}

fn block(app: *App) limites.Block {
    return send_limits.blockForId(&app.store, activeId(app), now());
}

fn input(app: *App) []const u8 {
    return std.mem.sliceTo(&app.st.input, 0);
}

fn loaded(app: *App, id: Id) bool {
    const cs = app.store.channel(id) orelse return false;
    return activeId(app) == id and cs.history == .loaded;
}

/// A nossa última mensagem no canal aberto com este texto.
fn mine(app: *App, text: []const u8) ?*@import("core/store.zig").StoredMessage {
    const cs = app.store.channel(activeId(app)) orelse return null;
    var i = cs.messages.items.len;
    while (i > 0) {
        i -= 1;
        const m = &cs.messages.items[i];
        if (m.msg.author == app.store.me and std.mem.eql(u8, m.msg.content, text)) return m;
    }
    return null;
}

fn push(app: *App, e: @import("core/event.zig").Event) void {
    app.events.push(e);
    platform.Window.wake(app.win.wake_type, .gateway);
}

var sent_mark: u64 = 0;
var refusals_mark: u64 = 0;
var subs_mark: u64 = 0;
var dms_mark: u64 = 0;

fn markCounters(_: *App) void {
    sent_mark = gw.sent.messages.load(.monotonic);
    refusals_mark = gw.sent.slowmode_refusals.load(.monotonic);
    dms_mark = gw.sent.create_dms.load(.monotonic);
}
fn sentSince() u64 {
    return gw.sent.messages.load(.monotonic) - sent_mark;
}

// --- Modo lento ---------------------------------------------------------------

fn memesOpen(app: *App) bool {
    return loaded(app, memes1);
}
fn slowLabel(app: *App) bool {
    const b = block(app);
    return b.slowmode_s == 5 and !b.exempt and b.reason == .none and qa.find("slowmode") != null and qa.find("composer") != null;
}
fn firstSentAndCooling(app: *App) bool {
    const m = mine(app, "primeira no modo lento") orelse return false;
    return !m.pending and sentSince() == 1 and block(app).reason == .slowmode and qa.find("slowmode-cooldown") != null;
}
fn heldDraft(app: *App) bool {
    return sentSince() == 1 and mine(app, "segunda cedo demais") == null and std.mem.eql(u8, input(app), "segunda cedo demais") and block(app).reason == .slowmode;
}
fn cooldownOver(app: *App) bool {
    return block(app).reason == .none and qa.find("slowmode") != null and qa.find("slowmode-cooldown") == null;
}
fn draftSent(app: *App) bool {
    const m = mine(app, "segunda cedo demais") orelse return false;
    return !m.pending and !m.failed and sentSince() == 2 and input(app).len == 0;
}
/// Como depois de reabrir o app: a contagem daqui se perdeu, a do Discord não.
fn forgetCooldown(app: *App) void {
    _ = app;
    send_limits.state.cooldowns.clearRetainingCapacity();
}
fn refusedAndCooling(app: *App) bool {
    const m = mine(app, "terceira") orelse return false;
    return m.failed and gw.sent.slowmode_refusals.load(.monotonic) - refusals_mark == 1 and block(app).reason == .slowmode and sentSince() == 2;
}
fn resendHeld(app: *App) bool {
    const m = mine(app, "terceira") orelse return false;
    return m.failed and gw.sent.slowmode_refusals.load(.monotonic) - refusals_mark == 1;
}
fn resendTerceira(app: *App) void {
    const m = mine(app, "terceira") orelse return;
    app.actions.append(app.gpa, .{ .resend_message = .{ .channel = activeId(app), .nonce = m.msg.nonce } }) catch {};
}

// --- Liberado ------------------------------------------------------------------

fn bugsOpen(app: *App) bool {
    return loaded(app, bugs0);
}
fn exemptLabel(app: *App) bool {
    const b = block(app);
    return b.slowmode_s == 30 and b.exempt and b.reason == .none and qa.find("slowmode") != null;
}
fn bothSent(app: *App) bool {
    const a = mine(app, "uma") orelse return false;
    const b = mine(app, "duas") orelse return false;
    return !a.pending and !b.pending and !a.failed and !b.failed and sentSince() == 2 and block(app).reason == .none and
        gw.sent.slowmode_refusals.load(.monotonic) == refusals_mark;
}

/// O Discord recusou com 429 sem modo lento que valha (limite do canal para
/// mensagens seguidas): como o envio faria, só que direto pelo evento.
fn serverHoldBugs(app: *App) void {
    push(app, .{ .send_cooldown = .{ .channel = bugs0, .ms = 2500 } });
}
fn rateLimitedShown(app: *App) bool {
    return block(app).reason == .rate_limited and qa.find("slowmode-cooldown") != null and qa.find("composer") != null;
}
fn heldRate(app: *App) bool {
    return sentSince() == 2 and mine(app, "tres") == null and std.mem.eql(u8, input(app), "tres") and block(app).reason == .rate_limited;
}
fn rateOver(app: *App) bool {
    return block(app).reason == .none and qa.find("slowmode-cooldown") == null;
}
fn rateSent(app: *App) bool {
    const m = mine(app, "tres") orelse return false;
    return !m.pending and !m.failed and sentSince() == 3 and input(app).len == 0;
}

// --- Motivos no lugar da caixa ---------------------------------------------------

fn readonlyFor(app: *App, id: Id, reason: limites.Reason) bool {
    if (activeId(app) != id and id != 0) return false;
    var buf: [48]u8 = undefined;
    const k = std.fmt.bufPrint(&buf, "composer-reason:{t}", .{reason}) catch return false;
    return block(app).reason == reason and qa.find(k) != null and qa.find("composer-readonly") != null and qa.find("composer") == null;
}
fn noPermBand(app: *App) bool {
    return readonlyFor(app, anuncios1, .no_permission);
}
fn timeoutBand(app: *App) bool {
    const cs = app.store.channel(activeId(app)) orelse return false;
    if (cs.info.guild != gw.guildId(gw.timeout_guild)) return false;
    const b = block(app);
    // Uns 3 h na demonstração: o aviso mostra as horas.
    return readonlyFor(app, 0, .timed_out) and b.until_ms - now() > 2 * 3_600_000;
}
/// Os dois servidores ficam dentro de pastas na barra: abre como a pasta abriria.
fn openTimeoutGuild(app: *App) void {
    app.actions.append(app.gpa, .{ .select_guild = gw.guildId(gw.timeout_guild) }) catch {};
}
fn openQuarantineGuild(app: *App) void {
    app.actions.append(app.gpa, .{ .select_guild = gw.guildId(gw.quarantine_guild) }) catch {};
}
fn liftTimeout(app: *App) void {
    push(app, .{ .my_limits = .{ .guild = gw.guildId(gw.timeout_guild), .timeout_until_ms = 0 } });
}
fn composerBack(app: *App) bool {
    return block(app).reason == .none and qa.find("composer") != null and qa.find("composer-readonly") == null;
}
fn quarantineBand(app: *App) bool {
    const cs = app.store.channel(activeId(app)) orelse return false;
    return cs.info.guild == gw.guildId(gw.quarantine_guild) and readonlyFor(app, 0, .quarantined);
}
fn quarantineAccount(app: *App) void {
    push(app, .{ .account_flags = limites.user_quarantined });
}
fn accountQuarantined(_: *App) bool {
    return send_limits.state.accountQuarantined();
}
fn openNewDm(app: *App) void {
    app.actions.append(app.gpa, .{ .open_dm = no_dm_user }) catch {};
}
fn noDmAsked(app: *App) bool {
    return gw.sent.create_dms.load(.monotonic) == dms_mark and app.st.pending_dm != no_dm_user;
}
fn unquarantineAccount(app: *App) void {
    push(app, .{ .account_flags = 0 });
}
fn accountFree(_: *App) bool {
    return !send_limits.state.accountQuarantined();
}
fn dmAsked(_: *App) bool {
    return gw.sent.create_dms.load(.monotonic) == dms_mark + 1;
}

// --- Ctrl+Tab e op 14 -------------------------------------------------------------

fn threeTabs(app: *App) void {
    app.st.tabs.clearRetainingCapacity();
    for ([_]usize{ 4, 9, 5 }) |ci| app.st.tabs.append(app.gpa, gw.channelId(0, ci)) catch {};
    app.actions.append(app.gpa, .{ .focus_tab = 0 }) catch {};
}
fn onFirstTab(app: *App) bool {
    return app.st.tabs.items.len == 3 and app.st.tab == 0 and activeId(app) == gw.channelId(0, 4);
}
fn holdCtrlTab(app: *App) void {
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiMod_Ctrl, true);
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiKey_LeftCtrl, true);
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiKey_Tab, true);
}
fn releaseCtrlTab(app: *App) void {
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiKey_Tab, false);
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiKey_LeftCtrl, false);
    c.ImGuiIO_AddKeyEvent(app.io, c.ImGuiMod_Ctrl, false);
}
fn movedOnce(app: *App) bool {
    return app.st.tab == 1 and activeId(app) == gw.channelId(0, 9);
}

fn markSubs(_: *App) void {
    subs_mark = gw.sent.subscribes.load(.monotonic);
}
fn subsSince() u64 {
    return gw.sent.subscribes.load(.monotonic) - subs_mark;
}
fn switchTo(app: *App, ci: usize) void {
    app.actions.append(app.gpa, .{ .select_channel = gw.channelId(0, ci) }) catch {};
}
fn switchA(app: *App) void {
    switchTo(app, 5);
}
fn switchB(app: *App) void {
    switchTo(app, 6);
}
fn switchC(app: *App) void {
    switchTo(app, 7);
}
fn switchD(app: *App) void {
    switchTo(app, 10);
}
fn noSubYet(app: *App) bool {
    return activeId(app) == gw.channelId(0, 10) and subsSince() == 0;
}
fn oneSubForLast(_: *App) bool {
    return subsSince() == 1 and gw.sent.sub_channel.load(.monotonic) == gw.channelId(0, 10);
}

pub const ops = [_]Op{
    s("limites: modo lento"),
    .{ .run = markCounters },
    click("guild:501000"),
    click("channel:501006"),
    slow("#memes do Rice carrega", memesOpen, 3000),
    expect("o modo lento do canal aparece acima da caixa (5s)", slowLabel),
    .{ .shot = "limites-modo-lento" },
    click("composer"),
    .{ .text = "primeira no modo lento" },
    key(c.ImGuiKey_Enter),
    slow("a primeira sai e a contagem começa", firstSentAndCooling, 3000),
    .{ .shot = "limites-contagem" },
    .{ .text = "segunda cedo demais" },
    key(c.ImGuiKey_Enter),
    .{ .wait = 300 },
    expect("Enter durante a contagem não manda e o texto fica na caixa", heldDraft),
    slow("a contagem acaba sozinha e a caixa volta ao normal", cooldownOver, 7000),
    key(c.ImGuiKey_Enter),
    slow("depois da contagem, o Enter manda o rascunho", draftSent, 3000),

    s("limites: 429 do modo lento"),
    .{ .run = forgetCooldown },
    .{ .text = "terceira" },
    key(c.ImGuiKey_Enter),
    slow("o servidor recusa: \"não enviada\" e a contagem volta pelo 429", refusedAndCooling, 3000),
    .{ .run = resendTerceira },
    .{ .wait = 300 },
    expect("reenviar durante a contagem não manda de novo", resendHeld),
    .{ .shot = "limites-429" },

    s("limites: liberado do modo lento"),
    .{ .run = markCounters },
    click("guild:500000"),
    click("channel:500012"),
    slow("#bugs do nosso servidor carrega", bugsOpen, 3000),
    expect("modo lento com o aviso de liberado", exemptLabel),
    click("composer"),
    .{ .text = "uma" },
    key(c.ImGuiKey_Enter),
    .{ .text = "duas" },
    key(c.ImGuiKey_Enter),
    slow("quem gerencia o canal manda uma atrás da outra", bothSent, 3000),
    .{ .run = serverHoldBugs },
    slow("429 do Discord sem modo lento que valha: a contagem aparece mesmo assim", rateLimitedShown, 2000),
    .{ .text = "tres" },
    key(c.ImGuiKey_Enter),
    .{ .wait = 300 },
    expect("Enter durante o 429 não manda e o texto fica", heldRate),
    .{ .shot = "limites-429-liberado" },
    slow("a contagem do 429 acaba sozinha", rateOver, 4000),
    key(c.ImGuiKey_Enter),
    slow("depois dela, o Enter manda", rateSent, 3000),

    s("limites: motivos no lugar da caixa"),
    click("guild:501000"),
    click("channel:501003"),
    slow("#anúncios sem SEND_MESSAGES: a caixa vira aviso", noPermBand, 3000),
    .{ .shot = "limites-sem-permissao" },
    .{ .run = openTimeoutGuild },
    slow("de castigo: o aviso com o tempo que falta, sem caixa", timeoutBand, 3000),
    .{ .shot = "limites-castigo" },
    .{ .run = liftTimeout },
    slow("castigo tirado (GUILD_MEMBER_UPDATE): a caixa volta", composerBack, 3000),
    .{ .run = openQuarantineGuild },
    slow("quarentena do AutoMod: aviso no lugar da caixa", quarantineBand, 3000),
    .{ .shot = "limites-quarentena" },
    .{ .run = markCounters },
    .{ .run = quarantineAccount },
    expect("flag de quarentena da conta chegou", accountQuarantined),
    .{ .run = openNewDm },
    .{ .wait = 300 },
    expect("conta em quarentena: não pede DM nova ao Discord", noDmAsked),
    .{ .run = unquarantineAccount },
    expect("flag de quarentena da conta saiu", accountFree),
    .{ .run = openNewDm },
    slow("sem a quarentena, a DM nova é pedida", dmAsked, 3000),

    s("limites: Ctrl+Tab segurado"),
    .{ .run = threeTabs },
    slow("três abas, na primeira", onFirstTab, 3000),
    .{ .run = holdCtrlTab },
    .{ .wait = 1200 },
    .{ .run = releaseCtrlTab },
    .{ .wait = 100 },
    expect("segurar Ctrl+Tab troca de aba uma vez só", movedOnce),

    s("limites: op 14 só do canal que ficou"),
    .{ .wait = 400 },
    .{ .run = markSubs },
    .{ .run = switchA },
    .{ .wait = 40 },
    .{ .run = switchB },
    .{ .wait = 40 },
    .{ .run = switchC },
    .{ .wait = 40 },
    .{ .run = switchD },
    .{ .wait = 50 },
    expect("trocando rápido, a lista de membros ainda não foi pedida", noSubYet),
    slow("parou: só o canal que ficou pede a lista de membros", oneSubForLast, 2000),
    .{ .wait = 400 },
    expect("e mais nenhum pedido depois", oneSubForLast),
};
