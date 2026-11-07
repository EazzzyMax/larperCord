//! QA da busca de mensagens no painel: filtros, sugestões, a conversa com o Discord (o servidor
//! de mentira guarda a consulta que iria para a API), páginas, ordem e os estados de erro.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const search = @import("ui/search.zig");
const sugg = @import("ui/search_sugg.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const Id = types.Id;

const geral: Id = 500005;
const memes: Id = 500006;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 6000 } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}

fn params() []const u8 {
    return gw.sent.search_params[0..gw.sent.search_len.load(.acquire)];
}
fn sent(part: []const u8) bool {
    return std.mem.indexOf(u8, params(), part) != null;
}
fn done() bool {
    return search.source == .server and search.server == .done;
}

fn toGeral(app: *App) void {
    app.handle(.{ .open_message = .{ .channel = geral, .id = 0 } });
}
fn isOpen(_: *App) bool {
    return search.open and qa.find("search-input") != null;
}
fn isClosed(_: *App) bool {
    return !search.open;
}
fn hintInk(app: *App) bool {
    return R.hasInk(app, "search-input");
}
fn tipsShown(_: *App) bool {
    return qa.find("search-tip:from:") != null and qa.find("search-tip:pinned:") != null;
}
fn typedFrom(_: *App) bool {
    return std.mem.eql(u8, search.text(), "from:") and sugg.count > 0 and qa.find("search-sugg:0") != null;
}
fn pickedPerson(_: *App) bool {
    const t = search.text();
    return std.mem.startsWith(u8, t, "from:") and t.len > 6 and t[t.len - 1] == ' ';
}
fn isEmpty(_: *App) bool {
    return search.text().len == 0;
}
fn localOnly(_: *App) bool {
    return search.source == .local and qa.find("search-run") != null;
}
fn firstPage(_: *App) bool {
    return done() and search.total == 60 and search.results.items.len == 25 and
        sent("content=zig") and sent("sort_by=timestamp") and sent("sort_order=desc") and sent("offset=0");
}
fn secondPage(_: *App) bool {
    return done() and search.offset == 25 and search.results.items.len == 25 and sent("offset=25");
}
fn byRelevance(_: *App) bool {
    return done() and search.offset == 0 and sent("sort_by=relevance") and sent("offset=0");
}
var last_result: struct { ch: Id = 0, id: Id = 0 } = .{};
fn noteResult(_: *App) void {
    if (search.results.items.len == 0) return;
    const r = search.results.items[0];
    last_result = .{ .ch = r.channel, .id = r.id };
}
fn jumped(app: *App) bool {
    if (!search.open or app.st.activeChannel() != last_result.ch) return false;
    var b: [40]u8 = undefined;
    return qa.find(std.fmt.bufPrint(&b, "msg:{d}", .{last_result.id}) catch return false) != null;
}
fn filtersSent(app: *App) bool {
    if (!done()) return false;
    var it = app.store.users.valueIterator();
    var ana: Id = 0;
    while (it.next()) |u| if (std.mem.indexOf(u8, u.name, "ana") != null) {
        ana = u.id;
    };
    var b: [48]u8 = undefined;
    const author = std.fmt.bufPrint(&b, "author_id={d}", .{ana}) catch return false;
    return ana != 0 and sent(author) and sent("has=image") and sent("channel_id=500006") and sent("max_id=") and !sent("content=");
}
fn chipsShown(_: *App) bool {
    return qa.find("search-chip:0") != null and qa.find("search-chip:3") != null;
}
fn chipRemoved(_: *App) bool {
    return std.mem.indexOf(u8, search.text(), "has:") == null and std.mem.indexOf(u8, search.text(), "from:ana") != null and qa.find("search-chip:2") != null and qa.find("search-chip:3") == null;
}
var searches_before: u64 = 0;
fn noteSearches(_: *App) void {
    searches_before = gw.sent.searches.load(.monotonic);
}
fn problemNoRequest(_: *App) bool {
    return search.problem().len > 0 and gw.sent.searches.load(.monotonic) == searches_before;
}
fn serverOnlyAsked(_: *App) bool {
    return done() and sent("pinned=true") and search.results.items.len > 0;
}
fn serverOnlyHint(_: *App) bool {
    return search.source == .local and search.serverOnly() and search.results.items.len == 0;
}
fn failedShown(_: *App) bool {
    return search.server == .failed and search.source == .local and qa.find("search-retry") != null;
}
fn retried(_: *App) bool {
    return gw.sent.searches.load(.monotonic) > searches_before and search.server == .failed;
}
fn forbiddenShown(_: *App) bool {
    return search.server == .forbidden and search.source == .server;
}
fn indexingThenDone(_: *App) bool {
    return done() and search.total == 60 and gw.sent.searches.load(.monotonic) >= searches_before + 2;
}
fn noResults(_: *App) bool {
    return done() and search.total == 0 and search.results.items.len == 0;
}
fn recentShown(_: *App) bool {
    return search.recentCount() > 0 and qa.find("search-recent:0") != null;
}
fn tabCompleted(_: *App) bool {
    return std.mem.eql(u8, search.text(), "in:memes ");
}
fn palettePanelNarrow(app: *App) bool {
    // O painel reserva lugar: a conversa fica toda à esquerda dele.
    return search.panel.x > 0 and search.panel.right() <= app.io.*.DisplaySize.x + 1 and qa.find("composer") != null and qa.find("composer").?.right() <= search.panel.x + 1;
}

pub const ops = [_]Op{
    s("busca: o painel e os filtros"),
    .{ .run = toGeral },
    .{ .wait = 300 },
    click("header-find"),
    expect("a caixa do cabeçalho abre o painel", isOpen),
    expect("a dica aparece na caixa de texto", hintInk),
    expect("sem nada digitado, os filtros", tipsShown),
    expect("a conversa fica ao lado do painel, sem nada por baixo", palettePanelNarrow),
    .{ .wait = 200 },
    .{ .shot = "busca-vazia" },
    click("search-tip:from:"),
    expect("clicar num filtro escreve ele e sugere pessoas", typedFrom),
    .{ .wait = 150 },
    .{ .shot = "busca-sugestoes" },
    click("search-sugg:0"),
    expect("escolher a pessoa completa o filtro", pickedPerson),
    click("search-clear"),
    expect("o X limpa a caixa", isEmpty),
    .{ .text = "in:mem" },
    .{ .wait = 100 },
    key(c.ImGuiKey_Tab),
    expect("Tab completa o canal", tabCompleted),
    click("search-clear"),

    s("busca: no Discord"),
    .{ .text = "zig" },
    expect("digitando, procura neste computador e oferece o Discord", localOnly),
    expect("o que se digita aparece na tela", hintInk),
    key(c.ImGuiKey_Enter),
    expect("Enter pergunta ao Discord, com a consulta certa", firstPage),
    .{ .wait = 250 },
    .{ .shot = "busca-discord" },
    click("search-page:next"),
    expect("a próxima página pede o offset 25", secondPage),
    click("search-sort:relevance"),
    expect("trocar a ordem pede de novo, do começo", byRelevance),
    click("search-sort:newest"),
    .{ .expect = .{ .name = "volta para as mais recentes", .check = firstPage, .timeout_ms = 6000 } },
    .{ .run = noteResult },
    click("search-result:0"),
    .{ .expect = .{ .name = "clicar pula até a mensagem, com o painel aberto", .check = jumped, .timeout_ms = 8000 } },

    s("busca: filtros no Discord"),
    click("search-clear"),
    .{ .text = "from:ana has:imagem in:memes before:2026-01-02" },
    expect("as etiquetas mostram os filtros", chipsShown),
    click("search-run"),
    expect("os filtros viram os parâmetros da API", filtersSent),
    .{ .wait = 150 },
    .{ .shot = "busca-filtros" },
    click("search-chip:1"),
    expect("a etiqueta tira o filtro do texto", chipRemoved),
    click("search-clear"),
    .{ .text = "pinned:true" },
    expect("filtro que só o Discord resolve avisa em vez de mostrar errado", serverOnlyHint),
    key(c.ImGuiKey_Enter),
    expect("e vai para a API", serverOnlyAsked),

    s("busca: o que pode dar errado"),
    click("search-clear"),
    .{ .run = noteSearches },
    .{ .text = "from:ninguem-existe" },
    key(c.ImGuiKey_Enter),
    expect("pessoa desconhecida avisa e não pergunta nada", problemNoRequest),
    click("search-clear"),
    .{ .text = "before:logo" },
    key(c.ImGuiKey_Enter),
    expect("data que não dá para entender avisa e não pergunta nada", problemNoRequest),
    click("search-clear"),
    .{ .text = "falha" },
    key(c.ImGuiKey_Enter),
    expect("sem resposta, avisa e fica com o que está aqui", failedShown),
    .{ .wait = 150 },
    .{ .shot = "busca-falha" },
    .{ .run = noteSearches },
    click("search-retry"),
    expect("tentar de novo pergunta outra vez", retried),
    click("search-clear"),
    .{ .text = "proibido" },
    key(c.ImGuiKey_Enter),
    expect("sem permissão, explica", forbiddenShown),
    click("search-clear"),
    .{ .run = noteSearches },
    .{ .text = "indexando" },
    key(c.ImGuiKey_Enter),
    .{ .expect = .{ .name = "o Discord ainda indexando: tenta de novo sozinho", .check = indexingThenDone, .timeout_ms = 8000 } },
    click("search-clear"),
    .{ .text = "nada" },
    key(c.ImGuiKey_Enter),
    expect("nenhum resultado, sem erro", noResults),
    .{ .wait = 150 },
    .{ .shot = "busca-nada" },
    click("search-clear"),
    expect("as últimas buscas ficam na lista", recentShown),
    .{ .wait = 150 },
    .{ .shot = "busca-recentes" },
    click("search-recent:0"),
    expect("clicar numa busca recente faz ela de novo", noResults),
    .{ .wait = 100 },
    key(c.ImGuiKey_Escape),
    expect("Esc fecha o painel", isClosed),
};
