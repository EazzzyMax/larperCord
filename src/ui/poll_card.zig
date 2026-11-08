//! O cartão de votar de uma enquete: escolher uma opção (ou várias, se a
//! enquete deixa), votar, ver os resultados, tirar o voto e ver quem votou em
//! cada opção (buscado só ao clicar). A altura é a mesma em todos os estados:
//! votar ou a enquete acabar não faz a conversa pular.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const anim = @import("anim.zig");
const inbox = @import("inbox.zig");
const reactors = @import("reactors.zig");
const polls = @import("../core/polls.zig");
const types = @import("../core/types.zig");
const StoredMessage = @import("../core/store.zig").StoredMessage;
const Id = types.Id;

pub const max_w: f32 = 460;
const pad: f32 = 14;
const row_h: f32 = 40;
const row_gap: f32 = 6;
const footer_h: f32 = 32;
const question_size: f32 = 16;

/// O que está marcado antes de votar (uma enquete por vez) e o voto que acabou
/// de sair (espera o gateway confirmar, no máximo alguns segundos).
var sel_msg: Id = 0;
var sel_mask: u16 = 0;
/// Mostrando os resultados sem ter votado.
var results_msg: Id = 0;
var pending_msg: Id = 0;
var pending_until: i64 = 0;
var pending_voted: bool = false;

fn questionH(ctx: *d.Ctx, p: *const polls.Poll, inner: f32) f32 {
    return inbox.wrapText(null, ctx.ui.get(.bold), question_size, 0, 0, inner, p.question, 3, ctx.col(.text));
}

pub fn height(ctx: *d.Ctx, p: *const polls.Poll, wd: f32) f32 {
    const n: f32 = @floatFromInt(p.n);
    return pad + questionH(ctx, p, wd - pad * 2) + 4 + 20 + 8 + n * (row_h + row_gap) + 4 + footer_h + pad;
}

fn remaining(buf: []u8, secs: i64) []const u8 {
    if (secs >= 86400) return i18n.fmt(buf, "{d}d restantes", "{d}d left", .{@divTrunc(secs, 86400)});
    if (secs >= 3600) return i18n.fmt(buf, "{d}h restantes", "{d}h left", .{@divTrunc(secs, 3600)});
    if (secs >= 60) return i18n.fmt(buf, "{d} min restantes", "{d} min left", .{@divTrunc(secs, 60)});
    return i18n.tr("menos de 1 min", "less than 1 min");
}

fn votesLabel(buf: []u8, p: *const polls.Poll) []const u8 {
    if (!p.known) return i18n.tr("votos desconhecidos", "votes unknown");
    const t = p.total();
    return if (t == 1) i18n.tr("1 voto", "1 vote") else i18n.fmt(buf, "{d} votos", "{d} votes", .{t});
}

pub fn draw(ctx: *d.Ctx, dl: *c.ImDrawList, m: *const StoredMessage, p: *const polls.Poll, x: f32, y: f32, wd: f32, alpha: f32) void {
    const fam = ctx.ui;
    const id = m.msg.id;
    const now_s = @divTrunc(ctx.now_ms, 1000);
    const ended = p.ended(now_s);
    const voted = p.voted();
    const pending = pending_msg == id and ctx.now_ms < pending_until and voted == pending_voted;
    // O cartão parado não muda até a resposta (que redesenha) ou até o prazo vencer: um
    // quadro só nessa hora, não 60 por segundo.
    if (pending) anim.at(pending_until);
    const results = ended or voted or results_msg == id;
    const mask: u16 = if (sel_msg == id) sel_mask else 0;
    const h = height(ctx, p, wd);
    const card: d.Rect = .{ .x = x, .y = y, .w = wd, .h = h };
    const radius = std.math.clamp(ctx.th.radius + 2, 4, 10);
    const card_bg = ctx.col(.elevated).mix(ctx.col(.rail), 0.35);
    d.rect(dl, card, card_bg.alpha(alpha), radius);
    d.border(dl, card, ctx.col(.border).alpha(alpha), radius, 1);
    qa.mark(card, "poll:{d}", .{id});

    const inner = wd - pad * 2;
    var yy = y + pad;
    yy += inbox.wrapText(dl, fam.get(.bold), question_size, x + pad, yy, inner, p.question, 3, ctx.col(.text).alpha(alpha));
    yy += 4;
    const sub = if (ended)
        (if (p.finalized) i18n.tr("Resultado final", "Final results") else i18n.tr("Enquete encerrada", "Poll closed"))
    else if (results)
        i18n.tr("Resultados até agora", "Results so far")
    else if (p.multi)
        i18n.tr("Escolha uma ou mais opções", "Select one or more answers")
    else
        i18n.tr("Escolha uma opção", "Select one answer");
    d.text(dl, fam.get(.medium), 12.5, x + pad, yy + 2, ctx.col(.muted).alpha(alpha), sub);
    yy += 20 + 8;

    const total = p.total();
    var top: u32 = 0;
    for (p.slice()) |a| top = @max(top, a.count);
    for (p.slice(), 0..) |*a, k| {
        const rr: d.Rect = .{ .x = x + pad, .y = yy, .w = inner, .h = row_h };
        const bit = @as(u16, 1) << @intCast(k);
        const hb = d.hit(ctx, @truncate((id ^ 0x9011) +% k), rr);
        qa.mark(rr, "poll-answer:{d}:{d}", .{ id, a.id });
        const row_r = @max(radius - 2, 4);
        d.rect(dl, rr, card_bg.mix(ctx.col(.text), if (hb.hovered and !pending) 0.09 else 0.05).alpha(alpha), row_r);
        var tx = rr.x + 12;
        if (results) {
            // Barra do tamanho da fatia de votos: mais forte onde votamos e em quem ganhou.
            const frac: f32 = if (p.known and total > 0) @as(f32, @floatFromInt(a.count)) / @as(f32, @floatFromInt(total)) else 0;
            const strong = a.me or (ended and p.known and a.count == top and top > 0);
            if (frac > 0) d.rect(dl, .{ .x = rr.x, .y = rr.y, .w = @max(rr.w * frac, row_r * 2), .h = rr.h }, ctx.col(.accent).alpha((if (strong) @as(f32, 0.34) else 0.16) * alpha), row_r);
            if (a.me) d.border(dl, rr, ctx.col(.accent).alpha(alpha), row_r, 1.2);
        } else {
            const on = mask & bit != 0;
            if (on) d.border(dl, rr, ctx.col(.accent).alpha(alpha), row_r, 1.5) else if (hb.hovered) d.border(dl, rr, ctx.col(.border).mix(ctx.col(.text), 0.2).alpha(alpha), row_r, 1);
            mark(ctx, dl, rr.x + 20, rr.y + rr.h / 2, p.multi, on, alpha);
            tx = rr.x + 38;
        }
        const ew = reactors.drawEmoji(ctx, dl, &a.emoji, tx, rr.y + rr.h / 2, 20, hb.hovered);
        if (ew > 0) tx += ew + 8;
        // O lado direito: porcentagem e votos (resultados).
        var right_w: f32 = 0;
        if (results and p.known) {
            var pb: [16]u8 = undefined;
            var cb: [24]u8 = undefined;
            const pct: u32 = if (total > 0) @intFromFloat(@round(@as(f32, @floatFromInt(a.count)) * 100 / @as(f32, @floatFromInt(total)))) else 0;
            const pt = std.fmt.bufPrint(&pb, "{d}%", .{pct}) catch "";
            const ct = std.fmt.bufPrint(&cb, "{d}", .{a.count}) catch "";
            const pw = d.width(fam.get(.bold), 13.5, pt);
            const cw = d.width(fam.get(.regular), 12, ct);
            d.text(dl, fam.get(.regular), 12, rr.right() - 12 - cw, d.centerY(rr, 12), ctx.col(.muted).alpha(alpha), ct);
            d.text(dl, fam.get(.bold), 13.5, rr.right() - 22 - cw - pw, d.centerY(rr, 13.5), ctx.col(.text).alpha(alpha), pt);
            right_w = cw + pw + 30;
        }
        if (results and a.me) {
            check(dl, tx + 7, rr.y + rr.h / 2, ctx.col(.accent).alpha(alpha));
            tx += 20;
        }
        _ = d.textClipped(dl, fam.get(.medium), 14, tx, d.centerY(rr, 14), ctx.col(.text).alpha(alpha), a.text, rr.right() - tx - right_w - 8);
        if (results) {
            // Quem votou: só ao clicar, uma página por vez.
            const can_list = !p.known or a.count > 0;
            if (can_list) d.tip(ctx, rr, i18n.tr("Ver quem votou", "See who voted"), hb.hovered);
            if (hb.clicked and can_list) reactors.openVoters(ctx, m.msg.channel, id, a.id, ctx.mouse.x, ctx.mouse.y);
        } else if (hb.clicked and !pending) {
            // Marcar numa enquete esquece o que estava marcado em outra.
            sel_msg = id;
            sel_mask = if (p.multi) mask ^ bit else (if (mask == bit) 0 else bit);
        }
        yy += row_h + row_gap;
    }
    yy += 4;

    // Rodapé: votos e prazo à esquerda, os botões à direita.
    const fr: d.Rect = .{ .x = x + pad, .y = yy, .w = inner, .h = footer_h };
    var vb: [48]u8 = undefined;
    var rb: [48]u8 = undefined;
    var lb: [128]u8 = undefined;
    const when = if (ended) "" else if (p.expiry == 0) "" else remaining(&rb, p.expiry - now_s);
    const left = if (when.len > 0) std.fmt.bufPrint(&lb, "{s}  ·  {s}", .{ votesLabel(&vb, p), when }) catch "" else votesLabel(&vb, p);
    var bx = fr.right();
    if (!ended) {
        if (results) {
            const label = if (voted)
                (if (pending) i18n.tr("Tirando…", "Removing…") else i18n.tr("Tirar voto", "Remove vote"))
            else
                i18n.tr("Voltar a votar", "Back to voting");
            if (textButton(ctx, dl, &bx, fr, label, "poll-back", id, 1, alpha) and !pending) {
                if (voted) vote(ctx, m.msg.channel, id, p, 0, true) else results_msg = 0;
            }
        } else {
            const can = mask != 0 and !pending;
            if (accentButton(ctx, dl, &bx, fr, if (pending) i18n.tr("Votando…", "Voting…") else i18n.tr("Votar", "Vote"), "poll-vote", id, can, alpha)) vote(ctx, m.msg.channel, id, p, mask, false);
            if (textButton(ctx, dl, &bx, fr, i18n.tr("Ver resultados", "Show results"), "poll-results", id, 2, alpha)) results_msg = id;
        }
    }
    _ = d.textClipped(dl, fam.get(.regular), 12.5, fr.x, d.centerY(fr, 12.5), ctx.col(.muted).alpha(alpha), left, bx - fr.x - 8);
}

/// Manda o voto (`mask` = as opções marcadas; 0 tira o voto). Os votos mudam
/// quando o gateway confirma.
fn vote(ctx: *d.Ctx, channel: Id, id: Id, p: *const polls.Poll, mask: u16, remove: bool) void {
    var pv: @import("../core/event.zig").PollVote = .{ .channel = channel, .id = id };
    if (!remove) for (p.slice(), 0..) |a, k| {
        if (mask & (@as(u16, 1) << @intCast(k)) == 0) continue;
        pv.answers[pv.n] = a.id;
        pv.n += 1;
    };
    ctx.act(.{ .poll_vote = pv });
    pending_msg = id;
    pending_until = ctx.now_ms + 5000;
    pending_voted = p.voted();
    sel_mask = 0;
    results_msg = 0;
}

/// Bolinha (uma escolha) ou quadradinho (várias), marcado ou não.
fn mark(ctx: *d.Ctx, dl: *c.ImDrawList, cx: f32, cy: f32, multi: bool, on: bool, alpha: f32) void {
    const ink = (if (on) ctx.col(.accent) else ctx.col(.muted)).alpha(alpha);
    if (multi) {
        const b: d.Rect = .{ .x = cx - 8, .y = cy - 8, .w = 16, .h = 16 };
        if (on) {
            d.rect(dl, b, ink, 4);
            check(dl, cx, cy, ctx.col(.accent_text).alpha(alpha));
        } else d.border(dl, b, ink, 4, 1.6);
        return;
    }
    c.ImDrawList_AddCircleEx(dl, d.v(cx, cy), 8, ink.u(), 0, 1.6, 0);
    if (on) d.circle(dl, cx, cy, 4.5, ink);
}

fn check(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba) void {
    d.line(dl, cx - 4.5, cy, cx - 1.5, cy + 3.5, col, 1.8);
    d.line(dl, cx - 1.5, cy + 3.5, cx + 4.5, cy - 3.5, col, 1.8);
}

/// Botão com a cor de destaque, encostado à direita de `bx` (que anda para a esquerda).
fn accentButton(ctx: *d.Ctx, dl: *c.ImDrawList, bx: *f32, fr: d.Rect, label: []const u8, mark_name: []const u8, id: Id, enabled: bool, alpha: f32) bool {
    const fam = ctx.ui;
    const bw = d.width(fam.get(.semibold), 13.5, label) + 28;
    const br: d.Rect = .{ .x = bx.* - bw, .y = fr.y, .w = bw, .h = fr.h };
    bx.* = br.x - 8;
    const hb = d.hit(ctx, @truncate(id ^ 0x9077), br);
    qa.mark(br, "{s}:{d}", .{ mark_name, id });
    const bg = if (!enabled) ctx.col(.accent).alpha(0.4) else if (hb.hovered) ctx.col(.accent).mix(d.Rgba.white, 0.1) else ctx.col(.accent);
    d.rect(dl, br, bg.alpha(alpha), @max(ctx.th.radius, 4));
    d.text(dl, fam.get(.semibold), 13.5, br.x + 14, d.centerY(br, 13.5), ctx.col(.accent_text).alpha(alpha * (if (enabled) @as(f32, 1) else 0.7)), label);
    return hb.clicked and enabled;
}

fn textButton(ctx: *d.Ctx, dl: *c.ImDrawList, bx: *f32, fr: d.Rect, label: []const u8, mark_name: []const u8, id: Id, slot: u8, alpha: f32) bool {
    const fam = ctx.ui;
    const bw = d.width(fam.get(.semibold), 13, label) + 20;
    const br: d.Rect = .{ .x = bx.* - bw, .y = fr.y, .w = bw, .h = fr.h };
    bx.* = br.x - 4;
    const hb = d.hit(ctx, @truncate((id ^ 0x9078) +% slot), br);
    qa.mark(br, "{s}:{d}", .{ mark_name, id });
    if (hb.hovered) d.rect(dl, br, ctx.col(.hover).alpha(alpha), @max(ctx.th.radius, 4));
    d.text(dl, fam.get(.semibold), 13, br.x + 10, d.centerY(br, 13), (if (hb.hovered) ctx.col(.text) else ctx.col(.link)).alpha(alpha), label);
    return hb.clicked;
}
