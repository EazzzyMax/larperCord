//! Quem reagiu a uma mensagem e quem votou numa opção de enquete. A lista é
//! buscada só quando abre (botão direito numa reação, "Ver reações" no menu,
//! clique numa opção da enquete) e a página seguinte só no "Mostrar mais":
//! cada clique é um pedido, e nada fica guardado depois de fechar.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const w = @import("widgets.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const anim = @import("anim.zig");
const emoji_img = @import("emoji_img.zig");
const types = @import("../core/types.zig");
const ev = @import("../core/event.zig");
const Id = types.Id;

/// A reação aberta (posição nas reações da mensagem) e se mostra as super.
var sel: u8 = 0;
var burst: bool = false;
/// O pedido da lista que está na tela (o "Mostrar mais" repete com a página seguinte).
var query: ev.PeopleQuery = .{ .channel = 0, .id = 0 };

const pop_w: f32 = 320;
const pop_h: f32 = 384;
const row_h: f32 = 40;

fn want(ctx: *d.Ctx, q: ev.PeopleQuery) void {
    query = q;
    ctx.act(.{ .want_people = .{ .q = q } });
}

/// Abre a lista de quem reagiu com a reação `index` da mensagem.
pub fn openReactions(ctx: *d.Ctx, msg: Id, index: usize, x: f32, y: f32) void {
    const f = ctx.store.findAny(msg) orelse return;
    if (f.m.n_reactions == 0 or f.m.msg.id == 0) return;
    sel = @intCast(@min(index, f.m.n_reactions - 1));
    burst = false;
    ctx.popup(.{ .reactions = .{ .message = msg, .x = x, .y = y } });
    want(ctx, .{ .channel = f.cs.info.id, .id = msg, .emoji = f.m.reactions[sel] });
}

/// Abre a lista de quem votou na opção `answer` da enquete da mensagem.
pub fn openVoters(ctx: *d.Ctx, channel: Id, msg: Id, answer: u32, x: f32, y: f32) void {
    ctx.popup(.{ .poll_voters = .{ .message = msg, .answer = answer, .x = x, .y = y } });
    want(ctx, .{ .channel = channel, .id = msg, .answer = answer });
}

/// Desenha um emoji de reação (ou de opção de enquete) com o canto em `x`,
/// centrado em `cy`. Devolve a largura.
pub fn drawEmoji(ctx: *d.Ctx, dl: *c.ImDrawList, r: *const types.Reaction, x: f32, cy: f32, size: f32, hovered: bool) f32 {
    if (r.len == 0) return 0;
    if (r.custom != 0) {
        if (emoji_img.enabled(ctx)) {
            emoji_img.draw(ctx, dl, r.custom, r.animated, .{ .x = x, .y = cy - size / 2, .w = size, .h = size }, 1, hovered, true);
            return size;
        }
        var nb: [40]u8 = undefined;
        const shown = std.fmt.bufPrint(&nb, ":{s}:", .{r.text()}) catch r.text();
        const fs = size * 0.7;
        d.text(dl, ctx.ui.get(.medium), fs, x, cy - d.fontPx(fs) / 2, ctx.col(.text).mix(ctx.col(.muted), 0.3), shown);
        return d.width(ctx.ui.get(.medium), fs, shown);
    }
    const pick = @import("emoji_picker.zig");
    const g = pick.drawable(r.text());
    const es = pick.fitSize(ctx.ui.get(.regular), g.slice(), size * 0.85, size);
    d.text(dl, ctx.ui.get(.regular), es, x, cy - es * 0.67, d.Rgba.white, g.slice());
    return @min(d.width(ctx.ui.get(.regular), es, g.slice()), size);
}

fn frame(ctx: *d.Ctx, x: f32, y: f32) struct { r: d.Rect, dl: *c.ImDrawList } {
    const wd = @min(pop_w, ctx.win.w - 24);
    const h = @min(pop_h, ctx.win.h - 24);
    // Abaixo do clique quando cabe; senão, acima.
    const top = if (y + 12 + h <= ctx.win.bottom() - 8) y + 12 else y - h - 12;
    const r = popup.fit(ctx, x - 24, top, wd, h);
    const dl = popup.beginWindow("##people", r);
    ctx.dl = dl;
    const radius = @max(ctx.th.radius, 6);
    d.shadow(dl, r, radius, 14, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.overlay), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    return .{ .r = r, .dl = dl };
}

pub fn drawReactions(ctx: *d.Ctx, msg: Id, x: f32, y: f32) void {
    const f = ctx.store.findAny(msg) orelse return popup.close(ctx);
    const rs = f.m.reactionSlice();
    if (rs.len == 0) return popup.close(ctx);
    if (sel >= rs.len) sel = 0;
    const fr = frame(ctx, x, y);
    defer c.ImGui_End();
    const r = fr.r;
    const dl = fr.dl;
    qa.mark(r, "reactors", .{});
    const fam = ctx.ui;

    // Uma aba por emoji, com quantas pessoas.
    var tx = r.x + 10;
    var cb: [16]u8 = undefined;
    for (rs, 0..) |*rc, i| {
        const cnt = std.fmt.bufPrint(&cb, "{d}", .{rc.count}) catch "";
        const tw: f32 = 8 + 20 + 6 + d.width(fam.get(.semibold), 13, cnt) + 10;
        const tr: d.Rect = .{ .x = tx, .y = r.y + 10, .w = tw, .h = 30 };
        if (tr.right() > r.right() - 8) break;
        const hb = d.hit(ctx, 0x5e00 + i, tr);
        qa.mark(tr, "reactors-tab:{d}", .{i});
        const on = i == sel;
        const cr = @min(8, ctx.th.radius + 2);
        d.rect(dl, tr, if (on) ctx.col(.accent).alpha(0.2) else if (hb.hovered) ctx.col(.hover) else ctx.col(.elevated), cr);
        if (on) d.border(dl, tr, ctx.col(.accent), cr, 1);
        _ = drawEmoji(ctx, dl, rc, tr.x + 8, tr.y + 15, 20, hb.hovered);
        d.text(dl, fam.get(.semibold), 13, tr.x + 34, d.centerY(tr, 13), if (on) ctx.col(.accent).mix(ctx.col(.text), 0.3) else ctx.col(.muted), cnt);
        if (hb.clicked and !on) {
            sel = @intCast(i);
            burst = false;
            want(ctx, .{ .channel = f.cs.info.id, .id = msg, .emoji = rc.* });
        }
        tx += tw + 6;
    }
    var top = r.y + 48;
    const cur = &rs[sel];
    // Super reações: uma segunda lista, só quando a reação tem alguma.
    if (cur.burst > 0) {
        var lb: [64]u8 = undefined;
        var sb: [64]u8 = undefined;
        const labels = [2][]const u8{
            i18n.fmt(&lb, "Reações {d}", "Reactions {d}", .{cur.count -| cur.burst}),
            i18n.fmt(&sb, "Super reações {d}", "Super Reactions {d}", .{cur.burst}),
        };
        var sx = r.x + 10;
        for (labels, 0..) |label, i| {
            const lw = d.width(fam.get(.semibold), 12.5, label) + 18;
            const sr: d.Rect = .{ .x = sx, .y = top, .w = lw, .h = 24 };
            const hb = d.hit(ctx, 0x5e40 + i, sr);
            qa.mark(sr, "reactors-kind:{d}", .{i});
            const on = burst == (i == 1);
            if (on or hb.hovered) d.rect(dl, sr, if (on) ctx.col(.selected) else ctx.col(.hover), 12);
            d.text(dl, fam.get(.semibold), 12.5, sr.x + 9, d.centerY(sr, 12.5), if (on) ctx.col(.text) else ctx.col(.muted), label);
            if (hb.clicked and !on) {
                burst = i == 1;
                want(ctx, .{ .channel = f.cs.info.id, .id = msg, .emoji = cur.*, .burst = burst });
            }
            sx += lw + 6;
        }
        top += 32;
    }
    d.line(dl, r.x, top, r.right(), top, ctx.col(.border), 1);
    list(ctx, dl, .{ .x = r.x + 1, .y = top + 1, .w = r.w - 2, .h = r.bottom() - top - 6 }, f.cs.info.guild);
}

pub fn drawVoters(ctx: *d.Ctx, msg: Id, answer: u32, x: f32, y: f32) void {
    const f = ctx.store.findAny(msg) orelse return popup.close(ctx);
    const p = ctx.store.polls.get(msg) orelse return popup.close(ctx);
    const a = p.find(answer) orelse return popup.close(ctx);
    const fr = frame(ctx, x, y);
    defer c.ImGui_End();
    const r = fr.r;
    const dl = fr.dl;
    qa.mark(r, "voters", .{});
    const fam = ctx.ui;
    var ax = r.x + 14;
    ax += drawEmoji(ctx, dl, &a.emoji, ax, r.y + 22, 20, false);
    if (a.emoji.len > 0) ax += 6;
    _ = d.textClipped(dl, fam.get(.bold), 15, ax, r.y + 13, ctx.col(.text), a.text, r.right() - ax - 14);
    var vb: [48]u8 = undefined;
    const votes = if (p.known) i18n.fmt(&vb, "{d} votos", "{d} votes", .{a.count}) else i18n.tr("votos desconhecidos", "votes unknown");
    d.text(dl, fam.get(.regular), 12.5, r.x + 14, r.y + 36, ctx.col(.muted), votes);
    const top = r.y + 58;
    d.line(dl, r.x, top, r.right(), top, ctx.col(.border), 1);
    list(ctx, dl, .{ .x = r.x + 1, .y = top + 1, .w = r.w - 2, .h = r.bottom() - top - 6 }, f.cs.info.guild);
}

/// A lista de pessoas (a que está no Store), com "Mostrar mais" no fim.
fn list(ctx: *d.Ctx, dl_outer: *c.ImDrawList, body: d.Rect, guild: Id) void {
    const fam = ctx.ui;
    const pl = &ctx.store.people;
    const bdl = d.beginRegion(ctx, "##people-body", body, 0);
    popup.track(bdl);
    ctx.dl = bdl;
    defer ctx.dl = dl_outer;
    var y = c.ImGui_GetCursorScreenPos().y + 6;
    for (pl.users.items) |uid| {
        const rr: d.Rect = .{ .x = body.x + 6, .y = y, .w = body.w - 12, .h = row_h - 4 };
        if (rr.bottom() >= body.y - row_h and rr.y <= body.bottom() + row_h) {
            const hb = d.hit(ctx, @truncate(uid), rr);
            qa.mark(rr, "people-row:{d}", .{uid});
            if (hb.hovered) d.rect(bdl, rr, ctx.col(.hover), @max(ctx.th.radius - 2, 3));
            w.avatar(ctx, bdl, rr.x + 18, rr.y + rr.h / 2, 26, uid, .circle, null, 1);
            const u = ctx.store.user(uid);
            const name = if (u) |x| x.name else "?";
            const nw = d.textClipped(bdl, fam.get(.semibold), 14, rr.x + 40, d.centerY(rr, 14), w.nameColor(ctx, guild, uid), name, rr.w - 60);
            _ = w.botTag(ctx, bdl, rr.x + 40 + nw, rr.y + rr.h / 2, u, false, 1);
            // Clicar abre o cartão da pessoa (no lugar desta lista).
            if (hb.clicked) ctx.popup(.{ .profile = .{ .user = uid, .x = rr.right() + 8, .y = rr.y } });
        }
        y += row_h;
    }
    switch (pl.state) {
        .none, .loading => {
            w.typingDots(bdl, body.x + body.w / 2 - 7, y + 18, ctx.col(.muted), ctx.now_ms);
            anim.active = true;
            y += 40;
        },
        .failed => {
            const t = i18n.tr("Não consegui carregar.", "Couldn't load.");
            d.text(bdl, fam.get(.medium), 13.5, body.x + (body.w - d.width(fam.get(.medium), 13.5, t)) / 2, y + 8, ctx.col(.muted), t);
            const b = button(ctx, bdl, body, y + 32, i18n.tr("Tentar de novo", "Try again"), "people-retry");
            y = b.y;
            if (b.clicked) want(ctx, query);
        },
        .loaded => {
            if (pl.users.items.len == 0) {
                const t = i18n.tr("Ninguém por aqui.", "Nobody here.");
                d.text(bdl, fam.get(.medium), 13.5, body.x + (body.w - d.width(fam.get(.medium), 13.5, t)) / 2, y + 12, ctx.col(.muted), t);
                qa.mark(.{ .x = body.x, .y = y, .w = body.w, .h = 40 }, "people-empty", .{});
                y += 44;
            } else if (pl.more) {
                const b = button(ctx, bdl, body, y + 4, i18n.tr("Mostrar mais", "Show more"), "people-more");
                y = b.y;
                if (b.clicked) ctx.act(.{ .want_people = .{ .q = query, .more = true } });
            }
        },
    }
    d.endRegion(ctx, y + 4, body.x);
}

/// Botão de texto no meio da lista: onde a lista continua e se foi clicado.
fn button(ctx: *d.Ctx, dl: *c.ImDrawList, body: d.Rect, y: f32, label: []const u8, mark: []const u8) struct { y: f32, clicked: bool } {
    const fam = ctx.ui;
    const bw = d.width(fam.get(.semibold), 13.5, label) + 28;
    const br: d.Rect = .{ .x = body.x + (body.w - bw) / 2, .y = y, .w = bw, .h = 30 };
    const hb = d.hit(ctx, 0x5e80, br);
    qa.mark(br, "{s}", .{mark});
    d.rect(dl, br, if (hb.hovered) ctx.col(.accent) else ctx.col(.elevated), @max(ctx.th.radius, 4));
    d.text(dl, fam.get(.semibold), 13.5, br.x + 14, d.centerY(br, 13.5), if (hb.hovered) ctx.col(.accent_text) else ctx.col(.text), label);
    return .{ .y = y + 40, .clicked = hb.clicked };
}
