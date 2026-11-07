//! QA do envio (QA_SUITE=envio): as opções da caixa (silenciosa, sem prévias,
//! sem menções, "@silent"), o "@ LIGADO" da resposta, spoiler e texto
//! alternativo na bandeja, votar nas enquetes, quem votou, quem reagiu e as
//! fixadas em páginas. O corpo e o caminho de cada pedido que iria para o
//! Discord ficam em `gw.sent`, montados como o gateway de verdade monta.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const polls = @import("core/polls.zig");
const Id = types.Id;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn dyn(f: *const fn (*App, []u8) []const u8) Op {
    return .{ .click = .{ .dyn = f } };
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
/// Rola a lista que está sob o mouse até o fim (o "Mostrar mais" fica lá).
fn wheelDown(app: *App) void {
    c.ImGuiIO_AddMouseWheelEvent(app.io, 0, -60);
}
fn mk(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch "";
}

fn body() []const u8 {
    return gw.sent.view(&gw.sent.send_body, &gw.sent.send_body_len);
}
fn has(text: []const u8, part: []const u8) bool {
    return std.mem.indexOf(u8, text, part) != null;
}

// --- Navegação ----------------------------------------------------------------

fn toPolls(app: *App) void {
    app.handle(.{ .open_message = .{ .channel = gw.poll_channel, .id = 0 } });
}

/// A enquete de uma escolha (`multi` = false) ou a de várias.
fn pollId(app: *App, multi: bool) ?Id {
    const cs = app.store.channel(gw.poll_channel) orelse return null;
    for (cs.messages.items) |*m| {
        const p = app.store.polls.get(m.msg.id) orelse continue;
        if (p.multi == multi) return m.msg.id;
    }
    return null;
}
fn poll(app: *App, multi: bool) ?*polls.Poll {
    return app.store.polls.get(pollId(app, multi) orelse return null);
}

/// A mensagem cheia de 🎉 (a última do canal, como a demonstração monta).
fn partyMsg(app: *App) ?*@import("core/store.zig").StoredMessage {
    const cs = app.store.channel(gw.poll_channel) orelse return null;
    var i = cs.messages.items.len;
    while (i > 0) {
        i -= 1;
        const m = &cs.messages.items[i];
        for (m.reactionSlice()) |r| if (r.custom == 0 and std.mem.eql(u8, r.text(), "🎉") and r.burst > 0) return m;
    }
    return null;
}

/// Mensagem de outra pessoa para responder (nem enquete, nem nossa).
fn otherMsg(app: *App) Id {
    const cs = app.store.channel(gw.poll_channel) orelse return 0;
    var i = cs.messages.items.len;
    while (i > 0) {
        i -= 1;
        const m = &cs.messages.items[i];
        if (m.msg.id != 0 and m.msg.author != app.store.me and m.msg.content.len > 0 and app.store.polls.get(m.msg.id) == null) return m.msg.id;
    }
    return 0;
}

fn jumpPoll(app: *App) void {
    if (pollId(app, false)) |id| app.handle(.{ .jump_to = id });
}
fn jumpMulti(app: *App) void {
    if (pollId(app, true)) |id| app.handle(.{ .jump_to = id });
}
fn jumpParty(app: *App) void {
    if (partyMsg(app)) |m| app.handle(.{ .jump_to = m.msg.id });
}

// --- Opções da caixa ----------------------------------------------------------

fn pollsLoaded(app: *App) bool {
    return app.st.activeChannel() == gw.poll_channel and pollId(app, false) != null and pollId(app, true) != null and partyMsg(app) != null;
}
fn nothingFetched(_: *App) bool {
    return gw.sent.people_fetches.load(.monotonic) == 0 and gw.sent.votes.load(.monotonic) == 0;
}
fn menuOpen(app: *App) bool {
    return app.st.popup == .compose_options and R.hasInk(app, "compose-options-menu");
}
fn twoOn(app: *App) bool {
    const o = app.st.send_opts;
    return o.silent and o.no_embeds and !o.no_pings;
}
fn closed(app: *App) bool {
    return app.st.popup == .none;
}
fn silentNoEmbeds(app: *App) bool {
    const b = body();
    return has(b, "\"content\":\"silenciosa e sem prévia https://ziglang.org\"") and has(b, "\"flags\":4100") and app.st.send_opts.count() == 0;
}
fn atSilent(app: *App) bool {
    const b = body();
    const cs = app.store.channel(gw.poll_channel) orelse return false;
    const last = cs.messages.items[cs.messages.items.len - 1];
    return has(b, "\"content\":\"psiu\"") and has(b, "\"flags\":4096") and std.mem.eql(u8, last.msg.content, "psiu");
}
fn pingsOn(app: *App) bool {
    return app.st.send_opts.no_pings and app.st.send_opts.count() == 1;
}
fn noPings(app: *App) bool {
    const b = body();
    return has(b, "\"content\":\"ninguém é avisado\"") and has(b, "\"allowed_mentions\":{\"parse\":[],\"replied_user\":false}") and !has(b, "\"flags\"") and app.st.send_opts.count() == 0;
}

// --- Resposta -----------------------------------------------------------------

fn replyOther(app: *App) void {
    const id = otherMsg(app);
    if (id != 0) app.handle(.{ .reply = id });
}
fn toggleShown(app: *App) bool {
    return app.st.reply_to != 0 and app.st.reply_ping and R.hasInk(app, "reply-ping");
}
fn repliedWithPing(_: *App) bool {
    const b = body();
    return has(b, "\"content\":\"com menção\"") and has(b, "\"message_reference\":{\"message_id\":") and has(b, "\"parse\":[\"users\",\"roles\",\"everyone\"],\"replied_user\":true");
}
fn pingOff(app: *App) bool {
    return app.st.reply_to != 0 and !app.st.reply_ping;
}
fn repliedNoPing(app: *App) bool {
    const b = body();
    return has(b, "\"content\":\"sem menção\"") and has(b, "\"replied_user\":false") and app.st.reply_to == 0;
}
fn remembered(app: *App) bool {
    return app.st.reply_to != 0 and !app.st.reply_ping and R.hasInk(app, "reply-ping");
}
fn pingBack(app: *App) bool {
    return app.st.reply_ping;
}
fn notReplying(app: *App) bool {
    return app.st.reply_to == 0;
}

// --- Bandeja ------------------------------------------------------------------

fn attachImage(app: *App) void {
    const surf = c.SDL_CreateSurface(120, 80, c.SDL_PIXELFORMAT_RGBA32) orelse return;
    defer c.SDL_DestroySurface(surf);
    const px: [*]u8 = @ptrCast(surf.*.pixels.?);
    const pitch: usize = @intCast(surf.*.pitch);
    for (0..80) |y| for (0..120) |x| {
        const o = px[y * pitch + x * 4 ..][0..4];
        o.* = .{ 240, @intCast(120 + x / 2), @intCast(y * 2), 255 };
    };
    _ = c.SDL_CreateDirectory("qa-out");
    _ = c.SDL_SavePNG(surf, "qa-out/envio-anexo.png");
    var buf: [1024]u8 = undefined;
    const cwd = c.SDL_GetCurrentDirectory() orelse return;
    defer c.SDL_free(cwd);
    app.attachFile(std.fmt.bufPrint(&buf, "{s}qa-out/envio-anexo.png", .{std.mem.span(cwd)}) catch return);
}
fn oneUpload(app: *App) bool {
    return app.st.uploads.items.len == 1 and qa.find("upload-spoiler:0") != null and qa.find("upload-alt:0") != null;
}
fn spoilerOn(app: *App) bool {
    return app.st.uploads.items.len == 1 and app.st.uploads.items[0].spoiler;
}
fn altOpen(app: *App) bool {
    return app.st.popup == .upload_alt and qa.find("upload-alt-input") != null;
}
fn altSaved(app: *App) bool {
    return app.st.popup == .none and app.st.uploads.items.len == 1 and std.mem.eql(u8, app.st.uploads.items[0].alt, "um gato laranja");
}
fn sentSpoiler(app: *App) bool {
    return has(body(), "{\"id\":0,\"filename\":\"SPOILER_envio-anexo.png\",\"is_spoiler\":true,\"description\":\"um gato laranja\"}") and app.st.uploads.items.len == 0;
}

// --- Enquetes -----------------------------------------------------------------

fn tAnswer(app: *App, b: []u8, multi: bool, answer: u32) []const u8 {
    return mk(b, "poll-answer:{d}:{d}", .{ pollId(app, multi) orelse return "", answer });
}
fn tA1(app: *App, b: []u8) []const u8 {
    return tAnswer(app, b, false, 1);
}
fn tA2(app: *App, b: []u8) []const u8 {
    return tAnswer(app, b, false, 2);
}
fn tB1(app: *App, b: []u8) []const u8 {
    return tAnswer(app, b, true, 1);
}
fn tB3(app: *App, b: []u8) []const u8 {
    return tAnswer(app, b, true, 3);
}
fn tVoteA(app: *App, b: []u8) []const u8 {
    return mk(b, "poll-vote:{d}", .{pollId(app, false) orelse return ""});
}
fn tVoteB(app: *App, b: []u8) []const u8 {
    return mk(b, "poll-vote:{d}", .{pollId(app, true) orelse return ""});
}
fn tBackA(app: *App, b: []u8) []const u8 {
    return mk(b, "poll-back:{d}", .{pollId(app, false) orelse return ""});
}
fn tResultsA(app: *App, b: []u8) []const u8 {
    return mk(b, "poll-results:{d}", .{pollId(app, false) orelse return ""});
}

fn pollCardShown(app: *App) bool {
    var b: [48]u8 = undefined;
    return R.hasInk(app, mk(&b, "poll:{d}", .{pollId(app, false) orelse return false})) and qa.find(tVoteA(app, &b)) != null;
}
fn resultsShown(app: *App) bool {
    var b: [48]u8 = undefined;
    // Sem votar: os resultados e o "Voltar a votar" no lugar do "Votar".
    return qa.find(tBackA(app, &b)) != null and qa.find(tVoteA(app, &b)) == null and !poll(app, false).?.voted();
}
fn votingAgain(app: *App) bool {
    var b: [48]u8 = undefined;
    return qa.find(tVoteA(app, &b)) != null;
}
fn votedA(app: *App) bool {
    const p = poll(app, false) orelse return false;
    return p.answers[1].me and p.answers[1].count == 4 and !p.answers[0].me and
        std.mem.eql(u8, gw.sent.view(&gw.sent.vote_body, &gw.sent.vote_len), "{\"answer_ids\":[2]}");
}
fn votersPage(app: *App) bool {
    const pl = &app.store.people;
    var b: [96]u8 = undefined;
    const want = mk(&b, "/channels/{d}/polls/{d}/answers/1?limit=25", .{ gw.poll_channel, pollId(app, false) orelse return false });
    return app.st.popup == .poll_voters and pl.state == .loaded and pl.users.items.len == 25 and pl.more and
        std.mem.eql(u8, gw.sent.view(&gw.sent.people_path, &gw.sent.people_path_len), want) and R.hasInk(app, "voters");
}
fn votersAll(app: *App) bool {
    const pl = &app.store.people;
    return pl.state == .loaded and pl.users.items.len == 30 and !pl.more and has(gw.sent.view(&gw.sent.people_path, &gw.sent.people_path_len), "&after=");
}
fn unvotedA(app: *App) bool {
    const p = poll(app, false) orelse return false;
    return !p.voted() and p.answers[1].count == 3 and std.mem.eql(u8, gw.sent.view(&gw.sent.vote_body, &gw.sent.vote_len), "{\"answer_ids\":[]}");
}
fn votedB(app: *App) bool {
    const p = poll(app, true) orelse return false;
    return p.answers[0].me and !p.answers[1].me and p.answers[2].me and p.answers[0].count == 5 and p.answers[2].count == 3 and
        std.mem.eql(u8, gw.sent.view(&gw.sent.vote_body, &gw.sent.vote_len), "{\"answer_ids\":[1,3]}");
}
fn endPollA(app: *App) void {
    const id = pollId(app, false) orelse return;
    const p = app.store.polls.get(id) orelse return;
    p.expiry = @divTrunc(gw.nowMs(), 1000) - 60;
    if (app.store.channel(gw.poll_channel)) |cs| if (app.store.find(cs, id)) |m| {
        m.layout_w = -1;
    };
}
fn endedShown(app: *App) bool {
    var b: [48]u8 = undefined;
    const id = pollId(app, false) orelse return false;
    return R.hasInk(app, mk(&b, "poll:{d}", .{id})) and qa.find(tVoteA(app, &b)) == null and qa.find(tBackA(app, &b)) == null;
}

// --- Reações ------------------------------------------------------------------

var fetches_before: u64 = 0;
fn noteFetches(_: *App) void {
    fetches_before = gw.sent.people_fetches.load(.monotonic);
}
fn tPartyChip(app: *App, b: []u8) []const u8 {
    const m = partyMsg(app) orelse return "";
    for (m.reactionSlice(), 0..) |r, i| if (std.mem.eql(u8, r.text(), "🎉")) return mk(b, "chip:{d}:{d}", .{ m.msg.id, i });
    return "";
}
fn tPartyMsg(app: *App, b: []u8) []const u8 {
    const m = partyMsg(app) orelse return "";
    return mk(b, "msg:{d}", .{m.msg.id});
}
fn chipHoverNoFetch(_: *App) bool {
    return gw.sent.people_fetches.load(.monotonic) == fetches_before;
}
fn reactorsPage(app: *App) bool {
    const pl = &app.store.people;
    const path = gw.sent.view(&gw.sent.people_path, &gw.sent.people_path_len);
    return app.st.popup == .reactions and pl.state == .loaded and pl.users.items.len == 25 and pl.more and
        has(path, "/reactions/%F0%9F%8E%89?limit=25&type=0") and gw.sent.people_fetches.load(.monotonic) == fetches_before + 1 and R.hasInk(app, "reactors");
}
fn reactorsAll(app: *App) bool {
    const pl = &app.store.people;
    return pl.state == .loaded and pl.users.items.len == 30 and !pl.more;
}
fn burstList(app: *App) bool {
    const pl = &app.store.people;
    return pl.state == .loaded and pl.users.items.len == 2 and has(gw.sent.view(&gw.sent.people_path, &gw.sent.people_path_len), "type=1");
}
fn reactionsPopup(app: *App) bool {
    return app.st.popup == .reactions and app.store.people.state == .loaded;
}

// --- Fixadas ------------------------------------------------------------------

fn pinsFirstPage(app: *App) bool {
    const l = app.store.pins.getPtr(gw.poll_channel) orelse return false;
    var b: [96]u8 = undefined;
    const want = mk(&b, "/channels/{d}/messages/pins?limit=50", .{gw.poll_channel});
    return app.st.popup == .pins and l.state == .loaded and l.items.items.len == 50 and l.more and qa.find("pins-more") != null and
        std.mem.eql(u8, gw.sent.view(&gw.sent.pins_path, &gw.sent.pins_path_len), want);
}
fn morePins(app: *App) void {
    app.handle(.{ .more_pins = gw.poll_channel });
}
fn pinsAll(app: *App) bool {
    const l = app.store.pins.getPtr(gw.poll_channel) orelse return false;
    return l.state == .loaded and l.items.items.len == 60 and !l.more and qa.find("pins-more") == null and
        has(gw.sent.view(&gw.sent.pins_path, &gw.sent.pins_path_len), "/messages/pins?limit=50&before=50") and gw.sent.pin_pages.load(.monotonic) == 1;
}

pub const ops = [_]Op{
    s("envio: canal das enquetes"),
    run(toPolls),
    .{ .wait = 500 },
    expect("abre o canal com as duas enquetes e a mensagem de reações", pollsLoaded),
    expect("nada de quem reagiu ou votou é buscado só por abrir", nothingFetched),

    s("envio: opções da caixa"),
    click("compose-options"),
    expect("o botão ao lado do GIF abre o menu de opções", menuOpen),
    .{ .shot = "envio-opcoes" },
    click("compose-opt:silent"),
    click("compose-opt:embeds"),
    expect("silenciosa e sem prévias ligam", twoOn),
    key(c.ImGuiKey_Escape),
    expect("Esc fecha o menu", closed),
    .{ .wait = 100 },
    .{ .shot = "envio-opcoes-ligadas" },
    click("composer"),
    .{ .text = "silenciosa e sem prévia https://ziglang.org" },
    key(c.ImGuiKey_Enter),
    expect("vai com SUPPRESS_NOTIFICATIONS | SUPPRESS_EMBEDS e as opções voltam ao normal", silentNoEmbeds),
    click("composer"),
    .{ .text = "@silent psiu" },
    key(c.ImGuiKey_Enter),
    expect("\"@silent \" no começo sai do texto e deixa a mensagem silenciosa", atSilent),
    click("compose-options"),
    click("compose-opt:pings"),
    expect("\"não mencionar ninguém\" liga", pingsOn),
    key(c.ImGuiKey_Escape),
    click("composer"),
    .{ .text = "ninguém é avisado" },
    key(c.ImGuiKey_Enter),
    expect("vai com allowed_mentions de parse vazio", noPings),

    s("envio: mencionar quem escreveu"),
    run(replyOther),
    .{ .wait = 150 },
    expect("respondendo, a barra mostra o @ LIGADO", toggleShown),
    .{ .shot = "envio-resposta" },
    click("composer"),
    .{ .text = "com menção" },
    key(c.ImGuiKey_Enter),
    expect("resposta com replied_user verdadeiro e as menções normais", repliedWithPing),
    run(replyOther),
    .{ .wait = 150 },
    click("reply-ping"),
    expect("clicar desliga", pingOff),
    click("composer"),
    .{ .text = "sem menção" },
    key(c.ImGuiKey_Enter),
    expect("resposta com replied_user falso", repliedNoPing),
    run(replyOther),
    .{ .wait = 150 },
    expect("a escolha fica para a próxima resposta", remembered),
    .{ .shot = "envio-resposta-desligada" },
    click("reply-ping"),
    expect("e liga de novo", pingBack),
    click("compose-cancel"),
    expect("cancelar a resposta", notReplying),

    s("envio: spoiler e texto alternativo"),
    run(attachImage),
    expect("o arquivo entra na bandeja com ALT e spoiler", oneUpload),
    click("upload-spoiler:0"),
    expect("o olho marca como spoiler", spoilerOn),
    click("upload-alt:0"),
    expect("ALT abre o texto alternativo", altOpen),
    .{ .text = "um gato laranja" },
    .{ .shot = "envio-alt" },
    click("upload-alt-save"),
    expect("salvar guarda o texto no arquivo", altSaved),
    .{ .wait = 100 },
    .{ .shot = "envio-bandeja-spoiler" },
    click("composer"),
    key(c.ImGuiKey_Enter),
    expect("vai com SPOILER_ no nome, is_spoiler e description", sentSpoiler),

    s("envio: enquetes"),
    run(jumpPoll),
    .{ .wait = 700 },
    expect("o cartão de votar aparece no lugar do parado", pollCardShown),
    .{ .shot = "enquete" },
    dyn(tResultsA),
    expect("ver resultados sem votar", resultsShown),
    dyn(tBackA),
    expect("e voltar a votar", votingAgain),
    dyn(tA2),
    dyn(tVoteA),
    expect("votar manda answer_ids e o voto volta pelo gateway", votedA),
    .{ .wait = 100 },
    .{ .shot = "enquete-votou" },
    dyn(tA1),
    expect("clicar numa opção busca quem votou (uma página)", votersPage),
    .{ .shot = "enquete-votantes" },
    .{ .hover = .{ .mark = "voters" } },
    run(wheelDown),
    .{ .wait = 300 },
    click("people-more"),
    expect("mostrar mais traz a página seguinte, depois da última", votersAll),
    key(c.ImGuiKey_Escape),
    dyn(tBackA),
    expect("tirar o voto manda a lista vazia", unvotedA),
    run(jumpMulti),
    .{ .wait = 700 },
    dyn(tB1),
    dyn(tB3),
    dyn(tVoteB),
    expect("na de várias escolhas vão as duas", votedB),
    .{ .shot = "enquete-varias" },
    run(endPollA),
    run(jumpPoll),
    .{ .wait = 700 },
    expect("encerrada: só os resultados, sem votar", endedShown),
    .{ .shot = "enquete-encerrada" },

    s("envio: quem reagiu"),
    run(jumpParty),
    .{ .wait = 700 },
    run(noteFetches),
    .{ .hover = .{ .dyn = tPartyChip } },
    .{ .wait = 300 },
    expect("passar o mouse na reação não busca nada", chipHoverNoFetch),
    .{ .rclick = .{ .dyn = tPartyChip } },
    expect("botão direito na reação busca uma página de quem reagiu", reactorsPage),
    .{ .shot = "reacoes" },
    .{ .hover = .{ .mark = "reactors" } },
    run(wheelDown),
    .{ .wait = 300 },
    click("people-more"),
    expect("mostrar mais traz o resto", reactorsAll),
    click("reactors-kind:1"),
    expect("as super reações são outra lista (type=1)", burstList),
    .{ .shot = "reacoes-super" },
    key(c.ImGuiKey_Escape),
    expect("Esc fecha", closed),
    .{ .rclick = .{ .dyn = tPartyMsg } },
    click("menu:Ver reações"),
    expect("\"Ver reações\" no menu da mensagem abre a mesma lista", reactionsPopup),
    key(c.ImGuiKey_Escape),

    s("envio: fixadas em páginas"),
    click("header-pins"),
    expect("as fixadas vêm pelo caminho novo, 50 por página", pinsFirstPage),
    .{ .shot = "fixadas-paginas" },
    run(morePins),
    expect("carregar mais traz as de antes da última", pinsAll),
    key(c.ImGuiKey_Escape),
};
