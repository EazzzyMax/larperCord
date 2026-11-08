//! QA do menu rápido de dispositivos (ui/device_menu.zig), dos atalhos de mudo
//! e ensurdecer e dos controles do zen na barra de status. `ops_theme` entra na
//! bateria por tema do qa_runner.zig; `ops_call` entra no meio da call do qa_voz.zig.
//! O driver de áudio do QA é mudo (um dispositivo só): a lista vem de mentira.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const Op = @import("qa_runner.zig").Op;
const qa = @import("ui/qa.zig");
const S = @import("ui/settings_state.zig");
const devices = @import("ui/device_menu.zig");

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}

/// O que estava escolhido antes (volta no fim, para o resto da bateria).
var saved_mic: S.Text = .{};
var saved_out: S.Text = .{};
var saved_in_gain: u8 = 100;
var saved_out_gain: u8 = 100;

fn hasPanel(app: *App) bool {
    return if (app.themes.active) |t| t.has_user_panel else true;
}
fn isZen(app: *App) bool {
    return std.mem.eql(u8, app.themes.name(), "zen");
}

fn fake(app: *App) void {
    const s = &app.st.settings;
    saved_mic = s.voice_mic;
    saved_out = s.voice_out;
    saved_in_gain = s.voice_in_gain;
    saved_out_gain = s.voice_out_gain;
    s.voice_mic = .{};
    s.voice_out = .{};
    s.voice_out_gain = 100;
    devices.qaFake(3);
}

fn restore(app: *App) void {
    const s = &app.st.settings;
    s.voice_mic = saved_mic;
    s.voice_out = saved_out;
    s.voice_in_gain = saved_in_gain;
    s.voice_out_gain = saved_out_gain;
    app.st.muted = false;
    app.st.deafened = false;
    devices.qaFake(0);
}

// Onde ficam os botões: no painel do usuário ou, no zen, na barra de status.
fn tMic(app: *App, _: []u8) []const u8 {
    return if (hasPanel(app)) "user-btn:0" else "status-mic";
}
fn tDeafMenu(app: *App, _: []u8) []const u8 {
    return if (hasPanel(app)) "user-btn:1-menu" else "status-deaf-menu";
}
fn tZenMic(app: *App, _: []u8) []const u8 {
    return if (isZen(app)) "status-mic" else "";
}
fn tZenDeaf(app: *App, _: []u8) []const u8 {
    return if (isZen(app)) "status-deaf" else "";
}
fn tZenMe(app: *App, _: []u8) []const u8 {
    return if (isZen(app)) "status-me" else "";
}

/// O nome (e o status) no painel do usuário tem espaço ao lado dos botões (nos temas
/// de terminal, os rótulos [mic] [fone] encurtam quando o painel é estreito).
fn nameRoom(app: *App) bool {
    if (!hasPanel(app)) return true;
    const r = qa.find("me") orelse return false;
    return r.w >= 100;
}
fn micMenu(app: *App) bool {
    return switch (app.st.popup) {
        .devices => |dv| dv.which == .mic and qa.find("device-menu") != null,
        else => false,
    };
}
/// Os três de mentira, mais o padrão do sistema (marcado: nada escolhido ainda).
fn listsFake(_: *App) bool {
    return qa.find("device-opt:mic:0") != null and qa.find("device-opt:mic:3") != null and
        qa.find("device-opt:mic:4") == null and qa.find("device-sel:mic:0") != null and
        qa.find("device-opt:out:0") == null and qa.find("device-vol:mic") != null and qa.find("device-settings") != null;
}
fn micChosen(app: *App) bool {
    return app.st.popup == .none and std.mem.eql(u8, app.st.settings.voice_mic.slice(), "Microfone de teste 2");
}
/// Saída escolhida que não está ligada agora: aparece no fim da lista, marcada.
const lost_out = "Fone que sumiu";
fn setLostOut(app: *App) void {
    app.st.settings.voice_out.set(lost_out);
}
fn lostListed(app: *App) bool {
    return switch (app.st.popup) {
        .devices => |dv| dv.which == .out and qa.find("device-opt:out:4") != null and qa.find("device-sel:out:4") != null,
        else => false,
    };
}
fn lostKept(app: *App) bool {
    return app.st.popup == .none and std.mem.eql(u8, app.st.settings.voice_out.slice(), lost_out);
}
fn outMenu(app: *App) bool {
    return switch (app.st.popup) {
        .devices => |dv| dv.which == .out and qa.find("device-opt:out:3") != null and qa.find("device-opt:mic:0") == null,
        else => false,
    };
}
fn outGainLow(app: *App) bool {
    return app.st.settings.voice_out_gain < 30 and app.st.popup == .devices;
}
fn voicePage(app: *App) bool {
    return app.st.settings.open and app.st.settings.page == .voz and app.st.popup == .none;
}
fn settingsClosed(app: *App) bool {
    return !app.st.settings.open;
}
fn muted(app: *App) bool {
    return app.st.muted;
}
fn unmuted(app: *App) bool {
    return !app.st.muted;
}
fn deafened(app: *App) bool {
    return app.st.deafened;
}
fn undeafened(app: *App) bool {
    return !app.st.deafened;
}
fn popupClosed(app: *App) bool {
    return app.st.popup == .none;
}

// Zen: em outro tema os passos com alvo vazio pulam e estas conferências passam.
fn zenControls(app: *App) bool {
    if (!isZen(app)) return true;
    return qa.find("status-mic") != null and qa.find("status-deaf") != null and qa.find("status-me") != null;
}
fn zenMuted(app: *App) bool {
    return !isZen(app) or app.st.muted;
}
fn zenUnmuted(app: *App) bool {
    return !isZen(app) or !app.st.muted;
}
fn zenDeaf(app: *App) bool {
    return !isZen(app) or (app.st.deafened and app.st.muted);
}
fn zenUndeaf(app: *App) bool {
    return !isZen(app) or !app.st.deafened;
}
fn zenStatusMenu(app: *App) bool {
    if (!isZen(app)) return true;
    return switch (app.st.popup) {
        .menu => |m| m.kind == .status,
        else => false,
    };
}
fn unmute(app: *App) void {
    app.st.muted = false;
    app.st.deafened = false;
}

pub const ops_theme = [_]Op{
    .{ .section = "dispositivos" },
    expect("o nome no painel do usuário tem espaço ao lado dos botões", nameRoom),
    .{ .run = fake },
    .{ .rclick = .{ .dyn = tMic } },
    expect("botão direito no microfone abre o menu de dispositivos", micMenu),
    expect("o menu lista os dispositivos, o padrão marcado, o volume e o atalho", listsFake),
    .{ .shot = "tema-dispositivos" },
    click("device-opt:mic:2"),
    expect("escolher um microfone grava na hora nas configurações", micChosen),
    .{ .run = setLostOut },
    .{ .click = .{ .dyn = tDeafMenu } },
    expect("a saída que sumiu aparece marcada no fim da lista", lostListed),
    click("device-opt:out:4"),
    expect("clicar nela fecha o menu e o nome continua guardado", lostKept),
    .{ .click = .{ .dyn = tDeafMenu } },
    expect("a setinha do fone abre as saídas", outMenu),
    .{ .drag = .{ .from = .{ .at = .{ .key = "device-vol:out", .fx = 0.5, .fy = 0.5 } }, .to = .{ .at = .{ .key = "device-vol:out", .fx = 0.04, .fy = 0.5 } } } },
    expect("arrastar o volume de saída muda o número das configurações", outGainLow),
    click("device-settings"),
    expect("o atalho abre Configurações → Voz", voicePage),
    key(c.ImGuiKey_Escape),
    expect("Esc fecha as configurações", settingsClosed),
    .{ .run = restore },
    // Os atalhos que as dicas dos botões mostram.
    .{ .key = .{ .key = c.ImGuiKey_M, .ctrl = true, .shift = true } },
    expect("Ctrl+Shift+M muta", muted),
    .{ .key = .{ .key = c.ImGuiKey_M, .ctrl = true, .shift = true } },
    expect("Ctrl+Shift+M desmuta", unmuted),
    .{ .key = .{ .key = c.ImGuiKey_D, .ctrl = true, .shift = true } },
    expect("Ctrl+Shift+D ensurdece", deafened),
    .{ .key = .{ .key = c.ImGuiKey_D, .ctrl = true, .shift = true } },
    expect("Ctrl+Shift+D volta a ouvir", undeafened),
    .{ .run = unmute },
    // Zen: sem painel do usuário, o rodapé tem o status, o microfone e o fone.
    expect("zen: status, microfone e fone no rodapé", zenControls),
    .{ .click = .{ .dyn = tZenMic } },
    expect("zen: o microfone do rodapé muta", zenMuted),
    .{ .shot = "tema-rodape" },
    .{ .click = .{ .dyn = tZenMic } },
    expect("zen: e desmuta", zenUnmuted),
    .{ .click = .{ .dyn = tZenDeaf } },
    expect("zen: o fone do rodapé ensurdece", zenDeaf),
    .{ .click = .{ .dyn = tZenDeaf } },
    expect("zen: e volta a ouvir", zenUndeaf),
    .{ .run = unmute },
    .{ .click = .{ .dyn = tZenMe } },
    expect("zen: o status do rodapé abre o menu de status", zenStatusMenu),
    key(c.ImGuiKey_Escape),
    expect("Esc fecha o menu", popupClosed),
};

fn bothMenu(app: *App) bool {
    return switch (app.st.popup) {
        .devices => |dv| dv.which == .both and qa.find("device-opt:mic:0") != null and qa.find("device-opt:out:0") != null and
            qa.find("device-vol:mic") != null and qa.find("device-vol:out") != null,
        else => false,
    };
}

/// Na call: botão direito na faixa de voz abre microfone e saída juntos.
pub const ops_call = [_]Op{
    .{ .rclick = .{ .mark = "voice-line" } },
    expect("botão direito na faixa de voz abre microfone e saída", bothMenu),
    .{ .shot = "voz-dispositivos" },
    key(c.ImGuiKey_Escape),
    expect("Esc fecha o menu de dispositivos", popupClosed),
};
