//! QA do proxy (tipo, endereço, porta, login e senha, guardados numa URL só) e da
//! contagem de desafios do Discord no registro de depuração. Sozinho: QA_SUITE=proxy.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const invites = @import("ui/invites.zig");
const settings = @import("ui/settings.zig");
const proxy = @import("net/proxy.zig");
const challenge = @import("net/challenge.zig");

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 5000 } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}
fn ctrl(k: c_int) Op {
    return .{ .key = .{ .key = k, .ctrl = true } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}
/// Seleciona tudo no campo e escreve por cima.
fn typeInto(comptime mark: []const u8, comptime text: []const u8) [3]Op {
    return .{ click(mark), ctrl(c.ImGuiKey_A), .{ .text = text } };
}
fn clearField(comptime mark: []const u8) [3]Op {
    return .{ click(mark), ctrl(c.ImGuiKey_A), key(c.ImGuiKey_Backspace) };
}

const page_marks = [_][]const u8{ "pg:", "button:", "toggle:", "select:", "slider:", "seg:", "radio:" };
fn noOverlap(_: *App) bool {
    return qa.overlapping(&page_marks) == null;
}

// --- Desafios ------------------------------------------------------------------

var captcha_before: u32 = 0;
fn noteChallenges(_: *App) void {
    captcha_before = challenge.count(.captcha);
}
fn resetGap(_: *App) void {
    invites.qaResetGap();
}
fn captchaCounted(_: *App) bool {
    return challenge.count(.captcha) == captcha_before + 1 and challenge.count(.verification) == 0 and challenge.count(.unauthorized) == 0;
}
/// A tela mostra o número de agora (a marcação leva o número desenhado).
fn countsShown(_: *App) bool {
    var b: [48]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "challenge:captcha:{d}", .{challenge.count(.captcha)}) catch return false;
    return qa.find(want) != null and qa.find("challenge:verification:0") != null and qa.find("challenge:unauthorized:0") != null;
}

// --- Proxy ---------------------------------------------------------------------

fn field(buf: []const u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}
fn rejected(app: *App) bool {
    return app.st.settings.proxy.len == 0 and std.mem.indexOf(u8, app.st.toast.text(), "inválido") != null and qa.find("proxy-input") != null;
}
fn pastedFills(_: *App) bool {
    const f = &settings.proxy_form;
    return f.kindOf() == .socks5 and std.mem.eql(u8, field(&f.host), "::1") and std.mem.eql(u8, field(&f.port), "1080") and
        std.mem.eql(u8, field(&f.user), "us@er") and std.mem.eql(u8, field(&f.pass), "p:ss/w");
}
/// Salvo e em uso: só a mídia de fora passa pelo proxy (sem "em tudo").
fn inUse(app: *App, want: []const u8) bool {
    var b: proxy.Buf = undefined;
    if (!std.mem.eql(u8, app.st.settings.proxy.slice(), want)) return false;
    const ext = proxy.forUrl(&b, "https://media.tenor.com/x.webp") orelse return false;
    return std.mem.eql(u8, ext, want) and proxy.forUrl(&b, "https://cdn.discordapp.com/x.png") == null and proxy.forDiscord(&b) == null;
}
fn savedPasted(app: *App) bool {
    return inUse(app, "socks5://us%40er:p%3Ass%2Fw@[::1]:1080");
}
fn passShown(_: *App) bool {
    return settings.proxy_show;
}
fn savedFields(app: *App) bool {
    return inUse(app, "http://eu%40casa:s3%3Anh%40%2F%25@proxy.local:3128") and !settings.proxy_show;
}
fn externalOnly(app: *App) bool {
    return inUse(app, "socks5h://127.0.0.1:9050");
}
fn everywhere(app: *App) bool {
    var b: proxy.Buf = undefined;
    const d = proxy.forDiscord(&b) orelse return false;
    return app.st.settings.proxy_all and std.mem.eql(u8, d, "socks5h://127.0.0.1:9050") and proxy.forUrl(&b, "https://cdn.discordapp.com/x.png") != null;
}
fn persisted(app: *App) bool {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(app.gpa);
    @import("ui/settings_state.zig").write(&app.st.settings, "classico", &out, app.gpa) catch return false;
    return std.mem.indexOf(u8, out.items, "proxy=\"socks5h://127.0.0.1:9050\"") != null and std.mem.indexOf(u8, out.items, "proxy_all=#true") != null;
}
fn removed(app: *App) bool {
    var b: proxy.Buf = undefined;
    return app.st.settings.proxy.len == 0 and proxy.forUrl(&b, "https://media.tenor.com/x.webp") == null and proxy.forDiscord(&b) == null and
        settings.proxy_form.empty();
}

pub const ops = [_]Op{
    s("desafios do Discord no registro"),
    run(noteChallenges),
    run(resetGap),
    click("guild-join"),
    .{ .text = "discord.gg/qacaptcha" },
    .{ .wait = 300 },
    click("join-go"),
    expect("o pedido de captcha do Discord entra na contagem", captchaCounted),
    click("join-cancel"),
    run(resetGap),
    ctrl(c.ImGuiKey_Comma),
    click("settings:Avançado"),
    .{ .wait = 200 },
    expect("Avançado → Depuração mostra as contagens", countsShown),
    expect("Avançado: nada se sobrepõe", noOverlap),
    .{ .shot = "38-desafios" },

    s("proxy"),
    click("settings:Privacidade"),
    .{ .wait = 200 },
    click("proxy-input"),
    .{ .text = "ftp://nao.serve:21" },
    key(c.ImGuiKey_Enter),
    expect("proxy com URL inválida é recusado", rejected),
} ++ typeInto("proxy-input", "socks5://us%40er:p%3Ass%2Fw@[::1]:1080") ++ [_]Op{
    expect("colar a URL inteira no endereço preenche todos os campos", pastedFills),
    click("button:Salvar proxy"),
    expect("salvo, a URL volta com o IPv6 e o login e a senha codificados", savedPasted),
    click("seg:HTTP"),
} ++ typeInto("proxy-input", "proxy.local") ++ typeInto("proxy-port", "3128") ++ typeInto("proxy-user", "eu@casa") ++ typeInto("proxy-pass", "s3:nh@/%") ++ [_]Op{
    click("proxy-show"),
    expect("o olho mostra a senha", passShown),
    .{ .wait = 100 },
    .{ .shot = "37a-proxy-campos" },
    expect("Privacidade com os campos: nada se sobrepõe", noOverlap),
    click("proxy-show"),
    click("button:Salvar proxy"),
    expect("os campos viram a URL certa, com @ : / % do login e da senha codificados", savedFields),
    click("seg:SOCKS5h (Tor)"),
} ++ typeInto("proxy-input", "127.0.0.1") ++ typeInto("proxy-port", "9050") ++ clearField("proxy-user") ++ clearField("proxy-pass") ++ [_]Op{
    click("button:Salvar proxy"),
    expect("proxy salvo vale só para a mídia de fora", externalOnly),
    .{ .shot = "37-proxy" },
    click("toggle:Usar o proxy em tudo"),
    expect("\"em tudo\" inclui o Discord (API, gateway, imagens)", everywhere),
    expect("proxy vai para o settings.kdl", persisted),
    click("button:Remover proxy"),
    expect("remover volta à conexão direta e limpa os campos", removed),
    click("toggle:Usar o proxy em tudo"),
    click("settings-close"),
};
