//! Calls em DM e grupo, do lado do app: começar, atender, recusar, e o que
//! fazer quando o Discord avisa que está tocando para nós (o toque, a
//! notificação do sistema, a janela piscando; no Não perturbe e na conversa
//! silenciada, o aviso sem o toque). Roda ao tratar os eventos da
//! rede, então funciona com a janela minimizada ou escondida na bandeja.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const app_conta = @import("app_conta.zig");
const ev = @import("core/event.zig");
const types = @import("core/types.zig");
const chamada = @import("ui/chamada.zig");
const voz_audio = @import("net/voz_audio.zig");
const i18n = @import("ui/i18n.zig");
const now = @import("net/fake_gateway.zig").nowMs;
const Id = types.Id;

/// Começamos a call e ninguém estava nela: toca para os outros assim que o
/// Discord confirmar que entramos (o pedido antes disso pode chegar antes da call).
var ring_after_join: Id = 0;

/// Botão de ligar no cabeçalho: entra na call da conversa (ou começa uma).
pub fn start(app: *App, ch: Id) void {
    const cs = app.store.channel(ch) orelse return;
    if (cs.info.guild != 0 or app.st.voice == ch) return;
    const ongoing = cs.voice_members.items.len > 0;
    // Tocando para nós nesta mesma conversa: ligar é atender.
    if (chamada.ring_channel == ch) stopRing();
    join(app, ch);
    ring_after_join = if (ongoing) 0 else ch;
}

pub fn accept(app: *App) void {
    const ch = chamada.ring_channel;
    if (ch == 0) return;
    stopRing();
    join(app, ch);
}

/// Recusar: para de tocar só para nós (os outros continuam sendo chamados).
pub fn decline(app: *App) void {
    const ch = chamada.ring_channel;
    if (ch == 0) return;
    stopRing();
    app.cmd(.{ .call_stop_ringing = ch });
}

/// Outra conta (trocar de conta, sair): nada da anterior continua tocando.
pub fn reset() void {
    stopRing();
    chamada.reset();
    ring_after_join = 0;
}

fn join(app: *App, ch: Id) void {
    const st = &app.st;
    st.voice = ch;
    st.voice_guild = 0;
    st.voice_status = .connecting;
    st.voice_mixer = false;
    app.resetCallState();
    chamada.out_channel = ch;
    chamada.out_ringing = 0;
    app.cmd(.{ .join_voice = .{ .guild = 0, .channel = ch, .mute = st.muted, .deaf = st.deafened } });
    var vit = st.voice_volumes.iterator();
    while (vit.next()) |e| app.cmd(.{ .voice_volume = .{ .user = e.key_ptr.*, .volume = e.value_ptr.* } });
}

fn stopRing() void {
    chamada.ring_channel = 0;
    voz_audio.setRinging(false);
}

/// Cada evento da rede, depois do Store.
pub fn onEvent(app: *App, e: ev.Event) void {
    switch (e) {
        .call => |cl| onCall(app, cl),
        // Sessão nova: o que estiver tocando de verdade volta num CALL_CREATE.
        .ready => {
            stopRing();
            ring_after_join = 0;
        },
        .voice_state => |vs| if (vs.user == app.store.me and app.store.me != 0) {
            if (ring_after_join != 0 and vs.channel == ring_after_join) {
                app.cmd(.{ .call_ring = ring_after_join });
                ring_after_join = 0;
            }
            // Entramos (por aqui ou por outro aparelho) na call que tocava.
            if (vs.channel != null and vs.channel.? == chamada.ring_channel) stopRing();
        },
        else => {},
    }
}

fn onCall(app: *App, cl: ev.Call) void {
    if (cl.ended) {
        if (chamada.ring_channel == cl.channel) stopRing();
        if (chamada.out_channel == cl.channel) chamada.out_ringing = 0;
        return;
    }
    if (app.st.voice == cl.channel) {
        chamada.out_channel = cl.channel;
        chamada.out_ringing = cl.ringing;
    }
    if (!cl.ringing_me) {
        // Atendeu em outro aparelho, recusou lá, ou quem ligou desistiu.
        if (chamada.ring_channel == cl.channel) stopRing();
        return;
    }
    if (app.st.voice == cl.channel) return;
    // Já tocando (um CALL_UPDATE a mais). Passado o tempo do aviso, o Discord
    // ainda chamando é chamada de novo.
    if (chamada.ring_channel == cl.channel and now() - chamada.ring_since_ms < chamada.ring_max_ms) return;
    chamada.ring_channel = cl.channel;
    chamada.ring_since_ms = now();
    // Não perturbe, ou a DM/grupo silenciado na conta: o aviso aparece, sem som.
    const dnd = if (app.store.user(app.store.me)) |u| u.status == .dnd else false;
    voz_audio.setRinging(!dnd and !app_conta.mutedNow(app, cl.channel));
    notify(app, cl.channel);
}

/// Janela piscando na barra de tarefas e a notificação do sistema
/// (notify-send no Linux, o aviso da bandeja no Windows).
fn notify(app: *App, ch: Id) void {
    chamada.notified +%= 1;
    if (app.opts.qa or app.store.demo) return;
    const flags = c.SDL_GetWindowFlags(app.win.window);
    const hidden = flags & c.SDL_WINDOW_HIDDEN != 0;
    const focused = !hidden and flags & c.SDL_WINDOW_INPUT_FOCUS != 0;
    if (focused) return;
    if (!hidden) _ = c.SDL_FlashWindow(app.win.window, c.SDL_FLASH_UNTIL_FOCUSED);
    if (!app.st.settings.desktop_notifs) return;
    const cs = app.store.channel(ch);
    var tb: [160]u8 = undefined;
    const name = if (cs) |x| x.info.name else "?";
    const title = std.fmt.bufPrintSentinel(&tb, "{s}", .{name}, 0) catch return;
    const group = if (cs) |x| x.info.group else false;
    app.desktopNotify(title, if (group) i18n.trZ("Chamada no grupo", "Group call") else i18n.trZ("Chamada recebida", "Incoming call"));
}
