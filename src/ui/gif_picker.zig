//! Seletor de GIFs (o botão ao lado dos emojis). Em alta e busca vêm do Discord, os
//! favoritos vêm das configurações da conta, e o GIF escolhido vai como o link dele, como
//! no app oficial. As imagens ficam no Tenor: sem "Animar GIFs do Tenor e do Giphy" ligado,
//! o app não fala com ele e o seletor pede a permissão antes.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const icons = @import("icons.zig");
const popup = @import("popup.zig");
const media_url = @import("../net/media_url.zig");
const types = @import("../core/types.zig");
const store_mod = @import("../core/store.zig");

const pad: f32 = 10;
const gap: f32 = 6;
const cell_h: f32 = 112;
/// Espera a pessoa parar de digitar antes de ir ao Discord.
const type_wait_ms: i64 = 350;

var query: [96]u8 = @splat(0);
var searched: [96]u8 = @splat(0);
var tab: u8 = 0;
var pending_scroll: ?f32 = null;
var search_due: i64 = 0;
/// O que está na lista de resultados agora.
var listed: [96]u8 = @splat(0);
/// A aba de figurinhas acabou de aparecer (volta a rolagem ao topo).
var sticker_was_open = false;

fn stickerAppearing() bool {
    defer sticker_was_open = tab == 2;
    return tab == 2 and !sticker_was_open;
}

fn request(ctx: *d.Ctx, q: []const u8) void {
    const owned = ctx.st.gpa.dupe(u8, q) catch return;
    ctx.act(.{ .gif_search = owned });
    @memset(&listed, 0);
    @memcpy(listed[0..q.len], q);
    search_due = 0;
    pending_scroll = 0;
}

/// Da nossa casa (Discord, demonstração, arquivo) ou de outro site?
fn external(url: []const u8) bool {
    return url.len > 0 and !std.mem.startsWith(u8, url, "demo:") and !std.mem.startsWith(u8, url, "file://") and !media_url.discordHost(url);
}

/// O nome legível do link: tenor.com/view/gato-dancando-gif-123 vira gato-dancando-gif-123.
fn nameOf(g: types.Gif) []const u8 {
    if (g.title.len > 0) return g.title;
    const end = std.mem.indexOfAny(u8, g.url, "?#") orelse g.url.len;
    const start = if (std.mem.lastIndexOfScalar(u8, g.url[0..end], '/')) |i| i + 1 else 0;
    return g.url[start..end];
}

fn drawCell(ctx: *d.Ctx, dl: *c.ImDrawList, g: types.Gif, i: usize, r: d.Rect) bool {
    const hb = d.hit(ctx, 9000 + i, r);
    qa.mark(r, "gif:{d}", .{i});
    d.rect(dl, r, ctx.col(.elevated), 6);
    const scale = ctx.io.*.DisplayFramebufferScale.x;
    const allowed = ctx.st.settings.gif_hosts;
    const still = if (g.preview.len > 0) g.preview else g.src;
    var drawn = false;
    // Parado economiza memória: só anima o que está sob o mouse.
    if (hb.hovered and (allowed or !external(g.src))) switch (ctx.images.get(g.src, r.w * scale, r.h * scale)) {
        .ready => |t| {
            @import("embeds.zig").imageCover(dl, t, r, 1, 6, 0);
            drawn = true;
        },
        else => {},
    };
    if (!drawn and (allowed or !external(still))) switch (if (g.preview.len > 0) ctx.images.get(still, r.w * scale, r.h * scale) else ctx.images.getStill(still, r.w * scale, r.h * scale)) {
        .ready => |t| {
            @import("embeds.zig").imageCover(dl, t, r, 1, 6, 0);
            drawn = true;
        },
        else => {},
    };
    if (!drawn) {
        const f = ctx.ui.get(.medium);
        _ = d.textClipped(dl, f, 12, r.x + 8, d.centerY(r, 12), ctx.col(.muted), nameOf(g), r.w - 16);
    }
    if (hb.hovered) d.border(dl, r, ctx.col(.accent), 6, 2);
    d.tip(ctx, r, nameOf(g), hb.hovered);
    return hb.clicked;
}

fn send(ctx: *d.Ctx, g: types.Gif) void {
    const text = ctx.st.gpa.dupe(u8, g.url) catch return;
    ctx.act(.{ .send_message = text });
    popup.close(ctx);
}

fn centered(ctx: *d.Ctx, dl: *c.ImDrawList, body: d.Rect, y: f32, msg: []const u8) void {
    const f = ctx.ui.get(.medium);
    d.text(dl, f, 13, body.x + @max(0, (body.w - d.width(f, 13, msg)) / 2), y, ctx.col(.muted), msg);
}

pub fn draw(ctx: *d.Ctx, x: f32, y: f32) void {
    const font = ctx.ui.get(.regular);
    if (popup.appearing) {
        @memset(&query, 0);
        @memset(&searched, 0);
        tab = 0;
        pending_scroll = 0;
        search_due = 0;
        const list = ctx.store.gif_results;
        // Em alta muda devagar: só pede de novo se a lista guardada for de uma busca.
        if (list.state == .none or list.state == .failed or listed[0] != 0) request(ctx, "");
    }
    const wd: f32 = 420;
    const h = @min(@as(f32, 480), ctx.win.h - 16);
    const r = popup.fit(ctx, x - wd + 40, y - h - 8, wd, h);
    const dl = popup.beginWindow("##gifs", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    const radius = @max(ctx.th.radius + 2, 6);
    d.shadow(dl, r, radius, 16, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.overlay), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    qa.mark(r, "gif-picker", .{});

    // Busca.
    const sb: d.Rect = .{ .x = r.x + pad, .y = r.y + pad, .w = r.w - pad * 2, .h = 32 };
    qa.mark(sb, "gif-search", .{});
    const fs: f32 = 14;
    d.rect(dl, sb, ctx.col(.elevated), @max(ctx.th.radius, 4));
    icons.search(dl, sb.x + 16, sb.y + 16, ctx.col(.faint).u());
    c.ImGui_PushFontFloat(font, fs * d.text_scale);
    c.ImGui_PushStyleColorImVec4(c.ImGuiCol_FrameBg, .{ .x = 0, .y = 0, .z = 0, .w = 0 });
    c.ImGui_SetCursorScreenPos(d.v(sb.x + 28, sb.y + 5));
    c.ImGui_SetNextItemWidth(sb.w - 34);
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    const stickers_tab = tab == 2;
    const hint = if (stickers_tab) i18n.trZ("Buscar figurinhas", "Search stickers") else i18n.trZ("Buscar GIFs", "Search GIFs");
    const enter = c.ImGui_InputTextWithHint("##gif-q", hint.ptr, &query, query.len, c.ImGuiInputTextFlags_EnterReturnsTrue);
    c.ImGui_PopStyleColor();
    c.ImGui_PopFont();
    const q = std.mem.sliceTo(&query, 0);
    if (!std.mem.eql(u8, q, std.mem.sliceTo(&searched, 0))) {
        searched = query;
        search_due = ctx.now_ms + type_wait_ms;
    }
    // Na aba de figurinhas a busca é local (pelo nome): nada vai ao Discord.
    if (stickers_tab) search_due = 0;
    if (search_due != 0 and (enter or ctx.now_ms >= search_due)) request(ctx, q);
    // O app dorme sem entrada: acorda quando a espera acabar.
    if (search_due != 0) @import("anim.zig").at(search_due);
    const searching = q.len > 0 and !stickers_tab;

    var ty = sb.bottom() + 8;
    if (!searching) {
        var tx = r.x + pad;
        const tabs = [_][]const u8{ i18n.tr("Em alta", "Trending"), i18n.tr("Favoritos", "Favorites"), i18n.tr("Figurinhas", "Stickers") };
        for (tabs, 0..) |t, i| {
            const f = ctx.ui.get(.semibold);
            const tw = d.width(f, 13, t) + 20;
            const tr: d.Rect = .{ .x = tx, .y = ty, .w = tw, .h = 26 };
            const hb = d.hit(ctx, 8900 + i, tr);
            qa.mark(tr, "gif-tab:{d}", .{i});
            const on = tab == i;
            if (on) d.rect(dl, tr, ctx.col(.accent).alpha(0.18), 6) else if (hb.hovered) d.rect(dl, tr, ctx.col(.hover), 6);
            d.text(dl, f, 13, tr.x + 10, d.centerY(tr, 13), if (on) ctx.col(.accent).mix(ctx.col(.text), 0.4) else ctx.col(.muted), t);
            if (hb.clicked and !on) {
                // Saindo das figurinhas com algo digitado: vira busca de GIFs.
                if (tab == 2 and q.len > 0) search_due = ctx.now_ms;
                tab = @intCast(i);
                pending_scroll = 0;
                if (i == 1 and ctx.store.gif_favorites.state != .ready and ctx.store.gif_favorites.state != .loading) ctx.act(.gif_favorites);
            }
            tx += tw + 4;
        }
        ty += 32;
    }
    const sticker_fresh = stickerAppearing();
    if (stickers_tab) return @import("sticker_picker.zig").body(ctx, r, ty, q, sticker_fresh);
    const favorites = tab == 1 and !searching;
    const list: store_mod.GifList = if (favorites) ctx.store.gif_favorites else ctx.store.gif_results;

    // Sem a permissão, não fala com o site de fora: explica e deixa ligar aqui mesmo.
    var needs_ok = false;
    if (!ctx.st.settings.gif_hosts) for (list.items) |g| {
        if (external(if (g.preview.len > 0) g.preview else g.src)) {
            needs_ok = true;
            break;
        }
    };
    if (needs_ok) {
        const br: d.Rect = .{ .x = r.x + pad, .y = ty, .w = r.w - pad * 2, .h = 56 };
        d.rect(dl, br, ctx.col(.elevated), 6);
        const small = ctx.ui.get(.regular);
        _ = d.textClipped(dl, small, 12, br.x + 10, br.y + 9, ctx.col(.text), i18n.tr("As prévias ficam no site do Tenor, que vê o seu IP.", "Previews are hosted by Tenor, which sees your IP."), br.w - 20);
        const label = i18n.tr("Ligar prévias", "Turn on previews");
        const bf = ctx.ui.get(.semibold);
        const bb: d.Rect = .{ .x = br.x + 10, .y = br.y + 27, .w = d.width(bf, 12, label) + 18, .h = 22 };
        const bh = d.hit(ctx, 8950, bb);
        qa.mark(bb, "gif-previews-on", .{});
        d.rect(dl, bb, if (bh.hovered) ctx.col(.accent).mix(d.Rgba.white, 0.12) else ctx.col(.accent), 5);
        d.text(dl, bf, 12, bb.x + 9, d.centerY(bb, 12), ctx.col(.accent_text), label);
        if (bh.clicked) ctx.st.settings.gif_hosts = true;
        ty += br.h + 8;
    }

    const body: d.Rect = .{ .x = r.x + pad, .y = ty, .w = r.w - pad - 2, .h = r.bottom() - pad - ty };
    const col_w = (r.w - pad * 2 - gap) / 2;
    const rows = (list.items.len + 1) / 2;
    const total = @as(f32, @floatFromInt(rows)) * (cell_h + gap);

    if (pending_scroll) |p| {
        c.ImGui_SetNextWindowScroll(d.v(-1, p));
        pending_scroll = null;
    }
    const gdl = d.beginRegion(ctx, "##gif-grid", body, 0);
    popup.track(gdl);
    c.ImGui_Dummy(d.v(body.w - 14, @max(total, 1)));
    const scroll = c.ImGui_GetScrollY();
    var chosen: ?types.Gif = null;
    if (list.state != .loading) for (list.items, 0..) |g, i| {
        const row: f32 = @floatFromInt(i / 2);
        const col: f32 = @floatFromInt(i % 2);
        const cell: d.Rect = .{ .x = body.x + col * (col_w + gap), .y = body.y - scroll + row * (cell_h + gap), .w = col_w, .h = cell_h };
        // Fora da tela não baixa nada.
        if (cell.bottom() < body.y or cell.y > body.bottom()) continue;
        if (drawCell(ctx, gdl, g, i, cell)) chosen = g;
    };
    const my = body.y + 40;
    switch (list.state) {
        .none, .loading => centered(ctx, gdl, body, my, i18n.tr("Carregando…", "Loading…")),
        .failed => {
            centered(ctx, gdl, body, my, i18n.tr("Não deu para carregar os GIFs.", "Couldn't load the GIFs."));
            const label = i18n.tr("Tentar de novo", "Try again");
            const bf = ctx.ui.get(.semibold);
            const tw = d.width(bf, 13, label) + 24;
            const bb: d.Rect = .{ .x = body.x + (body.w - tw) / 2, .y = my + 28, .w = tw, .h = 28 };
            const bh = d.hit(ctx, 8951, bb);
            qa.mark(bb, "gif-retry", .{});
            d.rect(gdl, bb, if (bh.hovered) ctx.col(.hover) else ctx.col(.elevated), 6);
            d.text(gdl, bf, 13, bb.x + 12, d.centerY(bb, 13), ctx.col(.text), label);
            if (bh.clicked) {
                if (favorites) ctx.act(.gif_favorites) else request(ctx, q);
            }
        },
        .ready => if (list.items.len == 0) centered(ctx, gdl, body, my, if (favorites) i18n.tr("Você ainda não tem GIFs favoritos.", "You have no favorite GIFs yet.") else i18n.tr("Nada encontrado.", "Nothing found.")),
    }
    c.ImGui_EndChild();
    if (chosen) |g| send(ctx, g);
}
