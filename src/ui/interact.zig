//! Interações com bots na interface: botões e menus de seleção nas mensagens,
//! o modal que o bot abre, a lista de comandos de barra (no autocompletar da
//! caixa de texto) e o formulário com as opções do comando escolhido.
//!
//! Cada pedido ao Discord sai de um clique ou de uma tecla da pessoa (o
//! autocompletar das opções espera ela parar de digitar). O índice de comandos
//! só é buscado quando alguém digita `/` pela primeira vez naquele lugar.
//! Parado, nada custa: sem pedido em andamento, sem modal e sem formulário,
//! `draw` só confere alguns campos.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const i18n = @import("i18n.zig");
const icons = @import("icons.zig");
const dropdown = @import("dropdown.zig");
const autocomplete = @import("autocomplete.zig");
const forum = @import("forum.zig");
const inbox = @import("inbox.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;
const types = @import("../core/types.zig");
const ix = @import("../core/interaction.zig");
const store_mod = @import("../core/store.zig");
const Store = store_mod.Store;
const StoredMessage = store_mod.StoredMessage;
const Id = types.Id;
const comp = ix.comp;

const gpa = std.heap.c_allocator;

// --- Pedidos em andamento e falhas ----------------------------------------------

const Pending = struct { nonce: u64 = 0, msg: Id = 0, key: u64 = 0, at: i64 = 0 };
var pending: [8]Pending = @splat(.{});
/// Sem resposta do Discord até aqui: dá a interação por falha.
const timeout_ms: i64 = 12_000;

/// Nonces que mandamos há pouco: um modal só abre se for resposta a um deles.
var recent: [8]Pending = @splat(.{});
var recent_next: usize = 0;

var failed: [8]Id = @splat(0);
var failed_next: usize = 0;
var seq: u64 = 0;

const Dismiss = struct { channel: Id, id: Id };
var dismiss_q: [8]Dismiss = undefined;
var n_dismiss: usize = 0;

fn keyOf(custom_id: []const u8) u64 {
    return std.hash.Wyhash.hash(0x1A7E, custom_id) | 1;
}

fn nextNonce(now_ms: i64) u64 {
    seq +%= 1;
    return ix.makeNonce(now_ms, seq);
}

fn addPending(nonce: u64, msg: Id, key: u64, now_ms: i64) void {
    var slot: usize = 0;
    var oldest: i64 = std.math.maxInt(i64);
    for (&pending, 0..) |*p, i| {
        if (p.nonce == 0) {
            slot = i;
            break;
        }
        if (p.at < oldest) {
            oldest = p.at;
            slot = i;
        }
    }
    pending[slot] = .{ .nonce = nonce, .msg = msg, .key = key, .at = now_ms };
    recent[recent_next] = pending[slot];
    recent_next = (recent_next + 1) % recent.len;
    anim.at(now_ms + timeout_ms);
}

fn sentRecently(nonce: u64, now_ms: i64) bool {
    if (nonce == 0) return false;
    for (recent) |r| if (r.nonce == nonce and now_ms - r.at < 60_000) return true;
    return false;
}

fn takePending(nonce: u64) ?Pending {
    if (nonce == 0) return null;
    for (&pending) |*p| if (p.nonce == nonce) {
        const x = p.*;
        p.* = .{};
        return x;
    };
    return null;
}

fn busy(msg: Id, key: u64) bool {
    for (pending) |p| if (p.nonce != 0 and p.msg == msg and p.key == key) return true;
    return false;
}

fn isFailed(msg: Id) bool {
    if (msg == 0) return false;
    return std.mem.indexOfScalar(Id, &failed, msg) != null;
}

/// A altura da mensagem muda (a linha de "falhou"): mede de novo.
fn invalidate(store: *Store, msg: Id) void {
    if (store.findAny(msg)) |f| f.m.layout_w = -1;
}

fn markFailed(store: *Store, msg: Id) void {
    if (msg == 0 or isFailed(msg)) return;
    const old = failed[failed_next];
    failed[failed_next] = msg;
    failed_next = (failed_next + 1) % failed.len;
    if (old != 0) invalidate(store, old);
    invalidate(store, msg);
}

fn clearFailed(store: *Store, msg: Id) void {
    for (&failed) |*f| if (f.* == msg and msg != 0) {
        f.* = 0;
        invalidate(store, msg);
    };
}

fn send(ctx: *d.Ctx, s: ix.Send) void {
    ctx.act(.{ .interaction = .{ .send = s } });
}

// --- Mensagem sendo desenhada ----------------------------------------------------

var cur: ?*const StoredMessage = null;

/// Chamado por ui/embeds.zig antes dos cartões: os botões e menus sabem de
/// qual mensagem são.
pub fn beginMessage(m: *const StoredMessage) void {
    cur = m;
}

const MsgCtx = struct { app: Id, guild: Id, channel: Id, msg: Id, flags: u32 };

fn msgCtx(ctx: *d.Ctx) ?MsgCtx {
    const m = cur orelse return null;
    if (m.pending or m.deleted or m.msg.id == 0) return null;
    // Aplicação: a da resposta de interação ou o próprio bot (o ID é o mesmo).
    const app = if (m.msg.app != 0) m.msg.app else m.msg.author;
    if (app == 0 or app & types.webhook_id_bit != 0) return null;
    const cs = ctx.store.channel(m.msg.channel) orelse return null;
    return .{ .app = app, .guild = cs.info.guild, .channel = m.msg.channel, .msg = m.msg.id, .flags = m.msg.flags };
}

fn sendComponent(ctx: *d.Ctx, mc: MsgCtx, kind: u8, custom_id: []const u8, values: ?[]const []const u8) void {
    const data = ix.componentData(gpa, kind, custom_id, values) catch return;
    const nonce = nextNonce(ctx.now_ms);
    send(ctx, .{ .kind = .component, .app = mc.app, .guild = mc.guild, .channel = mc.channel, .message = mc.msg, .message_flags = mc.flags, .nonce = nonce, .data = data });
    addPending(nonce, mc.msg, keyOf(custom_id), ctx.now_ms);
    clearFailed(ctx.store, mc.msg);
}

fn radius(ctx: *const d.Ctx) f32 {
    return std.math.clamp(ctx.th.radius, 0, 8);
}

// --- Botões ------------------------------------------------------------------------

fn styleColors(ctx: *const d.Ctx, style: u8) struct { bg: d.Rgba, fg: d.Rgba } {
    return switch (style) {
        1 => .{ .bg = ctx.col(.accent), .fg = ctx.col(.accent_text) },
        3 => .{ .bg = ctx.col(.online), .fg = d.Rgba.white },
        4 => .{ .bg = ctx.col(.danger), .fg = d.Rgba.white },
        else => .{ .bg = ctx.col(.text).alpha(0.1), .fg = ctx.col(.text) },
    };
}

/// Botão de interação (estilos 1 a 4). Clicar manda o `custom_id` ao bot; até
/// a resposta chegar, os pontinhos ficam no lugar do texto.
pub fn drawButton(ctx: *d.Ctx, dl: *c.ImDrawList, it: *const types.EmbedMedia, r: d.Rect, alpha: f32) void {
    const mc = msgCtx(ctx);
    const working = if (mc) |m| busy(m.msg, keyOf(it.custom_id)) else false;
    const live = !it.disabled and mc != null;
    const hb = d.hit(ctx, @truncate(@intFromPtr(it)), r);
    qa.mark(r, "ix-button:{s}", .{it.custom_id});
    const sc = styleColors(ctx, it.style);
    var bg = sc.bg;
    if (live and !working and hb.held) {
        bg = bg.mix(d.Rgba.black, 0.12);
    } else if (live and !working and hb.hovered) {
        bg = if (it.style == 1 or it.style == 3 or it.style == 4) bg.mix(d.Rgba.white, 0.12) else ctx.col(.hover);
    }
    const a = alpha * (if (live) @as(f32, 1) else 0.5);
    d.rect(dl, r, bg.alpha(a), radius(ctx));
    const f = ctx.ui.get(.semibold);
    if (working) {
        w.typingDots(dl, r.x + r.w / 2 - 7, r.y + r.h / 2, sc.fg.alpha(a), ctx.now_ms);
    } else {
        _ = d.textClipped(dl, f, 13, r.x + 12, d.centerY(r, 13), sc.fg.alpha(a), it.label, r.w - 24);
    }
    if (hb.clicked and live and !working) sendComponent(ctx, mc.?, comp.button, it.custom_id, null);
}

// --- Menus de seleção ---------------------------------------------------------------

pub const select_h: f32 = 40;

/// Quem dá para escolher num menu de pessoas, cargos ou canais.
const Cand = struct { id: Id, kind: u8, name: []const u8, color: u32 = 0 };
var cands: [60]Cand = undefined;

fn addCand(n: *usize, cand: Cand, q: []const u8) void {
    if (n.* == cands.len or cand.name.len == 0) return;
    for (cands[0..n.*]) |x| if (x.id == cand.id) return;
    if (q.len > 0 and std.ascii.findIgnoreCase(cand.name, q) == null) return;
    cands[n.*] = cand;
    n.* += 1;
}

fn addUser(ctx: *d.Ctx, n: *usize, uid: Id, q: []const u8) void {
    if (uid == 0 or uid & types.webhook_id_bit != 0) return;
    const u = ctx.store.user(uid) orelse return;
    addCand(n, .{ .id = uid, .kind = comp.user_select, .name = u.name }, q);
}

/// Número do tipo de canal do Discord (para `channel_types`).
fn discordType(ch: *const types.Channel) u8 {
    if (ch.thread != null) return 11;
    return switch (ch.kind) {
        .text => 0,
        .voice => 2,
        .category => 4,
        .forum => 15,
    };
}

fn gather(ctx: *d.Ctx, kind: u8, channel: Id, channel_types: []const u8, q: []const u8) []Cand {
    var n: usize = 0;
    const cs = ctx.store.channel(channel) orelse return cands[0..0];
    const guild = cs.info.guild;
    if (kind == comp.user_select or kind == comp.mentionable_select) {
        // Quem falou há pouco vem primeiro; depois a lista de membros.
        var i = cs.messages.items.len;
        var seen: usize = 0;
        while (i > 0 and seen < 80) : (seen += 1) {
            i -= 1;
            addUser(ctx, &n, cs.messages.items[i].msg.author, q);
        }
        if (guild == 0) {
            addUser(ctx, &n, cs.info.recipient, q);
            for (cs.info.recipients) |uid| addUser(ctx, &n, uid, q);
        } else {
            if (ctx.store.memberList(guild)) |ml| for (ml.items.items) |entry| {
                if (entry == .member) addUser(ctx, &n, entry.member.user, q);
            };
            var it = ctx.store.members.keyIterator();
            while (it.next()) |k| {
                if (n == cands.len) break;
                if (k.*[0] == guild) addUser(ctx, &n, k.*[1], q);
            }
        }
        addUser(ctx, &n, ctx.store.me, q);
    }
    if ((kind == comp.role_select or kind == comp.mentionable_select) and guild != 0) {
        var ri = ctx.store.roles.valueIterator();
        while (ri.next()) |r| if (r.guild == guild and r.id != guild) addCand(&n, .{ .id = r.id, .kind = comp.role_select, .name = r.name, .color = r.color }, q);
    }
    if (kind == comp.channel_select and guild != 0) for (ctx.store.channelsOf(guild)) |id| {
        const ch = ctx.store.channel(id) orelse continue;
        if (!ctx.store.canAccess(&ch.info)) continue;
        if (channel_types.len > 0 and std.mem.indexOfScalar(u8, channel_types, discordType(&ch.info)) == null) continue;
        addCand(&n, .{ .id = id, .kind = comp.channel_select, .name = ch.info.name }, q);
    };
    return cands[0..n];
}

/// Nome de uma pessoa, cargo ou canal escolhido.
fn entityName(ctx: *d.Ctx, id: Id) []const u8 {
    if (ctx.store.user(id)) |u| return u.name;
    if (ctx.store.roles.get(id)) |r| return r.name;
    if (ctx.store.channel(id)) |ch| return ch.info.name;
    return "?";
}

/// A lista aberta de um menu (só uma por vez, como o dropdown).
const Picker = struct {
    key: usize = 0,
    mask: u32 = 0,
    ids: [25]Id = undefined,
    n: u8 = 0,
    query: [64]u8 = @splat(0),
};
var pk: Picker = .{};

fn pickerInit(key: usize, mask: u32, ids: []const Id) void {
    pk = .{ .key = key, .mask = mask };
    const n = @min(ids.len, pk.ids.len);
    @memcpy(pk.ids[0..n], ids[0..n]);
    pk.n = @intCast(n);
}

fn pickedCount(s: *const ix.Select) usize {
    return if (s.kind == comp.string_select) @popCount(pk.mask) else pk.n;
}

fn checkBox(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, cy: f32, on: bool, round: bool) void {
    const r: d.Rect = .{ .x = x, .y = cy - 8, .w = 16, .h = 16 };
    const rad: f32 = if (round) 8 else @min(radius(ctx), 4);
    if (on) {
        d.rect(dl, r, ctx.col(.accent), rad);
        if (round) {
            d.circle(dl, x + 8, cy, 3.5, ctx.col(.accent_text));
        } else {
            const col = ctx.col(.accent_text);
            d.line(dl, x + 4, cy, x + 7, cy + 3, col, 2);
            d.line(dl, x + 7, cy + 3, x + 12, cy - 3, col, 2);
        }
    } else d.border(dl, r, ctx.col(.muted), rad, 1.5);
}

/// Desenha a lista aberta de um menu. true = a pessoa confirmou a escolha
/// (um clique num menu de um item; o botão no de vários).
fn picker(ctx: *d.Ctx, anchor: d.Rect, s: *const ix.Select, channel: Id, confirm: []const u8) bool {
    const entity = s.kind != comp.string_select;
    const q = std.mem.sliceTo(&pk.query, 0);
    const list: []Cand = if (entity) gather(ctx, s.kind, channel, s.channel_types, q) else &.{};
    const rows = if (entity) list.len else s.options.len;
    const multi = s.max > 1;
    const has_desc = !entity and for (s.options) |o| {
        if (o.description.len > 0) break true;
    } else false;
    const row_h: f32 = if (has_desc) 44 else 34;
    const search_h: f32 = if (entity) 42 else 0;
    const foot_h: f32 = if (multi) 44 else 0;
    const content = search_h + foot_h + (if (rows == 0) 34 else @as(f32, @floatFromInt(rows)) * row_h);
    var p = dropdown.begin(ctx, pk.key, anchor, @max(anchor.w, 260), content) orelse return false;
    defer p.end();
    const fam = ctx.ui;
    var done = false;
    if (entity) {
        const sr: d.Rect = .{ .x = p.x, .y = p.y + 2, .w = p.w, .h = 34 };
        qa.mark(sr, "ix-pick-search", .{});
        if (pk.query[0] == 0 and !c.ImGui_IsAnyItemActive()) c.ImGui_SetKeyboardFocusHere();
        _ = forum.textInput(ctx, p.dl, sr, "##ix-pick-q", i18n.trZ("Buscar", "Search").ptr, pk.query[0 .. pk.query.len - 1], 0);
        p.y += search_h;
    }
    if (rows == 0) {
        d.text(p.dl, fam.get(.regular), 13, p.x + 10, p.y + 9, ctx.col(.faint), i18n.tr("Nada encontrado", "Nothing found"));
        p.y += 34;
    }
    for (0..rows) |i| {
        const on = if (entity) std.mem.indexOfScalar(Id, pk.ids[0..pk.n], list[i].id) != null else pk.mask & (@as(u32, 1) << @intCast(i)) != 0;
        const row = p.row(row_h, on and !multi);
        qa.mark(row.rect, "ix-pick:{d}", .{i});
        var tx = row.rect.x + 10;
        if (multi) {
            checkBox(ctx, p.dl, tx, row.rect.y + row.rect.h / 2, on, false);
            tx += 26;
        }
        const label = if (entity) list[i].name else s.options[i].label;
        if (entity and list[i].kind == comp.user_select) {
            w.avatar(ctx, p.dl, tx + 10, row.rect.y + row.rect.h / 2, 20, list[i].id, .circle, null, 1);
            tx += 28;
        } else if (entity) {
            const glyph: []const u8 = if (list[i].kind == comp.role_select) "@" else "#";
            const gc = if (list[i].color != 0) d.Rgba.hex(list[i].color) else ctx.col(.muted);
            d.text(p.dl, fam.get(.bold), 15, tx, d.centerY(row.rect, 15), gc, glyph);
            tx += 20;
        }
        if (has_desc and s.options[i].description.len > 0) {
            _ = d.textClipped(p.dl, fam.get(.medium), 13.5, tx, row.rect.y + 5, ctx.col(.text), label, row.rect.right() - tx - 8);
            _ = d.textClipped(p.dl, fam.get(.regular), 12, tx, row.rect.y + 24, ctx.col(.muted), s.options[i].description, row.rect.right() - tx - 8);
        } else {
            _ = d.textClipped(p.dl, fam.get(.medium), 13.5, tx, d.centerY(row.rect, 13.5), ctx.col(.text), label, row.rect.right() - tx - 8);
        }
        if (row.hit.clicked) {
            // Num menu de um item, clicar no escolhido só desmarca se puder ficar vazio.
            if (entity) {
                const id = list[i].id;
                const at = std.mem.indexOfScalar(Id, pk.ids[0..pk.n], id);
                if (!multi) {
                    if (at != null and s.min == 0) pk.n = 0 else {
                        pk.ids[0] = id;
                        pk.n = 1;
                    }
                } else if (at) |k| {
                    std.mem.copyForwards(Id, pk.ids[k .. pk.n - 1], pk.ids[k + 1 .. pk.n]);
                    pk.n -= 1;
                } else if (pk.n < s.max) {
                    pk.ids[pk.n] = id;
                    pk.n += 1;
                }
            } else {
                const bit = @as(u32, 1) << @intCast(i);
                if (!multi) {
                    pk.mask = if (on and s.min == 0) 0 else bit;
                } else if (on) {
                    pk.mask &= ~bit;
                } else if (@popCount(pk.mask) < s.max) pk.mask |= bit;
            }
            if (!multi) done = true;
        }
    }
    if (multi) {
        const n = pickedCount(s);
        const ok = n >= s.min and n <= s.max and (n > 0 or s.min == 0);
        var lb: [64]u8 = undefined;
        const lbl = std.fmt.bufPrint(&lb, "{s} ({d}/{d})", .{ confirm, n, s.max }) catch confirm;
        const br: d.Rect = .{ .x = p.x + 4, .y = p.y + 6, .w = p.w - 8, .h = 32 };
        qa.mark(br, "ix-pick-ok", .{});
        if (forum.primary(ctx, p.dl, fam, 0x1A7E_0001, br, lbl, ok)) done = true;
        p.y += foot_h;
    }
    if (done) dropdown.close();
    return done;
}

fn boxFrame(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, hovered: bool, open: bool, alpha: f32) void {
    d.rect(dl, r, ctx.col(.rail).mix(ctx.col(.surface), 0.35).alpha(alpha), radius(ctx));
    const bc = if (open) ctx.col(.accent) else if (hovered) ctx.col(.text).alpha(0.35) else ctx.col(.border);
    d.border(dl, r, bc.alpha(alpha), radius(ctx), 1);
}

/// Texto da caixa fechada: o que está escolhido, ou a dica.
fn summary(ctx: *d.Ctx, buf: []u8, s: *const ix.Select, mask: u32, ids: []const Id) struct { text: []const u8, hint: bool } {
    var n: usize = 0;
    if (s.kind == comp.string_select) {
        for (s.options, 0..) |o, i| if (mask & (@as(u32, 1) << @intCast(i)) != 0) {
            const sep: []const u8 = if (n > 0) ", " else "";
            const add = std.fmt.bufPrint(buf[n..], "{s}{s}", .{ sep, o.label }) catch break;
            n += add.len;
        };
    } else for (ids) |id| {
        const sep: []const u8 = if (n > 0) ", " else "";
        const add = std.fmt.bufPrint(buf[n..], "{s}{s}", .{ sep, entityName(ctx, id) }) catch break;
        n += add.len;
    }
    if (n > 0) return .{ .text = buf[0..n], .hint = false };
    return .{ .text = if (s.placeholder.len > 0) s.placeholder else i18n.tr("Faça uma escolha", "Make a selection"), .hint = true };
}

fn defaultMask(s: *const ix.Select) u32 {
    var mask: u32 = 0;
    for (s.options, 0..) |o, i| if (o.default) {
        mask |= @as(u32, 1) << @intCast(i);
        if (s.max == 1) break;
    };
    return mask;
}

/// Menu de seleção de uma mensagem. Escolher manda os valores ao bot.
pub fn selectBox(ctx: *d.Ctx, dl: ?*c.ImDrawList, os: *const ix.OwnedSelect, x: f32, y: f32, wd: f32, alpha: f32) f32 {
    const l = dl orelse return select_h;
    const s = &os.sel;
    const r: d.Rect = .{ .x = x, .y = y, .w = @min(wd, 420), .h = select_h };
    const mc = msgCtx(ctx);
    const key = keyOf(s.custom_id);
    const working = if (mc) |m| busy(m.msg, key) else false;
    const live = !s.disabled and mc != null;
    const dd_key: usize = @truncate((if (mc) |m| m.msg else 0) *% 31 +% key);
    const open = dropdown.isOpen(dd_key);
    const hb = d.hit(ctx, @truncate(@intFromPtr(os)), r);
    qa.mark(r, "ix-select:{s}", .{s.custom_id});
    const a = alpha * (if (live) @as(f32, 1) else 0.5);
    boxFrame(ctx, l, r, hb.hovered and live, open, a);
    var sb: [256]u8 = undefined;
    const sm = summary(ctx, &sb, s, defaultMask(s), s.defaults);
    _ = d.textClipped(l, ctx.ui.get(.regular), 14, r.x + 12, d.centerY(r, 14), (if (sm.hint) ctx.col(.faint) else ctx.col(.text)).alpha(a), sm.text, r.w - 44);
    if (working) {
        w.typingDots(l, r.right() - 30, r.y + r.h / 2, ctx.col(.muted).alpha(a), ctx.now_ms);
    } else icons.chevron(l, r.right() - 18, r.y + r.h / 2, ctx.col(.muted).alpha(a).u(), if (open) 1 else 0);
    if (hb.clicked and live and !working) {
        if (!open) pickerInit(dd_key, defaultMask(s), s.defaults);
        dropdown.toggle(dd_key);
    }
    const m = mc orelse return select_h;
    if (pk.key == dd_key and dropdown.isOpen(dd_key)) if (picker(ctx, r, s, m.channel, i18n.tr("Enviar", "Send"))) {
        var vals: [25][]const u8 = undefined;
        var idb: [25][24]u8 = undefined;
        var n: usize = 0;
        if (s.kind == comp.string_select) {
            for (s.options, 0..) |o, i| if (pk.mask & (@as(u32, 1) << @intCast(i)) != 0 and n < vals.len) {
                vals[n] = o.value;
                n += 1;
            };
        } else for (pk.ids[0..pk.n]) |id| {
            vals[n] = std.fmt.bufPrint(&idb[n], "{d}", .{id}) catch continue;
            n += 1;
        }
        sendComponent(ctx, m, s.kind, s.custom_id, vals[0..n]);
    };
    return select_h;
}

// --- Rodapé da mensagem: pensando, falhou, só você vê --------------------------------

fn thinking(m: *const StoredMessage) bool {
    return m.msg.flags & ix.loading_flag != 0 and m.msg.content.len == 0 and m.msg.embeds.len == 0 and m.msg.attachments.len == 0;
}

/// Altura das linhas de baixo (0 = nenhuma). Barato: chamado em toda medida.
pub fn footerHeight(m: *const StoredMessage) f32 {
    var h: f32 = 0;
    if (thinking(m)) h += 24;
    if (isFailed(m.msg.id)) h += 20;
    if (m.msg.flags & ix.ephemeral_flag != 0) h += 22;
    return h;
}

pub fn footer(ctx: *d.Ctx, dl: ?*c.ImDrawList, m: *const StoredMessage, x: f32, y_in: f32, alpha: f32) f32 {
    const h = footerHeight(m);
    const l = dl orelse return h;
    if (h == 0) return 0;
    var y = y_in;
    const f = ctx.ui.get(.regular);
    if (thinking(m)) {
        const name = if (ctx.store.user(m.msg.author)) |u| u.name else "bot";
        var tb: [128]u8 = undefined;
        const t = i18n.fmt(&tb, "{s} está pensando", "{s} is thinking", .{name});
        d.text(l, ctx.ui.get(.medium), 13.5, x, y + 3, ctx.col(.muted).alpha(alpha), t);
        w.typingDots(l, x + d.width(ctx.ui.get(.medium), 13.5, t) + 8, y + 13, ctx.col(.muted).alpha(alpha), ctx.now_ms);
        y += 24;
    }
    if (isFailed(m.msg.id)) {
        const t = i18n.tr("Esta interação falhou", "This interaction failed");
        d.circle(l, x + 6, y + 10, 6, ctx.col(.danger).alpha(alpha));
        d.text(l, ctx.ui.get(.bold), 10, x + 3.5, y + 3, d.Rgba.white.alpha(alpha), "!");
        d.text(l, f, 13, x + 18, y + 2, ctx.col(.danger).alpha(alpha), t);
        qa.mark(.{ .x = x, .y = y, .w = 200, .h = 20 }, "ix-failed:{d}", .{m.msg.id});
        y += 20;
    }
    if (m.msg.flags & ix.ephemeral_flag != 0) {
        const t = i18n.tr("Só você pode ver isto ·", "Only you can see this ·");
        eye(l, x + 7, y + 11, ctx.col(.muted).alpha(alpha));
        d.text(l, f, 12.5, x + 18, y + 3, ctx.col(.muted).alpha(alpha), t);
        const lx = x + 18 + d.width(f, 12.5, t) + 4;
        const lt = i18n.tr("Descartar mensagem", "Dismiss message");
        const lr: d.Rect = .{ .x = lx, .y = y, .w = d.width(f, 12.5, lt), .h = 20 };
        const hb = d.hit(ctx, @truncate(m.msg.id ^ 0xD15_0155), lr);
        qa.mark(lr, "ix-dismiss:{d}", .{m.msg.id});
        d.text(l, f, 12.5, lx, y + 3, ctx.col(.link).alpha(alpha), lt);
        if (hb.hovered) d.line(l, lx, y + 18, lr.right(), y + 18, ctx.col(.link).alpha(alpha), 1);
        // Só daqui: o Discord não guarda mensagens efêmeras.
        if (hb.clicked and n_dismiss < dismiss_q.len) {
            dismiss_q[n_dismiss] = .{ .channel = m.msg.channel, .id = m.msg.id };
            n_dismiss += 1;
        }
        y += 22;
    }
    return y - y_in;
}

/// Olho pequeno (mensagem que só você vê).
fn eye(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba) void {
    c.ImDrawList_AddEllipse(dl, d.v(cx, cy), d.v(6, 3.6), col.u());
    d.circle(dl, cx, cy, 1.8, col);
}

// --- Índice de comandos -----------------------------------------------------------------

const Cache = struct { key: Id = 0, state: enum { loading, ready, failed } = .loading, index: ?*ix.Index = null, at: i64 = 0 };
var caches: [6]Cache = undefined;
var n_caches: usize = 0;

fn pinnedKey() ?Id {
    return if (form) |*f| f.cache_key else null;
}

/// O índice deste lugar, já carregado; se ainda não veio, pede (uma vez).
fn ensure(ctx: *d.Ctx, sc: ix.Scope) ?*const ix.Index {
    const key = sc.key();
    for (caches[0..n_caches]) |*e| if (e.key == key) {
        if (e.state == .failed and ctx.now_ms - e.at > 10_000) {
            e.state = .loading;
            e.at = ctx.now_ms;
            ctx.act(.{ .interaction = .{ .fetch_commands = sc } });
        }
        return if (e.state == .ready) e.index else null;
    };
    var slot = n_caches;
    if (n_caches == caches.len) {
        // Cheio: sai o mais antigo (menos o do formulário aberto).
        var oldest: i64 = std.math.maxInt(i64);
        for (caches, 0..) |e, i| if (e.at < oldest and e.key != pinnedKey()) {
            oldest = e.at;
            slot = i;
        };
        if (caches[slot].index) |old| ix.freeIndex(old);
    } else n_caches += 1;
    caches[slot] = .{ .key = key, .state = .loading, .at = ctx.now_ms };
    ctx.act(.{ .interaction = .{ .fetch_commands = sc } });
    return null;
}

pub const Found = struct { cmd: *const ix.Command, app: []const u8 };

/// Comandos de barra que valem neste canal (do servidor ou da DM, e os apps
/// da conta). O primeiro `/` num lugar pede o índice; ele chega depois.
pub fn appCommands(ctx: *d.Ctx, ch_id: Id, out: []Found) usize {
    const cs = ctx.store.channel(ch_id) orelse return 0;
    const guild = cs.info.guild;
    const bot_dm = guild == 0 and cs.info.recipient != 0 and if (ctx.store.user(cs.info.recipient)) |u| u.bot else false;
    const place: ix.Place = if (guild != 0) .guild else if (bot_dm) .bot_dm else .private;
    const perms = if (guild != 0) ctx.store.channelPermissions(&cs.info) else 0;
    var n: usize = 0;
    const scopes = [2]ix.Scope{ if (guild != 0) .{ .guild = guild } else .{ .channel = ch_id }, .{ .user = true } };
    for (scopes) |sc| {
        const index = ensure(ctx, sc) orelse continue;
        for (index.commands) |*cmd| {
            if (n == out.len) break;
            // Apps da conta não dependem das permissões do servidor.
            if (cmd.kind != 1 or !ix.usable(cmd, place, if (sc.user) std.math.maxInt(u64) else perms, false)) continue;
            const dup = for (out[0..n]) |f| {
                if (f.cmd.id == cmd.id) break true;
            } else false;
            if (dup) continue;
            out[n] = .{ .cmd = cmd, .app = index.appName(cmd.app) };
            n += 1;
        }
    }
    return n;
}

// --- Eventos da rede --------------------------------------------------------------------

/// Chamado pelo app com cada evento de interação (dono da memória dele).
pub fn onEvent(st: *State, store: *Store, e: ix.Event) void {
    switch (e) {
        .created => {},
        .succeeded => |x| _ = takePending(x.nonce),
        .failed => |x| if (takePending(x.nonce)) |p| {
            if (p.msg != 0) markFailed(store, p.msg) else st.showToast(anim.now_ms, true, "a interação falhou", "the interaction failed", .{});
        },
        .modal => |m| {
            // Só o modal pedido por um clique nosso (nada aparece do nada).
            if (!sentRecently(m.nonce, anim.now_ms)) return ix.freeModal(m);
            _ = takePending(m.nonce);
            openModal(store, m);
        },
        .autocomplete => |cl| {
            if (form) |*f| if (f.ac_nonce != 0 and cl.nonce == f.ac_nonce) {
                if (f.ac_list) |old| ix.freeChoices(old);
                f.ac_list = cl;
                f.ac_nonce = 0;
                return;
            };
            ix.freeChoices(cl);
        },
        .commands => |cm| {
            for (caches[0..n_caches]) |*ent| if (ent.key == cm.key and ent.state == .loading) {
                ent.index = cm.index;
                ent.state = if (cm.index != null) .ready else .failed;
                ent.at = anim.now_ms;
                // A lista do `/` aberta ganha os comandos que acabaram de chegar.
                autocomplete.refreshList();
                return;
            };
            if (cm.index) |i| ix.freeIndex(i);
        },
    }
}

/// Troca de conta ou saída: esquece tudo o que era da conta.
pub fn reset() void {
    closeModal();
    closeForm();
    for (caches[0..n_caches]) |e| if (e.index) |i| ix.freeIndex(i);
    n_caches = 0;
    pending = @splat(.{});
    recent = @splat(.{});
    failed = @splat(0);
    n_dismiss = 0;
    cur = null;
}

/// Algo daqui está aberto por cima da conversa (o app não manda as teclas para a caixa).
pub fn anyOpen() bool {
    return modal != null or form != null;
}

// --- Modal ---------------------------------------------------------------------------------

const max_fields = 10;
const ModalState = struct {
    m: *ix.Modal,
    guild: Id,
    bufs: [max_fields][]u8 = @splat(&.{}),
    masks: [max_fields]u32 = @splat(0),
    ids: [max_fields][25]Id = undefined,
    n_ids: [max_fields]u8 = @splat(0),
    checked: [max_fields]bool = @splat(false),
    tried: bool = false,
    fresh: bool = true,
};
var modal: ?ModalState = null;

fn openModal(store: *Store, m: *ix.Modal) void {
    closeModal();
    var ms: ModalState = .{ .m = m, .guild = if (store.channel(m.channel)) |cs| cs.info.guild else 0 };
    for (m.fields, 0..) |*f, i| switch (f.kind) {
        comp.text_display, comp.file_upload => {},
        comp.text_input => {
            const n = @as(usize, f.max_len) * 4 + 1;
            const b = gpa.alloc(u8, n) catch {
                for (ms.bufs) |x| if (x.len > 0) gpa.free(x);
                ix.freeModal(m);
                return;
            };
            @memset(b, 0);
            const v = d.utf8Prefix(f.value, n - 1);
            @memcpy(b[0..v.len], v);
            ms.bufs[i] = b;
        },
        comp.checkbox => ms.checked[i] = f.checked,
        else => {
            ms.masks[i] = defaultMask(&f.select);
            const k = @min(f.select.defaults.len, 25);
            @memcpy(ms.ids[i][0..k], f.select.defaults[0..k]);
            ms.n_ids[i] = @intCast(k);
        },
    };
    modal = ms;
    dropdown.close();
}

fn closeModal() void {
    if (modal) |*ms| {
        for (ms.bufs) |b| if (b.len > 0) gpa.free(b);
        ix.freeModal(ms.m);
    }
    modal = null;
}

/// A pessoa fechou (ou enviou) o modal: o foco volta para a caixa de texto.
fn dismissModal(ctx: *d.Ctx) void {
    closeModal();
    ctx.st.focus_input = true;
}

fn problemText(p: ix.Problem) []const u8 {
    return switch (p) {
        .none => "",
        .missing => i18n.tr("Obrigatório.", "Required."),
        .too_short => i18n.tr("Curto demais.", "Too short."),
        .too_long => i18n.tr("Longo demais.", "Too long."),
        .not_integer => i18n.tr("Precisa ser um número inteiro.", "Must be a whole number."),
        .not_number => i18n.tr("Precisa ser um número.", "Must be a number."),
        .too_small => i18n.tr("Pequeno demais.", "Too small."),
        .too_large => i18n.tr("Grande demais.", "Too large."),
        .too_few => i18n.tr("Escolha mais opções.", "Pick more options."),
        .too_many => i18n.tr("Opções demais.", "Too many options."),
    };
}

/// Valores escolhidos de um campo de seleção (texto dos itens ou IDs).
fn fieldValues(a: std.mem.Allocator, ms: *const ModalState, i: usize) ![]const []const u8 {
    const f = &ms.m.fields[i];
    var out: std.ArrayList([]const u8) = .empty;
    if (f.kind == comp.string_select or f.kind == comp.radio_group or f.kind == comp.checkbox_group) {
        for (f.select.options, 0..) |o, k| if (ms.masks[i] & (@as(u32, 1) << @intCast(k)) != 0) try out.append(a, o.value);
    } else for (ms.ids[i][0..ms.n_ids[i]]) |id| try out.append(a, try std.fmt.allocPrint(a, "{d}", .{id}));
    return out.toOwnedSlice(a);
}

fn fieldValue(a: std.mem.Allocator, ms: *const ModalState, i: usize) !ix.FieldValue {
    const f = &ms.m.fields[i];
    return switch (f.kind) {
        comp.text_display, comp.file_upload => .none,
        comp.text_input => .{ .text = std.mem.sliceTo(ms.bufs[i], 0) },
        comp.checkbox => .{ .checked = ms.checked[i] },
        comp.radio_group => blk: {
            const vs = try fieldValues(a, ms, i);
            break :blk .{ .text = if (vs.len > 0) vs[0] else "" };
        },
        else => .{ .values = try fieldValues(a, ms, i) },
    };
}

fn fieldProblem(ms: *const ModalState, i: usize) ix.Problem {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const v = fieldValue(fba.allocator(), ms, i) catch return .none;
    return ix.checkField(&ms.m.fields[i], v);
}

fn controlHeight(f: *const ix.Field) f32 {
    return switch (f.kind) {
        comp.text_input => if (f.style == 2) 96 else 36,
        comp.checkbox => 26,
        comp.radio_group, comp.checkbox_group => @as(f32, @floatFromInt(f.select.options.len)) * 30,
        comp.file_upload => 34,
        else => select_h,
    };
}

fn fieldHeight(ctx: *d.Ctx, ms: *const ModalState, i: usize, wd: f32) f32 {
    const f = &ms.m.fields[i];
    if (f.kind == comp.text_display) return inbox.wrapText(null, ctx.ui.get(.regular), 14, 0, 0, wd, f.value, 40, ctx.col(.text)) + 12;
    var h: f32 = 0;
    if (f.label.len > 0 and f.kind != comp.checkbox) h += 22;
    if (f.description.len > 0) h += 18;
    h += controlHeight(f);
    if (ms.tried and fieldProblem(ms, i) != .none) h += 18;
    return h + 14;
}

fn hintZ(buf: []u8, s: []const u8) [*:0]const u8 {
    const t = d.utf8Prefix(s, buf.len - 1);
    // O texto pode já estar no começo de buf (a faixa "mín – máx" de optionHint).
    if (t.ptr != buf.ptr) @memcpy(buf[0..t.len], t);
    buf[t.len] = 0;
    return @ptrCast(buf.ptr);
}

/// Janela por cima de tudo, com o fundo escurecido segurando os cliques.
fn beginDialog(ctx: *d.Ctx, id: [*:0]const u8, r: d.Rect, fresh: bool, dim: bool) *c.ImDrawList {
    if (dim) {
        c.ImGui_SetNextWindowPos(d.v(ctx.win.x, ctx.win.y), 0);
        c.ImGui_SetNextWindowSize(d.v(ctx.win.w, ctx.win.h), 0);
        if (fresh) c.ImGui_SetNextWindowFocus();
        _ = c.ImGui_Begin("##ix-backdrop", null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoBackground | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus);
        d.rect(c.ImGui_GetWindowDrawList(), ctx.win, d.Rgba.black.alpha(0.5), 0);
        c.ImGui_SetCursorScreenPos(d.v(ctx.win.x, ctx.win.y));
        _ = c.ImGui_InvisibleButton("##ix-bd", d.v(ctx.win.w, ctx.win.h), c.ImGuiButtonFlags_MouseButtonLeft | c.ImGuiButtonFlags_MouseButtonRight);
        c.ImGui_End();
    }
    c.ImGui_SetNextWindowPos(d.v(r.x, r.y), 0);
    c.ImGui_SetNextWindowSize(d.v(r.w, r.h), 0);
    if (fresh) c.ImGui_SetNextWindowFocus();
    _ = c.ImGui_Begin(id, null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoBackground | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoScrollWithMouse);
    // Sem foco nenhum (clicou no fundo): a janela volta para a frente.
    if (!fresh and !c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_RootAndChildWindows) and !dropdown.anyOpen() and dim) c.ImGui_SetWindowFocus();
    const dl = c.ImGui_GetWindowDrawList();
    inbox.panelFrame(ctx, dl, r);
    return dl;
}

fn paragraph(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, id: [*:0]const u8, hint: []const u8, buf: []u8, focus: bool) void {
    d.rect(dl, r, ctx.col(.rail).mix(ctx.col(.surface), 0.35), @max(ctx.th.radius, 2));
    if (buf.len > 0 and buf[0] == 0 and hint.len > 0) d.text(dl, ctx.ui.get(.regular), 14, r.x + 11, r.y + 9, ctx.col(.faint), hint);
    c.ImGui_PushFontFloat(ctx.ui.get(.regular), 14);
    c.ImGui_SetCursorScreenPos(d.v(r.x + 6, r.y + 6));
    if (focus) c.ImGui_SetKeyboardFocusHere();
    _ = c.ImGui_InputTextMultilineEx(id, buf.ptr, buf.len, d.v(r.w - 12, r.h - 12), c.ImGuiInputTextFlags_WordWrap, null, null);
    c.ImGui_PopFont();
}

fn drawModal(ctx: *d.Ctx) void {
    const ms = if (modal) |*x| x else return;
    const m = ms.m;
    const fam = ctx.ui;
    const wd: f32 = @min(480, ctx.win.w - 24);
    const inner = wd - 36;
    var content: f32 = 0;
    for (m.fields, 0..) |_, i| content += fieldHeight(ctx, ms, i, inner);
    const head_h: f32 = 60;
    const foot_h: f32 = 62;
    const h = @min(head_h + content + foot_h, ctx.win.h - 24);
    const r = forum.dialogRect(ctx, wd, h);
    const fresh = ms.fresh;
    ms.fresh = false;
    const dl = beginDialog(ctx, "##ix-modal", r, fresh, true);
    defer c.ImGui_End();
    qa.mark(r, "ix-modal", .{});
    _ = d.textClipped(dl, fam.get(.bold), 17, r.x + 18, r.y + 14, ctx.col(.text), m.title, r.w - 36);
    if (m.app_name.len > 0) _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + 18, r.y + 36, ctx.col(.muted), m.app_name, r.w - 36);

    const body: d.Rect = .{ .x = r.x, .y = r.y + head_h, .w = r.w, .h = h - head_h - foot_h };
    const bdl = d.beginRegion(ctx, "##ix-modal-body", body, 0);
    var y = c.ImGui_GetCursorScreenPos().y;
    const x = r.x + 18;
    var focus_next = fresh;
    var enter = false;
    var ib: [16]u8 = undefined;
    var hb_buf: [128]u8 = undefined;
    for (m.fields, 0..) |*f, i| {
        if (f.kind == comp.text_display) {
            y += inbox.wrapText(bdl, fam.get(.regular), 14, x, y, inner, f.value, 40, ctx.col(.text).mix(ctx.col(.muted), 0.15)) + 12;
            continue;
        }
        if (f.label.len > 0 and f.kind != comp.checkbox) {
            const lw = d.textClipped(bdl, fam.get(.bold), 12.5, x, y + 3, ctx.col(.text).mix(ctx.col(.muted), 0.3), f.label, inner - 12);
            if (f.required) d.text(bdl, fam.get(.bold), 12.5, x + lw + 3, y + 3, ctx.col(.danger), "*");
            y += 22;
        }
        if (f.description.len > 0) {
            _ = d.textClipped(bdl, fam.get(.regular), 12, x, y, ctx.col(.muted), f.description, inner);
            y += 18;
        }
        const cr: d.Rect = .{ .x = x, .y = y, .w = inner, .h = controlHeight(f) };
        qa.mark(cr, "ix-field:{d}", .{i});
        const idz = std.fmt.bufPrintSentinel(&ib, "##ixm{d}", .{i}, 0) catch "##ixm";
        switch (f.kind) {
            comp.text_input => {
                if (f.style == 2) {
                    paragraph(ctx, bdl, cr, idz, f.placeholder, ms.bufs[i], focus_next);
                } else {
                    if (focus_next) c.ImGui_SetKeyboardFocusHere();
                    // Enter no campo de uma linha envia, como no formulário dos comandos.
                    if (forum.textInput(ctx, bdl, cr, idz, hintZ(&hb_buf, f.placeholder), ms.bufs[i], c.ImGuiInputTextFlags_EnterReturnsTrue)) enter = true;
                }
                focus_next = false;
            },
            comp.checkbox => {
                const hb = d.hit(ctx, 0x1A7E_0100 + i, cr);
                checkBox(ctx, bdl, x, cr.y + cr.h / 2, ms.checked[i], false);
                _ = d.textClipped(bdl, fam.get(.medium), 13.5, x + 26, d.centerY(cr, 13.5), ctx.col(.text), f.label, inner - 30);
                if (hb.clicked) ms.checked[i] = !ms.checked[i];
            },
            comp.radio_group, comp.checkbox_group => {
                const round = f.kind == comp.radio_group;
                for (f.select.options, 0..) |o, k| {
                    const rr: d.Rect = .{ .x = x, .y = y + @as(f32, @floatFromInt(k)) * 30, .w = inner, .h = 30 };
                    const bit = @as(u32, 1) << @intCast(k);
                    const on = ms.masks[i] & bit != 0;
                    const hb = d.hit(ctx, 0x1A7E_0200 + i * 32 + k, rr);
                    if (hb.hovered) d.rect(bdl, rr, ctx.col(.hover), radius(ctx));
                    checkBox(ctx, bdl, x + 6, rr.y + 15, on, round);
                    _ = d.textClipped(bdl, fam.get(.medium), 13.5, x + 30, d.centerY(rr, 13.5), ctx.col(.text), o.label, inner - 36);
                    if (hb.clicked) {
                        if (round) {
                            ms.masks[i] = if (on and !f.required) 0 else bit;
                        } else if (on) {
                            ms.masks[i] &= ~bit;
                        } else if (@popCount(ms.masks[i]) < f.select.max) ms.masks[i] |= bit;
                    }
                }
            },
            comp.file_upload => {
                // Envio de arquivo pelo modal ainda não: dizemos, sem fingir.
                d.rect(bdl, cr, ctx.col(.text).alpha(0.05), radius(ctx));
                _ = d.textClipped(bdl, fam.get(.regular), 12.5, x + 10, d.centerY(cr, 12.5), ctx.col(.muted), i18n.tr("Envio de arquivo em modal: use o app oficial.", "File upload in modals: use the official app."), inner - 20);
            },
            else => modalSelect(ctx, bdl, ms, i, cr),
        }
        y += cr.h;
        if (ms.tried) {
            const p = fieldProblem(ms, i);
            if (p != .none) {
                d.text(bdl, fam.get(.regular), 12, x, y + 3, ctx.col(.danger), problemText(p));
                y += 18;
            }
        }
        y += 14;
    }
    d.endRegion(ctx, y, x);

    // Rodapé.
    const lbl = i18n.tr("Enviar", "Submit");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - bw, .y = r.bottom() - 48, .w = bw, .h = 34 };
    qa.mark(br, "ix-modal-submit", .{});
    const submit = forum.primary(ctx, dl, fam, 0x1A7E_0300, br, lbl, m.app != 0);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "ix-modal-cancel", .{});
    if (inbox.button(ctx, dl, 0x1A7E_0301, cr, cancel, false)) return dismissModal(ctx);
    const esc = c.ImGui_IsKeyPressed(c.ImGuiKey_Escape) and !dropdown.ownsEsc();
    if (esc) return dismissModal(ctx);
    if (submit or (enter and m.app != 0)) submitModal(ctx, ms);
}

fn modalSelect(ctx: *d.Ctx, dl: *c.ImDrawList, ms: *ModalState, i: usize, r: d.Rect) void {
    const f = &ms.m.fields[i];
    const dd_key: usize = @truncate(ms.m.id *% 31 +% i +% 0x40D_A1);
    const open = dropdown.isOpen(dd_key);
    const hb = d.hit(ctx, 0x1A7E_0400 + i, r);
    boxFrame(ctx, dl, r, hb.hovered, open, 1);
    var sb: [256]u8 = undefined;
    const sm = summary(ctx, &sb, &f.select, ms.masks[i], ms.ids[i][0..ms.n_ids[i]]);
    _ = d.textClipped(dl, ctx.ui.get(.regular), 14, r.x + 12, d.centerY(r, 14), if (sm.hint) ctx.col(.faint) else ctx.col(.text), sm.text, r.w - 44);
    icons.chevron(dl, r.right() - 18, r.y + r.h / 2, ctx.col(.muted).u(), if (open) 1 else 0);
    if (hb.clicked) {
        if (!open) pickerInit(dd_key, ms.masks[i], ms.ids[i][0..ms.n_ids[i]]);
        dropdown.toggle(dd_key);
    }
    if (pk.key == dd_key and dropdown.isOpen(dd_key)) {
        const done = picker(ctx, r, &f.select, ms.m.channel, "OK");
        // Num menu de vários, o que se marca já vale (o botão só fecha).
        if (done or f.select.max > 1) {
            ms.masks[i] = pk.mask;
            @memcpy(ms.ids[i][0..pk.n], pk.ids[0..pk.n]);
            ms.n_ids[i] = pk.n;
        }
    }
}

fn submitModal(ctx: *d.Ctx, ms: *ModalState) void {
    const m = ms.m;
    for (m.fields, 0..) |_, i| if (fieldProblem(ms, i) != .none) {
        ms.tried = true;
        return;
    };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var vals: [max_fields]ix.FieldValue = undefined;
    for (m.fields, 0..) |_, i| vals[i] = fieldValue(arena.allocator(), ms, i) catch return;
    const data = ix.modalData(gpa, m, vals[0..m.fields.len]) catch return;
    const nonce = nextNonce(ctx.now_ms);
    send(ctx, .{ .kind = .modal_submit, .app = m.app, .guild = ms.guild, .channel = m.channel, .nonce = nonce, .data = data });
    addPending(nonce, 0, 0, ctx.now_ms);
    dismissModal(ctx);
}

// --- Formulário do comando de barra -----------------------------------------------------------

const max_opts = 25;
const FormState = struct {
    cache_key: Id,
    cmd: *const ix.Command,
    app_name: []const u8,
    channel: Id,
    guild: Id,
    path: [2]*const ix.CmdOption = undefined,
    path_len: u8 = 0,
    /// Já sabe qual subcomando (ou o comando não tem).
    chosen: bool = false,
    leaf: []const ix.CmdOption = &.{},
    bufs: [max_opts][]u8 = @splat(&.{}),
    /// Nome mostrado de uma escolha (pessoa, canal, sugestão); 0 = digitando.
    names: [max_opts][64]u8 = undefined,
    name_len: [max_opts]u8 = @splat(0),
    tried: bool = false,
    fresh: bool = true,
    /// Autocompletar: o campo, quando pedir, o pedido em voo e a lista que veio.
    ac_field: usize = 0,
    ac_due: i64 = 0,
    ac_nonce: u64 = 0,
    ac_list: ?*ix.ChoiceList = null,
    ac_shown: ?usize = null,
    /// Onde fica o campo com a lista de sugestões aberta (neste quadro).
    ac_rect: ?d.Rect = null,
    active: ?usize = null,
    /// O arquivo de cada opção de anexo (c_allocator), escolhido pelo "Escolher
    /// arquivo" do próprio formulário: o que está na bandeja da caixa não entra.
    files: [max_opts]?[:0]u8 = @splat(null),
    /// A opção de anexo esperando o seletor de arquivos responder.
    picking: ?usize = null,
};
var form: ?FormState = null;

/// O mesmo limite dos anexos da caixa (App.attachFile): o do Discord sem Nitro.
const max_upload: u64 = 10 * 1024 * 1024;

fn clearFiles(fs: *FormState) void {
    for (&fs.files) |*f| if (f.*) |p| {
        std.heap.c_allocator.free(p);
        f.* = null;
    };
    fs.picking = null;
}

/// O seletor de arquivos devolveu `path`: é da opção de anexo que pediu? Se não
/// for (nenhuma pediu, ou o formulário fechou), ele vai para a bandeja da caixa.
pub fn takePicked(st: *State, now_ms: i64, path: [:0]const u8) bool {
    const fs = if (form) |*f| f else return false;
    const i = fs.picking orelse return false;
    fs.picking = null;
    if (i >= fs.leaf.len or fs.leaf[i].kind != ix.opt.attachment) return false;
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path.ptr, &info) or info.type != c.SDL_PATHTYPE_FILE) {
        st.showToast(now_ms, true, "não consegui abrir esse arquivo", "couldn't open that file", .{});
    } else if (info.size > max_upload) {
        st.showToast(now_ms, true, "arquivo maior que 10 MB (limite do Discord sem Nitro)", "file larger than 10 MB (Discord's limit without Nitro)", .{});
    } else if (std.heap.c_allocator.dupeSentinel(u8, path, 0)) |p| {
        if (fs.files[i]) |old| std.heap.c_allocator.free(old);
        fs.files[i] = p;
    } else |_| {}
    return true;
}

fn setLeaf(fs: *FormState, opts: []const ix.CmdOption) void {
    for (&fs.bufs) |*b| if (b.len > 0) {
        gpa.free(b.*);
        b.* = &.{};
    };
    clearFiles(fs);
    fs.leaf = opts[0..@min(opts.len, max_opts)];
    fs.name_len = @splat(0);
    for (fs.leaf, 0..) |*o, i| {
        const n: usize = if (o.kind == ix.opt.string and o.choices.len == 0) @as(usize, o.max_len) * 4 + 1 else 128;
        fs.bufs[i] = gpa.alloc(u8, n) catch &.{};
        @memset(fs.bufs[i], 0);
    }
    fs.chosen = true;
    fs.fresh = true;
}

fn closeForm() void {
    if (form) |*fs| {
        for (fs.bufs) |b| if (b.len > 0) gpa.free(b);
        if (fs.ac_list) |l| ix.freeChoices(l);
        clearFiles(fs);
    }
    form = null;
}

/// A pessoa fechou o formulário (Esc ou ×): o foco volta para a caixa de texto.
fn dismissForm(ctx: *d.Ctx) void {
    closeForm();
    ctx.st.focus_input = true;
}

/// Escolheu um comando na lista do `/`: abre o formulário dele.
pub fn openCommand(ctx: *d.Ctx, ch_id: Id, cmd_id: Id) bool {
    const cs = ctx.store.channel(ch_id) orelse return false;
    for (caches[0..n_caches]) |*e| {
        const index = e.index orelse continue;
        for (index.commands) |*cmd| if (cmd.id == cmd_id) {
            closeForm();
            dropdown.close();
            form = .{ .cache_key = e.key, .cmd = cmd, .app_name = index.appName(cmd.app), .channel = ch_id, .guild = cs.info.guild };
            if (!cmd.hasSubs()) setLeaf(&form.?, cmd.options);
            return true;
        };
    }
    return false;
}

fn bufText(fs: *const FormState, i: usize) []const u8 {
    return if (fs.bufs[i].len > 0) std.mem.sliceTo(fs.bufs[i], 0) else "";
}

fn setBuf(fs: *FormState, i: usize, text: []const u8, shown: []const u8) void {
    const b = fs.bufs[i];
    if (b.len == 0) return;
    @memset(b, 0);
    const t = d.utf8Prefix(text, b.len - 1);
    @memcpy(b[0..t.len], t);
    const s = d.utf8Prefix(shown, fs.names[i].len);
    @memcpy(fs.names[i][0..s.len], s);
    fs.name_len[i] = @intCast(s.len);
}

/// Texto que a validação vê (o anexo vale pelo nome do arquivo escolhido para ele).
fn optionText(fs: *const FormState, i: usize) []const u8 {
    if (fs.leaf[i].kind == ix.opt.attachment) return if (fs.files[i]) |p| std.fs.path.basename(p) else "";
    return bufText(fs, i);
}

fn entityKind(o: *const ix.CmdOption) u8 {
    return switch (o.kind) {
        ix.opt.user => comp.user_select,
        ix.opt.channel => comp.channel_select,
        ix.opt.role => comp.role_select,
        else => comp.mentionable_select,
    };
}

fn optionHint(buf: []u8, o: *const ix.CmdOption) [*:0]const u8 {
    const t: []const u8 = switch (o.kind) {
        ix.opt.integer, ix.opt.number => blk: {
            if (o.min_value != null and o.max_value != null) break :blk std.fmt.bufPrint(buf[0 .. buf.len - 1], "{d} – {d}", .{ o.min_value.?, o.max_value.? }) catch "";
            break :blk if (o.kind == ix.opt.integer) i18n.tr("número inteiro", "whole number") else i18n.tr("número", "number");
        },
        else => if (o.autocomplete) i18n.tr("Digite para ver sugestões", "Type to see suggestions") else o.description,
    };
    return hintZ(buf, t);
}

const opt_label_h: f32 = 20;
const opt_ctrl_h: f32 = 34;

fn optionHeight(fs: *const FormState, i: usize) f32 {
    var h: f32 = opt_label_h + opt_ctrl_h + 12;
    if (fs.tried and ix.checkOption(&fs.leaf[i], optionText(fs, i)) != .none) h += 16;
    return h;
}

/// Subcomandos para escolher (grupo + subcomando viram uma linha só).
fn subRows(cmd: *const ix.Command, out: [][2]?*const ix.CmdOption) usize {
    var n: usize = 0;
    for (cmd.options) |*o| {
        if (o.kind == ix.opt.sub_command) {
            if (n < out.len) out[n] = .{ o, null };
            n += 1;
        } else if (o.kind == ix.opt.sub_command_group) for (o.options) |*sub| {
            if (n < out.len) out[n] = .{ o, sub };
            n += 1;
        };
    }
    return @min(n, out.len);
}

fn drawForm(ctx: *d.Ctx) void {
    const fs = if (form) |*x| x else return;
    const cmd = fs.cmd;
    const fam = ctx.ui;
    // Fica onde a lista do `/` ficava: logo acima da caixa de texto.
    var anchor = autocomplete.anchorRect();
    if (anchor.w < 100) anchor = .{ .x = ctx.win.x + 24, .y = ctx.win.bottom() - 80, .w = @min(640, ctx.win.w - 48), .h = 0 };
    const wd = @min(anchor.w, ctx.win.w - 24);
    var subs: [max_opts][2]?*const ix.CmdOption = undefined;
    const n_subs = if (fs.chosen) 0 else subRows(cmd, &subs);
    var content: f32 = 0;
    if (!fs.chosen) {
        content = @as(f32, @floatFromInt(n_subs)) * 40;
    } else for (fs.leaf, 0..) |_, i| {
        content += optionHeight(fs, i);
    }
    if (fs.chosen and fs.leaf.len == 0) content = 4;
    const head_h: f32 = if (cmd.description.len > 0) 62 else 44;
    const foot_h: f32 = if (fs.chosen) 52 else 12;
    const max_h = @max(anchor.y - ctx.win.y - 16, 160);
    const h = @min(head_h + content + foot_h, max_h);
    const r: d.Rect = .{ .x = anchor.x + (anchor.w - wd) / 2, .y = @max(anchor.y - h - 8, ctx.win.y + 8), .w = wd, .h = h };
    const fresh = fs.fresh;
    fs.fresh = false;
    const dl = beginDialog(ctx, "##ix-form", r, fresh, false);
    defer c.ImGui_End();
    qa.mark(r, "ix-form", .{});

    // Cabeçalho: /comando subcomando · app
    var tb: [160]u8 = undefined;
    var title_len: usize = 0;
    if (std.fmt.bufPrint(&tb, "/{s}", .{cmd.label})) |t| title_len = t.len else |_| {}
    for (fs.path[0..fs.path_len]) |p| {
        if (std.fmt.bufPrint(tb[title_len..], " {s}", .{p.label})) |t| title_len += t.len else |_| {}
    }
    const tw = d.textClipped(dl, fam.get(.bold), 15, r.x + 16, r.y + 12, ctx.col(.text), tb[0..title_len], r.w - 120);
    if (fs.app_name.len > 0) _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + 16 + tw + 10, r.y + 14, ctx.col(.muted), fs.app_name, r.w - tw - 80);
    const desc = if (fs.path_len > 0) fs.path[fs.path_len - 1].description else cmd.description;
    if (desc.len > 0) _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + 16, r.y + 36, ctx.col(.muted), desc, r.w - 32);
    const xr: d.Rect = .{ .x = r.right() - 36, .y = r.y + 8, .w = 26, .h = 26 };
    const xh = d.hit(ctx, 0x1A7E_0500, xr);
    qa.mark(xr, "ix-form-close", .{});
    if (xh.hovered) d.rect(dl, xr, ctx.col(.hover), radius(ctx));
    d.line(dl, xr.x + 8, xr.y + 8, xr.right() - 8, xr.bottom() - 8, ctx.col(.muted), 1.5);
    d.line(dl, xr.right() - 8, xr.y + 8, xr.x + 8, xr.bottom() - 8, ctx.col(.muted), 1.5);
    if (xh.clicked) return dismissForm(ctx);
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Escape) and !dropdown.ownsEsc()) return dismissForm(ctx);

    const body: d.Rect = .{ .x = r.x, .y = r.y + head_h, .w = r.w, .h = h - head_h - foot_h };
    const bdl = d.beginRegion(ctx, "##ix-form-body", body, 0);
    var y = c.ImGui_GetCursorScreenPos().y;
    const x = r.x + 16;
    const inner = r.w - 32;
    if (!fs.chosen) {
        for (subs[0..n_subs], 0..) |pair, k| {
            const row: d.Rect = .{ .x = x - 6, .y = y, .w = inner + 12, .h = 38 };
            const hb = d.hit(ctx, 0x1A7E_0600 + k, row);
            qa.mark(row, "ix-sub:{d}", .{k});
            if (hb.hovered) d.rect(bdl, row, ctx.col(.hover), radius(ctx));
            const leaf = pair[1] orelse pair[0].?;
            var nb: [80]u8 = undefined;
            const name = if (pair[1] != null) std.fmt.bufPrint(&nb, "{s} {s}", .{ pair[0].?.label, leaf.label }) catch leaf.label else leaf.label;
            const nw = d.textClipped(bdl, fam.get(.semibold), 14, x, d.centerY(row, 14), ctx.col(.text), name, inner * 0.5);
            _ = d.textClipped(bdl, fam.get(.regular), 12.5, x + nw + 12, d.centerY(row, 12.5), ctx.col(.muted), leaf.description, inner - nw - 12);
            if (hb.clicked) {
                fs.path[0] = pair[0].?;
                fs.path_len = 1;
                if (pair[1]) |sub| {
                    fs.path[1] = sub;
                    fs.path_len = 2;
                }
                setLeaf(fs, leaf.options);
            }
            y += 40;
        }
        d.endRegion(ctx, y, x);
        return;
    }
    var submit = false;
    var focus_next = fresh;
    var ac_rect: ?d.Rect = null;
    fs.ac_rect = null;
    var now_active: ?usize = null;
    var ib: [16]u8 = undefined;
    var hb_buf: [128]u8 = undefined;
    for (fs.leaf, 0..) |*o, i| {
        const lw = d.textClipped(bdl, fam.get(.semibold), 13, x, y + 2, ctx.col(.text), o.label, inner * 0.45);
        var lx = x + lw;
        if (o.required) {
            d.text(bdl, fam.get(.bold), 13, lx + 3, y + 2, ctx.col(.danger), "*");
            lx += 12;
        }
        _ = d.textClipped(bdl, fam.get(.regular), 12, lx + 10, y + 3, ctx.col(.muted), o.description, inner - (lx - x) - 10);
        y += opt_label_h;
        const cr: d.Rect = .{ .x = x, .y = y, .w = inner, .h = opt_ctrl_h };
        qa.mark(cr, "ix-opt:{s}", .{o.name});
        const idz = std.fmt.bufPrintSentinel(&ib, "##ixo{d}", .{i}, 0) catch "##ixo";
        if (o.choices.len > 0) {
            choiceBox(ctx, bdl, fs, i, cr);
        } else switch (o.kind) {
            ix.opt.boolean => {
                for ([_][]const u8{ "true", "false" }, 0..) |val, k| {
                    const lbl = if (k == 0) i18n.tr("Sim", "True") else i18n.tr("Não", "False");
                    const bw = d.width(fam.get(.medium), 13, lbl) + 28;
                    const br: d.Rect = .{ .x = x + @as(f32, @floatFromInt(k)) * (bw + 8), .y = cr.y + 3, .w = bw, .h = cr.h - 6 };
                    const on = std.mem.eql(u8, bufText(fs, i), val);
                    const hb = d.hit(ctx, 0x1A7E_0700 + i * 2 + k, br);
                    qa.mark(br, "ix-bool:{s}:{s}", .{ o.name, val });
                    d.rect(bdl, br, if (on) ctx.col(.accent) else if (hb.hovered) ctx.col(.hover) else ctx.col(.text).alpha(0.07), radius(ctx));
                    d.text(bdl, fam.get(.medium), 13, br.x + 14, d.centerY(br, 13), if (on) ctx.col(.accent_text) else ctx.col(.text), lbl);
                    if (hb.clicked) setBuf(fs, i, if (on) "" else val, "");
                }
            },
            ix.opt.user, ix.opt.channel, ix.opt.role, ix.opt.mentionable => entityBox(ctx, bdl, fs, i, cr),
            ix.opt.attachment => {
                const lbl = i18n.tr("Escolher arquivo", "Choose file");
                const bw = d.width(fam.get(.medium), 13, lbl) + 28;
                const br: d.Rect = .{ .x = x, .y = cr.y + 3, .w = bw, .h = cr.h - 6 };
                const hb = d.hit(ctx, 0x1A7E_0800 + i, br);
                qa.mark(br, "ix-file:{s}", .{o.name});
                d.rect(bdl, br, if (hb.hovered) ctx.col(.hover) else ctx.col(.text).alpha(0.07), radius(ctx));
                d.text(bdl, fam.get(.medium), 13, br.x + 14, d.centerY(br, 13), ctx.col(.text), lbl);
                // O arquivo escolhido aqui é só desta opção (takePicked); a bandeja da caixa fica como está.
                if (hb.clicked) {
                    fs.picking = i;
                    ctx.act(.pick_file);
                }
                const file = fs.files[i];
                const shown = if (file) |p| std.fs.path.basename(p) else i18n.tr("nenhum arquivo", "no file");
                const nx = br.right() + 12;
                const nw = d.textClipped(bdl, fam.get(.regular), 13, nx, d.centerY(cr, 13), if (file != null) ctx.col(.text) else ctx.col(.faint), shown, inner - bw - 12 - 30);
                if (file != null) {
                    // O × tira o arquivo (a opção pode ser opcional).
                    const fx: d.Rect = .{ .x = nx + nw + 4, .y = cr.y + 5, .w = 24, .h = cr.h - 10 };
                    const fh = d.hit(ctx, 0x1A7E_0D00 + i, fx);
                    qa.mark(fx, "ix-file-clear:{s}", .{o.name});
                    const col = if (fh.hovered) ctx.col(.text) else ctx.col(.muted);
                    d.line(bdl, fx.x + 7, fx.y + 7, fx.right() - 7, fx.bottom() - 7, col, 1.5);
                    d.line(bdl, fx.right() - 7, fx.y + 7, fx.x + 7, fx.bottom() - 7, col, 1.5);
                    if (fh.clicked) if (fs.files[i]) |p| {
                        std.heap.c_allocator.free(p);
                        fs.files[i] = null;
                    };
                }
            },
            else => {
                if (fs.name_len[i] > 0) {
                    // Sugestão escolhida: mostra o nome; o × volta a digitar.
                    chip(ctx, bdl, fs, i, cr);
                } else {
                    if (focus_next) c.ImGui_SetKeyboardFocusHere();
                    focus_next = false;
                    if (forum.textInput(ctx, bdl, cr, idz, optionHint(&hb_buf, o), fs.bufs[i], c.ImGuiInputTextFlags_EnterReturnsTrue)) submit = true;
                    if (c.ImGui_IsItemActive()) now_active = i;
                    if (o.autocomplete) {
                        // Pede depois que a pessoa para de digitar (e ao entrar no campo).
                        if (c.ImGui_IsItemEdited() or (c.ImGui_IsItemActivated() and fs.ac_shown != i)) {
                            fs.ac_field = i;
                            fs.ac_due = ctx.now_ms + (if (c.ImGui_IsItemEdited()) @as(i64, 300) else 0);
                            anim.at(fs.ac_due);
                        }
                        // O clique numa sugestão tira o foco do campo neste mesmo quadro, antes de a
                        // lista ser desenhada: no quadro em que ele sai, ela ainda aparece para
                        // receber o clique (fora dela, some no quadro seguinte).
                        const focused = c.ImGui_IsItemActive() or (c.ImGui_IsItemDeactivated() and c.ImGui_IsMouseClicked(0));
                        if (focused and fs.ac_shown == i and fs.ac_list != null and fs.ac_list.?.choices.len > 0) ac_rect = cr;
                    }
                }
            },
        }
        y += opt_ctrl_h;
        if (fs.tried) {
            const p = ix.checkOption(o, optionText(fs, i));
            if (p != .none) {
                d.text(bdl, fam.get(.regular), 12, x, y + 1, ctx.col(.danger), problemText(p));
                y += 16;
            }
        }
        y += 12;
    }
    d.endRegion(ctx, y, x);
    fs.active = now_active;
    fs.ac_rect = ac_rect;

    const lbl = i18n.tr("Enviar", "Send");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 16 - bw, .y = r.bottom() - 44, .w = bw, .h = 32 };
    qa.mark(br, "ix-form-send", .{});
    if (forum.primary(ctx, dl, fam, 0x1A7E_0900, br, lbl, true)) submit = true;
    if (submit) submitForm(ctx, fs);
}

fn chip(ctx: *d.Ctx, dl: *c.ImDrawList, fs: *FormState, i: usize, r: d.Rect) void {
    const fam = ctx.ui;
    d.rect(dl, r, ctx.col(.rail).mix(ctx.col(.surface), 0.35), radius(ctx));
    const name = fs.names[i][0..fs.name_len[i]];
    _ = d.textClipped(dl, fam.get(.medium), 14, r.x + 12, d.centerY(r, 14), ctx.col(.text), name, r.w - 50);
    const xr: d.Rect = .{ .x = r.right() - 30, .y = r.y + 5, .w = 24, .h = r.h - 10 };
    const hb = d.hit(ctx, 0x1A7E_0A00 + i, xr);
    qa.mark(xr, "ix-clear:{d}", .{i});
    const col = if (hb.hovered) ctx.col(.text) else ctx.col(.muted);
    d.line(dl, xr.x + 7, xr.y + 7, xr.right() - 7, xr.bottom() - 7, col, 1.5);
    d.line(dl, xr.right() - 7, xr.y + 7, xr.x + 7, xr.bottom() - 7, col, 1.5);
    if (hb.clicked) {
        setBuf(fs, i, "", "");
        fs.fresh = true;
    }
}

/// Opção com escolhas fixas: uma lista para escolher.
fn choiceBox(ctx: *d.Ctx, dl: *c.ImDrawList, fs: *FormState, i: usize, r: d.Rect) void {
    const o = &fs.leaf[i];
    const dd_key: usize = @truncate(fs.cmd.id *% 31 +% i +% 0xC401CE);
    const open = dropdown.isOpen(dd_key);
    const hb = d.hit(ctx, 0x1A7E_0B00 + i, r);
    boxFrame(ctx, dl, r, hb.hovered, open, 1);
    const shown = if (fs.name_len[i] > 0) fs.names[i][0..fs.name_len[i]] else i18n.tr("Escolha uma opção", "Choose an option");
    _ = d.textClipped(dl, ctx.ui.get(.regular), 14, r.x + 12, d.centerY(r, 14), if (fs.name_len[i] > 0) ctx.col(.text) else ctx.col(.faint), shown, r.w - 44);
    icons.chevron(dl, r.right() - 18, r.y + r.h / 2, ctx.col(.muted).u(), if (open) 1 else 0);
    if (hb.clicked) dropdown.toggle(dd_key);
    var p = dropdown.begin(ctx, dd_key, r, r.w, @as(f32, @floatFromInt(o.choices.len)) * 32) orelse return;
    defer p.end();
    for (o.choices, 0..) |ch, k| {
        const on = std.mem.eql(u8, bufText(fs, i), ch.value);
        const row = p.row(32, on);
        qa.mark(row.rect, "ix-choice:{d}", .{k});
        _ = d.textClipped(p.dl, ctx.ui.get(.medium), 13.5, row.rect.x + 10, d.centerY(row.rect, 13.5), ctx.col(.text), ch.name, row.rect.w - 20);
        if (row.hit.clicked) {
            setBuf(fs, i, ch.value, ch.name);
            dropdown.close();
        }
    }
}

/// Pessoa, canal, cargo ou menção: a mesma lista dos menus, com um item só.
fn entityBox(ctx: *d.Ctx, dl: *c.ImDrawList, fs: *FormState, i: usize, r: d.Rect) void {
    const o = &fs.leaf[i];
    const dd_key: usize = @truncate(fs.cmd.id *% 31 +% i +% 0xE7717);
    const open = dropdown.isOpen(dd_key);
    const hb = d.hit(ctx, 0x1A7E_0C00 + i, r);
    boxFrame(ctx, dl, r, hb.hovered, open, 1);
    const shown = if (fs.name_len[i] > 0) fs.names[i][0..fs.name_len[i]] else i18n.tr("Escolha…", "Choose…");
    _ = d.textClipped(dl, ctx.ui.get(.regular), 14, r.x + 12, d.centerY(r, 14), if (fs.name_len[i] > 0) ctx.col(.text) else ctx.col(.faint), shown, r.w - 44);
    icons.chevron(dl, r.right() - 18, r.y + r.h / 2, ctx.col(.muted).u(), if (open) 1 else 0);
    if (hb.clicked) {
        if (!open) {
            const cur_id = std.fmt.parseInt(Id, bufText(fs, i), 10) catch 0;
            pickerInit(dd_key, 0, if (cur_id != 0) &.{cur_id} else &.{});
        }
        dropdown.toggle(dd_key);
    }
    if (pk.key != dd_key or !dropdown.isOpen(dd_key)) return;
    const sel: ix.Select = .{ .kind = entityKind(o), .min = 0, .max = 1, .channel_types = o.channel_types };
    if (picker(ctx, r, &sel, fs.channel, "OK")) {
        if (pk.n == 0) return setBuf(fs, i, "", "");
        var nb: [24]u8 = undefined;
        setBuf(fs, i, std.fmt.bufPrint(&nb, "{d}", .{pk.ids[0]}) catch "", entityName(ctx, pk.ids[0]));
    }
}

/// Para o QA: o ImGui diz que o mouse está sobre a lista (ela é a janela da frente ali).
pub var qa_ac_hovered = false;

/// Lista do autocompletar embaixo do campo, numa janela por cima do
/// formulário (recebe o mouse antes dos campos que ficam embaixo dela).
fn acWindow(ctx: *d.Ctx, fs: *FormState) void {
    qa_ac_hovered = false;
    const field = fs.ac_rect orelse return;
    const list = fs.ac_list orelse return;
    const k = fs.ac_shown orelse return;
    const rows = @min(list.choices.len, 8);
    const row_h: f32 = 30;
    const h = @as(f32, @floatFromInt(rows)) * row_h + 8;
    var r: d.Rect = .{ .x = field.x, .y = field.bottom() + 2, .w = field.w, .h = h };
    if (r.bottom() > ctx.win.bottom() - 4) r.y = field.y - h - 2;
    c.ImGui_SetNextWindowPos(d.v(r.x, r.y), 0);
    c.ImGui_SetNextWindowSize(d.v(r.w, r.h), 0);
    // Sem pegar o foco ao aparecer: o campo continua sendo digitado.
    _ = c.ImGui_Begin("##ix-ac", null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoBackground | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoFocusOnAppearing | c.ImGuiWindowFlags_NoNav);
    defer c.ImGui_End();
    // Sem o foco, o ImGui não a traz para a frente quando ela volta: a partir da
    // segunda vez ficava embaixo do formulário (que pega o foco ao abrir).
    d.windowToFront();
    if (qa.on()) qa_ac_hovered = c.ImGui_IsWindowHovered(0);
    const dl = c.ImGui_GetWindowDrawList();
    d.shadow(dl, r, radius(ctx), 10, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.elevated), radius(ctx));
    d.border(dl, r, ctx.col(.border), radius(ctx), 1);
    qa.mark(r, "ix-ac", .{});
    for (list.choices[0..rows], 0..) |ch, i| {
        const row: d.Rect = .{ .x = r.x + 4, .y = r.y + 4 + @as(f32, @floatFromInt(i)) * row_h, .w = r.w - 8, .h = row_h };
        const over = row.contains(ctx.mouse.x, ctx.mouse.y);
        qa.mark(row, "ix-ac:{d}", .{i});
        if (over) d.rect(dl, row, ctx.col(.hover), radius(ctx));
        _ = d.textClipped(dl, ctx.ui.get(.medium), 13.5, row.x + 8, d.centerY(row, 13.5), ctx.col(.text), ch.name, row.w - 16);
        if (over) {
            c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
            ctx.hot = true;
        }
        // Na descida do botão: o campo perde o foco neste mesmo quadro.
        if (over and c.ImGui_IsMouseClicked(0)) {
            setBuf(fs, k, ch.value, ch.name);
            fs.ac_shown = null;
            fs.ac_rect = null;
            return;
        }
    }
}

/// Pede as sugestões do campo com autocompletar (o tempo de espera já passou).
fn requestAutocomplete(ctx: *d.Ctx, fs: *FormState) void {
    fs.ac_due = 0;
    const i = fs.ac_field;
    if (i >= fs.leaf.len) return;
    var vals: [max_opts]ix.OptValue = undefined;
    var n: usize = 0;
    for (fs.leaf, 0..) |*o, k| {
        if (o.kind == ix.opt.attachment) continue;
        const t = bufText(fs, k);
        if (k != i and t.len == 0) continue;
        vals[n] = .{ .opt = o, .text = t, .focused = k == i };
        n += 1;
    }
    const data = ix.commandData(gpa, fs.cmd, fs.path[0..fs.path_len], vals[0..n], &.{}) catch return;
    const nonce = nextNonce(ctx.now_ms);
    send(ctx, .{ .kind = .autocomplete, .app = fs.cmd.app, .guild = fs.guild, .channel = fs.channel, .nonce = nonce, .data = data });
    fs.ac_nonce = nonce;
    fs.ac_shown = i;
    if (fs.ac_list) |old| {
        ix.freeChoices(old);
        fs.ac_list = null;
    }
}

fn submitForm(ctx: *d.Ctx, fs: *FormState) void {
    for (fs.leaf, 0..) |*o, i| if (ix.checkOption(o, optionText(fs, i)) != .none) {
        fs.tried = true;
        return;
    };
    var vals: [max_opts]ix.OptValue = undefined;
    var names: [max_opts][]const u8 = undefined;
    var paths: [max_opts][:0]const u8 = undefined;
    var n: usize = 0;
    var n_files: usize = 0;
    for (fs.leaf, 0..) |*o, i| {
        const t = optionText(fs, i);
        if (t.len == 0) continue;
        if (o.kind == ix.opt.attachment) {
            names[n_files] = t;
            paths[n_files] = fs.files[i].?;
            n_files += 1;
        }
        vals[n] = .{ .opt = o, .text = t };
        n += 1;
    }
    const data = ix.commandData(gpa, fs.cmd, fs.path[0..fs.path_len], vals[0..n], names[0..n_files]) catch return;
    var files: []const [:0]const u8 = &.{};
    if (n_files > 0) {
        const list = gpa.alloc([:0]const u8, n_files) catch return gpa.free(data);
        for (list, paths[0..n_files], 0..) |*dst, src, k| dst.* = gpa.dupeSentinel(u8, src, 0) catch {
            for (list[0..k]) |x| gpa.free(x);
            gpa.free(list);
            gpa.free(data);
            return;
        };
        files = list;
    }
    const nonce = nextNonce(ctx.now_ms);
    send(ctx, .{ .kind = .command, .app = fs.cmd.app, .guild = fs.guild, .channel = fs.channel, .nonce = nonce, .data = data, .files = files });
    addPending(nonce, 0, 0, ctx.now_ms);
    closeForm();
    ctx.st.focus_input = true;
}

// --- A cada quadro ---------------------------------------------------------------------------

/// No fim do quadro, por cima do resto: descartes, prazos, autocompletar,
/// o formulário e o modal.
pub fn draw(ctx: *d.Ctx) void {
    for (dismiss_q[0..n_dismiss]) |x| ctx.store.apply(.{ .message_delete = .{ .channel = x.channel, .id = x.id, .local = true } }, ctx.now_ms) catch {};
    n_dismiss = 0;
    for (&pending) |*p| if (p.nonce != 0) {
        if (ctx.now_ms - p.at >= timeout_ms) {
            if (p.msg != 0) markFailed(ctx.store, p.msg) else ctx.st.showToast(ctx.now_ms, true, "a interação falhou", "the interaction failed", .{});
            p.* = .{};
        } else anim.at(p.at + timeout_ms);
    };
    // Mudou de conversa: o comando era de lá.
    if (form) |*fs| if (ctx.st.activeChannel()) |active| if (active != fs.channel) closeForm();
    if (form) |*fs| {
        if (fs.ac_due != 0 and ctx.now_ms >= fs.ac_due) requestAutocomplete(ctx, fs);
        const saved = ctx.dl;
        defer ctx.dl = saved;
        drawForm(ctx);
        if (form) |*f2| acWindow(ctx, f2);
    }
    if (modal != null) {
        const saved = ctx.dl;
        defer ctx.dl = saved;
        drawModal(ctx);
    }
}
