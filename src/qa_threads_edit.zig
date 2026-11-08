//! QA de editar threads e das threads privadas (roda depois de qa_threads.zig,
//! na bateria geral e em QA_SUITE=threads). No "Faculdade 2026" da
//! demonstração temos todas as permissões; no "Lo-fi & café", só o @everyone
//! (sem gerenciar threads nem responder nelas). O corpo do PATCH que iria para
//! o Discord fica em `fake_gateway.sent_threads`.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const forum = @import("ui/forum.zig");
const te = @import("core/thread_edit.zig");
const platform = @import("platform/window.zig");
const Id = types.Id;

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn clickD(f: *const fn (*App, []u8) []const u8) Op {
    return .{ .click = .{ .dyn = f } };
}
fn rclickD(f: *const fn (*App, []u8) []const u8) Op {
    return .{ .rclick = .{ .dyn = f } };
}
fn rclick(k: []const u8) Op {
    return .{ .rclick = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn expectT(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 3000 } };
}
fn key(k: c_int) Op {
    return .{ .key = .{ .key = k } };
}
fn mk(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch "";
}

const zig: Id = 505010;
const geral1: Id = 507005;
const forum0: Id = 505031;
const media0: Id = 505032;

var bench: Id = 0; // a solta do #zig (não é nossa; aqui gerenciamos threads)
var geral_t: Id = 0; // a do #geral do segundo servidor (sem permissão)
var post: Id = 0; // o primeiro post do fórum
var mine: Id = 0; // nossa, no segundo servidor (só o dono edita)
var edits0: u64 = 0;
var fetches0: u64 = 0;

fn byCount(app: *App, parent: Id, count: u32) Id {
    for (app.store.threadsOf(parent)) |id| {
        const cs = app.store.channel(id) orelse continue;
        if ((cs.info.thread orelse continue).message_count == count) return id;
    }
    return 0;
}
/// A dos benchmarks (o nome tem "bench" nas duas línguas; a contagem já mudou
/// em qa_threads.zig).
fn byName(app: *App, parent: Id, part: []const u8) Id {
    for (app.store.threadsOf(parent)) |id| {
        const cs = app.store.channel(id) orelse continue;
        if (cs.info.thread != null and std.mem.indexOf(u8, cs.info.name, part) != null) return id;
    }
    return 0;
}
fn remember(app: *App) void {
    bench = byName(app, zig, "bench");
    geral_t = byCount(app, geral1, 5);
    edits0 = gw.sent_threads.edits.load(.acquire);
    fetches0 = gw.sent_threads.private_fetches.load(.acquire);
}
fn info(app: *App, id: Id) ?types.ThreadInfo {
    const cs = app.store.channel(id) orelse return null;
    return cs.info.thread;
}
fn active(app: *App, id: Id) bool {
    return id != 0 and app.st.activeChannel() == id and !app.st.friends;
}
fn has(m: []const u8) bool {
    return qa.find(m) != null;
}
/// O último PATCH foi este (e chegou mais um).
fn lastBody(want: []const u8) bool {
    const n = gw.sent_threads.edits.load(.acquire);
    if (n <= edits0) return false;
    const len = gw.sent_threads.edit_len.load(.acquire);
    if (!std.mem.eql(u8, gw.sent_threads.edit_body[0..len], want)) return false;
    edits0 = n;
    return true;
}

fn tBench(_: *App, b: []u8) []const u8 {
    return mk(b, "channel:{d}", .{bench});
}
fn tGeral(_: *App, b: []u8) []const u8 {
    return mk(b, "channel:{d}", .{geral_t});
}
fn tMine(_: *App, b: []u8) []const u8 {
    return mk(b, "channel:{d}", .{mine});
}
fn tPost(_: *App, b: []u8) []const u8 {
    return mk(b, "post:{d}", .{post});
}

// --- Com permissão ----------------------------------------------------------------

/// Depois de qa_threads.zig, os posts do fórum e do canal de mídia aparecem abaixo deles na
/// lista e empurram o #zig para fora da tela: recolhidos, o #zig e as threads dele voltam à vista.
fn forumsCollapsed(app: *App) bool {
    var b: [40]u8 = undefined;
    return app.st.collapsed.contains(forum0) and app.st.collapsed.contains(media0) and has("channel:505010") and
        bench != 0 and qa.find(mk(&b, "channel:{d}", .{bench})) != null;
}
fn forumsExpanded(app: *App) bool {
    return !app.st.collapsed.contains(forum0) and !app.st.collapsed.contains(media0);
}

fn benchOpen(app: *App) bool {
    return active(app, bench) and has("header-thread");
}
fn fullMenu(app: *App) bool {
    return app.st.popup == .menu and has("menu:Editar thread…") and has("menu:Arquivar thread") and has("menu:Trancar thread");
}
fn editOpen(app: *App) bool {
    return app.st.popup == .edit_thread and has("thread-edit-name") and has("thread-edit-dur:4320") and has("thread-edit-save");
}
fn renamed(app: *App) bool {
    const cs = app.store.channel(bench) orelse return false;
    const t = cs.info.thread orelse return false;
    return app.st.popup == .none and std.mem.eql(u8, cs.info.name, "benchmarks novos") and t.auto_archive == 4320 and
        lastBody("{\"name\":\"benchmarks novos\",\"auto_archive_duration\":4320}");
}
fn locked(app: *App) bool {
    return (info(app, bench) orelse return false).locked and lastBody("{\"locked\":true}");
}
fn unlockOffered(app: *App) bool {
    return app.st.popup == .menu and has("menu:Destrancar thread");
}
fn unlocked(app: *App) bool {
    return !(info(app, bench) orelse return false).locked and lastBody("{\"locked\":false}");
}
fn archived(app: *App) bool {
    const t = info(app, bench) orelse return false;
    // Aberta, a linha continua à vista mesmo arquivada.
    var b: [40]u8 = undefined;
    return t.archived and lastBody("{\"archived\":true}") and qa.find(mk(&b, "channel:{d}", .{bench})) != null and has("header-thread");
}
fn unarchiveOffered(app: *App) bool {
    // Arquivada: nada de trancar; editar e desarquivar sim.
    return app.st.popup == .menu and has("menu:Desarquivar thread") and has("menu:Editar thread…") and !has("menu:Trancar thread") and !has("menu:Arquivar thread");
}
fn unarchived(app: *App) bool {
    return !(info(app, bench) orelse return false).archived and lastBody("{\"archived\":false}");
}
fn headerMenu(app: *App) bool {
    return app.st.popup == .menu and app.st.popup.menu.id == bench and has("menu:Editar thread…");
}
fn nothingSent(_: *App) bool {
    return gw.sent_threads.edits.load(.acquire) == edits0;
}
fn popupClosed(app: *App) bool {
    return app.st.popup == .none;
}

// --- Fórum: tags ------------------------------------------------------------------------

fn forumOpen(app: *App) bool {
    const cs = app.store.channel(forum0) orelse return false;
    if (!active(app, forum0) or cs.active_page.state != .loaded) return false;
    const ids = forum.visible(false);
    if (ids.len == 0) return false;
    post = ids[0];
    return true;
}
/// O que as tags do post devem virar ao marcar a terceira tag do fórum.
var want_tags: te.Tags = .{};
fn tagsShown(app: *App) bool {
    const t = info(app, post) orelse return false;
    want_tags = te.Tags.from(t.tags);
    _ = want_tags.toggle(forum0 * 10 + 2);
    return editOpen(app) and has("thread-edit-tag:0") and has("thread-edit-tag:3");
}
fn tagsSaved(app: *App) bool {
    const t = info(app, post) orelse return false;
    if (!want_tags.same(t.tags)) return false;
    var want: [160]u8 = undefined;
    var n: usize = 0;
    const head = "{\"applied_tags\":[";
    @memcpy(want[0..head.len], head);
    n = head.len;
    for (want_tags.slice(), 0..) |id, i| n += (std.fmt.bufPrint(want[n..], "{s}\"{d}\"", .{ if (i > 0) "," else "", id }) catch return false).len;
    @memcpy(want[n..][0..2], "]}");
    return lastBody(want[0 .. n + 2]);
}

// --- Privadas -------------------------------------------------------------------------------

fn privateTab(app: *App) bool {
    if (app.st.popup != .threads) return false;
    const p = app.st.popup.threads;
    const cs = app.store.channel(zig) orelse return false;
    // Quem gerencia threads: o caminho de todas, com a que não é nossa.
    return p.parent == zig and p.private and cs.private_page.state == .loaded and forum.visible(true).len == 3 and
        gw.sent_threads.private_fetches.load(.acquire) == fetches0 + 1 and gw.sent_threads.private_manage.load(.acquire) == 1;
}
fn privateRows(app: *App) bool {
    for (forum.visible(true)) |id| {
        const t = info(app, id) orelse return false;
        if (!t.private or !t.archived) return false;
        var b: [40]u8 = undefined;
        if (qa.find(mk(&b, "post:{d}", .{id})) == null) return false;
    }
    return true;
}
fn archivedHidesPrivate(app: *App) bool {
    if (app.st.popup != .threads or app.st.popup.threads.private) return false;
    for (forum.visible(true)) |id| if ((info(app, id) orelse return false).private) return false;
    return forum.visible(true).len > 0;
}
fn noRefetch(app: *App) bool {
    // Voltar à aba não pede de novo: já veio.
    return privateTab(app);
}
var priv_live: Id = 0;
fn pushPrivate(app: *App) void {
    const ca = std.heap.c_allocator;
    priv_live = types.makeSnowflake(gw.nowMs(), 0x3d2001);
    // THREAD_CREATE de uma privada em que nos colocaram.
    app.events.push(.{ .channel_upsert = .{ .id = priv_live, .guild = 505000, .parent = zig, .name = ca.dupe(u8, "privada ao vivo") catch "", .topic = ca.dupe(u8, "") catch "", .thread = .{ .private = true, .joined = true, .joined_known = true, .last_message = priv_live } } });
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn privateListed(app: *App) bool {
    const idx = app.store.threadIndex(zig) orelse return false;
    var b: [40]u8 = undefined;
    return std.mem.indexOfScalar(Id, idx.shown[0..idx.n_shown], priv_live) != null and qa.find(mk(&b, "channel:{d}", .{priv_live})) != null;
}
fn dropPrivate(app: *App) void {
    app.events.push(.{ .channel_delete = priv_live });
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn privateGone(app: *App) bool {
    return app.store.channel(priv_live) == null;
}

// --- Sem permissão -----------------------------------------------------------------------

fn geralOpen(app: *App) bool {
    return active(app, geral1);
}
fn bareMenu(app: *App) bool {
    return app.st.popup == .menu and has("menu:Entrar na thread") and !has("menu:Editar thread…") and !has("menu:Arquivar thread") and !has("menu:Desarquivar thread") and !has("menu:Trancar thread");
}
fn geralThreadOpen(app: *App) bool {
    return active(app, geral_t) and has("header-thread");
}
fn pushMine(app: *App) void {
    const ca = std.heap.c_allocator;
    mine = types.makeSnowflake(gw.nowMs(), 0x3d3001);
    app.events.push(.{ .channel_upsert = .{ .id = mine, .guild = 507000, .parent = geral1, .name = ca.dupe(u8, "minha thread") catch "", .topic = ca.dupe(u8, "") catch "", .thread = .{ .owner = app.store.me, .joined = true, .joined_known = true, .last_message = mine } } });
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn mineListed(_: *App) bool {
    var b: [40]u8 = undefined;
    return mine != 0 and qa.find(mk(&b, "channel:{d}", .{mine})) != null;
}
fn ownerMenu(app: *App) bool {
    // Dona: edita e arquiva; trancar pede gerenciar threads.
    return app.st.popup == .menu and has("menu:Editar thread…") and has("menu:Arquivar thread") and !has("menu:Trancar thread");
}
fn ownerDialog(app: *App) bool {
    // Fora de fórum, sem tags.
    return editOpen(app) and !has("thread-edit-tag:0");
}
fn dropMine(app: *App) void {
    app.events.push(.{ .channel_delete = mine });
    platform.Window.wake(app.win.wake_type, .gateway);
}
fn mineGone(app: *App) bool {
    return app.store.channel(mine) == null;
}
fn joinedPath(app: *App) bool {
    if (app.st.popup != .threads or !app.st.popup.threads.private) return false;
    const cs = app.store.channel(geral1) orelse return false;
    // Sem gerenciar threads: o caminho das nossas (e aqui não há nenhuma).
    return cs.private_page.state == .loaded and gw.sent_threads.private_manage.load(.acquire) == 0 and
        gw.sent_threads.private_fetches.load(.acquire) == fetches0 + 2 and has("forum-empty");
}

pub const ops = [_]Op{
    s("threads: editar"),
    click("guild:505000"),
    .{ .run = remember },
    click("thread-toggle:505031"),
    click("thread-toggle:505032"),
    expect("recolher os posts do fórum e da mídia traz o #zig de volta à lista", forumsCollapsed),
    click("channel:505010"),
    clickD(tBench),
    expectT("a thread abre e o título vira botão", benchOpen),
    rclickD(tBench),
    expect("com gerenciar threads: editar, arquivar e trancar", fullMenu),
    click("menu:Editar thread…"),
    expect("\"Editar thread\" abre com nome e auto-arquivar", editOpen),
    .{ .wait = 200 },
    .{ .shot = "76-editar-thread" },
    click("thread-edit-save"),
    expect("sem mudança, salvar não manda nada", nothingSent),
    click("thread-edit-name"),
    .{ .key = .{ .key = c.ImGuiKey_A, .ctrl = true } },
    .{ .text = "benchmarks novos" },
    click("thread-edit-dur:4320"),
    click("thread-edit-save"),
    expectT("renomear e auto-arquivar: um PATCH só com o que mudou", renamed),
    rclickD(tBench),
    click("menu:Trancar thread"),
    expectT("trancar manda locked e a thread fica trancada", locked),
    rclickD(tBench),
    expect("trancada: o menu oferece destrancar", unlockOffered),
    click("menu:Destrancar thread"),
    expectT("destrancar", unlocked),
    rclickD(tBench),
    click("menu:Arquivar thread"),
    expectT("arquivar manda archived e a aberta continua à vista", archived),
    rclickD(tBench),
    expect("arquivada: desarquivar e editar, sem trancar", unarchiveOffered),
    click("menu:Desarquivar thread"),
    expectT("desarquivar", unarchived),
    click("header-thread"),
    expect("o título no cabeçalho abre o menu da thread", headerMenu),
    key(c.ImGuiKey_Escape),
    expect("Esc fecha", popupClosed),

    s("threads: tags de um post"),
    click("channel:505031"),
    expectT("o fórum abre", forumOpen),
    rclickD(tPost),
    click("menu:Editar thread…"),
    expect("no fórum, o popup mostra as tags", tagsShown),
    click("thread-edit-tag:2"),
    .{ .wait = 100 },
    .{ .shot = "77-editar-tags" },
    click("thread-edit-save"),
    expectT("mudar as tags manda applied_tags inteiro", tagsSaved),

    s("threads: privadas"),
    click("channel:505010"),
    rclick("channel:505010"),
    click("menu:Threads arquivadas"),
    click("forum-tab:private"),
    expectT("aba das privadas: só ao abrir, pelo caminho de quem gerencia", privateTab),
    expect("as linhas são privadas e arquivadas", privateRows),
    .{ .wait = 150 },
    .{ .shot = "78-threads-privadas" },
    click("forum-tab:archived"),
    expect("a aba das arquivadas não mistura as privadas", archivedHidesPrivate),
    click("forum-tab:private"),
    expect("voltar à aba não pede de novo", noRefetch),
    key(c.ImGuiKey_Escape),
    .{ .run = pushPrivate },
    expectT("privada em que nos colocaram aparece na lista do canal", privateListed),
    .{ .run = dropPrivate },
    expectT("e some quando sai", privateGone),
    click("thread-toggle:505031"),
    click("thread-toggle:505032"),
    expect("os posts do fórum e da mídia voltam à lista", forumsExpanded),

    s("threads: sem permissão, as ações nem aparecem"),
    click("guild:507000"),
    click("channel:507005"),
    expectT("#geral do segundo servidor", geralOpen),
    rclickD(tGeral),
    expect("sem gerenciar threads e sem ser dono: nada de editar, arquivar ou trancar", bareMenu),
    key(c.ImGuiKey_Escape),
    clickD(tGeral),
    expectT("a thread abre", geralThreadOpen),
    click("header-thread"),
    expect("o menu do cabeçalho também não oferece", bareMenu),
    key(c.ImGuiKey_Escape),
    .{ .run = pushMine },
    expectT("thread nossa no mesmo canal", mineListed),
    rclickD(tMine),
    expect("dona: editar e arquivar, mas não trancar", ownerMenu),
    click("menu:Editar thread…"),
    expect("o popup abre, sem tags fora de fórum", ownerDialog),
    click("thread-edit-cancel"),
    expect("cancelar fecha sem mandar nada", nothingSent),
    .{ .run = dropMine },
    expectT("a nossa some", mineGone),
    rclick("channel:507005"),
    click("menu:Threads arquivadas"),
    click("forum-tab:private"),
    expectT("sem gerenciar threads: as privadas vêm pelo caminho das nossas", joinedPath),
    key(c.ImGuiKey_Escape),
    click("guild:500000"),
    click("channel:500005"),
};
