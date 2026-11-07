//! Opções de envio na caixa de texto: o "@ LIGADO / DESLIGADO" da barra de
//! resposta (mencionar ou não o autor da mensagem respondida) e o menu ao
//! lado dos botões (mensagem silenciosa, sem prévias de links, não mencionar
//! ninguém). As do menu valem para a próxima mensagem; a da resposta fica
//! até fechar o app.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const anim = @import("anim.zig");
const popup = @import("popup.zig");

/// Na barra "Respondendo a…", encostado à esquerda de `right`. Devolve a
/// largura que ocupou (0 = sem botão: responder a si mesmo não avisa ninguém).
pub fn replyToggle(ctx: *d.Ctx, dl: *c.ImDrawList, fam: *d.Family, bar: d.Rect, right: f32) f32 {
    const st = ctx.st;
    const f = ctx.store.findAny(st.reply_to) orelse return 0;
    if (f.m.msg.author == ctx.store.me) return 0;
    const on = st.reply_ping;
    const label = if (on) i18n.tr("@ LIGADO", "@ ON") else i18n.tr("@ DESLIGADO", "@ OFF");
    const font = fam.get(.bold);
    const tw = d.width(font, 12, label);
    const r: d.Rect = .{ .x = right - tw - 16, .y = bar.y + 6, .w = tw + 16, .h = 22 };
    const hb = d.hit(ctx, 0x0E41, r);
    qa.mark(r, "reply-ping", .{});
    if (hb.hovered) d.rect(dl, r, ctx.col(.hover), 11);
    d.text(dl, font, 12, r.x + 8, d.centerY(r, 12), if (on) ctx.col(.accent) else ctx.col(.muted), label);
    d.tip(ctx, r, if (on) i18n.tr("Quem escreveu vai ser mencionado", "The author will be pinged") else i18n.tr("Quem escreveu não vai ser mencionado", "The author won't be pinged"), hb.hovered);
    if (hb.clicked) {
        st.reply_ping = !on;
        st.focus_input = true;
    }
    return r.w + 6;
}

/// O botão do menu de opções. `prompt`: o tema de terminal (texto entre colchetes).
pub fn button(ctx: *d.Ctx, dl: *c.ImDrawList, fam: *d.Family, r: d.Rect, prompt: bool) void {
    const o = ctx.st.send_opts;
    const n = o.count();
    const hb = d.hit(ctx, 0x0E42, r);
    qa.mark(r, "compose-options", .{});
    const ink = if (n > 0) ctx.col(.accent) else if (hb.hovered) ctx.col(.text) else ctx.col(.muted);
    if (prompt) {
        const fs = ctx.th.font_size;
        d.text(dl, fam.get(.bold), fs, r.x + 4, d.centerY(r, fs), ink, if (n > 0) "[!]" else "[~]");
    } else {
        sliders(dl, r.x + r.w / 2, r.y + r.h / 2, ink);
        if (n > 0) {
            // Quantas estão ligadas, num pontinho no canto.
            const bx = r.right() - 3;
            const by = r.y + 3;
            d.circle(dl, bx, by, 7, ctx.col(.accent));
            var nb: [4]u8 = undefined;
            const t = std.fmt.bufPrint(&nb, "{d}", .{n}) catch "";
            d.text(dl, fam.get(.bold), 10, bx - d.width(fam.get(.bold), 10, t) / 2, by - d.fontPx(10) / 2, ctx.col(.accent_text), t);
        }
    }
    var tb: [160]u8 = undefined;
    d.tip(ctx, r, activeText(&tb, o), hb.hovered);
    if (hb.clicked) ctx.popup(.{ .compose_options = .{ .x = r.right(), .y = r.y } });
}

/// "Opções de envio", ou as que estão ligadas.
fn activeText(buf: []u8, o: @import("../core/envio.zig").SendOpts) []const u8 {
    if (o.count() == 0) return i18n.tr("Opções de envio", "Send options");
    var wr = std.Io.Writer.fixed(buf);
    var first = true;
    const parts = [_]struct { on: bool, t: []const u8 }{
        .{ .on = o.silent, .t = i18n.tr("silenciosa", "silent") },
        .{ .on = o.no_embeds, .t = i18n.tr("sem prévias", "no previews") },
        .{ .on = o.no_pings, .t = i18n.tr("sem menções", "no pings") },
    };
    for (parts) |p| if (p.on) {
        wr.print("{s}{s}", .{ if (first) "" else " · ", p.t }) catch break;
        first = false;
    };
    return wr.buffered();
}

/// Três controles deslizantes: o ícone de "opções".
fn sliders(dl: *c.ImDrawList, cx: f32, cy: f32, ink: d.Rgba) void {
    const knobs = [_]f32{ -3.5, 3.5, -1 };
    for (knobs, 0..) |kx, i| {
        const y = cy - 5 + @as(f32, @floatFromInt(i)) * 5;
        d.line(dl, cx - 7, y, cx + 7, y, ink, 1.6);
        d.circle(dl, cx + kx, y, 2.6, ink);
    }
}

const Row = struct { field: enum { silent, embeds, pings }, title: []const u8, desc: []const u8, mark: []const u8 };

/// O menu: cada linha liga ou desliga uma opção da próxima mensagem.
pub fn drawMenu(ctx: *d.Ctx, x: f32, y: f32) void {
    const st = ctx.st;
    const rows = [_]Row{
        .{ .field = .silent, .title = i18n.tr("Mensagem silenciosa", "Silent message"), .desc = i18n.tr("Ninguém recebe notificação (como @silent)", "Nobody gets a notification (like @silent)"), .mark = "silent" },
        .{ .field = .embeds, .title = i18n.tr("Sem prévias de links", "No link previews"), .desc = i18n.tr("Os links vão sem o cartão de prévia", "Links are sent without the preview card"), .mark = "embeds" },
        .{ .field = .pings, .title = i18n.tr("Não mencionar ninguém", "Don't ping anyone"), .desc = i18n.tr("As @menções ficam no texto, sem avisar", "@mentions stay in the text, without pinging"), .mark = "pings" },
    };
    const fam = ctx.ui;
    const wd = @min(340, ctx.win.w - 24);
    const row_h: f32 = 54;
    const h: f32 = 40 + row_h * rows.len + 34;
    const r = popup.fit(ctx, x - wd, y - h - 8, wd, h);
    const dl = popup.beginWindow("##compose-options", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    const radius = @max(ctx.th.radius, 6);
    d.shadow(dl, r, radius, 14, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.overlay), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    qa.mark(r, "compose-options-menu", .{});
    d.text(dl, fam.get(.bold), 12.5, r.x + 16, r.y + 14, ctx.col(.muted), i18n.tr("PRÓXIMA MENSAGEM", "NEXT MESSAGE"));
    var yy = r.y + 40;
    for (rows, 0..) |row, i| {
        const rr: d.Rect = .{ .x = r.x + 6, .y = yy, .w = r.w - 12, .h = row_h - 4 };
        const hb = d.hit(ctx, 0x0E50 + i, rr);
        qa.mark(rr, "compose-opt:{s}", .{row.mark});
        if (hb.hovered) d.rect(dl, rr, ctx.col(.hover), @max(ctx.th.radius - 2, 3));
        const value: *bool = switch (row.field) {
            .silent => &st.send_opts.silent,
            .embeds => &st.send_opts.no_embeds,
            .pings => &st.send_opts.no_pings,
        };
        if (hb.clicked) value.* = !value.*;
        _ = d.textClipped(dl, fam.get(.medium), 14, rr.x + 10, rr.y + 7, ctx.col(.text), row.title, rr.w - 70);
        _ = d.textClipped(dl, fam.get(.regular), 12, rr.x + 10, rr.y + 28, ctx.col(.muted), row.desc, rr.w - 70);
        const sw: d.Rect = .{ .x = rr.right() - 50, .y = rr.y + rr.h / 2 - 11, .w = 38, .h = 22 };
        toggle(ctx, dl, sw, anim.to(anim.id("send-opt", i), if (value.*) 1 else 0, 22));
        yy += row_h;
    }
    d.line(dl, r.x + 10, yy + 2, r.right() - 10, yy + 2, ctx.col(.border), 1);
    _ = d.textClipped(dl, fam.get(.regular), 12, r.x + 16, yy + 10, ctx.col(.faint), i18n.tr("Vale só para a próxima mensagem.", "Applies to the next message only."), r.w - 32);
}

/// Interruptor (o mesmo desenho das configurações), `on` de 0 a 1.
fn toggle(ctx: *d.Ctx, dl: *c.ImDrawList, sw: d.Rect, on: f32) void {
    d.rect(dl, sw, ctx.col(.faint).mix(ctx.col(.accent), on), sw.h / 2);
    const r = sw.h / 2 - 2.5;
    const kx = sw.x + sw.h / 2 + on * (sw.w - sw.h);
    d.circle(dl, kx, sw.y + sw.h / 2, r, d.Rgba.white);
}
