//! Busca de mensagens (Ctrl+F ou a caixa do cabeçalho), num painel ao lado da conversa
//! (o desenho fica em search_view.zig).
//!
//! A cada tecla, procura nas mensagens que estão na memória e no cache em disco
//! (net/msg_cache.zig), sem falar com o Discord, então funciona offline. O texto já vai
//! dobrado (minúsculas, sem acento) uma vez por abertura (memória) ou por versão do arquivo
//! (disco, lido aos poucos, ~2 ms por quadro). O Enter pergunta ao Discord, que tem o
//! histórico inteiro; só o Enter, a troca de página e a de ordem saem para a rede.
//! Filtros: ver core/search_query.zig.
//! Clicar num resultado abre a conversa e pula até a mensagem, com o painel aberto.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const icons = @import("icons.zig");
const i18n = @import("i18n.zig");
const w = @import("widgets.zig");
const types = @import("../core/types.zig");
const sq = @import("../core/search_query.zig");
const msg_cache = @import("../net/msg_cache.zig");
const store_mod = @import("../core/store.zig");
const ev = @import("../core/event.zig");
const view = @import("search_view.zig");
const sugg = @import("search_sugg.zig");
const Id = types.Id;

const alloc = std.heap.c_allocator;

pub var open = false;
var appearing = false;
var focus = false;
var query: [256]u8 = @splat(0);
pub var selected: usize = 0;
/// A caixa de texto está ativa (e estava no quadro anterior: o Esc a solta no próprio quadro).
pub var input_active = false;
var was_active = false;
/// As setas escolheram um resultado: o Enter abre ele em vez de buscar.
var arrow_moved = false;
pub var scroll_to_selected = false;
var text_sync = false;
var cursor_end = false;
var tab_pressed = false;
/// Onde o painel fica neste quadro (ver `reserve`).
pub var panel: d.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

/// De onde vem a lista: deste computador ou da busca do Discord.
pub const Source = enum { local, server };
pub const ServerState = enum { idle, loading, done, indexing, forbidden, failed };
pub var source: Source = .local;
pub var server: ServerState = .idle;
/// Quantas o Discord achou, e a página que está na tela.
pub var total: u32 = 0;
pub var offset: u32 = 0;
pub var sort: sq.Sort = .newest;
/// Quantas mensagens o Discord já indexou, enquanto prepara a busca.
pub var indexed: u32 = 0;
/// A consulta da lista que está na tela (os termos marcados no texto).
pub var view_query: sq.Query = .{};
var req_id: u32 = 0;
var retry_at_ms: i64 = 0;
var retries: u8 = 0;
var delivered: ?ev.SearchResults = null;
var problem_buf: [240]u8 = undefined;
var problem_len: usize = 0;
/// As últimas buscas no Discord, só enquanto o app está aberto.
var recent_buf: [5][256]u8 = undefined;
var recent_len: [5]u16 = @splat(0);
var recent_n: usize = 0;
/// Muda a cada abertura: o campo do ImGui esquece o texto da vez anterior.
var gen: c_int = 0;

/// Mensagem que só está no disco (canal fora da memória).
/// `hay` e `who` já vêm "dobrados" (minúsculas, sem acento): cada tecla vira
/// só um `indexOf`, rápido mesmo com muitos MB de cache.
const Doc = struct { channel: Id, id: Id, author: Id, author_name: []const u8, content: []const u8, files: []const u8, hay: []const u8, who: []const u8, image: bool, file: bool };
/// Um arquivo do cache já lido. Fica de uma abertura para a outra e só é
/// lido de novo quando o arquivo muda (data ou tamanho).
const DiskFile = struct {
    stamp: msg_cache.Stamp,
    arena: std.heap.ArenaAllocator,
    docs: []const Doc = &.{},
    bytes: usize = 0,
};
var disk_files: std.AutoHashMapUnmanaged(Id, *DiskFile) = .empty;
var disk_used: usize = 0;
/// Conta do índice (outra conta, outra pasta: começa do zero).
var disk_acct: [24]u8 = undefined;
var disk_acct_len: usize = 0;
/// Canais por conferir nesta abertura, um pouco por quadro.
var todo: std.ArrayList(Id) = .empty;
var todo_i: usize = 0;
pub var scanning = false;
var built = false;
/// Arquivos lidos do disco desde o início (o QA confere que reabrir não relê).
pub var disk_reads: u32 = 0;
/// Teto do que a busca guarda do disco.
const disk_budget: usize = 16 * 1024 * 1024;
/// Tempo de leitura do disco por quadro (a busca segue respondendo).
const step_ns: u64 = 2 * std.time.ns_per_ms;

/// Mensagem da memória já dobrada; `idx` vale enquanto a versão da conversa
/// não mudar.
const MemDoc = struct { idx: u32, hay: []const u8, who: []const u8, image: bool, file: bool };
const MemFold = struct { version: u32, len: usize, arena: std.heap.ArenaAllocator, docs: std.ArrayList(MemDoc) = .empty };
var mem_folds: std.AutoHashMapUnmanaged(Id, *MemFold) = .empty;

pub const Result = struct {
    channel: Id,
    id: Id,
    ts: i64,
    author_id: Id = 0,
    author: []const u8,
    where: []const u8,
    snippet: []const u8,
    disk: bool = false,
    /// Linhas do trecho nessa largura (ver search_view.zig).
    lines: u8 = 1,
    wrap_w: f32 = 0,
};
var res_arena: std.heap.ArenaAllocator = .init(alloc);
pub var results: std.ArrayList(Result) = .empty;
/// Quantas casaram (antes do corte em `max_results`) e quantas vieram só do disco.
pub var found: usize = 0;
pub var found_disk: usize = 0;
const max_results = 200;

/// Ctrl+F: abre; com o painel aberto, volta para a caixa de texto; com ela ativa, fecha.
pub fn toggle() void {
    if (!open) return start();
    if (input_active) close() else refocus();
}

/// A caixa do cabeçalho: abre, ou volta para a caixa de texto.
pub fn focusOrStart() void {
    if (open) refocus() else start();
}

fn refocus() void {
    appearing = true;
    focus = false;
}

pub fn start() void {
    open = true;
    gen +%= 1;
    appearing = true;
    focus = false;
    @memset(&query, 0);
    selected = 0;
    built = false;
    scanning = false;
    source = .local;
    server = .idle;
    total = 0;
    offset = 0;
    problem_len = 0;
    input_active = false;
    was_active = false;
    arrow_moved = false;
    view_query = .{};
    view.scroll_y = 0;
    sugg.count = 0;
    sugg.selected = null;
    req_id +%= 1;
}

/// Fecha. O que veio do disco fica para a próxima vez; o resto sai.
pub fn close() void {
    open = false;
    scanning = false;
    input_active = false;
    if (delivered) |r| freeHits(r.hits);
    delivered = null;
    results.clearAndFree(alloc);
    _ = res_arena.reset(.free_all);
    var it = mem_folds.valueIterator();
    while (it.next()) |f| freeMemFold(f.*);
    mem_folds.clearAndFree(alloc);
    todo.clearAndFree(alloc);
    found = 0;
    found_disk = 0;
}

// --- Índice do disco --------------------------------------------------------------

fn dropFile(ch: Id) void {
    const kv = disk_files.fetchRemove(ch) orelse return;
    disk_used -|= kv.value.bytes;
    kv.value.arena.deinit();
    alloc.destroy(kv.value);
}

fn forgetDisk() void {
    var it = disk_files.valueIterator();
    while (it.next()) |f| {
        f.*.arena.deinit();
        alloc.destroy(f.*);
    }
    disk_files.clearRetainingCapacity();
    disk_used = 0;
}

/// Abriu: confere quais arquivos existem; a leitura vai em `stepDisk`.
fn beginDisk() void {
    built = true;
    const acct = msg_cache.account();
    if (!std.mem.eql(u8, acct, disk_acct[0..disk_acct_len])) {
        forgetDisk();
        const n = @min(acct.len, disk_acct.len);
        @memcpy(disk_acct[0..n], acct[0..n]);
        disk_acct_len = n;
    }
    todo.clearRetainingCapacity();
    todo_i = 0;
    msg_cache.listChannels(&todo);
    // Arquivo que sumiu (Apagar cache, teto do cache, cache desligado): sai do índice.
    if (disk_files.count() > 0) {
        var listed: std.AutoHashMapUnmanaged(Id, void) = .empty;
        defer listed.deinit(alloc);
        for (todo.items) |ch| listed.put(alloc, ch, {}) catch {};
        var gone: std.ArrayList(Id) = .empty;
        defer gone.deinit(alloc);
        var it = disk_files.keyIterator();
        while (it.next()) |ch| if (!listed.contains(ch.*)) gone.append(alloc, ch.*) catch {};
        for (gone.items) |ch| dropFile(ch);
    }
    scanning = true;
}

/// Lê arquivos novos ou mudados por até `step_ns`. Retorna se o índice mudou.
fn stepDisk(ctx: *d.Ctx) bool {
    const t0 = c.SDL_GetTicksNS();
    var changed = false;
    while (todo_i < todo.items.len) {
        if (c.SDL_GetTicksNS() - t0 >= step_ns) return changed;
        const ch = todo.items[todo_i];
        todo_i += 1;
        const cs = ctx.store.channel(ch) orelse continue;
        const st = msg_cache.stamp(ch) orelse {
            if (disk_files.contains(ch)) changed = true;
            dropFile(ch);
            continue;
        };
        if (disk_files.get(ch)) |f| {
            if (f.stamp.mtime_ns == st.mtime_ns and f.stamp.size == st.size) continue;
            dropFile(ch);
            changed = true;
        }
        // Na memória: a busca já olha lá (e é a versão mais nova).
        if (cs.history == .loaded or disk_used > disk_budget) continue;
        if (readFile(ctx, ch, st)) changed = true;
    }
    scanning = false;
    return changed;
}

fn readFile(ctx: *d.Ctx, ch: Id, st: msg_cache.Stamp) bool {
    var tmp = std.heap.ArenaAllocator.init(alloc);
    defer tmp.deinit();
    const ta = tmp.allocator();
    const dec = msg_cache.readChannel(ta, ch) orelse return false;
    disk_reads += 1;
    const f = alloc.create(DiskFile) catch return false;
    f.* = .{ .stamp = st, .arena = .init(alloc) };
    const da = f.arena.allocator();
    // Nome de cada autor do arquivo, sem procurar na lista a cada mensagem.
    var names: std.AutoHashMapUnmanaged(Id, []const u8) = .empty;
    for (dec.users) |u| names.put(ta, u.id, u.name) catch {};
    const docs = da.alloc(Doc, dec.entries.len) catch {
        f.arena.deinit();
        alloc.destroy(f);
        return false;
    };
    var n: usize = 0;
    for (dec.entries) |*e| {
        const m = &e.msg;
        var name: []const u8 = names.get(m.author) orelse "?";
        if (ctx.store.user(m.author)) |u| name = u.name;
        var image = false;
        var file = false;
        var files: std.ArrayList(u8) = .empty;
        for (m.attachments) |a| {
            if (a.isImage()) image = true else if (!a.embed) file = true;
            files.appendSlice(da, a.filename) catch {};
            files.append(da, ' ') catch {};
        }
        var fb: [fold_max]u8 = undefined;
        var wb: [64]u8 = undefined;
        docs[n] = .{
            .channel = ch,
            .id = m.id,
            .author = m.author,
            .author_name = da.dupe(u8, name) catch continue,
            .content = da.dupe(u8, m.content) catch continue,
            .files = files.items,
            .hay = da.dupe(u8, foldHay(&fb, m.content, files.items)) catch continue,
            .who = da.dupe(u8, sq.foldInto(&wb, name)) catch continue,
            .image = image,
            .file = file,
        };
        f.bytes += docs[n].content.len * 2 + docs[n].files.len + 96;
        n += 1;
    }
    f.docs = docs[0..n];
    disk_files.put(alloc, ch, f) catch {
        f.arena.deinit();
        alloc.destroy(f);
        return false;
    };
    disk_used += f.bytes;
    return n > 0;
}

// --- Memória, dobrada uma vez por abertura ------------------------------------------

fn freeMemFold(f: *MemFold) void {
    f.arena.deinit();
    alloc.destroy(f);
}

/// As mensagens da conversa já dobradas (refaz só se a conversa mudou).
fn memFold(ctx: *d.Ctx, cs: *const store_mod.ChannelState) ?*const MemFold {
    const gop = mem_folds.getOrPut(alloc, cs.info.id) catch return null;
    if (gop.found_existing) {
        const f = gop.value_ptr.*;
        if (f.version == cs.version and f.len == cs.messages.items.len) return f;
        f.docs = .empty;
        _ = f.arena.reset(.retain_capacity);
    } else {
        const f = alloc.create(MemFold) catch {
            _ = mem_folds.remove(cs.info.id);
            return null;
        };
        f.* = .{ .version = 0, .len = 0, .arena = .init(alloc) };
        gop.value_ptr.* = f;
    }
    const f = gop.value_ptr.*;
    f.version = cs.version;
    f.len = cs.messages.items.len;
    const fa = f.arena.allocator();
    f.docs.ensureTotalCapacity(fa, cs.messages.items.len) catch {};
    var fbuf: [256]u8 = undefined;
    var hay_buf: [fold_max]u8 = undefined;
    var who_buf: [64]u8 = undefined;
    for (cs.messages.items, 0..) |*m, i| {
        if (m.pending or m.msg.id == 0) continue;
        var image = false;
        var file = false;
        var fl: usize = 0;
        for (m.msg.attachments) |a| {
            if (a.isImage()) image = true else if (!a.embed) file = true;
            const n = @min(a.filename.len, fbuf.len - fl);
            @memcpy(fbuf[fl .. fl + n], a.filename[0..n]);
            fl += n;
            if (fl < fbuf.len) {
                fbuf[fl] = ' ';
                fl += 1;
            }
        }
        const hay = fa.dupe(u8, foldHay(&hay_buf, m.msg.content, fbuf[0..fl])) catch continue;
        const who = fa.dupe(u8, sq.foldInto(&who_buf, authorName(ctx, m.msg.author))) catch continue;
        f.docs.append(fa, .{ .idx = @intCast(i), .hay = hay, .who = who, .image = image, .file = file }) catch continue;
    }
    return f;
}

// --- Busca -------------------------------------------------------------------------

const Src = union(enum) { mem: *const store_mod.StoredMessage, disk: *const Doc };
const Hit = struct { id: Id, channel: Id, src: Src };

fn authorName(ctx: *d.Ctx, id: Id) []const u8 {
    return if (ctx.store.user(id)) |u| u.name else "?";
}

const fold_max = 4096;

/// Texto e nomes dos anexos, dobrados, num pedaço só.
fn foldHay(buf: *[fold_max]u8, content: []const u8, files: []const u8) []const u8 {
    const a = sq.foldInto(buf[0 .. fold_max - 260], content);
    buf[a.len] = '\n';
    const b = sq.foldInto(buf[a.len + 1 ..], files);
    return buf[0 .. a.len + 1 + b.len];
}

/// `hay` e `who` já dobrados (os termos da consulta também vêm assim).
fn matches(q: *const sq.Query, hay: []const u8, who: []const u8, image: bool, file: bool) bool {
    if (q.from_len > 0 and std.mem.indexOf(u8, who, q.from()) == null) return false;
    if (q.has_image and !image) return false;
    if (q.has_file and !file) return false;
    if (q.has_link and !sq.hasLink(hay)) return false;
    for (0..q.n_terms) |i| {
        if (std.mem.indexOf(u8, hay, q.term(i)) == null) return false;
    }
    return true;
}

fn channelOk(cs: *const store_mod.ChannelState, q: *const sq.Query) bool {
    if (cs.info.kind != .text) return false;
    return q.in_len == 0 or sq.containsFold(cs.info.name, q.in());
}

fn clearResults() void {
    results.clearRetainingCapacity();
    _ = res_arena.reset(.retain_capacity);
    found = 0;
    found_disk = 0;
}

/// `keep`: o índice do disco cresceu; a seleção fica onde estava.
fn rebuild(ctx: *d.Ctx, keep: bool) void {
    clearResults();
    if (!keep) {
        selected = 0;
        view.scroll_y = 0;
    }
    const q = sq.Query.parse(text());
    view_query = q;
    // Menção, "fixada", vídeo...: só o Discord tem como saber.
    if (q.empty() or q.serverOnly()) return;
    var hits: std.ArrayList(Hit) = .empty;
    defer hits.deinit(alloc);
    var it = ctx.store.channels.valueIterator();
    while (it.next()) |csp| {
        const cs = csp.*;
        if (!channelOk(cs, &q)) continue;
        const f = memFold(ctx, cs) orelse continue;
        for (f.docs.items) |*doc| {
            const m = &cs.messages.items[doc.idx];
            if (!q.idOk(m.msg.id) or !matches(&q, doc.hay, doc.who, doc.image, doc.file)) continue;
            hits.append(alloc, .{ .id = m.msg.id, .channel = cs.info.id, .src = .{ .mem = m } }) catch return;
        }
    }
    var fit = disk_files.iterator();
    while (fit.next()) |e| {
        const cs = ctx.store.channel(e.key_ptr.*) orelse continue;
        // Carregou depois de lido: a memória já respondeu.
        if (cs.history == .loaded or !channelOk(cs, &q)) continue;
        for (e.value_ptr.*.docs) |*doc| {
            if (!q.idOk(doc.id) or !matches(&q, doc.hay, doc.who, doc.image, doc.file)) continue;
            hits.append(alloc, .{ .id = doc.id, .channel = doc.channel, .src = .{ .disk = doc } }) catch return;
            found_disk += 1;
        }
    }
    found = hits.items.len;
    // Mais novas primeiro (o ID do Discord cresce com o tempo).
    @import("../core/sort.zig").stable(Hit, hits.items, {}, struct {
        fn lt(_: void, a: Hit, b: Hit) bool {
            return a.id > b.id;
        }
    }.lt);
    const ra = res_arena.allocator();
    const term: []const u8 = if (q.n_terms > 0) q.term(0) else "";
    for (hits.items[0..@min(hits.items.len, max_results)]) |h| {
        const cs = ctx.store.channel(h.channel) orelse continue;
        var content: []const u8 = "";
        var author: []const u8 = "";
        var author_id: Id = 0;
        var files: []const u8 = "";
        switch (h.src) {
            .mem => |m| {
                content = m.msg.content;
                author = authorName(ctx, m.msg.author);
                author_id = m.msg.author;
                for (m.msg.attachments) |att| if (files.len == 0) {
                    files = att.filename;
                };
            },
            .disk => |doc| {
                content = doc.content;
                author = doc.author_name;
                author_id = doc.author;
                files = doc.files;
            },
        }
        var r: Result = .{
            .channel = h.channel,
            .id = h.id,
            .ts = @divTrunc(types.snowflakeTime(h.id), 1000),
            .author_id = author_id,
            .author = ra.dupe(u8, author) catch continue,
            .where = whereLabel(ctx, ra, cs) catch continue,
            .snippet = "",
            .disk = h.src == .disk,
        };
        snippet(ctx, ra, &r, content, files, term);
        results.append(alloc, r) catch return;
    }
}

fn whereLabel(ctx: *d.Ctx, a: std.mem.Allocator, cs: *const store_mod.ChannelState) ![]const u8 {
    if (cs.info.guild == 0) return if (cs.info.group) a.dupe(u8, cs.info.name) else std.fmt.allocPrint(a, "@{s}", .{cs.info.name});
    const g = ctx.store.guild(cs.info.guild);
    return std.fmt.allocPrint(a, "#{s} · {s}", .{ cs.info.name, if (g) |x| x.name else "" });
}

/// Texto legível de uma linha: menções viram @nome / #canal, quebras viram espaço.
fn clean(ctx: *d.Ctx, out: []u8, s: []const u8) []const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len and n < out.len) {
        // Emoji personalizado (<:nome:123> ou <a:nome:123>) vira :nome:.
        if (s[i] == '<' and i + 2 < s.len and (s[i + 1] == ':' or (s[i + 1] == 'a' and s[i + 2] == ':'))) if (std.mem.indexOfScalarPos(u8, s, i, '>')) |end| {
            const body = s[i + @as(usize, if (s[i + 1] == ':') 2 else 3) .. end];
            if (std.mem.indexOfScalar(u8, body, ':')) |colon| {
                const piece = std.fmt.bufPrint(out[n..], ":{s}:", .{body[0..colon]}) catch break;
                n += piece.len;
                i = end + 1;
                continue;
            }
        };
        if (s[i] == '<' and i + 2 < s.len and (s[i + 1] == '@' or s[i + 1] == '#')) if (std.mem.indexOfScalarPos(u8, s, i, '>')) |end| {
            var body = s[i + 2 .. end];
            if (body.len > 0 and (body[0] == '!' or body[0] == '&')) body = body[1..];
            if (std.fmt.parseInt(Id, body, 10)) |id| {
                const name: ?[]const u8 = if (s[i + 1] == '@') (if (ctx.store.user(id)) |u| u.name else null) else (if (ctx.store.channel(id)) |cs| cs.info.name else null);
                if (name) |nm| {
                    const piece = std.fmt.bufPrint(out[n..], "{c}{s}", .{ s[i + 1], nm }) catch break;
                    n += piece.len;
                    i = end + 1;
                    continue;
                }
            } else |_| {}
        };
        // Um caractere inteiro por vez (o corte nunca parte um UTF-8).
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (n + len > out.len or i + len > s.len) break;
        if (len == 1) {
            out[n] = if (s[i] == '\n' or s[i] == '\r' or s[i] == '\t') ' ' else s[i];
        } else @memcpy(out[n .. n + len], s[i .. i + len]);
        n += len;
        i += len;
    }
    return out[0..n];
}

fn snippet(ctx: *d.Ctx, a: std.mem.Allocator, r: *Result, content: []const u8, files: []const u8, term: []const u8) void {
    var buf: [800]u8 = undefined;
    var line_text = clean(ctx, &buf, content);
    if (line_text.len == 0) line_text = if (files.len > 0) std.fmt.bufPrint(&buf, "📎 {s}", .{files}) catch "" else "";
    const at: usize = if (term.len > 0) (if (sq.findFold(line_text, term)) |m| m[0] else 0) else 0;
    // Janela em volta do que casou.
    var from: usize = if (at > 50) at - 50 else 0;
    while (from > 0 and (line_text[from] & 0xC0) == 0x80) from -= 1;
    var end = @min(line_text.len, from + 360);
    while (end < line_text.len and end > from and (line_text[end] & 0xC0) == 0x80) end -= 1;
    const lead: []const u8 = if (from > 0) "…" else "";
    r.snippet = std.fmt.allocPrint(a, "{s}{s}", .{ lead, line_text[from..end] }) catch return;
}

// --- O painel ------------------------------------------------------------------------

/// O desenho fica em search_view.zig.
pub const draw = view.draw;

/// O que sobra para o tema com o painel aberto. Janela estreita demais para os dois: o painel
/// cobre tudo, até fechar.
pub fn reserve(win: d.Rect) d.Rect {
    if (!open) return win;
    const pw = std.math.clamp(win.w * 0.36, 340, 480);
    if (win.w - pw < 440) {
        panel = win;
        return win;
    }
    panel = .{ .x = win.right() - pw, .y = win.y, .w = pw, .h = win.h };
    var r = win;
    r.w -= pw;
    return r;
}

/// O que acontece a cada quadro, antes de desenhar.
pub fn frame(ctx: *d.Ctx) void {
    sq.now_s = @divTrunc(ctx.now_ms, 1000);
    if (!built) sq.tz_offset_s = w.utcOffset(sq.now_s);
    takeDelivered(ctx);
    if (server == .indexing) {
        if (ctx.now_ms >= retry_at_ms) sendRequest(ctx) else anim.at(retry_at_ms);
    }
    if (!built) {
        beginDisk();
        rebuild(ctx, false);
    }
    if (scanning) {
        if (stepDisk(ctx) and source == .local) rebuild(ctx, true);
        // Continua no próximo quadro sem esperar evento.
        anim.at(ctx.now_ms);
    }
}

pub fn openingKey() usize {
    return @as(u32, @bitCast(gen));
}

pub fn takeAppearing() bool {
    defer appearing = false;
    return appearing;
}

pub fn text() []const u8 {
    return std.mem.sliceTo(&query, 0);
}

pub fn serverOnly() bool {
    return view_query.serverOnly();
}

pub fn problem() []const u8 {
    return problem_buf[0..problem_len];
}

pub fn recentCount() usize {
    return recent_n;
}

pub fn recent(i: usize) []const u8 {
    return recent_buf[i][0..recent_len[i]];
}

fn inputCallback(data: [*c]c.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.*.EventFlag == c.ImGuiInputTextFlags_CallbackCompletion) tab_pressed = true;
    if (text_sync) {
        text_sync = false;
        c.ImGuiInputTextCallbackData_DeleteChars(data, 0, data.*.BufTextLen);
        c.ImGuiInputTextCallbackData_InsertChars(data, 0, &query, null);
    }
    if (cursor_end) {
        cursor_end = false;
        data.*.CursorPos = data.*.BufTextLen;
        data.*.SelectionStart = data.*.BufTextLen;
        data.*.SelectionEnd = data.*.BufTextLen;
    }
    return 0;
}

pub fn inputField(ctx: *d.Ctx, x: f32, y: f32, width: f32) void {
    c.ImGui_SetCursorScreenPos(d.v(x, y));
    c.ImGui_PushFontFloat(ctx.ui.get(.regular), 16);
    defer c.ImGui_PopFont();
    if (!focus) {
        c.ImGui_SetKeyboardFocusHere();
        focus = true;
    }
    c.ImGui_SetNextItemWidth(width);
    c.ImGui_PushStyleColor(c.ImGuiCol_FrameBg, 0);
    defer c.ImGui_PopStyleColor();
    // O campo do ImGui esquece o texto da vez anterior.
    c.ImGui_PushIDInt(gen);
    defer c.ImGui_PopID();
    const flags = c.ImGuiInputTextFlags_CallbackAlways | c.ImGuiInputTextFlags_CallbackCompletion;
    const edited = c.ImGui_InputTextWithHintEx("##sq", i18n.trZ("Buscar mensagens…", "Search messages…").ptr, &query, query.len, flags, inputCallback, null);
    was_active = input_active;
    input_active = c.ImGui_IsItemActive();
    if (edited) onEdited(ctx);
}

/// O texto mudou: volta para o que está neste computador, e o Discord fica para o Enter.
fn onEdited(ctx: *d.Ctx) void {
    source = .local;
    server = .idle;
    offset = 0;
    total = 0;
    problem_len = 0;
    arrow_moved = false;
    // Uma resposta que ainda vinha a caminho não vale mais.
    req_id +%= 1;
    view.scroll_y = 0;
    sugg.rebuild(ctx);
    rebuild(ctx, false);
}

pub fn setText(ctx: *d.Ctx, s: []const u8) void {
    @memset(&query, 0);
    const n = @min(s.len, query.len - 1);
    @memcpy(query[0..n], s[0..n]);
    text_sync = true;
    cursor_end = true;
    focus = false;
    onEdited(ctx);
}

/// Um filtro no fim do que já está escrito.
pub fn appendText(ctx: *d.Ctx, s: []const u8) void {
    var buf: [query.len]u8 = undefined;
    const now = text();
    const sep: []const u8 = if (now.len > 0 and now[now.len - 1] != ' ') " " else "";
    setText(ctx, std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ now, sep, s }) catch return);
}

pub fn removeRange(ctx: *d.Ctx, from: usize, to: usize) void {
    var buf: [query.len]u8 = undefined;
    const now = text();
    const before = std.mem.trimEnd(u8, now[0..from], " ");
    const after = std.mem.trimStart(u8, now[to..], " ");
    const sep: []const u8 = if (before.len > 0 and after.len > 0) " " else "";
    setText(ctx, std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ before, sep, after }) catch return);
}

/// As teclas da busca. Depois de desenhar: aqui a busca pode fechar.
pub fn keys(ctx: *d.Ctx) void {
    const st = ctx.st;
    if (st.palette.open or st.popup != .none or st.viewer != null) return;
    // O ImGui solta a caixa no próprio quadro do Esc: vale como estava antes.
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Escape) and (was_active or !ctx.io.*.WantTextInput)) return close();
    if (!was_active) return;
    const n = results.items.len;
    const with_sugg = sugg.count > 0;
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_DownArrow)) {
        if (with_sugg) {
            sugg.move(1);
        } else if (n > 0) {
            selected = (selected + 1) % n;
            arrow_moved = true;
            scroll_to_selected = true;
        }
    }
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_UpArrow)) {
        if (with_sugg) {
            sugg.move(-1);
        } else if (n > 0) {
            selected = (selected + n - 1) % n;
            arrow_moved = true;
            scroll_to_selected = true;
        }
    }
    if (tab_pressed) {
        tab_pressed = false;
        if (with_sugg) sugg.accept(ctx, sugg.selected orelse 0);
        return;
    }
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Enter) or c.ImGui_IsKeyPressed(c.ImGuiKey_KeypadEnter)) {
        if (with_sugg) if (sugg.selected) |i| return sugg.accept(ctx, i);
        // Escolheu com as setas, ou já está vendo o que o Discord achou: abre a mensagem.
        const same_answer = source == .server and server == .done and n > 0;
        if (n > 0 and (arrow_moved or same_answer)) return choose(ctx, results.items[selected]);
        askServer(ctx);
    }
}

pub fn choose(ctx: *d.Ctx, r: Result) void {
    arrow_moved = false;
    ctx.act(.{ .open_message = .{ .channel = r.channel, .id = r.id } });
}

// --- A busca do Discord -----------------------------------------------------------------

pub fn askServer(ctx: *d.Ctx) void {
    offset = 0;
    sendRequest(ctx);
}

pub fn changeSort(ctx: *d.Ctx, to: sq.Sort) void {
    sort = to;
    offset = 0;
    sendRequest(ctx);
}

pub fn changePage(ctx: *d.Ctx, to: u32) void {
    offset = to;
    sendRequest(ctx);
}

fn setProblem(comptime pt: []const u8, comptime en: []const u8, args: anytype) void {
    problem_len = i18n.fmt(&problem_buf, pt, en, args).len;
}

fn findUser(ctx: *d.Ctx, guild: Id, needle: []const u8) ?Id {
    var best: ?Id = null;
    var best_score: u8 = 0;
    var it = ctx.store.users.valueIterator();
    while (it.next()) |u| {
        const score = sq.userScore(u.name, needle);
        if (score == 0) continue;
        const total_score = score + @as(u8, @intFromBool(ctx.store.members.contains(.{ guild, u.id })));
        if (total_score > best_score) {
            best = u.id;
            best_score = total_score;
        }
    }
    return best;
}

fn findChannel(ctx: *d.Ctx, guild: Id, needle: []const u8) ?Id {
    var best: ?Id = null;
    var best_score: u8 = 0;
    for (ctx.store.channelsOf(guild)) |id| {
        const cs = ctx.store.channel(id) orelse continue;
        if (cs.info.kind != .text) continue;
        var b: [64]u8 = undefined;
        const name = sq.foldInto(&b, cs.info.name);
        const score: u8 = if (std.mem.eql(u8, name, needle)) 3 else if (std.mem.startsWith(u8, name, needle)) 2 else if (std.mem.indexOf(u8, name, needle) != null) 1 else 0;
        if (score > best_score) {
            best = id;
            best_score = score;
        }
    }
    return best;
}

/// Pede a página atual. O Discord busca no servidor inteiro; em conversa direta, nela.
fn sendRequest(ctx: *d.Ctx) void {
    problem_len = 0;
    const src = text();
    const q = sq.Query.parse(src);
    if (q.invalid_len > 0) return setProblem("Não entendi este filtro: {s}. Datas como 2026-11-06 ou 06/11/2026.", "I didn't understand this filter: {s}. Dates look like 2026-11-06 or 06/11/2026.", .{q.invalid()});
    if (q.empty()) return;
    const ch = ctx.st.activeChannel() orelse return setProblem("Abra um servidor ou uma conversa para buscar no Discord.", "Open a server or a conversation to search Discord.", .{});
    const cs = ctx.store.channel(ch) orelse return setProblem("Abra um servidor ou uma conversa para buscar no Discord.", "Open a server or a conversation to search Discord.", .{});
    const guild = cs.info.guild;
    var ids: sq.ApiIds = .{};
    if (q.from_len > 0) ids.author = findUser(ctx, guild, q.from()) orelse return setProblem("Não achei \"{s}\" entre as pessoas que o app já carregou.", "Couldn't find \"{s}\" among the people the app has loaded.", .{q.from()});
    if (q.mentions_len > 0) ids.mentions = findUser(ctx, guild, q.mentions()) orelse return setProblem("Não achei \"{s}\" entre as pessoas que o app já carregou.", "Couldn't find \"{s}\" among the people the app has loaded.", .{q.mentions()});
    if (q.in_len > 0) {
        if (guild == 0) return setProblem("O filtro de canal só vale dentro de um servidor.", "The channel filter only works inside a server.", .{});
        ids.channel = findChannel(ctx, guild, q.in()) orelse return setProblem("Não achei o canal \"{s}\" neste servidor.", "Couldn't find channel \"{s}\" in this server.", .{q.in()});
    }
    var buf: [1024]u8 = undefined;
    const params = sq.apiParams(&buf, &q, ids, sort, offset) orelse return setProblem("Essa busca ficou longa demais.", "This search got too long.", .{});
    const owned = alloc.dupe(u8, params) catch return;
    req_id +%= 1;
    ctx.act(.{ .search_messages = .{ .req = req_id, .guild = guild, .channel = ch, .params = owned } });
    // Tentando de novo porque o Discord ainda indexava: a tela continua explicando isso.
    if (server == .indexing) {
        retry_at_ms = ctx.now_ms + 60_000;
    } else {
        retries = 0;
        server = .loading;
    }
    source = .server;
    view_query = q;
    remember(src);
    clearResults();
    selected = 0;
    arrow_moved = false;
    scroll_to_selected = false;
    view.scroll_y = 0;
}

fn remember(s: []const u8) void {
    var at: usize = recent_n;
    for (0..recent_n) |i| {
        if (std.mem.eql(u8, recent(i), s)) at = i;
    }
    if (at == recent_n) {
        if (recent_n < recent_buf.len) recent_n += 1 else at = recent_buf.len - 1;
    }
    if (at >= recent_n) at = recent_n - 1;
    var i = at;
    while (i > 0) : (i -= 1) {
        recent_buf[i] = recent_buf[i - 1];
        recent_len[i] = recent_len[i - 1];
    }
    const n = @min(s.len, recent_buf[0].len);
    @memcpy(recent_buf[0][0..n], s[0..n]);
    recent_len[0] = @intCast(n);
}

fn freeHits(hits: []ev.SearchHit) void {
    for (hits) |h| {
        alloc.free(h.author_name);
        alloc.free(h.content);
        alloc.free(h.files);
    }
    if (hits.len > 0) alloc.free(hits);
}

/// A resposta chegou (da thread da interface, entre os quadros).
pub fn deliver(r: ev.SearchResults) void {
    if (delivered) |old| freeHits(old.hits);
    delivered = r;
}

fn takeDelivered(ctx: *d.Ctx) void {
    const r = delivered orelse return;
    delivered = null;
    defer freeHits(r.hits);
    if (r.req != req_id) return;
    switch (r.status) {
        .ok => {
            server = .done;
            total = r.total;
            loadHits(ctx, r.hits);
        },
        .indexing => {
            retries +|= 1;
            if (retries > 10) return serverFailed(ctx);
            server = .indexing;
            indexed = r.indexed;
            retry_at_ms = ctx.now_ms + @max(r.retry_ms, 1000);
        },
        .forbidden => server = .forbidden,
        .failed => serverFailed(ctx),
    }
}

/// Sem resposta: fica o que está neste computador, com um aviso.
fn serverFailed(ctx: *d.Ctx) void {
    source = .local;
    server = .failed;
    rebuild(ctx, false);
}

fn loadHits(ctx: *d.Ctx, hits: []const ev.SearchHit) void {
    clearResults();
    const ra = res_arena.allocator();
    const term: []const u8 = if (view_query.n_terms > 0) view_query.term(0) else "";
    for (hits) |h| {
        const name = if (ctx.store.user(h.author)) |u| u.name else h.author_name;
        const where = if (ctx.store.channel(h.channel)) |cs| whereLabel(ctx, ra, cs) catch continue else i18n.tr("canal que não está na lista", "channel not in the list");
        var r: Result = .{
            .channel = h.channel,
            .id = h.id,
            .ts = @divTrunc(types.snowflakeTime(h.id), 1000),
            .author_id = h.author,
            .author = ra.dupe(u8, name) catch continue,
            .where = where,
            .snippet = "",
        };
        snippet(ctx, ra, &r, h.content, h.files, term);
        results.append(alloc, r) catch return;
    }
}
