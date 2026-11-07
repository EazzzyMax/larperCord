//! Status personalizado: texto, emoji e até quando vale. Salvar grava nas
//! configurações da conta (só esse campo; net/status_proto.zig) e aparece
//! na presença e no painel de baixo.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const forum = @import("forum.zig");
const inbox = @import("inbox.zig");
const conta = @import("../core/conta.zig");

/// 128 caracteres de até 4 bytes, mais o zero.
var text_buf: [conta.max_status_text * 4 + 1]u8 = @splat(0);
var emoji_buf: [64]u8 = @splat(0);
/// Como em `conta.expiryFor`.
var choice: u8 = 0;

const quick = [_][]const u8{ "💬", "🎧", "🎮", "💻", "📚", "🍕", "😴", "🔥" };
const expiries = [_]struct { pt: []const u8, en: []const u8 }{
    .{ .pt = "Não limpar", .en = "Don't clear" },
    .{ .pt = "30 min", .en = "30 min" },
    .{ .pt = "1 h", .en = "1 h" },
    .{ .pt = "4 h", .en = "4 h" },
    .{ .pt = "Hoje", .en = "Today" },
};

fn fill(buf: []u8, s: []const u8) void {
    @memset(buf, 0);
    const n = d.utf8Prefix(s, buf.len - 1).len;
    @memcpy(buf[0..n], s[0..n]);
}

pub fn draw(ctx: *d.Ctx, x: f32, y: f32) void {
    _ = x;
    _ = y;
    const cur = ctx.st.conta.custom;
    if (popup.appearing) {
        const live = cur.active(ctx.now_ms);
        fill(&text_buf, if (live) cur.text else "");
        fill(&emoji_buf, if (live) cur.emoji_name else "");
        choice = 0;
    }
    const r = forum.dialogRect(ctx, 440, 318);
    const dl = popup.beginWindow("##custom-status", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    qa.mark(r, "custom-status", .{});
    const fam = ctx.ui;
    d.text(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.tr("Status personalizado", "Custom status"));

    // Emoji: escrito (ou colado) ou um dos rápidos.
    d.text(dl, fam.get(.semibold), 12.5, r.x + 18, r.y + 50, ctx.col(.muted), i18n.tr("Emoji e texto", "Emoji and text"));
    const er: d.Rect = .{ .x = r.x + 18, .y = r.y + 70, .w = 56, .h = 36 };
    qa.mark(er, "custom-status-emoji", .{});
    _ = forum.textInput(ctx, dl, er, "##cs-emoji", "🙂", &emoji_buf, 0);
    const tr: d.Rect = .{ .x = er.right() + 8, .y = er.y, .w = r.right() - 18 - er.right() - 8, .h = 36 };
    qa.mark(tr, "custom-status-text", .{});
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    const enter = forum.textInput(ctx, dl, tr, "##cs-text", i18n.trZ("No que você está pensando?", "What's on your mind?"), &text_buf, c.ImGuiInputTextFlags_EnterReturnsTrue);
    const text = std.mem.sliceTo(&text_buf, 0);
    const chars = std.unicode.utf8CountCodepoints(text) catch text.len;
    var cb: [24]u8 = undefined;
    const count = std.fmt.bufPrint(&cb, "{d}/{d}", .{ chars, conta.max_status_text }) catch "";
    const over = chars > conta.max_status_text;
    d.text(dl, fam.get(.regular), 11.5, r.right() - 18 - d.width(fam.get(.regular), 11.5, count), tr.bottom() + 4, if (over) ctx.col(.danger) else ctx.col(.faint), count);

    var qx = r.x + 18;
    const qy = tr.bottom() + 22;
    for (quick, 0..) |e, i| {
        const qr: d.Rect = .{ .x = qx, .y = qy, .w = 34, .h = 32 };
        const hb = d.hit(ctx, 0x7400 + i, qr);
        qa.mark(qr, "custom-status-quick:{d}", .{i});
        const sel = std.mem.eql(u8, std.mem.sliceTo(&emoji_buf, 0), e);
        if (sel or hb.hovered) d.rect(dl, qr, if (sel) ctx.col(.accent).alpha(0.25) else ctx.col(.hover), @max(ctx.th.radius, 4));
        d.text(dl, fam.get(.regular), 18, qr.x + 7, qr.y + 5, d.Rgba.white, e);
        if (hb.clicked) fill(&emoji_buf, if (sel) "" else e);
        qx += 38;
    }

    // Até quando.
    d.text(dl, fam.get(.semibold), 12.5, r.x + 18, qy + 46, ctx.col(.muted), i18n.tr("Limpar depois de", "Clear after"));
    var sx = r.x + 18;
    const sy = qy + 66;
    for (expiries, 0..) |ex, i| {
        const label = i18n.tr(ex.pt, ex.en);
        const sw = d.width(fam.get(.semibold), 13, label) + 22;
        const sr: d.Rect = .{ .x = sx, .y = sy, .w = sw, .h = 30 };
        const hb = d.hit(ctx, 0x7410 + i, sr);
        qa.mark(sr, "custom-status-expiry:{d}", .{i});
        const on = choice == i;
        const radius = @max(ctx.th.radius, 4);
        d.rect(dl, sr, if (on) ctx.col(.accent) else if (hb.hovered) ctx.col(.hover) else ctx.col(.rail).mix(ctx.col(.surface), 0.35), radius);
        d.text(dl, fam.get(.semibold), 13, sr.x + 11, d.centerY(sr, 13), if (on) ctx.col(.accent_text) else ctx.col(.text), label);
        if (hb.clicked) choice = @intCast(i);
        sx += sw + 6;
    }

    // Salvar / limpar / cancelar.
    const busy = ctx.st.conta.status_busy;
    const lbl = if (busy) i18n.tr("Salvando…", "Saving…") else i18n.tr("Salvar", "Save");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - bw, .y = r.bottom() - 50, .w = bw, .h = 34 };
    qa.mark(br, "custom-status-save", .{});
    const emoji = std.mem.sliceTo(&emoji_buf, 0);
    const can = !busy and !over and (text.len > 0 or emoji.len > 0);
    const save = forum.primary(ctx, dl, fam, 0x7420, br, lbl, can);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "custom-status-cancel", .{});
    if (inbox.button(ctx, dl, 0x7421, cr, cancel, false)) return popup.close(ctx);
    if (cur.active(ctx.now_ms)) {
        const clear = i18n.tr("Limpar status", "Clear status");
        const kw = inbox.buttonWidth(ctx, clear);
        const kr: d.Rect = .{ .x = r.x + 18, .y = br.y + 3, .w = kw, .h = 28 };
        qa.mark(kr, "custom-status-clear", .{});
        if (inbox.button(ctx, dl, 0x7422, kr, clear, true) and !busy) {
            ctx.act(.{ .conta = .clear_custom_status });
            return popup.close(ctx);
        }
    }
    if ((save or (enter and can)) and can) {
        const t = ctx.st.gpa.dupe(u8, text) catch return;
        const e = ctx.st.gpa.dupe(u8, emoji) catch {
            ctx.st.gpa.free(t);
            return;
        };
        ctx.act(.{ .conta = .{ .custom_status = .{ .text = t, .emoji = e, .choice = choice } } });
        popup.close(ctx);
    }
}
