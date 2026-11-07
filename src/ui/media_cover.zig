//! Spoiler e conteúdo sensível nos anexos: uma capa no tema por cima, até o
//! clique. A escolha vale para a mensagem inteira e só nesta sessão (nada fica
//! gravado). Coberto, nada é baixado: a imagem só vem depois do clique.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const types = @import("../core/types.zig");

pub const Kind = enum { spoiler, sensitive };

/// Mensagens que a pessoa abriu nesta sessão.
var shown: std.AutoHashMapUnmanaged(types.Id, void) = .empty;

/// O que cobre esta mídia agora (null = nada). Sensível ganha do spoiler;
/// "Sempre mostrar spoilers" vale só para o spoiler.
pub fn hidden(ctx: *const d.Ctx, msg_id: types.Id, spoiler: bool, sensitive: bool) ?Kind {
    const k: Kind = if (sensitive) .sensitive else if (spoiler and !ctx.st.settings.show_spoilers) .spoiler else return null;
    if (msg_id != 0 and shown.contains(msg_id)) return null;
    return k;
}

pub fn reveal(msg_id: types.Id) void {
    if (msg_id == 0) return;
    shown.put(std.heap.c_allocator, msg_id, {}) catch {};
}

pub fn revealed(msg_id: types.Id) bool {
    return shown.contains(msg_id);
}

/// A capa sobre `r`; o clique mostra tudo o que estava coberto na mensagem.
pub fn draw(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, kind: Kind, hid: usize, msg_id: types.Id, alpha: f32) void {
    const hb = d.hit(ctx, hid ^ 0xC0FE_0000, r);
    const radius: f32 = @max(ctx.th.radius, 6);
    const base = ctx.col(.elevated).mix(ctx.col(.text), if (hb.hovered) 0.07 else 0.03);
    d.rect(dl, r, base.alpha(alpha), radius);
    // Listras finas na diagonal: a capa não parece um buraco vazio.
    c.ImDrawList_PushClipRect(dl, d.v(r.x, r.y), d.v(r.right(), r.bottom()), true);
    const stripe = ctx.col(.text).alpha(0.035 * alpha);
    var sx = r.x - r.h;
    while (sx < r.right()) : (sx += 14) d.line(dl, sx, r.bottom(), sx + r.h, r.y, stripe, 5);
    c.ImDrawList_PopClipRect(dl);
    const edge = if (kind == .sensitive) ctx.col(.danger).alpha(0.55 * alpha) else ctx.col(.border).alpha(alpha);
    d.border(dl, r, edge, radius, 1);

    const label = if (kind == .sensitive) i18n.tr("Conteúdo sensível", "Sensitive content") else i18n.tr("Spoiler", "Spoiler");
    const f = ctx.ui.get(.bold);
    const fs: f32 = 13;
    const icon_w: f32 = if (kind == .sensitive) 18 else 0;
    const pw = d.width(f, fs, label) + 24 + icon_w;
    const tall = r.h > 64;
    const pill: d.Rect = .{ .x = r.x + (r.w - pw) / 2, .y = r.y + r.h / 2 - (if (tall) @as(f32, 22) else 13), .w = pw, .h = 26 };
    if (pill.w < r.w - 4) {
        d.rect(dl, pill, ctx.col(.rail).alpha(0.92 * alpha), 13);
        var tx = pill.x + 12;
        if (kind == .sensitive) {
            warnIcon(dl, tx + 6, pill.y + 13, ctx.col(.danger).alpha(alpha));
            tx += icon_w;
        }
        d.text(dl, f, fs, tx, d.centerY(pill, fs), ctx.col(.text).alpha(alpha), label);
        if (tall) {
            const small = ctx.ui.get(.regular);
            const hint = i18n.tr("clique para ver", "click to reveal");
            const hw = d.width(small, 12, hint);
            if (hw < r.w - 8) d.text(dl, small, 12, r.x + (r.w - hw) / 2, pill.bottom() + 8, ctx.col(.muted).alpha(alpha), hint);
        }
    }
    if (hb.hovered) c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
    d.tip(ctx, r, if (kind == .sensitive) i18n.tr("Marcado pelo Discord como sensível. Clique para mostrar.", "Flagged by Discord as sensitive. Click to show.") else i18n.tr("Clique para mostrar o spoiler", "Click to show the spoiler"), hb.hovered);
    qa.mark(r, "cover:{d}", .{msg_id});
    if (hb.clicked) reveal(msg_id);
}

fn warnIcon(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba) void {
    c.ImDrawList_AddTriangleEx(dl, d.v(cx, cy - 6.5), d.v(cx + 7, cy + 5.5), d.v(cx - 7, cy + 5.5), col.u(), 1.6, 0);
    d.line(dl, cx, cy - 2.5, cx, cy + 1.5, col, 1.6);
    d.circle(dl, cx, cy + 3.6, 0.9, col);
}
