//! A caixa de texto e os limites de envio (core/limites.zig): o aviso no lugar
//! da caixa quando não dá para enviar (castigo, quarentena, permissão, thread
//! trancada), o modo lento com a contagem depois de enviar, e o portão que o
//! App consulta antes de mandar qualquer mensagem. Nada aqui roda sem a caixa
//! na tela; a contagem só pede quadro quando o número muda.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const kdl = @import("../theme/kdl.zig");
const i18n = @import("i18n.zig");
const icons = @import("icons.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const types = @import("../core/types.zig");
const limites = @import("../core/limites.zig");
const Store = @import("../core/store.zig").Store;
const Id = types.Id;

const ca = std.heap.c_allocator;

/// Os nossos limites nesta conta (App.afterEvent preenche; zera ao trocar de conta).
pub var state: limites.State = .{};

pub fn reset() void {
    state.reset(ca);
}

/// O motivo para este canal agora (o único lugar que junta o que `pick` precisa).
pub fn blockFor(store: *const Store, ch: *const types.Channel, now_ms: i64) limites.Block {
    const m = state.member(ch.guild);
    const cd = state.cooldown(ch.id);
    return limites.pick(.{
        .guild = ch.guild,
        .perms = store.channelPermissions(ch),
        // Dono e ADMINISTRATOR: `permissions` já devolve tudo.
        .guild_perms = if (ch.guild != 0) store.permissions(ch.guild) else std.math.maxInt(u64),
        .thread = ch.thread != null,
        .locked = if (ch.thread) |t| t.locked else false,
        .forum = ch.kind == .forum,
        .timeout_until_ms = m.timeout_until_ms,
        .member_flags = m.flags,
        .slowmode_s = ch.rate_limit_per_user,
        .cooldown_until_ms = cd.until_ms,
        .cooldown_from_server = cd.server,
        .now_ms = now_ms,
    });
}

/// O mesmo, pelo ID (canal que não conhecemos: nada a dizer).
pub fn blockForId(store: *const Store, channel: Id, now_ms: i64) limites.Block {
    const cs = store.channel(channel) orelse return .{};
    return blockFor(store, &cs.info, now_ms);
}

/// Mandamos uma mensagem neste canal: com modo lento que vale para nós, a
/// contagem começa agora (o Discord conta a partir do envio).
pub fn noteSent(store: *const Store, channel: Id, now_ms: i64) void {
    state.noteSent(ca, channel, blockForId(store, channel, now_ms), now_ms);
}

/// O Discord disse quanto falta (429 do envio, POST de "digitando").
pub fn holdFor(channel: Id, ms: u32, now_ms: i64) void {
    state.holdUntil(ca, channel, now_ms + ms, now_ms, true);
}

/// Por que não dá para enviar, numa frase (o aviso na caixa e o toast).
pub fn reasonText(buf: []u8, b: limites.Block, now_ms: i64) []const u8 {
    var tb: [32]u8 = undefined;
    return switch (b.reason) {
        .none => "",
        .timed_out => i18n.fmt(buf, "Você está de castigo neste servidor: faltam {s}.", "You're timed out in this server: {s} left.", .{limites.fmtLeft(&tb, b.until_ms - now_ms)}),
        .quarantined => i18n.tr("O AutoMod pôs você em quarentena neste servidor.", "AutoMod quarantined you in this server."),
        .thread_locked => i18n.tr("Esta thread está trancada.", "This thread is locked."),
        .thread_no_permission => i18n.tr("Você não tem permissão para responder nesta thread.", "You don't have permission to reply in this thread."),
        .no_permission => i18n.tr("Você não tem permissão para enviar mensagens neste canal.", "You don't have permission to send messages in this channel."),
        .slowmode => i18n.fmt(buf, "Modo lento: dá para enviar de novo em {s}.", "Slowmode: you can send again in {s}.", .{limites.fmtLeft(&tb, b.until_ms - now_ms)}),
        .rate_limited => i18n.fmt(buf, "Mensagens rápidas demais: o Discord pede {s} até a próxima.", "Sending too fast: Discord asks for {s} before the next one.", .{limites.fmtLeft(&tb, b.until_ms - now_ms)}),
    };
}

/// O que mais dá para dizer, com o mouse em cima do aviso.
fn reasonDetail(r: limites.Reason) ?[]const u8 {
    return switch (r) {
        .timed_out => i18n.tr("Até lá, dá para ler, mas não escrever, reagir nem entrar em call.", "Until then you can read, but not write, react or join calls."),
        .quarantined => i18n.tr("O seu nome, apelido ou tag do servidor bateu numa regra do AutoMod. Trocando, você volta a falar.", "Your name, nickname or server tag matched an AutoMod rule. Change it to talk again."),
        else => null,
    };
}

/// A dica dentro da caixa vazia enquanto a contagem corre.
pub fn cooldownHint(buf: []u8, b: limites.Block, now_ms: i64) [:0]const u8 {
    var tb: [32]u8 = undefined;
    const left = limites.fmtLeft(&tb, b.until_ms - now_ms);
    if (b.reason == .rate_limited) return i18n.fmtZ(buf, "Espere {s} para enviar", "Wait {s} to send", .{left});
    return i18n.fmtZ(buf, "Modo lento: espere {s} para enviar", "Slowmode: wait {s} to send", .{left});
}

/// No lugar da caixa, quando não dá para enviar: o cadeado (ou o relógio do
/// castigo) e o motivo. O mesmo desenho do aviso de thread sem permissão.
pub fn band(ctx: *d.Ctx, n: *const kdl.Node, r: d.Rect, b: limites.Block) void {
    const fam = ctx.familyFor(n);
    const dl = ctx.dl;
    const pill = d.is(n, "variant", "pill", "box");
    const prompt = d.is(n, "variant", "prompt", "box");
    const radius = if (pill) r.h / 2 else ctx.th.radius + 4;
    const fs = ctx.th.font_size;
    qa.mark(r, "composer-readonly", .{});
    qa.mark(r, "composer-reason:{t}", .{b.reason});
    if (prompt) {
        d.line(dl, r.x, r.y + 0.5, r.right(), r.y + 0.5, ctx.col(.border), 1);
    } else {
        d.rect(dl, r, ctx.col(.elevated).alpha(0.5), radius);
        if (b.reason == .timed_out) stopwatch(dl, r.x + 24, r.y + r.h / 2, ctx.col(.faint)) else icons.lock(dl, r.x + 24, r.y + r.h / 2 - 2, ctx.col(.faint).u());
    }
    var buf: [240]u8 = undefined;
    const t = reasonText(&buf, b, ctx.now_ms);
    const x = r.x + (if (prompt) @as(f32, 10) else 44);
    _ = d.textClipped(dl, fam.get(.regular), fs, x, d.centerY(r, fs), ctx.col(.faint), t, @max(r.right() - x - 12, 20));
    if (reasonDetail(b.reason)) |more| d.tip(ctx, r, more, ctx.hovering(r));
    if (b.until_ms > ctx.now_ms) anim.at(limites.nextChange(b.until_ms, ctx.now_ms));
}

/// O modo lento acima da caixa, à direita, na linha do "fulano está
/// digitando": o tempo do canal ou, depois de enviar, quanto falta.
pub fn slowmodeLabel(ctx: *d.Ctx, fam: *d.Family, b: limites.Block, right: f32, y: f32) void {
    if (b.slowmode_s == 0 and b.reason != .rate_limited) return;
    var buf: [96]u8 = undefined;
    var tb: [32]u8 = undefined;
    const cooling = b.reason.cooling();
    const t = if (b.reason == .rate_limited)
        i18n.fmt(&buf, "Aguarde: {s}", "Wait: {s}", .{limites.fmtLeft(&tb, b.until_ms - ctx.now_ms)})
    else if (cooling)
        i18n.fmt(&buf, "Modo lento: {s}", "Slowmode: {s}", .{limites.fmtLeft(&tb, b.until_ms - ctx.now_ms)})
    else if (b.exempt)
        i18n.fmt(&buf, "Modo lento: {s} · liberado para você", "Slowmode: {s} · you're exempt", .{limites.fmtSlowmode(&tb, b.slowmode_s)})
    else
        i18n.fmt(&buf, "Modo lento: {s}", "Slowmode: {s}", .{limites.fmtSlowmode(&tb, b.slowmode_s)});
    const font = fam.get(if (cooling) .semibold else .medium);
    const fs: f32 = 12.5;
    const tw = d.width(font, fs, t);
    const x = right - tw;
    const col = if (cooling) ctx.col(.idle) else ctx.col(.faint);
    stopwatch(ctx.dl, x - 11, y + 8, col);
    d.text(ctx.dl, font, fs, x, y + 1, col, t);
    const hr: d.Rect = .{ .x = x - 20, .y = y - 2, .w = tw + 22, .h = 20 };
    if (cooling) qa.mark(hr, "slowmode-cooldown", .{}) else qa.mark(hr, "slowmode", .{});
    var sb: [32]u8 = undefined;
    var tip_buf: [200]u8 = undefined;
    const tip = if (b.reason == .rate_limited)
        i18n.tr("O Discord recusou a última mensagem por envio rápido demais neste canal.", "Discord refused the last message for sending too fast in this channel.")
    else if (b.exempt)
        i18n.tr("Você pode gerenciar mensagens ou o canal: o modo lento não vale para você.", "You can manage messages or the channel: slowmode doesn't apply to you.")
    else
        i18n.fmt(&tip_buf, "Cada pessoa pode enviar uma mensagem a cada {s} neste canal.", "Everyone can send one message every {s} in this channel.", .{limites.fmtSlowmode(&sb, b.slowmode_s)});
    d.tip(ctx, hr, tip, ctx.hovering(hr));
    if (cooling) anim.at(limites.nextChange(b.until_ms, ctx.now_ms));
}

/// Cronômetro pequeno (~12 px): o aro, o botão em cima e o ponteiro.
fn stopwatch(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba) void {
    c.ImDrawList_AddCircleEx(dl, d.v(cx, cy + 1), 5.2, col.u(), 0, 1.5, 0);
    d.line(dl, cx - 1.8, cy - 5.6, cx + 1.8, cy - 5.6, col, 1.5);
    d.line(dl, cx, cy + 1, cx, cy - 2.2, col, 1.5);
    d.line(dl, cx, cy + 1, cx + 2.2, cy + 1, col, 1.3);
}
