//! QA de entrar num servidor com cuidado: o aviso antes de entrar por convite, a caixa de
//! texto de quem ainda não respondeu as regras, o formulário das regras respondido à mão e as
//! boas-vindas. O servidor de mentira tem um servidor com regras e perguntas (`entrada_guild`).
const std = @import("std");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const invites = @import("ui/invites.zig");
const entrada = @import("ui/entrada.zig");
const j = @import("net/jsonx.zig");
const gw = @import("net/fake_gateway.zig");

const guild = gw.guildId(gw.entrada_guild);

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

var joins0: u64 = 0;
fn start(app: *App) void {
    app.st.settings.join_warning = true;
    invites.qaResetGap();
    joins0 = gw.sent.invite_joins.load(.monotonic);
}
fn joinOpen(app: *App) bool {
    return app.st.popup == .join_invite and qa.find("join-input") != null;
}
fn previewShown(app: *App) bool {
    const inv = app.store.invites.get("qaregras") orelse return false;
    return inv.state == .ok and R.hasInk(app, "join-preview");
}
fn warned(app: *App) bool {
    return entrada.warning_open and app.st.popup == .join_invite and qa.find("join-warn-go") != null and R.hasInk(app, "join-warning") and
        gw.sent.invite_joins.load(.monotonic) == joins0;
}
fn backToForm(app: *App) bool {
    return !entrada.warning_open and app.st.popup == .join_invite and qa.find("join-input") != null and gw.sent.invite_joins.load(.monotonic) == joins0;
}
fn joinedPending(app: *App) bool {
    return app.st.popup == .none and app.st.guild == guild and app.store.isPending(guild) and !app.st.settings.join_warning and
        gw.sent.invite_joins.load(.monotonic) == joins0 + 1;
}
fn pendingBand(_: *App) bool {
    return qa.find("composer-pending") != null and qa.find("pending-rules") != null and gw.sent.entrada_forms.load(.monotonic) == 0;
}
fn rulesOpen(app: *App) bool {
    return app.st.popup == .server_rules and gw.sent.entrada_forms.load(.monotonic) == 1 and qa.find("rules-agree:0") != null and qa.find("rules-choice:3:2") != null;
}
fn cannotSend(_: *App) bool {
    return !entrada.qaCanSend() and gw.sent.entrada_form_sends.load(.monotonic) == 0;
}
fn canSend(_: *App) bool {
    return entrada.qaCanSend();
}

/// O último corpo que "foi para o Discord", lido como JSON.
fn sentJson(arena: std.mem.Allocator) ?std.json.Value {
    const body = gw.sent.entrada_body[0..gw.sent.entrada_len.load(.acquire)];
    return std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{}) catch null;
}
fn formSent(app: *App) bool {
    if (gw.sent.entrada_form_sends.load(.monotonic) != 1) return false;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const v = sentJson(arena.allocator()) orelse return false;
    const fields = j.array(j.get(v, "form_fields"));
    if (fields.len != 4) return false;
    const terms = j.get(fields[0], "response") orelse return false;
    if (terms != .bool or !terms.bool) return false;
    if (!std.mem.eql(u8, j.str(j.get(fields[1], "response")) orelse "", "Alex")) return false;
    // O opcional que ficou vazio vai sem resposta.
    if (j.get(fields[2], "response") != null) return false;
    if ((j.int(j.get(fields[3], "response")) orelse -1) != 1) return false;
    return !app.store.isPending(guild) and R.hasInk(app, "rules-ok");
}
fn composerBack(app: *App) bool {
    return app.st.popup == .none and qa.find("composer-pending") == null;
}
fn onbOpen(app: *App) bool {
    return app.st.popup == .onboarding and gw.sent.entrada_onboardings.load(.monotonic) == 1 and qa.find("onb-option:1:1") != null;
}
fn onbNothing(_: *App) bool {
    return entrada.qaSelected().len == 0 and gw.sent.entrada_onboarding_sends.load(.monotonic) == 0;
}
fn onbSingle(_: *App) bool {
    const sel = entrada.qaSelected();
    return sel.len == 1 and sel[0] == 9102;
}
fn onbSent(app: *App) bool {
    if (gw.sent.entrada_onboarding_sends.load(.monotonic) != 1 or gw.sent.entrada_onboarding_first.load(.monotonic) != 1) return false;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const v = sentJson(arena.allocator()) orelse return false;
    const resp = j.array(j.get(v, "onboarding_responses"));
    if (resp.len != 3) return false;
    for (resp, [_][]const u8{ "9102", "9201", "9202" }) |x, want| if (!std.mem.eql(u8, j.str(x) orelse "", want)) return false;
    return R.hasInk(app, "onb-ok");
}

pub const ops = [_]Op{
    s("entrada: aviso antes de entrar"),
    run(start),
    click("guild-join"),
    expect("o + da barra abre a entrada por convite", joinOpen),
    .{ .text = "discord.gg/qaregras" },
    expect("o servidor aparece antes de entrar", previewShown),
    click("join-go"),
    expect("antes de entrar, o aviso aparece e nada vai para o Discord", warned),
    .{ .wait = 150 },
    .{ .shot = "entrada-aviso" },
    click("join-warn-back"),
    expect("voltar não entra", backToForm),
    click("join-go"),
    expect("o aviso volta no próximo clique", warned),
    click("join-warn-never"),
    click("join-warn-go"),
    expect("entrar mesmo assim entra uma vez e guarda o não mostrar de novo", joinedPending),

    s("entrada: regras"),
    expect("pendente: a caixa de texto diz o motivo e não busca nada sozinha", pendingBand),
    .{ .wait = 150 },
    .{ .shot = "entrada-pendente" },
    click("pending-rules"),
    expect("abrir as regras busca o formulário uma vez", rulesOpen),
    .{ .wait = 150 },
    .{ .shot = "entrada-regras" },
    expect("nada vem marcado: enviar fica apagado", cannotSend),
    click("rules-submit"),
    expect("clicar no botão apagado não envia", cannotSend),
    click("rules-agree:0"),
    click("rules-text:1"),
    .{ .text = "Alex" },
    click("rules-choice:3:1"),
    expect("respondido à mão, dá para enviar", canSend),
    click("rules-submit"),
    expect("envia todos os campos com as respostas dadas, e o servidor libera", formSent),
    .{ .wait = 100 },
    .{ .shot = "entrada-regras-ok" },
    click("rules-ok"),
    expect("a caixa de texto volta", composerBack),

    s("entrada: boas-vindas"),
    click("guild-header"),
    click("menu:Boas-vindas do servidor…"),
    expect("abrir as boas-vindas busca as perguntas uma vez", onbOpen),
    .{ .wait = 150 },
    .{ .shot = "entrada-boas-vindas" },
    expect("nada vem escolhido", onbNothing),
    click("onb-option:0:0"),
    click("onb-option:0:1"),
    expect("escolha única troca a anterior", onbSingle),
    click("onb-option:1:0"),
    click("onb-option:1:1"),
    click("onb-submit"),
    expect("salva só o que foi escolhido", onbSent),
    click("onb-ok"),
    expect("fechar", composerBack),
};
