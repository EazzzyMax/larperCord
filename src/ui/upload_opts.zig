//! Spoiler e texto alternativo dos arquivos da bandeja, antes de enviar: os
//! dois botões no cartão de cada arquivo e a janelinha do texto alternativo.
//! Vão no envio como `SPOILER_` no nome e `description` do anexo.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const inbox = @import("inbox.zig");
const forum = @import("forum.zig");
const envio = @import("../core/envio.zig");
const Upload = @import("state.zig").Upload;

/// O texto sendo editado (até 1024 caracteres de até 4 bytes, e o 0 do fim).
var alt_buf: [envio.max_alt * 4 + 1]u8 = @splat(0);

/// Os botões ALT e SPOILER por cima da prévia (`pr`) do cartão `i`. Com o
/// spoiler ligado, a prévia fica coberta como vai aparecer para os outros.
pub fn cardButtons(ctx: *d.Ctx, dl: *c.ImDrawList, i: usize, u: *Upload, pr: d.Rect) void {
    const fam = ctx.ui;
    if (u.spoiler) {
        d.rect(dl, pr, ctx.col(.rail).alpha(0.88), 4);
        const t = "SPOILER";
        d.text(dl, fam.get(.bold), 10.5, pr.x + (pr.w - d.width(fam.get(.bold), 10.5, t)) / 2, pr.y + 12, ctx.col(.text), t);
    }
    const radius: f32 = 4;
    // ALT: aceso quando já tem texto.
    const ar: d.Rect = .{ .x = pr.x + 3, .y = pr.bottom() - 21, .w = 30, .h = 18 };
    const ah = d.hit(ctx, 0x7400 + i, ar);
    qa.mark(ar, "upload-alt:{d}", .{i});
    const has_alt = u.alt.len > 0;
    d.rect(dl, ar, if (has_alt) ctx.col(.accent) else ctx.col(.overlay).alpha(if (ah.hovered) 1 else 0.85), radius);
    d.text(dl, fam.get(.bold), 10.5, ar.x + (ar.w - d.width(fam.get(.bold), 10.5, "ALT")) / 2, d.centerY(ar, 10.5), if (has_alt) ctx.col(.accent_text) else ctx.col(.text), "ALT");
    d.tip(ctx, ar, if (has_alt) i18n.tr("Editar texto alternativo", "Edit alt text") else i18n.tr("Texto alternativo", "Alt text"), ah.hovered);
    if (ah.clicked) {
        load(u.alt);
        ctx.popup(.{ .upload_alt = .{ .index = @intCast(i), .x = ar.x, .y = ar.y } });
    }
    // Olho: marcar como spoiler.
    const sr: d.Rect = .{ .x = ar.right() + 4, .y = ar.y, .w = 24, .h = 18 };
    const sh = d.hit(ctx, 0x7480 + i, sr);
    qa.mark(sr, "upload-spoiler:{d}", .{i});
    d.rect(dl, sr, if (u.spoiler) ctx.col(.accent) else ctx.col(.overlay).alpha(if (sh.hovered) 1 else 0.85), radius);
    eye(dl, sr.x + sr.w / 2, sr.y + sr.h / 2, if (u.spoiler) ctx.col(.accent_text) else ctx.col(.text), u.spoiler);
    d.tip(ctx, sr, if (u.spoiler) i18n.tr("Tirar o spoiler", "Remove spoiler") else i18n.tr("Marcar como spoiler", "Mark as spoiler"), sh.hovered);
    if (sh.clicked) u.spoiler = !u.spoiler;
}

fn load(alt: []const u8) void {
    const n = @min(alt.len, alt_buf.len - 1);
    @memcpy(alt_buf[0..n], alt[0..n]);
    @memset(alt_buf[n..], 0);
}

/// Olho (riscado quando escondido).
fn eye(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba, hidden: bool) void {
    const pts = [_]c.ImVec2{ d.v(cx - 7, cy), d.v(cx - 3.5, cy - 3.6), d.v(cx, cy - 4.6), d.v(cx + 3.5, cy - 3.6), d.v(cx + 7, cy), d.v(cx + 3.5, cy + 3.6), d.v(cx, cy + 4.6), d.v(cx - 3.5, cy + 3.6) };
    c.ImDrawList_AddPolyline(dl, &pts, pts.len, col.u(), 1.4, c.ImDrawFlags_Closed);
    d.circle(dl, cx, cy, 1.9, col);
    if (hidden) d.line(dl, cx - 6, cy + 5, cx + 6, cy - 5, col, 1.5);
}

/// A janelinha do texto alternativo do arquivo `index`.
pub fn drawAlt(ctx: *d.Ctx, index: u8, x: f32, y: f32) void {
    _ = x;
    _ = y;
    const st = ctx.st;
    if (index >= st.uploads.items.len) return popup.close(ctx);
    const u = &st.uploads.items[index];
    const r = forum.dialogRect(ctx, 460, 236);
    const dl = popup.beginWindow("##upload-alt", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    qa.mark(r, "upload-alt-panel", .{});
    const fam = ctx.ui;
    d.text(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.tr("Texto alternativo", "Alt text"));
    _ = d.textClipped(dl, fam.get(.regular), 13, r.x + 18, r.y + 44, ctx.col(.muted), i18n.tr("Descreve o arquivo para quem usa leitor de tela.", "Describes the file for people using screen readers."), r.w - 36);
    const body: d.Rect = .{ .x = r.x + 18, .y = r.y + 70, .w = r.w - 36, .h = 86 };
    d.rect(dl, body, ctx.col(.rail).mix(ctx.col(.surface), 0.35), @max(ctx.th.radius, 2));
    qa.mark(body, "upload-alt-input", .{});
    c.ImGui_PushFontFloat(fam.get(.regular), 14);
    c.ImGui_SetCursorScreenPos(d.v(body.x + 6, body.y + 6));
    if (alt_buf[0] == 0) d.text(dl, fam.get(.regular), 14, body.x + 11, body.y + 9, ctx.col(.faint), u.name());
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    // Enter salva; Shift+Enter (ou Ctrl+Enter) quebra a linha, como na caixa de texto.
    const enter = c.ImGui_InputTextMultilineEx("##upload-alt", &alt_buf, alt_buf.len, d.v(body.w - 12, body.h - 12), c.ImGuiInputTextFlags_WordWrap | c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_CtrlEnterForNewLine, null, null);
    c.ImGui_PopFont();
    const text = std.mem.trim(u8, std.mem.sliceTo(&alt_buf, 0), " \t\r\n");
    const kept = envio.clampAlt(text);
    var cb: [32]u8 = undefined;
    const chars = std.unicode.utf8CountCodepoints(text) catch text.len;
    const count = std.fmt.bufPrint(&cb, "{d}/{d}", .{ chars, envio.max_alt }) catch "";
    d.text(dl, fam.get(.regular), 12, body.right() - d.width(fam.get(.regular), 12, count), body.bottom() + 6, if (chars > envio.max_alt) ctx.col(.danger) else ctx.col(.faint), count);

    const lbl = i18n.tr("Salvar", "Save");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - bw, .y = r.bottom() - 48, .w = bw, .h = 34 };
    qa.mark(br, "upload-alt-save", .{});
    const save = forum.primary(ctx, dl, fam, 0x7500, br, lbl, true);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "upload-alt-cancel", .{});
    if (inbox.button(ctx, dl, 0x7501, cr, cancel, false)) return popup.close(ctx);
    if (save or enter) {
        const ca = std.heap.c_allocator;
        const owned: []u8 = if (kept.len > 0) ca.dupe(u8, kept) catch return else &.{};
        if (u.alt.len > 0) ca.free(u.alt);
        u.alt = owned;
        popup.close(ctx);
    }
}
