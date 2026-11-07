//! As sugestões da busca: enquanto se digita um filtro, as pessoas, os canais e os valores que
//! servem. Enter ou Tab completa o que está marcado, e as setas andam na lista.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const w = @import("widgets.zig");
const types = @import("../core/types.zig");
const sq = @import("../core/search_query.zig");
const search = @import("search.zig");
const Id = types.Id;

const max_items = 7;
const row_h: f32 = 36;
const title_h: f32 = 26;

pub const Kind = enum { filter, user, channel, value };

const Item = struct {
    kind: Kind,
    id: Id = 0,
    score: u8 = 0,
    label_buf: [64]u8 = undefined,
    label_len: u8 = 0,
    hint_buf: [64]u8 = undefined,
    hint_len: u8 = 0,
    /// O que entra no lugar do filtro que está sendo digitado.
    insert_buf: [96]u8 = undefined,
    insert_len: u8 = 0,

    fn label(it: *const Item) []const u8 {
        return it.label_buf[0..it.label_len];
    }
    fn hint(it: *const Item) []const u8 {
        return it.hint_buf[0..it.hint_len];
    }
    fn insert(it: *const Item) []const u8 {
        return it.insert_buf[0..it.insert_len];
    }
};

var items: [max_items]Item = undefined;
pub var count: usize = 0;
/// Sem marcado (nome de filtro, enquanto pode ser só uma palavra), Enter continua buscando.
pub var selected: ?usize = null;
var title: []const u8 = "";
/// Onde começa o filtro que está sendo digitado.
var token_start: usize = 0;

fn copy(buf: []u8, s: []const u8) u8 {
    const p = d.utf8Prefix(s, buf.len);
    @memcpy(buf[0..p.len], p);
    return @intCast(p.len);
}

fn add(kind: Kind, id: Id, score: u8, label: []const u8, hint: []const u8, insert: []const u8) void {
    var it: Item = .{ .kind = kind, .id = id, .score = score };
    it.label_len = copy(&it.label_buf, label);
    it.hint_len = copy(&it.hint_buf, hint);
    it.insert_len = copy(&it.insert_buf, insert);
    // Em ordem de pontos; a lista é curta.
    var at = count;
    while (at > 0 and items[at - 1].score < score) at -= 1;
    if (at >= max_items) return;
    if (count < max_items) count += 1;
    var i = count - 1;
    while (i > at) : (i -= 1) items[i] = items[i - 1];
    items[at] = it;
}

/// `key:valor `, com aspas se o valor tiver espaço.
fn valueInsert(buf: []u8, key: []const u8, val: []const u8) []const u8 {
    const quoted = std.mem.indexOfScalar(u8, val, ' ') != null;
    return (if (quoted)
        std.fmt.bufPrint(buf, "{s}:\"{s}\" ", .{ key, val })
    else
        std.fmt.bufPrint(buf, "{s}:{s} ", .{ key, val })) catch "";
}

pub fn rebuild(ctx: *d.Ctx) void {
    count = 0;
    selected = null;
    title = "";
    const src = search.text();
    const t = sq.lastToken(src);
    token_start = t.start;
    if (t.start >= src.len) return;
    if (t.key.len == 0) {
        filterNames(t.val);
    } else switch (sq.filterOf(t.key)) {
        .from, .mentions => users(ctx, t.key, t.val),
        .in => channels(ctx, t.key, t.val),
        .has => hasValues(t.key, t.val),
        .before, .after, .during => dateValues(t.key, t.val),
        .pinned => pinnedValues(t.key, t.val),
        .none => return,
    }
    // O que está digitado já é a única opção: não há o que sugerir.
    if (count == 1 and items[0].kind != .filter and std.mem.eql(u8, std.mem.trimEnd(u8, items[0].insert(), " "), src[t.start..])) count = 0;
    if (count > 0 and t.key.len > 0) selected = 0;
}

fn filterNames(val: []const u8) void {
    if (val.len < 2) return;
    const Name = struct { name: []const u8, label: []const u8 };
    const names = [_]Name{
        .{ .name = "from:", .label = i18n.tr("de uma pessoa", "from someone") },
        .{ .name = "mentions:", .label = i18n.tr("menciona uma pessoa", "mentions someone") },
        .{ .name = "has:", .label = i18n.tr("tem link, imagem, arquivo…", "has a link, image, file…") },
        .{ .name = "in:", .label = i18n.tr("em um canal", "in a channel") },
        .{ .name = "before:", .label = i18n.tr("antes de uma data", "before a date") },
        .{ .name = "after:", .label = i18n.tr("depois de uma data", "after a date") },
        .{ .name = "during:", .label = i18n.tr("em um dia", "on a day") },
        .{ .name = "pinned:", .label = i18n.tr("fixada ou não", "pinned or not") },
    };
    title = i18n.tr("FILTROS", "FILTERS");
    for (names) |n| {
        if (n.name.len > val.len and std.ascii.startsWithIgnoreCase(n.name, val)) add(.filter, 0, 0, n.name, n.label, n.name);
    }
}

fn users(ctx: *d.Ctx, key: []const u8, val: []const u8) void {
    title = if (sq.filterOf(key) == .from) i18n.tr("DE QUEM", "FROM") else i18n.tr("QUEM FOI MENCIONADO", "MENTIONING");
    var needle_buf: [64]u8 = undefined;
    const needle = sq.foldInto(&needle_buf, std.mem.trim(u8, val, "\""));
    const ch = ctx.st.activeChannel() orelse 0;
    const cs = ctx.store.channel(ch);
    const guild: Id = if (cs) |x| x.info.guild else 0;
    var ib: [96]u8 = undefined;
    if (needle.len == 0) {
        // Sem nada digitado: quem falou por último nesta conversa.
        const list = cs orelse return;
        var i = list.messages.items.len;
        var seen: [max_items]Id = undefined;
        var n: usize = 0;
        outer: while (i > 0 and n < max_items) {
            i -= 1;
            const id = list.messages.items[i].msg.author;
            for (seen[0..n]) |s| if (s == id) continue :outer;
            const u = ctx.store.user(id) orelse continue;
            seen[n] = id;
            n += 1;
            addUser(key, u, 0, &ib);
        }
        return;
    }
    var it = ctx.store.users.valueIterator();
    while (it.next()) |u| {
        const s = sq.userScore(u.name, needle);
        if (s == 0) continue;
        addUser(key, u, s + @as(u8, @intFromBool(ctx.store.members.contains(.{ guild, u.id }))), &ib);
    }
}

fn addUser(key: []const u8, u: *const types.User, score: u8, ib: []u8) void {
    add(.user, u.id, score, u.name, "", valueInsert(ib, key, u.name));
}

fn channels(ctx: *d.Ctx, key: []const u8, val: []const u8) void {
    title = i18n.tr("EM QUAL CANAL", "IN WHICH CHANNEL");
    const ch = ctx.st.activeChannel() orelse return;
    const cs = ctx.store.channel(ch) orelse return;
    if (cs.info.guild == 0) return;
    var needle_buf: [64]u8 = undefined;
    const needle = sq.foldInto(&needle_buf, std.mem.trimStart(u8, std.mem.trim(u8, val, "\""), "#"));
    var ib: [96]u8 = undefined;
    var lb: [68]u8 = undefined;
    for (ctx.store.channelsOf(cs.info.guild)) |id| {
        const other = ctx.store.channel(id) orelse continue;
        if (other.info.kind != .text) continue;
        var fb: [64]u8 = undefined;
        const name = sq.foldInto(&fb, other.info.name);
        const score: u8 = if (needle.len == 0) 1 else if (std.mem.startsWith(u8, name, needle)) 3 else if (std.mem.indexOf(u8, name, needle) != null) 2 else 0;
        if (score == 0) continue;
        const label = std.fmt.bufPrint(&lb, "#{s}", .{other.info.name}) catch continue;
        add(.channel, id, score, label, "", valueInsert(&ib, key, other.info.name));
    }
}

fn hasValues(key: []const u8, val: []const u8) void {
    title = i18n.tr("TEM", "HAS");
    const Opt = struct { value: []const u8, label: []const u8 };
    const opts = [_]Opt{
        .{ .value = "link", .label = i18n.tr("um link", "a link") },
        .{ .value = i18n.tr("imagem", "image"), .label = i18n.tr("uma imagem", "an image") },
        .{ .value = i18n.tr("arquivo", "file"), .label = i18n.tr("um arquivo", "a file") },
        .{ .value = "video", .label = i18n.tr("um vídeo", "a video") },
        .{ .value = i18n.tr("som", "sound"), .label = i18n.tr("um áudio", "a sound") },
        .{ .value = "embed", .label = i18n.tr("uma prévia de link", "a link preview") },
        .{ .value = i18n.tr("figurinha", "sticker"), .label = i18n.tr("uma figurinha", "a sticker") },
    };
    var ib: [96]u8 = undefined;
    for (opts) |o| {
        if (std.ascii.startsWithIgnoreCase(o.value, val)) add(.value, 0, 0, o.value, o.label, valueInsert(&ib, key, o.value));
    }
}

fn dateValues(key: []const u8, val: []const u8) void {
    title = i18n.tr("DATA  (ou 2026-11-06, 06/11/2026)", "DATE  (or 2026-11-06, 06/11/2026)");
    var ib: [96]u8 = undefined;
    const today = i18n.tr("hoje", "today");
    const yesterday = i18n.tr("ontem", "yesterday");
    if (std.ascii.startsWithIgnoreCase(today, val)) add(.value, 0, 0, today, "", valueInsert(&ib, key, today));
    if (std.ascii.startsWithIgnoreCase(yesterday, val)) add(.value, 0, 0, yesterday, "", valueInsert(&ib, key, yesterday));
}

fn pinnedValues(key: []const u8, val: []const u8) void {
    title = i18n.tr("FIXADA", "PINNED");
    var ib: [96]u8 = undefined;
    if (std.ascii.startsWithIgnoreCase("true", val)) add(.value, 0, 0, "true", i18n.tr("só as fixadas", "only pinned"), valueInsert(&ib, key, "true"));
    if (std.ascii.startsWithIgnoreCase("false", val)) add(.value, 0, 0, "false", i18n.tr("só as não fixadas", "only not pinned"), valueInsert(&ib, key, "false"));
}

/// Troca o filtro que está sendo digitado pelo item.
pub fn accept(ctx: *d.Ctx, i: usize) void {
    var buf: [256]u8 = undefined;
    const src = search.text();
    const joined = std.fmt.bufPrint(&buf, "{s}{s}", .{ src[0..token_start], items[i].insert() }) catch return;
    search.setText(ctx, joined);
}

pub fn move(delta: i32) void {
    if (count == 0) return;
    const n: i32 = @intCast(count);
    const at: i32 = if (selected) |s| @intCast(s) else if (delta > 0) -1 else 0;
    selected = @intCast(@mod(at + delta, n));
}

pub fn rect(anchor: d.Rect) d.Rect {
    return .{ .x = anchor.x, .y = anchor.bottom() + 4, .w = anchor.w, .h = title_h + @as(f32, @floatFromInt(count)) * row_h + 6 };
}

/// Aberta com a caixa de texto ativa. Com o mouse em cima também: o clique tira o foco da
/// caixa antes de o botão responder.
pub fn visible(ctx: *d.Ctx, r: d.Rect) bool {
    return count > 0 and (search.input_active or ctx.hovering(r));
}

pub fn draw(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect) void {
    const radius = ctx.th.radius + 4;
    d.shadow(dl, r, radius, 16, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.elevated), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    const font = ctx.ui.get(.regular);
    const medium = ctx.ui.get(.medium);
    const mono = ctx.mono.get(.regular);
    d.text(dl, ctx.ui.get(.semibold), 11, r.x + 12, r.y + 8, ctx.col(.faint), title);
    var y = r.y + title_h;
    var taken: ?usize = null;
    for (items[0..count], 0..) |*it, i| {
        const rr: d.Rect = .{ .x = r.x + 4, .y = y, .w = r.w - 8, .h = row_h };
        const hb = d.hit(ctx, 0x5dc0 + i, rr);
        qa.mark(rr, "search-sugg:{d}", .{i});
        if (hb.hovered and (ctx.io.*.MouseDelta.x != 0 or ctx.io.*.MouseDelta.y != 0)) selected = i;
        if (hb.clicked) taken = i;
        if (selected == i) d.rect(dl, rr, ctx.col(.accent).alpha(0.18), ctx.th.radius + 2);
        var x = rr.x + 10;
        switch (it.kind) {
            .user => {
                w.avatar(ctx, dl, x + 12, rr.y + row_h / 2, 24, it.id, .circle, null, 1);
                x += 32;
            },
            .filter => {},
            .channel, .value => {},
        }
        const lf = if (it.kind == .filter) mono else medium;
        const lw = d.textClipped(dl, lf, 14, x, d.centerY(rr, 14), ctx.col(.text), it.label(), rr.right() - x - 8);
        if (it.hint_len > 0) _ = d.textClipped(dl, font, 12.5, x + lw + 10, d.centerY(rr, 12.5), ctx.col(.muted), it.hint(), @max(0, rr.right() - x - lw - 20));
        y += row_h;
    }
    if (taken) |i| accept(ctx, i);
}
