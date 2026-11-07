//! Pedidos de mensagem e spam na lista de DMs: uma linha embaixo de "Amigos"
//! com quantos são e, aberta, as duas abas com aceitar e recusar (um de cada
//! vez, um pedido por clique). Pedido não aparece entre as conversas.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const w = @import("widgets.zig");
const anim = @import("anim.zig");
const icons = @import("icons.zig");
const i18n = @import("i18n.zig");
const types = @import("../core/types.zig");
const Id = types.Id;

pub const View = enum { none, requests, spam };
/// O que a lista de DMs mostra: as conversas ou uma das abas de pedidos.
pub var view: View = .none;

pub const Counts = struct {
    pending: u16 = 0,
    spam: u16 = 0,
    /// Posição da última conversa comum (o "└" da árvore).
    last_normal: usize = 0,
};

/// Quantos pedidos e spam há entre as DMs (sem alocar; a lista de DMs já
/// passa por todas a cada quadro).
pub fn counts(store: anytype, dms: []const Id) Counts {
    var n: Counts = .{};
    for (dms, 0..) |id, i| {
        const cs = store.channel(id) orelse continue;
        switch (cs.info.request) {
            .none => n.last_normal = i,
            .pending => n.pending +|= 1,
            .spam => n.spam +|= 1,
        }
    }
    return n;
}

/// A linha "Pedidos de mensagem": só com algum pedido ou com a aba aberta.
/// Clicar abre (ou fecha) as abas. Retorna o novo `y`.
pub fn entry(ctx: *d.Ctx, dl: *c.ImDrawList, fam: *d.Family, tree: bool, pills: bool, r: d.Rect, y: f32, n: Counts) f32 {
    const total = n.pending +| n.spam;
    if (total == 0 and view == .none) return y;
    const fs = ctx.th.font_size;
    const row_h: f32 = if (tree) 24 else 42;
    const rr: d.Rect = .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = row_h - 2 };
    const hb = d.hit(ctx, 298, rr);
    qa.mark(rr, "dm-requests", .{});
    if (hb.clicked) view = if (view != .none) .none else if (n.pending == 0 and n.spam > 0) .spam else .requests;
    const sel = view != .none;
    const k = anim.to(anim.id("dm-requests", 0), if (sel) 1 else if (hb.hovered) 0.5 else 0, 24);
    if (tree) {
        if (sel) d.rect(dl, rr, ctx.col(.accent), 0) else if (hb.hovered) d.rect(dl, rr, ctx.col(.hover), 0);
        d.text(dl, fam.get(.bold), fs - 1, rr.x + 4, d.centerY(rr, fs - 1), if (sel) ctx.col(.accent_text) else ctx.col(.text), i18n.tr("├ ✉ pedidos de mensagem", "├ ✉ message requests"));
    } else {
        const on = pills and sel;
        if (k > 0.01) d.rect(dl, rr, if (on) ctx.col(.accent) else ctx.col(.selected).alpha(k), if (pills) rr.h / 2 else ctx.th.radius);
        const ink = if (on) ctx.col(.accent_text) else if (sel) ctx.col(.text) else ctx.col(.muted).mix(ctx.col(.text), k);
        icons.message(dl, rr.x + 21, rr.y + rr.h / 2 - 1, ink.u());
        _ = d.textClipped(dl, fam.get(.semibold), fs, rr.x + 46, d.centerY(rr, fs), ink, i18n.tr("Pedidos de mensagem", "Message Requests"), rr.w - 80);
    }
    if (total > 0) @import("comp_channels.zig").badgeAt(ctx, dl, fam, rr.right() - 10, rr.y + rr.h / 2, total);
    return y + row_h + (if (tree) @as(f32, 2) else 6);
}

/// As abas abertas: pedidos ou spam, cada um com aceitar e recusar.
pub fn list(ctx: *d.Ctx, dl: *c.ImDrawList, fam: *d.Family, tree: bool, pills: bool, r: d.Rect, y_in: f32, dms: []const Id, n: Counts) f32 {
    var y = y_in + 2;
    const fs = ctx.th.font_size;
    // Abas: "Pedidos 2" e "Spam 1".
    {
        const tr: d.Rect = .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = if (tree) 22 else 30 };
        const half = tr.w / 2;
        for ([_]View{ .requests, .spam }, 0..) |v, i| {
            const br: d.Rect = .{ .x = tr.x + half * @as(f32, @floatFromInt(i)), .y = tr.y, .w = half - 2, .h = tr.h };
            const hb = d.hit(ctx, 296 + i, br);
            qa.mark(br, "dm-tab:{s}", .{@tagName(v)});
            if (hb.clicked) view = v;
            const on = view == v;
            var lb: [48]u8 = undefined;
            const count = if (v == .requests) n.pending else n.spam;
            const label = if (v == .requests)
                i18n.fmt(&lb, "Pedidos {d}", "Requests {d}", .{count})
            else
                i18n.fmt(&lb, "Spam {d}", "Spam {d}", .{count});
            const radius: f32 = if (tree) 0 else if (pills) br.h / 2 else @max(ctx.th.radius - 2, 2);
            if (on) d.rect(dl, br, if (tree) ctx.col(.accent) else ctx.col(.selected), radius) else if (hb.hovered) d.rect(dl, br, ctx.col(.hover), radius);
            const ink = if (on) (if (tree) ctx.col(.accent_text) else ctx.col(.text)) else ctx.col(.muted);
            const font = fam.get(if (on) .semibold else .medium);
            const tsz = if (tree) fs - 1 else 13;
            d.text(dl, font, tsz, br.x + (br.w - d.width(font, tsz, label)) / 2, d.centerY(br, tsz), ink, label);
        }
        y += tr.h + 8;
    }
    const want: types.DmRequest = if (view == .spam) .spam else .pending;
    if (want == .spam and n.spam > 0) {
        _ = d.textClipped(dl, fam.get(.regular), 12, r.x + 16, y, ctx.col(.faint), i18n.tr("O Discord separou estas conversas como spam.", "Discord filtered these conversations as spam."), r.w - 32);
        y += 22;
    }
    if ((if (want == .spam) n.spam else n.pending) == 0) {
        const t = if (want == .spam) i18n.tr("Nada no spam.", "Nothing in spam.") else i18n.tr("Nenhum pedido de mensagem.", "No message requests.");
        qa.mark(.{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = 40 }, "dm-requests-empty", .{});
        const font = fam.get(.regular);
        d.text(dl, font, 13, r.x + (r.w - d.width(font, 13, t)) / 2, y + 12, ctx.col(.faint), t);
        return y + 40;
    }
    for (dms, 0..) |id, idx| {
        const cs = ctx.store.channel(id) orelse continue;
        if (cs.info.request != want) continue;
        const u = ctx.store.user(cs.info.recipient);
        const group = cs.info.group;
        if (!group and u == null) continue;
        const row_h: f32 = if (tree) 26 else 48;
        if (y + row_h < r.y - 64 or y > r.bottom() + 64) {
            y += row_h;
            continue;
        }
        const rr: d.Rect = .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = row_h - 2 };
        const bsz: f32 = if (tree) 20 else 28;
        // Os botões ficam fora da área que abre a conversa (um clique, uma coisa).
        const buttons_w = bsz * 2 + 14;
        const open_r: d.Rect = .{ .x = rr.x, .y = rr.y, .w = rr.w - buttons_w, .h = rr.h };
        const hb = d.hit(ctx, 400 + idx * 3, open_r);
        qa.mark(open_r, "request:{d}", .{id});
        if (hb.clicked) ctx.act(.{ .select_channel = id });
        const selected = ctx.st.activeChannel() == id and !ctx.st.friends;
        const k = anim.to(anim.id("dm-req", id), if (selected) 1 else if (hb.hovered) 0.5 else 0, 24);
        const name = if (group) cs.info.name else u.?.name;
        if (tree) {
            if (selected) d.rect(dl, rr, ctx.col(.accent), 0) else if (hb.hovered) d.rect(dl, rr, ctx.col(.hover), 0);
            var nb: [96]u8 = undefined;
            const t = std.fmt.bufPrint(&nb, "│ @{s}", .{name}) catch name;
            _ = d.textClipped(dl, fam.get(if (cs.info.unread) .bold else .regular), fs - 1, rr.x + 4, d.centerY(rr, fs - 1), if (selected) ctx.col(.accent_text) else ctx.col(.text), t, open_r.w - 8);
        } else {
            const on = pills and selected;
            if (k > 0.01) d.rect(dl, rr, if (on) ctx.col(.accent) else ctx.col(.selected).alpha(k), if (pills) rr.h / 2 else ctx.th.radius);
            if (group) @import("comp_channels.zig").groupIcon(ctx, dl, &cs.info, rr.x + 22, rr.y + rr.h / 2, 32) else w.avatar(ctx, dl, rr.x + 22, rr.y + rr.h / 2, 32, u.?.id, .circle, if (on) ctx.col(.accent) else ctx.col(.sidebar), 1);
            const tc = if (on) ctx.col(.accent_text) else ctx.col(.text);
            _ = d.textClipped(dl, fam.get(if (cs.info.unread) .semibold else .medium), fs - 1, rr.x + 46, rr.y + 6, tc, name, open_r.w - 52);
            const sub = if (want == .spam) i18n.tr("Possível spam", "Possible spam") else i18n.tr("Quer conversar com você", "Wants to message you");
            _ = d.textClipped(dl, fam.get(.regular), 12, rr.x + 46, rr.y + 26, if (on) tc.alpha(0.8) else ctx.col(.faint), sub, open_r.w - 52);
        }
        const cy = rr.y + rr.h / 2;
        const acc_r: d.Rect = .{ .x = rr.right() - bsz * 2 - 8, .y = cy - bsz / 2, .w = bsz, .h = bsz };
        const dec_r: d.Rect = .{ .x = rr.right() - bsz - 2, .y = cy - bsz / 2, .w = bsz, .h = bsz };
        qa.mark(acc_r, "request-accept:{d}", .{id});
        qa.mark(dec_r, "request-decline:{d}", .{id});
        if (roundButton(ctx, dl, 401 + idx * 3, acc_r, tree, false, i18n.tr("Aceitar", "Accept"))) ctx.act(.{ .social = .{ .accept_request = id } });
        if (roundButton(ctx, dl, 402 + idx * 3, dec_r, tree, true, i18n.tr("Recusar", "Decline"))) ctx.act(.{ .social = .{ .reject_request = id } });
        y += row_h;
    }
    return y;
}

/// Botão redondo com um ✓ (aceitar) ou um ✕ (recusar), desenhados em linha.
fn roundButton(ctx: *d.Ctx, dl: *c.ImDrawList, id: usize, r: d.Rect, tree: bool, danger: bool, tip: []const u8) bool {
    const hb = d.hit(ctx, id, r);
    const base = if (danger) ctx.col(.danger) else ctx.col(.online);
    const radius: f32 = if (tree) 0 else r.h / 2;
    d.rect(dl, r, if (hb.hovered) base.alpha(0.9) else ctx.col(.hover).mix(ctx.col(.sidebar), 0.2), radius);
    const ink = if (hb.hovered) d.Rgba.white else base;
    const cx = r.x + r.w / 2;
    const cy = r.y + r.h / 2;
    const s = r.w * 0.17;
    if (danger) {
        d.line(dl, cx - s, cy - s, cx + s, cy + s, ink, 2);
        d.line(dl, cx + s, cy - s, cx - s, cy + s, ink, 2);
    } else {
        d.line(dl, cx - s * 1.2, cy, cx - s * 0.3, cy + s, ink, 2);
        d.line(dl, cx - s * 0.3, cy + s, cx + s * 1.3, cy - s, ink, 2);
    }
    d.tip(ctx, r, tip, hb.hovered);
    return hb.clicked;
}
