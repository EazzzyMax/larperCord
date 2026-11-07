//! A estrela dos GIFs: em cima do GIF na conversa (com o mouse) e em cada GIF do
//! seletor. Liga e desliga nos favoritos da conta (net/discord.zig grava, só mexendo
//! nos favoritos; core/gif_favorites.zig). A lista muda na hora e a resposta confirma.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const i18n = @import("i18n.zig");
const icons = @import("icons.zig");
const types = @import("../core/types.zig");
const media_url = @import("../net/media_url.zig");

const size: f32 = 28;
const inset: f32 = 6;

/// A chave de um GIF da conversa nos favoritos (core/gif_favorites.zig). Vazio = sem estrela.
pub fn keyOf(content: []const u8, a: *const types.Attachment) []const u8 {
    // GIF antigo do Tenor (só a página): não há endereço da mídia para guardar.
    if (std.mem.startsWith(u8, a.url, media_url.tenor_page)) return "";
    return @import("../core/gif_favorites.zig").attachmentKey(content, a);
}

/// O canto de cima, à direita, do GIF em `r`. GIF pequeno não ganha estrela: ela
/// cobriria o meio, onde o clique abre o GIF.
pub fn rect(r: d.Rect) ?d.Rect {
    if (r.w < size * 3 or r.h < size * 2) return null;
    return .{ .x = r.right() - size - inset, .y = r.y + inset, .w = size, .h = size };
}

/// O mouse está no GIF e nada cobre a janela dele: a estrela aparece. A área clicável
/// dela vem antes da do GIF (a de cima ganha o clique).
pub fn shows(ctx: *d.Ctx, r: d.Rect) bool {
    return ctx.hovering(r) and c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_ChildWindows);
}

pub fn draw(ctx: *d.Ctx, dl: *c.ImDrawList, br: d.Rect, hb: d.Hit, on: bool) void {
    const radius = @min(@max(ctx.th.radius, 4), size / 2);
    d.rect(dl, br, ctx.col(.overlay).alpha(if (hb.hovered) 1 else 0.88), radius);
    d.border(dl, br, ctx.col(.border), radius, 1);
    const col = if (on or hb.hovered) ctx.col(.accent) else ctx.col(.text);
    icons.star(dl, br.x + size / 2, br.y + size / 2 + 0.5, 8.5, col.u(), on);
    d.tip(ctx, br, if (on) i18n.tr("Tirar dos favoritos", "Remove from Favorites") else i18n.tr("Adicionar aos favoritos", "Add to Favorites"), hb.hovered);
}

/// A lista da conta ainda não veio: pede uma vez, para a estrela saber se acende.
pub fn want(ctx: *d.Ctx) void {
    if (ctx.store.gif_favorites.state == .none) ctx.act(.gif_favorites);
}

pub fn isOn(ctx: *d.Ctx, key: []const u8) bool {
    return ctx.store.gif_favorites.has(key);
}

/// Liga (`on` = false) ou desliga. `shown` é o que a tela desenha (o WebP do Tenor,
/// o GIF anexado); nos favoritos vai o MP4 dele quando existe, como no app oficial.
pub fn toggle(ctx: *d.Ctx, key: []const u8, shown: []const u8, w: u16, h: u16, on: bool) void {
    var vb: [600]u8 = undefined;
    const video = media_url.videoFromGif(&vb, shown);
    const gpa = ctx.st.gpa;
    const url = gpa.dupe(u8, key) catch return;
    const src = gpa.dupe(u8, video orelse shown) catch {
        gpa.free(url);
        return;
    };
    const sh = gpa.dupe(u8, shown) catch {
        gpa.free(url);
        gpa.free(src);
        return;
    };
    ctx.act(.{ .gif_favorite = .{ .add = !on, .url = url, .src = src, .shown = sh, .width = w, .height = h, .video = video != null } });
}
