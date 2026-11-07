//! Pessoas de um grupo de DM: quem está nele (o dono pode tirar) e os amigos
//! que dá para pôr. Cada botão é um pedido; a lista muda com o evento que o
//! Discord manda (CHANNEL_RECIPIENT_ADD/REMOVE).
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const w = @import("widgets.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const forum = @import("forum.zig");
const inbox = @import("inbox.zig");
const types = @import("../core/types.zig");
const social = @import("../net/social.zig");
const Id = types.Id;

var filter_buf: [64]u8 = @splat(0);
/// Amigos em ordem de nome, montada ao abrir (nada de ordenar a cada quadro).
var friends: [1000]Id = undefined;
var n_friends: usize = 0;

pub fn open(ctx: *d.Ctx, channel: Id) void {
    @memset(&filter_buf, 0);
    n_friends = 0;
    var it = ctx.store.relationships.iterator();
    while (it.next()) |e| if (e.value_ptr.* == .friend and n_friends < friends.len) {
        friends[n_friends] = e.key_ptr.*;
        n_friends += 1;
    };
    std.sort.pdq(Id, friends[0..n_friends], ctx, struct {
        fn lt(cx: *d.Ctx, a: Id, b: Id) bool {
            const na = if (cx.store.user(a)) |u| u.name else "";
            const nb = if (cx.store.user(b)) |u| u.name else "";
            return std.ascii.lessThanIgnoreCase(na, nb);
        }
    }.lt);
    ctx.st.popup = .{ .group_members = .{ .channel = channel } };
}

pub fn draw(ctx: *d.Ctx, channel: Id) void {
    const cs = ctx.store.channel(channel) orelse return popup.close(ctx);
    if (!cs.info.group) return popup.close(ctx);
    const ch = &cs.info;
    const me = ctx.store.me;
    const r = forum.dialogRect(ctx, 440, 540);
    const dl = popup.beginWindow("##group-members", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    const fam = ctx.ui;
    d.text(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.tr("Pessoas do grupo", "Group Members"));
    _ = d.textClipped(dl, fam.get(.regular), 13, r.x + 18, r.y + 42, ctx.col(.muted), ch.name, r.w - 36);

    const ir: d.Rect = .{ .x = r.x + 18, .y = r.y + 68, .w = r.w - 36, .h = 34 };
    qa.mark(ir, "group-filter", .{});
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    _ = forum.textInput(ctx, dl, ir, "##group-filter", i18n.trZ("Buscar amigos para adicionar", "Search friends to add").ptr, &filter_buf, 0);
    const q = std.mem.trim(u8, std.mem.sliceTo(&filter_buf, 0), " ");

    const lr: d.Rect = .{ .x = r.x + 6, .y = ir.bottom() + 10, .w = r.w - 12, .h = r.bottom() - 60 - (ir.bottom() + 10) };
    d.line(dl, r.x, lr.y - 1, r.right(), lr.y - 1, ctx.col(.border), 1);
    const ldl = d.beginRegion(ctx, "##group-list", lr, 0);
    popup.track(ldl);
    var y = c.ImGui_GetCursorScreenPos().y + 8;
    const row_h: f32 = 40;
    const visible = struct {
        fn f(area: d.Rect, yy: f32, h: f32) bool {
            return yy + h >= area.y - 40 and yy <= area.bottom() + 40;
        }
    }.f;

    // Quem está no grupo: a gente primeiro, depois os outros.
    var hb_buf: [96]u8 = undefined;
    d.text(ldl, fam.get(.semibold), 12, lr.x + 12, y, ctx.col(.faint).mix(ctx.col(.muted), 0.4), i18n.fmt(&hb_buf, "NO GRUPO — {d}", "IN THE GROUP — {d}", .{ch.recipients.len + 1}));
    y += 24;
    var i: usize = 0;
    while (i <= ch.recipients.len) : (i += 1) {
        const uid = if (i == 0) me else ch.recipients[i - 1];
        if (visible(lr, y, row_h)) {
            const rr: d.Rect = .{ .x = lr.x + 6, .y = y, .w = lr.w - 12, .h = row_h - 2 };
            qa.mark(rr, "group-member:{d}", .{uid});
            _ = person(ctx, ldl, rr, uid, ch.owner == uid);
            if (social.canRemove(ch, me, uid)) {
                const lbl = i18n.tr("Remover", "Remove");
                const br: d.Rect = .{ .x = rr.right() - inbox.buttonWidth(ctx, lbl) - 4, .y = rr.y + (rr.h - 28) / 2, .w = inbox.buttonWidth(ctx, lbl), .h = 28 };
                qa.mark(br, "group-remove:{d}", .{uid});
                if (inbox.button(ctx, ldl, 1000 + i, br, lbl, true)) ctx.act(.{ .social = .{ .remove_member = .{ .channel = channel, .user = uid } } });
            }
        }
        y += row_h;
    }

    // Amigos que ainda não estão (o filtro procura no nome).
    y += 10;
    d.text(ldl, fam.get(.semibold), 12, lr.x + 12, y, ctx.col(.faint).mix(ctx.col(.muted), 0.4), i18n.tr("ADICIONAR AMIGOS", "ADD FRIENDS"));
    y += 24;
    const room = social.hasRoom(ch);
    if (!room) {
        qa.mark(.{ .x = lr.x + 6, .y = y, .w = lr.w - 12, .h = 24 }, "group-full", .{});
        _ = d.textClipped(ldl, fam.get(.regular), 13, lr.x + 12, y + 2, ctx.col(.faint), i18n.fmt(&hb_buf, "O grupo já tem {d} pessoas, o máximo.", "The group already has {d} people, the limit.", .{social.group_max}), lr.w - 24);
        y += 28;
    }
    var shown: usize = 0;
    for (friends[0..n_friends], 0..) |uid, fi| {
        // Desfez a amizade com o painel aberto, ou já entrou no grupo.
        if ((ctx.store.relationships.get(uid) orelse .none) != .friend) continue;
        if (std.mem.indexOfScalar(Id, ch.recipients, uid) != null) continue;
        const u = ctx.store.user(uid) orelse continue;
        if (q.len > 0 and std.ascii.findIgnoreCase(u.name, q) == null) continue;
        shown += 1;
        if (visible(lr, y, row_h)) {
            const rr: d.Rect = .{ .x = lr.x + 6, .y = y, .w = lr.w - 12, .h = row_h - 2 };
            qa.mark(rr, "group-friend:{d}", .{uid});
            _ = person(ctx, ldl, rr, uid, false);
            if (room) {
                const lbl = i18n.tr("Adicionar", "Add");
                const bw = inbox.buttonWidth(ctx, lbl);
                const br: d.Rect = .{ .x = rr.right() - bw - 4, .y = rr.y + (rr.h - 28) / 2, .w = bw, .h = 28 };
                qa.mark(br, "group-add:{d}", .{uid});
                if (inbox.button(ctx, ldl, 2000 + fi, br, lbl, false)) ctx.act(.{ .social = .{ .add_member = .{ .channel = channel, .user = uid } } });
            }
        }
        y += row_h;
    }
    if (shown == 0) {
        const t = if (q.len > 0) i18n.tr("Nenhum amigo com esse nome.", "No friend with that name.") else i18n.tr("Todos os seus amigos já estão aqui.", "All your friends are already here.");
        d.text(ldl, fam.get(.regular), 13, lr.x + 12, y + 4, ctx.col(.faint), t);
        y += 28;
    }
    d.endRegion(ctx, y + 8, lr.x);

    const close_lbl = i18n.tr("Fechar", "Close");
    const cw = inbox.buttonWidth(ctx, close_lbl);
    const cr: d.Rect = .{ .x = r.right() - 18 - cw, .y = r.bottom() - 46, .w = cw, .h = 28 };
    qa.mark(cr, "group-close", .{});
    if (inbox.button(ctx, dl, 90, cr, close_lbl, false)) popup.close(ctx);
}

/// Avatar e nome numa linha (com "dono" para quem é). Retorna a largura do nome.
fn person(ctx: *d.Ctx, dl: *c.ImDrawList, rr: d.Rect, uid: Id, owner: bool) f32 {
    const fam = ctx.ui;
    w.avatar(ctx, dl, rr.x + 18, rr.y + rr.h / 2, 28, uid, .circle, ctx.col(.overlay), 1);
    const name = if (ctx.store.user(uid)) |u| u.name else "?";
    const nw = d.textClipped(dl, fam.get(.medium), 14, rr.x + 40, d.centerY(rr, 14), ctx.col(.text), name, rr.w - 150);
    if (owner) d.text(dl, fam.get(.semibold), 11, rr.x + 48 + nw, d.centerY(rr, 11), ctx.col(.muted), i18n.tr("dono", "owner"));
    return nw;
}
