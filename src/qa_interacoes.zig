//! QA das interações com bots (QA_SUITE=interacoes): botões, menu de seleção,
//! modal, comandos de barra com subcomando, escolha fixa e autocompletar. O
//! bot da demonstração (net/fake_interactions.zig) responde e guarda o último
//! pedido, que é conferido campo a campo.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const interact = @import("ui/interact.zig");
const fake = @import("net/fake_interactions.zig");

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 4000 } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}
fn text(t: []const u8) Op {
    return .{ .text = t };
}

fn has(needle: []const u8) bool {
    return std.mem.indexOf(u8, fake.sent.lastPayload(), needle) != null;
}

var sent_before: u32 = 0;
fn note(_: *App) void {
    sent_before = fake.sent.interactions.load(.monotonic);
}
fn sentOne() bool {
    return fake.sent.interactions.load(.monotonic) > sent_before;
}

fn toBugs(app: *App) void {
    app.handle(.{ .open_message = .{ .channel = fake.channel(), .id = 0 } });
}
fn botShown(app: *App) bool {
    const cs = app.store.channel(fake.channel()) orelse return false;
    return cs.history == .loaded and qa.find("ix-button:demo:ping") != null and qa.find("ix-select:demo:cor") != null;
}

/// A última mensagem do bot que só nós vemos.
fn ephemeral(app: *App) ?u64 {
    const cs = app.store.channel(fake.channel()) orelse return null;
    var i = cs.messages.items.len;
    while (i > 0) {
        i -= 1;
        const m = &cs.messages.items[i].msg;
        if (m.flags & (1 << 6) != 0) return m.id;
    }
    return null;
}
fn lastText(app: *App, needle: []const u8) bool {
    const cs = app.store.channel(fake.channel()) orelse return false;
    const items = cs.messages.items;
    if (items.len == 0) return false;
    return std.mem.indexOf(u8, items[items.len - 1].msg.content, needle) != null;
}

fn pingSent(_: *App) bool {
    return sentOne() and has("\"type\":3,") and has("\"custom_id\":\"demo:ping\"") and has("\"component_type\":2") and
        has("\"message_id\":\"") and has("\"message_flags\":0") and has("\"session_id\":\"demo-session\"") and has("\"nonce\":\"") and
        has("\"guild_id\":\"500000\"") and has("\"application_id\":\"1013\"");
}
fn ephemeralShown(app: *App) bool {
    const id = ephemeral(app) orelse return false;
    var b: [40]u8 = undefined;
    return qa.find(std.fmt.bufPrint(&b, "ix-dismiss:{d}", .{id}) catch return false) != null;
}
fn dismissTarget(app: *App, buf: []u8) []const u8 {
    const id = ephemeral(app) orelse return "";
    return std.fmt.bufPrint(buf, "ix-dismiss:{d}", .{id}) catch "";
}
fn dismissed(app: *App) bool {
    return ephemeral(app) == null;
}
fn failedShown(_: *App) bool {
    var keys: [4][56]u8 = undefined;
    var lens: [4]u8 = undefined;
    return sentOne() and has("demo:falha") and qa.keysWith(&.{"ix-failed:"}, &keys, &lens) > 0;
}
fn pickOpen(_: *App) bool {
    return qa.find("ix-pick:0") != null and qa.find("ix-pick-ok") != null;
}
fn colorsSent(app: *App) bool {
    return sentOne() and has("\"component_type\":3,\"custom_id\":\"demo:cor\",\"values\":[\"azul\",\"verde\"]") and lastText(app, "azul");
}
fn modalOpen(_: *App) bool {
    return interact.anyOpen() and qa.find("ix-modal") != null and qa.find("ix-field:1") != null;
}
fn modalKept(_: *App) bool {
    // Nome obrigatório vazio: nada sai, o modal fica.
    return qa.find("ix-modal") != null and !sentOne();
}
fn modalSent(app: *App) bool {
    return qa.find("ix-modal") == null and sentOne() and has("\"type\":5,") and has("\"custom_id\":\"demo:feedback\"") and
        has("\"custom_id\":\"nome\",\"value\":\"Ana\"") and has("\"values\":[\"5\"]") and lastText(app, "Ana");
}
fn listShown(_: *App) bool {
    return fake.sent.fetches.load(.monotonic) >= 1 and qa.find("autocomplete") != null and qa.find("ac:0") != null;
}
fn formOpen(_: *App) bool {
    return qa.find("ix-form") != null and qa.find("ix-opt:texto") != null;
}
fn formKept(_: *App) bool {
    return qa.find("ix-form") != null and !sentOne();
}
fn echoSent(app: *App) bool {
    return qa.find("ix-form") == null and sentOne() and has("\"type\":2,") and has("\"name\":\"eco\"") and
        has("{\"type\":3,\"name\":\"texto\",\"value\":\"oi\"}") and has("{\"type\":4,\"name\":\"vezes\",\"value\":2}") and lastText(app, "oi\noi");
}
fn fruitForm(_: *App) bool {
    return qa.find("ix-form") != null and qa.find("ix-opt:nome") != null;
}
fn suggestions(_: *App) bool {
    // A lista de antes (campo vazio) some quando sai o pedido novo: uma linha só é a do "ban".
    return fake.sent.autocompletes.load(.monotonic) >= 1 and has("\"type\":4,") and has("\"value\":\"ban\",\"focused\":true") and
        qa.find("ix-ac:0") != null and qa.find("ix-ac:1") == null;
}
fn fruitSent(app: *App) bool {
    return qa.find("ix-form") == null and has("\"name\":\"fruta\"") and has("\"value\":\"banana\"") and lastText(app, "banana");
}
fn subsShown(_: *App) bool {
    return qa.find("ix-form") != null and qa.find("ix-sub:0") != null and qa.find("ix-sub:1") != null;
}
fn ticketForm(_: *App) bool {
    return qa.find("ix-opt:motivo") != null and qa.find("ix-opt:prioridade") != null;
}
fn choicesOpen(_: *App) bool {
    return qa.find("ix-choice:1") != null;
}
fn ticketSent(app: *App) bool {
    return qa.find("ix-form") == null and has("{\"type\":1,\"name\":\"abrir\",\"options\":[") and has("\"value\":\"alta\"") and
        has("\"value\":\"teste\"") and ephemeral(app) != null;
}

pub const ops = [_]Op{
    s("Interações: botões e menus"),
    run(toBugs),
    expect("o bot mostra botões e menus", botShown),
    .{ .shot = "interacoes-botoes" },
    run(note),
    click("ix-button:demo:ping"),
    expect("o botão manda a interação com os campos do Discord", pingSent),
    expect("a resposta efêmera aparece com \"descartar\"", ephemeralShown),
    .{ .shot = "interacoes-efemera" },
    .{ .click = .{ .dyn = dismissTarget } },
    expect("descartar tira a mensagem só daqui", dismissed),
    run(note),
    click("ix-button:demo:falha"),
    expect("o bot não responde: \"esta interação falhou\"", failedShown),
    run(note),
    click("ix-select:demo:cor"),
    expect("o menu abre com as opções", pickOpen),
    click("ix-pick:0"),
    click("ix-pick:1"),
    click("ix-pick-ok"),
    expect("as duas cores vão para o bot e ele responde", colorsSent),

    s("Interações: modal"),
    run(note),
    click("ix-button:demo:form"),
    expect("o modal do bot abre", modalOpen),
    .{ .shot = "interacoes-modal" },
    run(note),
    click("ix-modal-submit"),
    expect("com o nome vazio, o modal não envia", modalKept),
    click("ix-field:1"),
    text("Ana"),
    click("ix-modal-submit"),
    expect("enviar manda o tipo 5 com os valores", modalSent),

    s("Interações: comandos de barra"),
    click("composer"),
    text("/eco"),
    expect("o / busca o índice e lista os comandos", listShown),
    .{ .shot = "interacoes-comandos" },
    key(c.ImGuiKey_Enter),
    expect("escolher abre o formulário", formOpen),
    run(note),
    click("ix-form-send"),
    expect("sem a opção obrigatória, nada sai", formKept),
    click("ix-opt:texto"),
    text("oi"),
    click("ix-opt:vezes"),
    text("2"),
    .{ .shot = "interacoes-formulario" },
    click("ix-form-send"),
    expect("o comando vai com as opções tipadas", echoSent),
    click("composer"),
    text("/fruta"),
    expect("a lista mostra o comando com autocompletar", listShown),
    key(c.ImGuiKey_Enter),
    expect("abre o formulário da fruta", fruitForm),
    click("ix-opt:nome"),
    text("ban"),
    expect("o bot sugere enquanto digita (tipo 4)", suggestions),
    click("ix-ac:0"),
    click("ix-form-send"),
    expect("a sugestão escolhida vai como valor", fruitSent),
    click("composer"),
    text("/ticket"),
    expect("a lista mostra o comando com subcomandos", listShown),
    key(c.ImGuiKey_Enter),
    expect("os subcomandos aparecem para escolher", subsShown),
    click("ix-sub:0"),
    expect("o subcomando mostra as opções dele", ticketForm),
    click("ix-opt:motivo"),
    text("teste"),
    click("ix-opt:prioridade"),
    expect("a opção de escolha fixa abre a lista", choicesOpen),
    click("ix-choice:1"),
    click("ix-form-send"),
    expect("subcomando e escolha vão aninhados", ticketSent),
};
