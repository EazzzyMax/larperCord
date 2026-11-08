//! QA das calls em DM e grupo, contra a demonstração (net/fake_gateway.zig):
//! ligar pelo cabeçalho (op 4 sem servidor e o pedido de tocar), quem está na
//! call, a chamada chegando por cima de tudo, atender, recusar (stop-ringing),
//! a call que acaba (CALL_DELETE), o Não perturbe e a DM/grupo silenciado sem
//! toque, e a janela escondida. O som é o driver mudo do SDL: confere que o
//! toque foi posto na saída, não como ele soa.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const voz_audio = @import("net/voz_audio.zig");
const chamada = @import("ui/chamada.zig");
const fc = @import("net/fake_conta.zig");
const platform = @import("platform/window.zig");
const Id = @import("core/types.zig").Id;

const me: Id = 1000;
/// O grupo da demonstração (fake_gateway.group_id).
const group: Id = 900_006;
const dm0: Id = 900_000;
const dm1: Id = 900_001;
const dm2: Id = 900_002;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn expectLong(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 6000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}
fn shot(name: []const u8) Op {
    return .{ .shot = name };
}

// --- O que a demonstração recebeu --------------------------------------------

var rings0: u64 = 0;
var stops0: u64 = 0;
var chunks0: u32 = 0;
var notified0: u32 = 0;

fn markSent(_: *App) void {
    rings0 = gw.sent.rings.load(.acquire);
    stops0 = gw.sent.stop_rings.load(.acquire);
    chunks0 = voz_audio.sh.ring_chunks.load(.monotonic);
    notified0 = chamada.notified;
}

fn op4() []const u8 {
    const n = gw.sent.op4_len.load(.acquire);
    return gw.sent.op4[0..@min(n, gw.sent.op4.len)];
}

fn contains(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

// --- Injeção -------------------------------------------------------------------

fn openDm0(app: *App) void {
    app.actions.append(app.gpa, .{ .select_channel = dm0 }) catch {};
}
fn ring(app: *App, ch: Id) void {
    markSent(app);
    app.cmd(.{ .demo_call = .{ .channel = ch, .ring = true } });
}
fn ringGroup(app: *App) void {
    ring(app, group);
}
fn ringDm1(app: *App) void {
    ring(app, dm1);
}
fn ringDm2(app: *App) void {
    ring(app, dm2);
}
/// Outro aparelho nosso atendeu: CALL_UPDATE sem a gente no `ringing`.
fn answeredElsewhere(app: *App) void {
    app.events.push(.{ .call = .{ .channel = dm2 } });
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn hangupDm2(app: *App) void {
    app.cmd(.{ .demo_call = .{ .channel = dm2, .ring = false } });
}
fn clearToast(app: *App) void {
    app.st.toast.len = 0;
    app.st.toast.until_ms = 0;
}
fn setDnd(app: *App) void {
    app.handle(.{ .set_status = .dnd });
}
fn setOnline(app: *App) void {
    app.handle(.{ .set_status = .online });
}
fn hideWindow(app: *App) void {
    _ = c.SDL_HideWindow(app.win.window);
    ring(app, dm2);
}
fn showWindow(app: *App) void {
    _ = c.SDL_ShowWindow(app.win.window);
}
/// Outro aparelho silencia a DM 2 e o grupo nas configurações da conta (as das DMs
/// são as de "@me", guild_id null); depois volta ao padrão.
fn dmSettings(app: *App, json: []const u8) void {
    const e = fc.remoteEvent(json) orelse return;
    app.events.push(e);
    platform.Window.wake(app.win.wake_type, .gateway);
}
const muted_dms =
    \\{"guild_id":null,"muted":false,"mute_config":null,"message_notifications":3,"suppress_everyone":false,"suppress_roles":false,
    \\ "channel_overrides":[{"channel_id":"900002","muted":true,"mute_config":null,"message_notifications":3,"collapsed":false},
    \\ {"channel_id":"900006","muted":true,"mute_config":null,"message_notifications":3,"collapsed":false}],"version":20}
;
const default_dms =
    \\{"guild_id":null,"muted":false,"mute_config":null,"message_notifications":3,"suppress_everyone":false,"suppress_roles":false,"channel_overrides":[],"version":21}
;
fn muteDms(app: *App) void {
    dmSettings(app, muted_dms);
}
fn unmuteDms(app: *App) void {
    dmSettings(app, default_dms);
}

// --- Checagens -----------------------------------------------------------------

fn hasStart(app: *App) bool {
    return app.st.activeChannel() == dm0 and qa.find("call-start") != null;
}
fn inDm0(app: *App) bool {
    return app.st.voice == dm0 and app.st.voice_guild == 0 and qa.find("call-leave") != null;
}
fn op4Dm0(_: *App) bool {
    return contains(op4(), "\"guild_id\":null,\"channel_id\":\"900000\"");
}
fn rangDm0(_: *App) bool {
    return gw.sent.rings.load(.acquire) > rings0 and gw.sent.ring_channel.load(.acquire) == dm0;
}
fn membersShown(app: *App) bool {
    const rec = gw.dmRecipient(dm0) orelse return false;
    var b: [32]u8 = undefined;
    const k = std.fmt.bufPrint(&b, "call-member:{d}", .{rec}) catch return false;
    return qa.find("call-member:1000") != null and qa.find(k) != null and app.store.channel(dm0).?.voice_members.items.len == 2;
}
fn ringingOut(_: *App) bool {
    return chamada.out_channel == dm0 and chamada.out_ringing == 1 and qa.find("call-ringing-out") != null;
}
fn leftCall(app: *App) bool {
    return app.st.voice == null and contains(op4(), "\"guild_id\":null,\"channel_id\":null") and qa.find("call-start") != null;
}
fn overlayFor(ch: Id) bool {
    return chamada.ring_channel == ch and qa.find("call-accept") != null and qa.find("call-decline") != null;
}
fn overlayGroup(_: *App) bool {
    return overlayFor(group);
}
fn overlayDm1(_: *App) bool {
    return overlayFor(dm1);
}
fn overlayDm2(_: *App) bool {
    return overlayFor(dm2);
}
fn ringtonePlays(_: *App) bool {
    return voz_audio.ringing() and voz_audio.sh.ring_chunks.load(.monotonic) > chunks0 + 2;
}
fn notifiedOnce(_: *App) bool {
    return chamada.notified == notified0 + 1;
}
fn overlayGone(_: *App) bool {
    return chamada.ring_channel == 0 and qa.find("call-overlay") == null and !voz_audio.ringing();
}
fn stopSent(_: *App) bool {
    const n = gw.sent.stop_body_len.load(.acquire);
    return gw.sent.stop_rings.load(.acquire) > stops0 and std.mem.eql(u8, gw.sent.stop_body[0..@min(n, gw.sent.stop_body.len)], "{\"recipients\":[\"1000\"]}");
}
fn inDm1(app: *App) bool {
    return app.st.voice == dm1 and app.st.voice_status == .connected and chamada.ring_channel == 0 and !voz_audio.ringing() and
        qa.find("call-overlay") == null and contains(op4(), "\"guild_id\":null,\"channel_id\":\"900001\"");
}
fn notInVoice(app: *App) bool {
    return app.st.voice == null;
}
fn isDnd(app: *App) bool {
    return app.store.user(me).?.status == .dnd;
}
fn isOnline(app: *App) bool {
    return app.store.user(me).?.status == .online;
}
/// O aviso de `ch` está na tela e o toque não foi posto na saída.
fn silentFor(ch: Id) bool {
    // Um tempinho para a thread de áudio, se fosse tocar.
    c.SDL_Delay(120);
    return overlayFor(ch) and !voz_audio.ringing() and voz_audio.sh.ring_chunks.load(.monotonic) == chunks0;
}
fn silentInDnd(_: *App) bool {
    return silentFor(dm2);
}
fn dmsMuted(app: *App) bool {
    return app.st.muted_channels.contains(dm2) and app.st.muted_channels.contains(group) and !app.st.muted_channels.contains(dm1);
}
fn dmsUnmuted(app: *App) bool {
    return !app.st.muted_channels.contains(dm2) and !app.st.muted_channels.contains(group);
}
fn silentMutedDm(_: *App) bool {
    return silentFor(dm2);
}
fn silentMutedGroup(_: *App) bool {
    return silentFor(group);
}
/// A DM 1 não foi silenciada: a dela toca como sempre.
fn ringsDm1(_: *App) bool {
    return overlayFor(dm1) and voz_audio.ringing();
}
fn ringingHidden(app: *App) bool {
    const hidden = c.SDL_GetWindowFlags(app.win.window) & c.SDL_WINDOW_HIDDEN != 0;
    return hidden and chamada.ring_channel == dm2 and voz_audio.ringing() and chamada.notified == notified0 + 1;
}
/// O que foi digitado antes e depois de a chamada chegar está todo na caixa.
fn typedThrough(app: *App) bool {
    return std.mem.eql(u8, std.mem.sliceTo(&app.st.input, 0), "oizinho");
}
fn clearComposer(app: *App) void {
    @memset(&app.st.input, 0);
    app.st.input_sync = true;
}

pub const ops = [_]Op{
    s("chamada"),
    run(openDm0),
    expect("botão de ligar no cabeçalho da DM", hasStart),
    run(markSent),
    click("call-start"),
    expect("ligar entra na call da DM, sem servidor", inDm0),
    expect("op 4 com guild_id null e o canal da DM", op4Dm0),
    expect("pede para tocar para quem está na DM", rangDm0),
    expect("chamando quem está do outro lado", ringingOut),
    expectLong("quem está na call aparece na conversa", membersShown),
    run(clearToast),
    .{ .wait = 250 },
    shot("chamada-dm"),
    click("call-leave"),
    expect("desligar pelo cabeçalho sai da call (op 4 todo null)", leftCall),

    click("composer"),
    .{ .text = "oi" },
    run(ringGroup),
    expect("chamada no grupo aparece por cima", overlayGroup),
    .{ .text = "zinho" },
    expect("o aviso não tira o foco da caixa: o que se digita continua indo para ela", typedThrough),
    run(clearComposer),
    expectLong("o toque de chamada toca", ringtonePlays),
    expect("e avisa o sistema", notifiedOnce),
    shot("chamada-recebida"),
    click("call-decline"),
    expect("recusar some com o aviso e para o toque", overlayGone),
    expect("recusar manda stop-ringing com o nosso id", stopSent),

    run(ringDm1),
    expect("chamada numa DM aparece por cima", overlayDm1),
    click("call-accept"),
    expect("atender entra na call e o aviso some", inDm1),
    shot("chamada-atendida"),
    click("hangup"),
    expect("sair pela faixa de voz", notInVoice),

    run(ringDm2),
    expect("chamada chegando de novo", overlayDm2),
    run(answeredElsewhere),
    expect("atendida em outro aparelho: para de tocar", overlayGone),
    run(ringDm2),
    expect("e chega outra vez", overlayDm2),
    run(hangupDm2),
    expect("CALL_DELETE some com o aviso e para o toque", overlayGone),

    run(setDnd),
    expect("não perturbe ligado", isDnd),
    run(ringDm2),
    expect("não perturbe: o aviso aparece, sem toque", silentInDnd),
    click("call-decline"),
    expect("recusar no não perturbe", overlayGone),
    run(setOnline),
    expect("online de novo", isOnline),

    run(muteDms),
    expect("DM e grupo silenciados em outro aparelho", dmsMuted),
    run(ringDm2),
    expect("DM silenciada: o aviso aparece, sem toque", silentMutedDm),
    shot("chamada-silenciada"),
    click("call-decline"),
    expect("recusar a chamada da DM silenciada", overlayGone),
    run(ringGroup),
    expect("grupo silenciado: o aviso aparece, sem toque", silentMutedGroup),
    click("call-decline"),
    expect("recusar a chamada do grupo silenciado", overlayGone),
    run(ringDm1),
    expect("a DM que não foi silenciada toca", ringsDm1),
    click("call-decline"),
    expect("e recusar some com ela", overlayGone),
    run(unmuteDms),
    expect("silêncio tirado em outro aparelho", dmsUnmuted),

    run(hideWindow),
    expect("com a janela escondida, toca e avisa", ringingHidden),
    run(showWindow),
    expect("ao voltar, o aviso está lá", overlayDm2),
    click("call-decline"),
    expect("e recusar some com ele", overlayGone),
};

/// Por tema: o botão de ligar na DM aberta e o aviso de chamada por cima.
pub const ops_theme = [_]Op{
    expect("botão de ligar na DM", hasStartAny),
    run(ringGroup),
    expect("chamada chegando aparece no tema", overlayGroup),
    shot("tema-chamada"),
    click("call-decline"),
    expect("recusar some com o aviso", overlayGone),
};

fn hasStartAny(_: *App) bool {
    return qa.find("call-start") != null;
}
