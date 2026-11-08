//! Os quatro status no menu do usuário (ui/popup.zig desenha o menu). O
//! ausente, o não perturbe e o invisível têm o submenu do prazo (15 min, 1 h,
//! 8 h, 24 h, 3 dias, até eu mudar), que abre ao passar o mouse, como no
//! cliente oficial; clicar no próprio item é "até eu mudar". O status de agora
//! leva o visto, ou até quando vale, se foi escolhido por um tempo (também no
//! painel do usuário, quando ali não aparece uma atividade).
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const w = @import("widgets.zig");
const i18n = @import("i18n.zig");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const popup = @import("popup.zig");

/// Ids dos itens no popup.zig: 80 + o status (online, ausente, não perturbe, invisível).
pub const first_id: u8 = 80;

/// O item com o submenu aberto (0 = nenhum), onde ele está e o último quadro
/// em que o menu apareceu (o menu que reabre começa sem submenu).
var open_id: u8 = 0;
var open_row: d.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
var seen_frame: c_int = -10;
/// O submenu apareceu agora: pega o foco para ficar na frente do fundo do popup.
var sub_shown = false;

fn statusOf(id: u8) ?types.Status {
    if (id < first_id or id > first_id + 3) return null;
    return @enumFromInt(id - first_id);
}

/// Um item do menu do status foi desenhado (`ink`: a cor do texto dele).
/// Nos status, o visto no de agora e a setinha do submenu; nos outros
/// itens, passar o mouse fecha o submenu.
pub fn row(ctx: *d.Ctx, dl: *c.ImDrawList, ir: d.Rect, it: popup.Item, hovered: bool, ink: d.Rgba) void {
    const f = c.ImGui_GetFrameCount();
    if (f > seen_frame + 1) open_id = 0;
    seen_frame = f;
    const st = statusOf(it.id) orelse {
        if (hovered) open_id = 0;
        return;
    };
    const timed = st != .online;
    if (hovered) {
        open_id = if (timed) it.id else 0;
        open_row = ir;
    }
    const cy = ir.y + ir.h / 2;
    if (timed) {
        // A setinha do submenu.
        const ax = ir.right() - 12;
        d.line(dl, ax - 3, cy - 4, ax + 1, cy, ink, 1.6);
        d.line(dl, ax + 1, cy, ax - 3, cy + 4, ink, 1.6);
    }
    const me = ctx.store.user(ctx.store.me) orelse return;
    if (me.status != st) return;
    qa.mark(ir, "menu-on:{s}", .{it.label});
    // Escolhido por um tempo: até quando, no lugar do visto (se couber).
    const until = ctx.st.conta.status_expires_ms;
    if (timed and until > ctx.now_ms) {
        var ub: [48]u8 = undefined;
        const t = untilText(&ub, until, ctx.now_ms);
        const font = ctx.ui.get(.regular);
        const tx = ir.right() - 24 - d.width(font, 12, t);
        if (tx > ir.x + 18 + d.width(ctx.ui.get(.medium), 14, i18n.tr(it.label, it.en))) {
            d.text(dl, font, 12, tx, d.centerY(ir, 12), ink.alpha(0.8), t);
            qa.mark(ir, "menu-until:{s}", .{it.label});
            return;
        }
    }
    const cx = ir.right() - (if (timed) @as(f32, 30) else 18);
    d.line(dl, cx - 5, cy, cx - 1.5, cy + 4, ink, 2);
    d.line(dl, cx - 1.5, cy + 4, cx + 5.5, cy - 4.5, ink, 2);
}

/// Textos do submenu, na ordem de `conta.status_minutes`, mais "até eu mudar".
const labels = [_][2][]const u8{
    .{ "Por 15 minutos", "For 15 Minutes" },
    .{ "Por 1 hora", "For 1 Hour" },
    .{ "Por 8 horas", "For 8 Hours" },
    .{ "Por 24 horas", "For 24 Hours" },
    .{ "Por 3 dias", "For 3 Days" },
    .{ "Até eu mudar", "Until I Change It" },
};

/// Depois do menu (`menu_r`): o submenu do item com o mouse, ao lado dele.
/// true: escolheu um prazo (o menu fecha).
pub fn drawSub(ctx: *d.Ctx, menu_r: d.Rect) bool {
    const st = statusOf(open_id) orelse {
        sub_shown = false;
        return false;
    };
    const row_h: f32 = 32;
    const sw: f32 = 190;
    const sh = @as(f32, @floatFromInt(labels.len)) * row_h + 12;
    // À direita do menu; sem espaço, à esquerda.
    const right = menu_r.right() + 4 + sw <= ctx.win.right() - 8;
    const sx = if (right) menu_r.right() + 4 else menu_r.x - 4 - sw;
    const r = popup.fit(ctx, sx, open_row.y - 6, sw, sh);
    if (!sub_shown) c.ImGui_SetNextWindowFocus();
    sub_shown = true;
    const dl = popup.beginWindow("##menu-status", r);
    defer c.ImGui_End();
    const radius = @max(ctx.th.radius, 4);
    d.shadow(dl, r, radius, 14, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.overlay), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    var y = r.y + 6;
    for (labels, 0..) |lb, i| {
        const ir: d.Rect = .{ .x = r.x + 6, .y = y, .w = r.w - 12, .h = row_h - 2 };
        const hb = d.hit(ctx, i, ir);
        qa.mark(ir, "menu:{s}", .{lb[0]});
        if (hb.hovered) d.rect(dl, ir, ctx.col(.accent), @max(ctx.th.radius - 2, 2));
        const tc = if (hb.hovered) ctx.col(.accent_text) else ctx.col(.text).mix(ctx.col(.muted), 0.15);
        _ = d.textClipped(dl, ctx.ui.get(.medium), 14, ir.x + 10, d.centerY(ir, 14), tc, i18n.tr(lb[0], lb[1]), ir.w - 18);
        if (hb.clicked) {
            const minutes: u32 = if (i < conta.status_minutes.len) conta.status_minutes[i] else 0;
            ctx.act(.{ .set_status_for = .{ .status = st, .minutes = minutes } });
            open_id = 0;
            sub_shown = false;
            return true;
        }
        y += row_h;
    }
    return false;
}

/// "até 14:30" (nas próximas 24 h) ou "até 10/11 14:30" (mais longe): o prazo do status.
pub fn untilText(buf: []u8, expires_ms: i64, now_ms: i64) []const u8 {
    const ts = @divFloor(expires_ms, 1000);
    const t = w.localTime(ts);
    var cb: [16]u8 = undefined;
    const hm = w.clock(&cb, ts);
    if (expires_ms - now_ms < 86_400_000) return i18n.fmt(buf, "até {s}", "until {s}", .{hm});
    // Em inglês, mês antes do dia.
    return i18n.fmt(buf, "até {d:0>2}/{d:0>2} {s}", "until {1d:0>2}/{0d:0>2} {2s}", .{ t.day, t.month, hm });
}
