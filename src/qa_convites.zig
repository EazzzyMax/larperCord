//! QA dos convites: criar, gerar outro com outras regras, copiar e entrar pelo link. O servidor
//! de mentira responde também o que o Discord pode recusar.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const invites = @import("ui/invites.zig");
const att = @import("ui/attachments.zig");
const gw = @import("net/fake_gateway.zig");

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
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

fn toGeral(app: *App) void {
    app.handle(.{ .open_message = .{ .channel = 500005, .id = 0 } });
}
var first_code: [32]u8 = undefined;
var first_len: usize = 0;
fn noteCode(_: *App) void {
    const code = invites.madeCode();
    first_len = code.len;
    @memcpy(first_code[0..code.len], code);
}
fn firstLink(app: *App) bool {
    return invites.madeCode().len > 0 and gw.sent.invite_age.load(.monotonic) == 2592000 and gw.sent.invite_uses.load(.monotonic) == 0 and
        gw.sent.invite_temporary.load(.monotonic) == 0 and R.hasInk(app, "invite-link");
}
fn newRules(_: *App) bool {
    return gw.sent.invite_age.load(.monotonic) == 21600 and gw.sent.invite_uses.load(.monotonic) == 1 and gw.sent.invite_temporary.load(.monotonic) == 1 and
        !std.mem.eql(u8, invites.madeCode(), first_code[0..first_len]);
}
fn copied(_: *App) bool {
    const clip = c.SDL_GetClipboardText() orelse return false;
    defer c.SDL_free(clip);
    var b: [64]u8 = undefined;
    return std.mem.eql(u8, std.mem.span(clip), std.fmt.bufPrint(&b, "https://discord.gg/{s}", .{invites.madeCode()}) catch return false);
}
fn forbidden(_: *App) bool {
    return invites.create_state == .forbidden and invites.madeCode().len > 0;
}
fn closed(app: *App) bool {
    return app.st.popup == .none;
}
fn joinOpen(app: *App) bool {
    return app.st.popup == .join_invite and qa.find("join-input") != null;
}
fn previewShown(app: *App) bool {
    const inv = app.store.invites.get("qateste") orelse return false;
    return inv.state == .ok and R.hasInk(app, "join-preview");
}
fn enteredGuild(app: *App) bool {
    return app.st.popup == .none and app.st.guild == gw.guildId(2) and gw.sent.invite_joins.load(.monotonic) >= 1;
}
var joins_before: u64 = 0;
fn noteJoins(_: *App) void {
    joins_before = gw.sent.invite_joins.load(.monotonic);
}
fn waitsBetween(_: *App) bool {
    return gw.sent.invite_joins.load(.monotonic) == joins_before and invites.join_state == .idle;
}
fn resetGap(_: *App) void {
    invites.qaResetGap();
}
fn captchaOpensBrowser(app: *App) bool {
    const url = att.last_opened[0..att.last_opened_len];
    return invites.join_state == .captcha and app.st.popup == .join_invite and std.mem.eql(u8, url, "https://discord.gg/qacaptcha");
}
fn refused(_: *App) bool {
    return invites.join_state == .forbidden;
}
fn tooMany(_: *App) bool {
    return invites.join_state == .too_many;
}

pub const ops = [_]Op{
    s("convites: criar e gerar outro"),
    run(toGeral),
    .{ .wait = 300 },
    .{ .rclick = .{ .mark = "guild:500000" } },
    click("menu:Convidar pessoas…"),
    expect("o menu do servidor cria o link, como o Discord pede", firstLink),
    run(noteCode),
    .{ .wait = 150 },
    .{ .shot = "convite-criar" },
    click("invite-copy"),
    expect("copiar põe o link na área de transferência", copied),
    click("invite-age:21600"),
    click("invite-uses:1"),
    click("invite-temporary"),
    .{ .wait = 100 },
    .{ .shot = "convite-editar" },
    click("invite-generate"),
    expect("gerar outro manda as regras novas e troca o link", newRules),
    click("invite-uses:100"),
    click("invite-generate"),
    expect("sem permissão, explica e deixa o link que já existia", forbidden),
    click("invite-uses:0"),
    click("invite-temporary"),
    click("invite-close"),
    expect("fechar", closed),

    s("convites: entrar"),
    click("guild-join"),
    expect("o + da barra abre a entrada por convite", joinOpen),
    .{ .text = "https://discord.gg/qateste" },
    expect("o servidor aparece antes de entrar", previewShown),
    .{ .wait = 150 },
    .{ .shot = "convite-entrar" },
    click("join-go"),
    expect("entrar abre o servidor", enteredGuild),
    run(noteJoins),
    click("guild-join"),
    .{ .text = "qateste" },
    expect("só o código também serve", previewShown),
    click("join-go"),
    .{ .wait = 300 },
    expect("uma entrada logo depois da outra espera", waitsBetween),
    click("join-cancel"),
    run(resetGap),
    click("guild-join"),
    .{ .text = "discord.gg/qacaptcha" },
    .{ .wait = 300 },
    click("join-go"),
    expect("captcha abre o convite no navegador, sem insistir", captchaOpensBrowser),
    .{ .wait = 100 },
    .{ .shot = "convite-captcha" },
    click("join-cancel"),
    run(resetGap),
    click("guild-join"),
    .{ .text = "qabanido" },
    .{ .wait = 300 },
    click("join-go"),
    expect("recusa do Discord aparece na tela", refused),
    click("join-cancel"),
    run(resetGap),
    click("guild-join"),
    .{ .text = "qacheio" },
    .{ .wait = 300 },
    click("join-go"),
    expect("máximo de servidores aparece na tela", tooMany),
    click("join-cancel"),
    expect("cancelar fecha", closed),
    run(resetGap),
    // O resto da bateria conta com a conversa onde estava: entrar levou para outro servidor.
    run(toGeral),
    .{ .wait = 400 },
};
