//! Aba de figurinhas do seletor de GIFs: as do servidor aberto, as dos outros
//! servidores (trancadas quando a regra do Discord não deixa mandar aqui) e os
//! pacotes padrão do Discord, buscados só quando a aba abre. Um clique manda
//! a figurinha na conversa (`sticker_ids`). Lottie (animação vetorial) não é
//! desenhada: fica o nome no lugar.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const media_url = @import("../net/media_url.zig");
const types = @import("../core/types.zig");
const stickers = @import("../core/stickers.zig");

const cell: f32 = 86;
const gap: f32 = 8;
const head_h: f32 = 28;

fn matches(st: *const stickers.Sticker, q: []const u8) bool {
    return q.len == 0 or std.ascii.findIgnoreCase(st.name, q) != null;
}

fn count(list: []const stickers.Sticker, q: []const u8) usize {
    var n: usize = 0;
    for (list) |*st| {
        if (matches(st, q)) n += 1;
    }
    return n;
}

/// Uma seção: título e figurinhas (as que passam pela busca).
const Section = struct { title: []const u8, list: []const stickers.Sticker, n: usize };

const Layout = struct {
    ctx: *d.Ctx,
    dl: *c.ImDrawList,
    area: d.Rect,
    scroll: f32,
    cols: usize,
    cell_w: f32,
    y: f32 = 0,
    here: types.Id,
    perms: u64,
    channel: types.Id,
    chosen: ?types.Id = null,

    fn section(l: *Layout, s: Section) void {
        if (s.n == 0) return;
        const top = l.area.y - l.scroll + l.y;
        if (top + head_h > l.area.y and top < l.area.bottom()) {
            const f = l.ctx.ui.get(.semibold);
            _ = d.textClipped(l.dl, f, 12, l.area.x + 2, top + 8, l.ctx.col(.muted), s.title, l.area.w - 20);
        }
        l.y += head_h;
        var k: usize = 0;
        for (s.list) |*st| {
            if (!matches(st, query)) continue;
            const row: f32 = @floatFromInt(k / l.cols);
            const col: f32 = @floatFromInt(k % l.cols);
            k += 1;
            const r: d.Rect = .{ .x = l.area.x + col * (l.cell_w + gap), .y = l.area.y - l.scroll + l.y + row * (cell + gap), .w = l.cell_w, .h = cell };
            // Fora da tela não baixa nada.
            if (r.bottom() < l.area.y or r.y > l.area.bottom()) continue;
            if (l.drawCell(st, r)) l.chosen = st.id;
        }
        const rows = (s.n + l.cols - 1) / l.cols;
        l.y += @as(f32, @floatFromInt(rows)) * (cell + gap);
    }

    fn drawCell(l: *Layout, st: *const stickers.Sticker, r: d.Rect) bool {
        const ctx = l.ctx;
        const dl = l.dl;
        const use = stickers.canSend(st, l.here, ctx.store.premium_type, l.perms);
        const hb = d.hit(ctx, @truncate(st.id ^ 0x571C_0000), r);
        qa.mark(r, "sticker:{d}", .{st.id});
        d.rect(dl, r, ctx.col(.elevated).mix(ctx.col(.text), if (hb.hovered) 0.05 else 0), 8);
        const scale = ctx.io.*.DisplayFramebufferScale.x;
        var ub: [160]u8 = undefined;
        const animated = st.format == stickers.format_apng or st.format == stickers.format_gif;
        const url: ?[]const u8 = if (st.format == stickers.format_lottie)
            null
        else if (ctx.store.demo)
            std.fmt.bufPrint(&ub, "demo:sticker:{d}:{d}", .{ st.id, @intFromBool(animated) }) catch null
        else
            media_url.stickerUrl(&ub, st.id, st.format);
        const ir: d.Rect = .{ .x = r.x + 8, .y = r.y + 8, .w = r.w - 16, .h = r.h - 16 };
        var drawn = false;
        // Parada economiza: só anima a que está sob o mouse.
        if (url) |u| switch (ctx.images.getEx(u, ir.w * scale, ir.h * scale, hb.hovered)) {
            .ready => |t| {
                const tw: f32 = @floatFromInt(t.w);
                const th: f32 = @floatFromInt(t.h);
                const k = @min(ir.w / tw, ir.h / th);
                const x0 = ir.x + (ir.w - tw * k) / 2;
                const y0 = ir.y + (ir.h - th * k) / 2;
                const a: f32 = if (use == .ok) 1 else 0.35;
                c.ImDrawList_AddImageEx(dl, t.ref, d.v(x0, y0), d.v(x0 + tw * k, y0 + th * k), d.v(0, 0), d.v(1, 1), d.Rgba.white.col(a));
                drawn = true;
            },
            else => {},
        };
        if (!drawn) {
            // Lottie (ou ainda chegando): o nome no lugar.
            const f = ctx.ui.get(.medium);
            _ = d.textClipped(dl, f, 12, r.x + 8, d.centerY(r, 12) - (if (url == null) @as(f32, 7) else 0), ctx.col(if (use == .ok) .text else .faint), st.name, r.w - 16);
            if (url == null) {
                const small = ctx.ui.get(.regular);
                _ = d.textClipped(dl, small, 10.5, r.x + 8, d.centerY(r, 10.5) + 9, ctx.col(.faint), i18n.tr("animação (não exibida)", "animation (not shown)"), r.w - 16);
            }
        }
        if (use != .ok) lockIcon(dl, r.right() - 14, r.y + 14, ctx.col(.muted));
        if (hb.hovered and use == .ok) d.border(dl, r, ctx.col(.accent), 8, 2);
        if (hb.hovered) c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
        var tb: [160]u8 = undefined;
        const why: []const u8 = switch (use) {
            .ok => st.name,
            .needs_nitro => i18n.fmt(&tb, "{s} · precisa de Nitro fora do servidor dela", "{s} · needs Nitro outside its server", .{st.name}),
            .no_permission => i18n.fmt(&tb, "{s} · este canal não permite figurinhas de fora", "{s} · this channel doesn't allow external stickers", .{st.name}),
            .unavailable => i18n.fmt(&tb, "{s} · indisponível (o servidor perdeu o impulso)", "{s} · unavailable (the server lost its boost)", .{st.name}),
        };
        d.tip(ctx, r, why, hb.hovered);
        return hb.clicked and use == .ok;
    }
};

var query: []const u8 = "";

fn lockIcon(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba) void {
    d.border(dl, .{ .x = cx - 3.5, .y = cy - 7, .w = 7, .h = 8 }, col, 3.5, 1.5);
    d.rect(dl, .{ .x = cx - 5.5, .y = cy - 2, .w = 11, .h = 8 }, col, 2);
}

fn centered(ctx: *d.Ctx, dl: *c.ImDrawList, area: d.Rect, y: f32, msg: []const u8) void {
    const f = ctx.ui.get(.medium);
    d.text(dl, f, 13, area.x + @max(0, (area.w - d.width(f, 13, msg)) / 2), y, ctx.col(.muted), msg);
}

/// O corpo da aba, de `top` até o fim do seletor `r`. `q` filtra pelo nome.
pub fn body(ctx: *d.Ctx, r: d.Rect, top: f32, q: []const u8, appearing: bool) void {
    const store = ctx.store;
    const ch_id = ctx.st.activeChannel() orelse return;
    const cs = store.channel(ch_id) orelse return;
    const book = &store.stickers;
    // Os pacotes padrão só vêm quando a aba abre (uma vez por sessão).
    if (book.packs_state == .none) ctx.act(.fetch_sticker_packs);
    query = q;
    const here = cs.info.guild;
    const area: d.Rect = .{ .x = r.x + 10, .y = top, .w = r.w - 12, .h = r.bottom() - 10 - top };
    if (appearing) c.ImGui_SetNextWindowScroll(d.v(-1, 0));
    const gdl = d.beginRegion(ctx, "##sticker-grid", area, 0);
    defer c.ImGui_EndChild();
    popup.track(gdl);
    const inner_w = area.w - 14;
    const cols: usize = @max(1, @as(usize, @intFromFloat((inner_w + gap) / (cell + gap))));
    const cell_w = (inner_w - gap * @as(f32, @floatFromInt(cols - 1))) / @as(f32, @floatFromInt(cols));

    // Seções: o servidor aberto, os outros servidores (na ordem da barra) e os pacotes.
    var total: f32 = 0;
    const measure = struct {
        fn f(n: usize, cs_: usize) f32 {
            if (n == 0) return 0;
            return head_h + @as(f32, @floatFromInt((n + cs_ - 1) / cs_)) * (cell + gap);
        }
    }.f;
    const own: []const stickers.Sticker = if (here != 0) (book.guilds.get(here) orelse &.{}) else &.{};
    total += measure(count(own, q), cols);
    for (store.guilds.items) |*g| if (g.id != here) {
        if (book.guilds.get(g.id)) |list| total += measure(count(list, q), cols);
    };
    for (book.packs) |p| total += measure(count(p.stickers, q), cols);
    const status_h: f32 = if (book.packs_state == .ready) 0 else 64;
    c.ImGui_Dummy(d.v(inner_w, @max(total + status_h, 1)));
    const scroll = c.ImGui_GetScrollY();

    var l: Layout = .{ .ctx = ctx, .dl = gdl, .area = area, .scroll = scroll, .cols = cols, .cell_w = cell_w, .here = here, .perms = store.channelPermissions(&cs.info), .channel = ch_id };
    if (here != 0) if (store.guild(here)) |g| l.section(.{ .title = g.name, .list = own, .n = count(own, q) });
    for (store.guilds.items) |*g| if (g.id != here) {
        if (book.guilds.get(g.id)) |list| l.section(.{ .title = g.name, .list = list, .n = count(list, q) });
    };
    for (book.packs) |p| l.section(.{ .title = p.name, .list = p.stickers, .n = count(p.stickers, q) });

    const sy = area.y - scroll + l.y + 12;
    switch (book.packs_state) {
        .none, .loading => centered(ctx, gdl, area, sy, i18n.tr("Carregando os pacotes de figurinhas…", "Loading sticker packs…")),
        .failed => {
            centered(ctx, gdl, area, sy, i18n.tr("Não deu para carregar os pacotes.", "Couldn't load the sticker packs."));
            const label = i18n.tr("Tentar de novo", "Try again");
            const bf = ctx.ui.get(.semibold);
            const tw = d.width(bf, 13, label) + 24;
            const bb: d.Rect = .{ .x = area.x + (area.w - tw) / 2, .y = sy + 24, .w = tw, .h = 26 };
            const bh = d.hit(ctx, 8960, bb);
            qa.mark(bb, "sticker-retry", .{});
            d.rect(gdl, bb, if (bh.hovered) ctx.col(.hover) else ctx.col(.elevated), 6);
            d.text(gdl, bf, 13, bb.x + 12, d.centerY(bb, 13), ctx.col(.text), label);
            if (bh.clicked) ctx.act(.fetch_sticker_packs);
        },
        .ready => if (total == 0) centered(ctx, gdl, area, area.y + 40, if (q.len > 0) i18n.tr("Nada encontrado.", "Nothing found.") else i18n.tr("Nenhuma figurinha por aqui.", "No stickers here.")),
    }
    if (l.chosen) |id| {
        ctx.act(.{ .send_sticker = .{ .channel = ch_id, .sticker = id } });
        popup.close(ctx);
    }
}
