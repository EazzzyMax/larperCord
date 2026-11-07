//! QA da moderação (QA_SUITE=moderacao): o que aparece no menu de cada pessoa
//! conforme a hierarquia, a confirmação com motivo, o pedido que sairia para o
//! Discord (método, caminho, corpo e o cabeçalho do motivo), a pessoa saindo da
//! lista, o reloginho de castigo, silenciar na call e revogar um banimento.
//! No primeiro servidor somos donos; no terceiro (gw.mod_guild), da Moderação.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const mod_ui = @import("ui/moderacao.zig");
const Id = @import("core/types.zig").Id;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn rclick(k: []const u8) Op {
    return .{ .rclick = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 5000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}
const esc: Op = .{ .key = .{ .key = c.ImGuiKey_Escape } };

const dono = gw.guildId(0);
const moderado = gw.guildId(gw.mod_guild);

fn toDono(app: *App) void {
    app.st.popup = .none;
    app.handle(.{ .open_message = .{ .channel = gw.channelId(0, 4), .id = 0 } });
}
fn toModerado(app: *App) void {
    app.st.popup = .none;
    app.handle(.{ .open_message = .{ .channel = gw.channelId(gw.mod_guild, 4), .id = 0 } });
}
fn closePopup(app: *App) void {
    app.st.popup = .none;
}

/// O último pedido como sairia para o Discord.
fn lastReq() []const u8 {
    const n = gw.sent.mod_len.load(.acquire);
    return gw.sent.mod_req[0..@min(n, gw.sent.mod_req.len)];
}
fn reqIs(want: []const u8) bool {
    return std.mem.eql(u8, lastReq(), want);
}

fn inList(app: *App, guild: Id, user: Id) bool {
    const ml = app.store.memberList(guild) orelse return false;
    for (ml.items.items) |it| if (it == .member and it.member.user == user) return true;
    return false;
}

fn listaModerado(app: *App) bool {
    return app.st.guild == moderado and qa.find("member:1002") != null and qa.find("member:1001") != null;
}
fn listaDono(app: *App) bool {
    return app.st.guild == dono and qa.find("member:1002") != null and qa.find("member:1007") != null;
}
fn menuOpen(app: *App) bool {
    return app.st.popup == .menu and qa.find("menu:Perfil") != null;
}
fn modItemsAbaixo(app: *App) bool {
    return menuOpen(app) and qa.find("menu:Expulsar…") != null and qa.find("menu:Banir…") != null and qa.find("menu:Castigar…") != null;
}
fn semModItems(app: *App) bool {
    return menuOpen(app) and qa.find("menu:Expulsar…") == null and qa.find("menu:Banir…") == null and qa.find("menu:Castigar…") == null and
        qa.find("menu:Silenciar no servidor") == null and qa.find("menu:Tirar silêncio do servidor") == null;
}
fn vozItems(app: *App) bool {
    return menuOpen(app) and qa.find("menu:Silenciar no servidor") != null and qa.find("menu:Ensurdecer no servidor") != null;
}
fn mutou(app: *App) bool {
    var b: [96]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "PATCH /guilds/{d}/members/1005\n{{\"mute\":true}}\n", .{moderado}) catch return false;
    return reqIs(want) and app.store.voiceFlags(1005).mute;
}
fn desmutarAparece(app: *App) bool {
    return menuOpen(app) and qa.find("menu:Tirar silêncio do servidor") != null;
}
fn desmutou(app: *App) bool {
    var b: [96]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "PATCH /guilds/{d}/members/1005\n{{\"mute\":false}}\n", .{moderado}) catch return false;
    return reqIs(want) and !app.store.voiceFlags(1005).mute;
}
fn bansNoMenu(app: *App) bool {
    return app.st.popup == .menu and qa.find("menu:Banimentos") != null;
}
fn semBansNoMenu(app: *App) bool {
    return app.st.popup == .menu and qa.find("menu:Marcar como lido") != null and qa.find("menu:Banimentos") == null;
}

fn cartao(app: *App) bool {
    return app.st.popup == .profile and qa.find("profile-more") != null;
}

fn dialogo(app: *App) bool {
    return app.st.popup == .moderacao and qa.find("mod-dialog") != null and qa.find("mod-motivo") != null and qa.find("mod-confirm") != null;
}
fn expulsou(app: *App) bool {
    var b: [128]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "DELETE /guilds/{d}/members/1002\n\nX-Audit-Log-Reason: flood%20no%20%23geral", .{dono}) catch return false;
    return reqIs(want) and app.st.popup == .none and !inList(app, dono, 1002) and qa.find("member:1002") == null;
}
var mods_before: u64 = 0;
fn noteMods(_: *App) void {
    mods_before = gw.sent.mods.load(.acquire);
}
fn cancelou(app: *App) bool {
    return app.st.popup == .none and gw.sent.mods.load(.acquire) == mods_before and inList(app, dono, 1007);
}
fn recusou(app: *App) bool {
    return app.st.popup == .moderacao and qa.find("mod-erro") != null and inList(app, dono, gw.bot_user);
}
fn castigou(app: *App) bool {
    var b: [96]u8 = undefined;
    const head = std.fmt.bufPrint(&b, "PATCH /guilds/{d}/members/1007\n{{\"communication_disabled_until\":\"", .{dono}) catch return false;
    const mi = app.store.memberInfo(dono, 1007) orelse return false;
    const now_s = @divTrunc(gw.nowMs(), 1000);
    // Uma hora a partir de agora (com folga para o tempo do QA).
    const ok_time = @as(i64, mi.timeout_s) > now_s + 3500 and @as(i64, mi.timeout_s) <= now_s + 3600;
    return std.mem.startsWith(u8, lastReq(), head) and std.mem.endsWith(u8, lastReq(), ".000Z\"}\n") and ok_time and
        app.st.popup == .none and qa.find("timeout-badge") != null;
}
fn removerAparece(app: *App) bool {
    return menuOpen(app) and qa.find("menu:Remover castigo…") != null and qa.find("menu:Castigar…") == null;
}
fn descastigou(app: *App) bool {
    var b: [96]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "PATCH /guilds/{d}/members/1007\n{{\"communication_disabled_until\":null}}\n", .{dono}) catch return false;
    const mi = app.store.memberInfo(dono, 1007) orelse return false;
    return reqIs(want) and mi.timeout_s == 0 and qa.find("timeout-badge") == null;
}
fn baniu(app: *App) bool {
    var b: [128]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "PUT /guilds/{d}/bans/1004\n{{\"delete_message_seconds\":86400}}\nX-Audit-Log-Reason: spam", .{dono}) catch return false;
    return reqIs(want) and app.st.popup == .none and !inList(app, dono, 1004);
}
fn banido(list: []const @import("core/event.zig").Ban, user: Id) bool {
    for (list) |b| if (b.user == user) return true;
    return false;
}
fn bansAbertos(app: *App) bool {
    const list = mod_ui.banidos();
    return app.st.popup == .moderacao and qa.find("bans-panel") != null and banido(list, gw.banned_user) and banido(list, 1004) and
        qa.find("ban:1010") != null and qa.find("unban:1004") != null;
}
fn revogou(app: *App) bool {
    var b: [96]u8 = undefined;
    const want = std.fmt.bufPrint(&b, "DELETE /guilds/{d}/bans/1010\n\n", .{dono}) catch return false;
    return reqIs(want) and !banido(mod_ui.banidos(), gw.banned_user) and qa.find("ban:1010") == null and
        app.st.popup == .moderacao and banido(mod_ui.banidos(), 1004);
}
fn fechou(app: *App) bool {
    return app.st.popup == .none;
}

fn abrirNoTema(app: *App) void {
    mod_ui.qaAbrirExpulsar(&app.st, dono, 1002);
}

/// No QA de cada tema: o diálogo de confirmação, para ver se combina com o tema.
pub const ops_theme = [_]Op{
    run(abrirNoTema),
    expect("o diálogo de moderação abre", dialogo),
    .{ .wait = 250 },
    .{ .shot = "tema-moderacao" },
    click("mod-cancel"),
    expect("cancelar fecha o diálogo de moderação", fechou),
};

pub const ops = [_]Op{
    s("moderação: o que aparece conforme a hierarquia"),
    run(toModerado),
    expect("no servidor em que somos da Moderação, a lista de membros carrega", listaModerado),
    rclick("member:1002"),
    expect("alguém de cargo abaixo: expulsar, banir e castigar aparecem", modItemsAbaixo),
    .{ .shot = "moderacao-menu" },
    esc,
    rclick("member:1001"),
    expect("o dono (cargo acima): nada de moderação", semModItems),
    esc,
    rclick("member:1003"),
    expect("mesmo cargo que o nosso: nada de moderação", semModItems),
    esc,
    rclick("voice-member:502014:1005"),
    expect("na call, abaixo de nós: silenciar e ensurdecer no servidor", vozItems),
    click("menu:Silenciar no servidor"),
    expect("silenciar manda PATCH {\"mute\":true} e o ícone da call muda", mutou),
    rclick("voice-member:502014:1005"),
    expect("silenciada: o menu oferece tirar o silêncio", desmutarAparece),
    click("menu:Tirar silêncio do servidor"),
    expect("tirar o silêncio manda {\"mute\":false}", desmutou),
    rclick("voice-member:502014:1003"),
    expect("na call, com o mesmo cargo: nada de silenciar", semModItems),
    esc,
    rclick("guild-header"),
    expect("quem pode banir vê os banimentos no menu do servidor", bansNoMenu),
    esc,
    rclick("guild:501000"),
    expect("sem permissão de banir, o menu do servidor não tem banimentos", semBansNoMenu),
    esc,

    s("moderação: expulsar, com confirmação e motivo"),
    run(toDono),
    expect("no nosso servidor, a lista de membros carrega", listaDono),
    click("member:1007"),
    expect("o cartão de perfil tem o botão de mais opções", cartao),
    click("profile-more"),
    expect("o ⋯ do cartão abre o menu com a moderação", modItemsAbaixo),
    esc,
    rclick("member:1007"),
    click("menu:Expulsar…"),
    expect("expulsar pede confirmação, com o campo de motivo", dialogo),
    run(noteMods),
    click("mod-cancel"),
    expect("cancelar não manda nada e a pessoa fica", cancelou),
    rclick("member:1002"),
    click("menu:Expulsar…"),
    expect("o diálogo abre de novo", dialogo),
    .{ .text = "flood no #geral" },
    .{ .wait = 100 },
    .{ .shot = "moderacao-expulsar" },
    click("mod-confirm"),
    expect("manda DELETE com o motivo em URL, fecha e a pessoa sai da lista", expulsou),

    s("moderação: o Discord recusa"),
    rclick("member:1012"),
    click("menu:Expulsar…"),
    click("mod-confirm"),
    expect("sem permissão (50013): o diálogo explica e a pessoa fica", recusou),
    .{ .shot = "moderacao-erro" },
    click("mod-cancel"),
    expect("cancelar fecha", fechou),

    s("moderação: castigo"),
    rclick("member:1007"),
    click("menu:Castigar…"),
    expect("castigar abre o diálogo", dialogo),
    click("mod-castigo:3600"),
    click("mod-confirm"),
    expect("1 h: PATCH com a hora ISO e o reloginho aparece na lista", castigou),
    .{ .shot = "moderacao-castigo" },
    rclick("member:1007"),
    expect("de castigo: o menu oferece remover", removerAparece),
    click("menu:Remover castigo…"),
    expect("remover abre o diálogo", dialogo),
    click("mod-confirm"),
    expect("remover manda null e o reloginho some", descastigou),

    s("moderação: banir e revogar"),
    rclick("member:1004"),
    click("menu:Banir…"),
    expect("banir abre o diálogo", dialogo),
    click("mod-apagar:86400"),
    click("mod-motivo"),
    .{ .text = "spam" },
    click("mod-confirm"),
    expect("manda PUT com as mensagens a apagar e o motivo, e a pessoa sai", baniu),
    rclick("guild:500000"),
    click("menu:Banimentos"),
    expect("a lista de banimentos mostra quem já estava e quem acabou de ser banido", bansAbertos),
    .{ .wait = 150 },
    .{ .shot = "moderacao-banimentos" },
    click("unban:1010"),
    expect("revogar manda DELETE e tira da lista", revogou),
    click("bans-close"),
    expect("fechar", fechou),
    run(closePopup),
};
