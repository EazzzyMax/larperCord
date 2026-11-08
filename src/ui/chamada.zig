//! Calls em DM e grupo, na tela: o botão de ligar no cabeçalho da conversa,
//! quem está na call, e o aviso de chamada chegando, por cima de tudo em
//! qualquer tema. A lógica (tocar, atender, recusar) fica em app_chamada.zig;
//! aqui só o estado que as duas pontas leem.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const w = @import("widgets.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const i18n = @import("i18n.zig");
const types = @import("../core/types.zig");
const Id = types.Id;

/// DM ou grupo que está tocando para nós (0 = nada) e desde quando.
pub var ring_channel: Id = 0;
pub var ring_since_ms: i64 = 0;
/// Na call de DM em que estamos: quantos o Discord ainda está chamando.
pub var out_channel: Id = 0;
pub var out_ringing: u8 = 0;
/// Avisos de chamada (do sistema) já dados; o QA confere.
pub var notified: u32 = 0;

/// Depois disso o aviso some da tela mesmo sem notícia do Discord (o toque
/// para sozinho antes, em net/voz_audio.zig).
pub const ring_max_ms = 90_000;

pub fn reset() void {
    ring_channel = 0;
    ring_since_ms = 0;
    out_channel = 0;
    out_ringing = 0;
}

/// Quem está na call desta conversa (vazio fora de DM/grupo).
fn members(ctx: *d.Ctx, ch: *const types.Channel) []const Id {
    if (ch.guild != 0) return &.{};
    const cs = ctx.store.channel(ch.id) orelse return &.{};
    return cs.voice_members.items;
}

const max_faces = 4;
const face: f32 = 22;
const face_step: f32 = 15;

fn facesWidth(n: usize) f32 {
    if (n == 0) return 0;
    const shown = @min(n, max_faces);
    var wd = face + face_step * @as(f32, @floatFromInt(shown - 1));
    if (n > max_faces) wd += 26;
    return wd + 8;
}

/// Espaço que o cabeçalho reserva para o botão e os rostos (0 fora de DM).
pub fn headerSpace(ctx: *d.Ctx, ch: *const types.Channel) f32 {
    if (ch.guild != 0) return 0;
    var space = 36 + facesWidth(members(ctx, ch).len);
    if (callingOut(ctx, ch)) space += d.width(ctx.ui.get(.regular), 12, ringingLabel()) + 10;
    return space;
}

/// Estamos na call desta conversa e o Discord ainda está chamando alguém.
fn callingOut(ctx: *d.Ctx, ch: *const types.Channel) bool {
    return ctx.st.voice == ch.id and out_channel == ch.id and out_ringing > 0;
}

fn ringingLabel() []const u8 {
    return i18n.tr("chamando…", "ringing…");
}

/// O botão de ligar (ou desligar) e, à esquerda dele, quem está na call.
/// `right`: onde termina o botão; `cy`: o meio da linha.
pub fn headerButtons(ctx: *d.Ctx, dl: *c.ImDrawList, ch: *const types.Channel, right: f32, cy: f32) void {
    if (ch.guild != 0) return;
    const in_this = ctx.st.voice == ch.id;
    const list = members(ctx, ch);
    const br: d.Rect = .{ .x = right - 28, .y = cy - 14, .w = 28, .h = 28 };
    const hb = d.hit(ctx, 8, br);
    if (in_this) {
        qa.mark(br, "call-leave", .{});
        if (hb.clicked) ctx.act(.leave_voice);
        d.rect(dl, br, ctx.col(.danger).alpha(if (hb.hovered) 0.28 else 0.16), ctx.th.radius);
        phone(dl, br.x + 14, br.y + 14, ctx.col(.danger).u(), true);
        d.tip(ctx, br, i18n.tr("Sair da call", "Leave call"), hb.hovered);
    } else {
        qa.mark(br, "call-start", .{});
        if (hb.clicked) ctx.act(.{ .start_call = ch.id });
        // Já tem gente na call: o botão chama para entrar.
        const live = list.len > 0;
        const ink = if (live) ctx.col(.online) else if (hb.hovered) ctx.col(.text) else ctx.col(.muted);
        if (live) d.rect(dl, br, ctx.col(.online).alpha(if (hb.hovered) 0.24 else 0.14), ctx.th.radius);
        phone(dl, br.x + 14, br.y + 14, ink.u(), false);
        d.tip(ctx, br, if (live) i18n.tr("Entrar na call", "Join call") else i18n.tr("Ligar", "Start call"), hb.hovered);
    }
    faces(ctx, dl, ch, list, br.x - 6, cy);
}

/// Os rostos de quem está na call, encostados em `right` (o anel verde é quem fala).
fn faces(ctx: *d.Ctx, dl: *c.ImDrawList, ch: *const types.Channel, list: []const Id, right: f32, cy: f32) void {
    var x = right;
    if (list.len == 0) return;
    if (list.len > max_faces) {
        var nb: [8]u8 = undefined;
        const t = std.fmt.bufPrint(&nb, "+{d}", .{list.len - max_faces}) catch "";
        const font = ctx.ui.get(.semibold);
        const tw = d.width(font, 12, t);
        x -= tw + 6;
        d.text(dl, font, 12, x, d.centerY(.{ .x = x, .y = cy - 10, .w = tw, .h = 20 }, 12), ctx.col(.muted), t);
        x -= 6;
    }
    const shown = @min(list.len, max_faces);
    var i: usize = shown;
    while (i > 0) {
        i -= 1;
        const uid = list[i];
        const cx = x - face / 2 - face_step * @as(f32, @floatFromInt(shown - 1 - i));
        const speaking = ctx.store.isSpeaking(uid, ctx.now_ms);
        w.avatar(ctx, dl, cx, cy, face, uid, .circle, null, 1);
        if (speaking) c.ImDrawList_AddCircleEx(dl, d.v(cx, cy), face / 2 + 1.5, ctx.col(.online).u(), 0, 2, 0);
        const r: d.Rect = .{ .x = cx - face / 2, .y = cy - face / 2, .w = face, .h = face };
        qa.mark(r, "call-member:{d}", .{uid});
        if (ctx.hovering(r)) d.tip(ctx, r, if (ctx.store.user(uid)) |u| u.name else "?", true);
    }
    // O espaço já foi reservado em `headerSpace`.
    if (callingOut(ctx, ch)) {
        const font = ctx.ui.get(.regular);
        const t = ringingLabel();
        const left = x - facesWidth(shown) + 4;
        const tw = d.width(font, 12, t);
        d.text(dl, font, 12, left - tw - 6, cy - 7, ctx.col(.faint), t);
        qa.mark(.{ .x = left - tw - 6, .y = cy - 8, .w = tw, .h = 16 }, "call-ringing-out", .{});
    }
}

/// Versão em texto, para os temas de terminal: `[ligar]` / `[desligar]` e
/// `♪ ana, bia`. Devolve o novo canto esquerdo da área ocupada à direita.
pub fn headerTty(ctx: *d.Ctx, dl: *c.ImDrawList, font: *c.ImFont, fs: f32, ch: *const types.Channel, right_x: f32, r: d.Rect) f32 {
    if (ch.guild != 0) return right_x;
    const in_this = ctx.st.voice == ch.id;
    const lbl = if (in_this) i18n.tr("[desligar]", "[hang up]") else i18n.tr("[ligar]", "[call]");
    const lw = d.width(font, fs, lbl);
    const br: d.Rect = .{ .x = right_x - lw - 8, .y = r.y, .w = lw + 4, .h = r.h };
    const hb = d.hit(ctx, 8, br);
    if (in_this) qa.mark(br, "call-leave", .{}) else qa.mark(br, "call-start", .{});
    if (hb.clicked) {
        if (in_this) ctx.act(.leave_voice) else ctx.act(.{ .start_call = ch.id });
    }
    const list = members(ctx, ch);
    const ink = if (in_this) ctx.col(.danger) else if (list.len > 0) ctx.col(.online) else if (hb.hovered) ctx.col(.text) else ctx.col(.muted);
    d.text(dl, font, fs, br.x + 2, d.centerY(r, fs), ink, lbl);
    d.tip(ctx, br, if (in_this) i18n.tr("Sair da call", "Leave call") else if (list.len > 0) i18n.tr("Entrar na call", "Join call") else i18n.tr("Ligar", "Start call"), hb.hovered);
    var x = br.x;
    if (list.len > 0) {
        var buf: [160]u8 = undefined;
        var n: usize = 0;
        const head = "♪ ";
        @memcpy(buf[0..head.len], head);
        n = head.len;
        for (list, 0..) |uid, i| {
            const name = if (ctx.store.user(uid)) |u| u.name else "?";
            const sep: []const u8 = if (i == 0) "" else ", ";
            if (n + sep.len + name.len + 4 > buf.len) break;
            @memcpy(buf[n .. n + sep.len], sep);
            n += sep.len;
            @memcpy(buf[n .. n + name.len], name);
            n += name.len;
        }
        const t = buf[0..n];
        const tw = @min(d.width(font, fs, t), 200);
        x -= tw + 10;
        const tr: d.Rect = .{ .x = x, .y = r.y, .w = tw, .h = r.h };
        qa.mark(tr, "call-members", .{});
        for (list) |uid| qa.mark(tr, "call-member:{d}", .{uid});
        _ = d.textClipped(dl, font, fs, x, d.centerY(r, fs), ctx.col(.online), t, tw);
    }
    return x;
}

/// Fone: em pé para ligar, virado para baixo para desligar.
pub fn phone(dl: *c.ImDrawList, cx: f32, cy: f32, col: u32, down: bool) void {
    const s: f32 = if (down) -1 else 1;
    const ay = cy + 4 * s;
    const r: f32 = 7.5;
    c.ImDrawList_PathClear(dl);
    if (down) {
        c.ImDrawList_PathArcTo(dl, d.v(cx, ay), r, 0.42, std.math.pi - 0.42, 0);
    } else c.ImDrawList_PathArcTo(dl, d.v(cx, ay), r, std.math.pi + 0.42, 2 * std.math.pi - 0.42, 0);
    c.ImDrawList_PathStroke(dl, col, 3, 0);
    // Os dois lados do fone: o do ouvido e o da boca.
    const ex = r * @cos(@as(f32, 0.42));
    const ey = ay - s * r * @sin(@as(f32, 0.42));
    for ([_]f32{ -1, 1 }) |side| {
        const px = cx + side * ex;
        c.ImDrawList_AddRectFilledEx(dl, d.v(px - 3.2, ey - (if (down) @as(f32, 4.5) else 0.5)), d.v(px + 3.2, ey + (if (down) @as(f32, 0.5) else 4.5)), col, 1.8, 0);
    }
}

// --- Chamada chegando --------------------------------------------------------

/// O aviso de chamada chegando, por cima de tudo (configurações, paleta,
/// visualizador): foto ou ícone do grupo, nome, Atender e Recusar.
pub fn overlay(ctx: *d.Ctx) void {
    const ch_id = ring_channel;
    if (ch_id == 0 or ctx.now_ms - ring_since_ms > ring_max_ms) return;
    const cs = ctx.store.channel(ch_id);
    const win = ctx.win;
    const cw: f32 = @min(300, win.w - 32);
    const chh: f32 = 228;
    const card: d.Rect = .{ .x = win.x + (win.w - cw) / 2, .y = win.y + @max(56, win.h * 0.14), .w = cw, .h = chh };
    // Janela própria do ImGui, só do tamanho do cartão: recebe o clique
    // mesmo com outra janela aberta, e o resto da tela continua usável.
    c.ImGui_SetNextWindowPos(d.v(card.x - 24, card.y - 24), 0);
    c.ImGui_SetNextWindowSize(d.v(card.w + 48, card.h + 48), 0);
    // Na frente a cada quadro, sem pegar o foco: quem está digitando na caixa continua
    // digitando (o aviso não tem teclas; o clique em Atender ou Recusar vale assim mesmo).
    _ = c.ImGui_Begin("##chamada", null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoBackground |
        c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoScrollWithMouse | c.ImGuiWindowFlags_NoNav |
        c.ImGuiWindowFlags_NoFocusOnAppearing);
    defer c.ImGui_End();
    d.windowToFront();
    const dl = c.ImGui_GetWindowDrawList();
    const k = anim.to(anim.id("chamada", 0), 1, 18);
    const radius = @max(ctx.th.radius + 6, 4);
    const top = card.y - (1 - k) * 10;
    const box: d.Rect = .{ .x = card.x, .y = top, .w = card.w, .h = card.h };
    d.shadow(dl, box, radius, 26, ctx.col(.shadow).alpha(k));
    d.rect(dl, box, ctx.col(.overlay).mix(ctx.col(.elevated), 0.35).alpha(k), radius);
    d.border(dl, box, ctx.col(.accent).alpha(0.55 * k), radius, 1);
    qa.mark(box, "call-overlay", .{});

    // A foto pulsa enquanto toca (sem animação com "reduzir movimento").
    const cx = box.x + box.w / 2;
    const cy = box.y + 62;
    const size: f32 = 72;
    if (!ctx.st.settings.reduce_motion) {
        const period: i64 = 1400;
        const ph = @as(f32, @floatFromInt(@mod(ctx.now_ms - ring_since_ms, period))) / @as(f32, @floatFromInt(period));
        for ([_]f32{ 0, 0.5 }) |off| {
            const p = @mod(ph + off, 1);
            c.ImDrawList_AddCircleEx(dl, d.v(cx, cy), size / 2 + 4 + p * 16, ctx.col(.online).alpha((1 - p) * 0.55 * k).u(), 0, 2, 0);
        }
        // Uns 30 quadros por segundo enquanto o aviso está na tela.
        anim.at(ctx.now_ms + 33);
    } else c.ImDrawList_AddCircleEx(dl, d.v(cx, cy), size / 2 + 5, ctx.col(.online).alpha(0.6 * k).u(), 0, 2, 0);
    var title: []const u8 = "?";
    var sub: []const u8 = i18n.tr("está te ligando…", "is calling you…");
    if (cs) |x| {
        title = x.info.name;
        if (x.info.group) {
            @import("comp_channels.zig").groupIcon(ctx, dl, &x.info, cx, cy, size);
            sub = i18n.tr("chamada no grupo…", "group call…");
        } else w.avatar(ctx, dl, cx, cy, size, x.info.recipient, .circle, null, k);
    } else d.circle(dl, cx, cy, size / 2, ctx.col(.surface));
    const tf = ctx.ui.get(.semibold);
    const tw = @min(d.width(tf, 17, title), box.w - 32);
    _ = d.textClipped(dl, tf, 17, cx - tw / 2, box.y + 108, ctx.col(.text).alpha(k), title, box.w - 32);
    const sf = ctx.ui.get(.regular);
    const sw = d.width(sf, 13, sub);
    d.text(dl, sf, 13, cx - sw / 2, box.y + 131, ctx.col(.muted).alpha(k), sub);

    // Recusar à esquerda, atender à direita (como nos celulares).
    const by = box.y + 178;
    const labels = [_][]const u8{ i18n.tr("Recusar", "Decline"), i18n.tr("Atender", "Accept") };
    for (0..2) |i| {
        const accept = i == 1;
        const bx = cx + (if (accept) @as(f32, 56) else -56);
        const br: d.Rect = .{ .x = bx - 22, .y = by - 22, .w = 44, .h = 44 };
        const hb = d.hit(ctx, 1 + i, br);
        if (accept) qa.mark(br, "call-accept", .{}) else qa.mark(br, "call-decline", .{});
        const base = if (accept) ctx.col(.online) else ctx.col(.danger);
        const hk = anim.to(anim.id("chamada-btn", i), if (hb.hovered) 1 else 0, 24);
        d.circle(dl, bx, by, 22, base.mix(d.Rgba.white, 0.12 * hk).alpha(k));
        phone(dl, bx, by, d.Rgba.white.alpha(k).u(), !accept);
        const lf = ctx.ui.get(.medium);
        const lw = d.width(lf, 12, labels[i]);
        d.text(dl, lf, 12, bx - lw / 2, by + 26, ctx.col(.muted).alpha(k), labels[i]);
        if (hb.clicked) ctx.act(if (accept) .accept_call else .decline_call);
    }
}
