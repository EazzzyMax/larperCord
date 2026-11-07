//! Entrar num servidor com cuidado: o aviso antes de entrar por convite, o motivo de não
//! poder falar enquanto as regras do servidor não foram respondidas, a janela das regras e a
//! das boas-vindas.
//!
//! Tudo é lido e respondido à mão: nenhuma regra vem marcada, nenhum texto vem escrito e
//! nenhuma opção vem escolhida (as boas-vindas só mostram o que a própria conta já tinha
//! escolhido antes). O formulário e as perguntas só são buscados quando a janela abre, e
//! cada envio é um clique. Fechadas, as janelas não custam nada.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const kdl = @import("../theme/kdl.zig");
const types = @import("../core/types.zig");
const core = @import("../core/entrada.zig");
const popup = @import("popup.zig");
const forum = @import("forum.zig");
const inbox = @import("inbox.zig");
const icons = @import("icons.zig");
const Id = types.Id;
const ca = std.heap.c_allocator;

// --- Texto que quebra em linhas -----------------------------------------------------------

/// Desenha `s` quebrando nas palavras (e nos `\n`) e devolve a altura. Sem `dl`, só mede.
fn wrap(font: *c.ImFont, dl: ?*c.ImDrawList, x: f32, y_in: f32, max_w: f32, fs: f32, col: d.Rgba, s: []const u8) f32 {
    const line_h = fs * 1.45;
    var rest = s;
    var y = y_in;
    while (rest.len > 0) {
        var n = d.fitBytes(font, fs, rest, max_w);
        if (n == 0) n = @min(rest.len, std.unicode.utf8ByteSequenceLength(rest[0]) catch 1);
        var skip: usize = 0;
        if (std.mem.indexOfScalar(u8, rest[0..n], '\n')) |nl| {
            n = nl;
            skip = 1;
        } else if (n < rest.len) if (std.mem.lastIndexOfScalar(u8, rest[0..n], ' ')) |sp| {
            if (sp > 0) n = sp + 1;
        };
        if (dl) |l| d.text(l, font, fs, x, y, col, std.mem.trimEnd(u8, rest[0..n], " \r"));
        rest = rest[n + skip ..];
        y += line_h;
    }
    return y - y_in;
}

fn checkbox(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: f32, on: bool) void {
    const box: d.Rect = .{ .x = x, .y = y, .w = 18, .h = 18 };
    d.rect(dl, box, if (on) ctx.col(.accent) else ctx.col(.rail).mix(ctx.col(.surface), 0.25), 4);
    d.border(dl, box, if (on) ctx.col(.accent) else ctx.col(.border), 4, 1);
    if (on) {
        d.line(dl, box.x + 4, box.y + 9, box.x + 8, box.y + 13, ctx.col(.accent_text), 2);
        d.line(dl, box.x + 8, box.y + 13, box.x + 14, box.y + 5, ctx.col(.accent_text), 2);
    }
}

/// Os botões do pé de uma janela (sem `cancel`, só o principal); devolve (cancelar, confirmar).
fn footer(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, id: usize, cancel: ?[]const u8, ok_lbl: []const u8, ok_on: bool, cancel_mark: []const u8, ok_mark: []const u8) [2]bool {
    const fam = ctx.ui;
    const bw = d.width(fam.get(.semibold), 13.5, ok_lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - bw, .y = r.bottom() - 50, .w = bw, .h = 34 };
    qa.mark(br, "{s}", .{ok_mark});
    const go = forum.primary(ctx, dl, fam, id, br, ok_lbl, ok_on) and ok_on;
    const lbl = cancel orelse return .{ false, go };
    const cw = inbox.buttonWidth(ctx, lbl);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "{s}", .{cancel_mark});
    const back = inbox.button(ctx, dl, id + 1, cr, lbl, false);
    return .{ back, go };
}

/// Um texto à esquerda dos botões do pé (o que falta, o que deu errado).
fn footNote(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, col: d.Rgba, s: []const u8) void {
    const row: d.Rect = .{ .x = r.x, .y = r.bottom() - 50, .w = r.w, .h = 34 };
    _ = d.textClipped(dl, ctx.ui.get(.regular), 12.5, r.x + 18, d.centerY(row, 12.5), col, s, r.w * 0.5);
}

fn centered(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, col: d.Rgba, s: []const u8) void {
    const font = ctx.ui.get(.medium);
    const w = @min(d.width(font, 14, s), r.w - 48);
    const h = wrap(font, null, 0, 0, w + 1, 14, col, s);
    _ = wrap(font, dl, r.x + (r.w - w) / 2, r.y + (r.h - h) / 2, w + 1, 14, col, s);
}

// --- Aviso antes de entrar por convite ----------------------------------------------------

/// O aviso está aberto na janela de entrar (no lugar do cartão do convite).
pub var warning_open = false;
var warning_never = false;

pub const WarnChoice = enum { waiting, back, join };

/// Antes de entrar: o aviso aparece enquanto estiver ligado nas configurações.
pub fn wantsWarning(ctx: *const d.Ctx) bool {
    return ctx.st.settings.join_warning;
}

pub fn openWarning() void {
    warning_open = true;
    warning_never = false;
}

/// Desenha o aviso dentro da janela de entrar (`r` é a janela inteira).
pub fn joinWarning(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect) WarnChoice {
    const fam = ctx.ui;
    d.text(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.tr("Antes de entrar", "Before you join"));
    const msg = i18n.tr(
        "Entrar e sair de muitos servidores em pouco tempo é o motivo mais comum de contas que usam clientes de terceiros, como este, serem bloqueadas pelo Discord. Entre só nos servidores que você quer de verdade, um de cada vez.",
        "Joining or leaving many servers in a short time is the most common reason accounts on third-party clients like this one get locked by Discord. Only join servers you really want, one at a time.",
    );
    const font = fam.get(.regular);
    const text_w = r.w - 36 - 58;
    const card: d.Rect = .{ .x = r.x + 18, .y = r.y + 52, .w = r.w - 36, .h = wrap(font, null, 0, 0, text_w, 13.5, ctx.col(.text), msg) + 28 };
    const radius = @max(ctx.th.radius + 2, 4);
    const warn = ctx.col(.idle);
    d.rect(dl, card, warn.alpha(0.12), radius);
    d.border(dl, card, warn.alpha(0.5), radius, 1);
    qa.mark(card, "join-warning", .{});
    d.circle(dl, card.x + 24, card.y + 25, 11, warn);
    const bold = fam.get(.bold);
    d.text(dl, bold, 15, card.x + 24 - d.width(bold, 15, "!") / 2, card.y + 25 - 15 * 0.62, ctx.col(.bg), "!");
    _ = wrap(font, dl, card.x + 46, card.y + 14, text_w, 13.5, ctx.col(.text), msg);

    const cb: d.Rect = .{ .x = r.x + 18, .y = card.bottom() + 14, .w = r.w - 36, .h = 26 };
    qa.mark(cb, "join-warn-never", .{});
    if (d.hit(ctx, 0x7180, cb).clicked) warning_never = !warning_never;
    checkbox(ctx, dl, cb.x, cb.y + 4, warning_never);
    _ = d.textClipped(dl, font, 13, cb.x + 26, d.centerY(cb, 13), ctx.col(.muted), i18n.tr("Não mostrar de novo (dá para religar em Privacidade)", "Don't show this again (turn it back on in Privacy)"), cb.w - 28);

    const pressed = footer(ctx, dl, r, 0x7181, i18n.tr("Voltar", "Back"), i18n.tr("Entrar mesmo assim", "Join anyway"), true, "join-warn-back", "join-warn-go");
    if (pressed[0]) {
        warning_open = false;
        return .back;
    }
    if (pressed[1]) {
        warning_open = false;
        if (warning_never) {
            ctx.st.settings.join_warning = false;
            ctx.act(.save_settings);
        }
        return .join;
    }
    return .waiting;
}

// --- "Entrei, mas não consigo falar" ------------------------------------------------------

/// No lugar da caixa de texto, num servidor que ainda pede as regras: o motivo e o botão que
/// abre as regras. (Os outros motivos de não poder mandar ficam em outros lugares.)
pub fn pendingBand(ctx: *d.Ctx, n: *const kdl.Node, r: d.Rect, guild: Id) void {
    const fam = ctx.familyFor(n);
    const dl = ctx.dl;
    const pill = d.is(n, "variant", "pill", "box");
    const prompt = d.is(n, "variant", "prompt", "box");
    const radius = if (pill) r.h / 2 else ctx.th.radius + 4;
    const fs = ctx.th.font_size;
    if (prompt) d.line(dl, r.x, r.y + 0.5, r.right(), r.y + 0.5, ctx.col(.border), 1);
    qa.mark(r, "composer-pending", .{});
    if (!prompt) d.rect(dl, r, ctx.col(.elevated).alpha(0.5), radius);
    const lbl = i18n.tr("Ver as regras", "Read the rules");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 30;
    const bh = @min(30, r.h - 10);
    const br: d.Rect = .{ .x = r.right() - bw - (if (pill) r.h / 3 else 8), .y = r.y + (r.h - bh) / 2, .w = bw, .h = bh };
    qa.mark(br, "pending-rules", .{});
    if (forum.primary(ctx, dl, fam, 0x7190, br, lbl, true)) ctx.popup(.{ .server_rules = .{ .guild = guild } });
    var tx = r.x + 44;
    if (prompt) {
        tx = r.x + 10;
    } else icons.lock(dl, r.x + 24, r.y + r.h / 2 - 2, ctx.col(.faint).u());
    const t = if (waiting_guild == guild)
        i18n.tr("Respostas enviadas: falta a moderação do servidor aprovar.", "Answers sent: the server's moderators still need to approve them.")
    else
        i18n.tr("Para falar aqui, complete as regras do servidor.", "To talk here, complete the server's rules.");
    _ = d.textClipped(dl, fam.get(.regular), fs, tx, d.centerY(r, fs), ctx.col(.muted), t, br.x - tx - 12);
}

// --- Regras (verificação de membro) -------------------------------------------------------

const RulesState = enum { idle, loading, ready, failed, sending, send_failed, done, waiting, rejected };

var rules_guild: Id = 0;
var rules_state: RulesState = .idle;
var rules_err: core.Status = .failed;
var form: ?core.Form = null;
var agreed: [core.max_fields]bool = @splat(false);
var choice: [core.max_fields]?u8 = @splat(null);
/// Resposta curta: 150 letras de até 4 bytes; parágrafo: 1000.
var texts: [core.max_fields][4004]u8 = undefined;
/// Pedido que foi para a moderação aprovar à mão.
var waiting_guild: Id = 0;

fn freeForm() void {
    if (form) |*f| f.deinit();
    form = null;
}

fn loadRules(ctx: *d.Ctx, guild: Id) void {
    freeForm();
    rules_guild = guild;
    rules_state = .loading;
    agreed = @splat(false);
    choice = @splat(null);
    for (&texts) |*t| t[0] = 0;
    ctx.act(.{ .entrada = .{ .form = guild } });
}

fn answers(out: []core.Answer, f: *const core.Form) []core.Answer {
    for (f.fields, 0..) |fd, i| out[i] = switch (fd.kind) {
        .terms => if (agreed[i]) .agreed else .none,
        .text_input, .paragraph => .{ .text = std.mem.sliceTo(&texts[i], 0) },
        .multiple_choice => if (choice[i]) |k| .{ .choice = k } else .none,
        .unknown => .none,
    };
    return out[0..f.fields.len];
}

/// Para o QA: o formulário na tela pode ser enviado.
pub fn qaCanSend() bool {
    const f = if (form) |*x| x else return false;
    var buf: [core.max_fields]core.Answer = undefined;
    return rules_state == .ready and core.ready(f, answers(&buf, f));
}

pub fn drawRules(ctx: *d.Ctx, guild: Id) void {
    if (rules_guild != guild or rules_state == .idle or (popup.appearing and (rules_state == .failed or rules_state == .done or rules_state == .rejected))) loadRules(ctx, guild);
    const r = forum.dialogRect(ctx, 580, 640);
    const dl = popup.beginWindow("##server-rules", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    const fam = ctx.ui;
    var tb: [200]u8 = undefined;
    const gname = if (ctx.store.guild(guild)) |g| g.name else "";
    const title = if (gname.len > 0) i18n.fmt(&tb, "Regras de {s}", "{s} rules", .{gname}) else i18n.tr("Regras do servidor", "Server rules");
    _ = d.textClipped(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), title, r.w - 36);
    _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + 18, r.y + 42, ctx.col(.muted), i18n.tr("Leia e responda cada item. Nada vem marcado: o envio é seu.", "Read and answer each item. Nothing is filled in for you."), r.w - 36);
    const body: d.Rect = .{ .x = r.x + 1, .y = r.y + 68, .w = r.w - 2, .h = r.h - 68 - 64 };
    d.line(dl, r.x + 18, body.y - 0.5, r.right() - 18, body.y - 0.5, ctx.col(.border), 1);

    switch (rules_state) {
        .idle, .loading => centered(ctx, dl, body, ctx.col(.muted), i18n.tr("carregando as regras…", "loading the rules…")),
        .failed => centered(ctx, dl, body, ctx.col(.danger), switch (rules_err) {
            .not_found => i18n.tr("Este servidor não tem regras para responder agora.", "This server has no rules to answer right now."),
            .forbidden => i18n.tr("O Discord não mostrou as regras deste servidor para esta conta.", "Discord didn't show this server's rules to this account."),
            else => i18n.tr("Não consegui carregar as regras.", "Couldn't load the rules."),
        }),
        .done => centered(ctx, dl, body, ctx.col(.text), i18n.tr("Pronto: as regras foram respondidas. Você já pode falar no servidor.", "Done: the rules are answered. You can talk in the server now.")),
        .waiting => centered(ctx, dl, body, ctx.col(.text), i18n.tr("Respostas enviadas. A moderação do servidor ainda precisa aprovar a sua entrada.", "Answers sent. The server's moderators still need to approve you.")),
        .rejected => centered(ctx, dl, body, ctx.col(.danger), i18n.tr("O servidor recusou o pedido de entrada.", "The server rejected the join request.")),
        .ready, .sending, .send_failed => if (form) |*f| fields(ctx, body, f),
    }

    const f = if (form) |*x| x else null;
    const answering = f != null and (rules_state == .ready or rules_state == .sending or rules_state == .send_failed);
    if (!answering) {
        const failed = rules_state == .failed;
        const pressed = footer(ctx, dl, r, 0x71a0, if (failed) i18n.tr("Fechar", "Close") else null, if (failed) i18n.tr("Tentar de novo", "Try again") else i18n.tr("Fechar", "Close"), true, "rules-close", "rules-ok");
        if (pressed[0]) return popup.close(ctx);
        if (pressed[1]) {
            if (rules_state == .failed) return loadRules(ctx, guild);
            return popup.close(ctx);
        }
        return;
    }
    var buf: [core.max_fields]core.Answer = undefined;
    const ans = answers(&buf, f.?);
    const blocked = core.blocked(f.?);
    const ok = rules_state != .sending and core.ready(f.?, ans);
    const pressed = footer(ctx, dl, r, 0x71a0, i18n.tr("Cancelar", "Cancel"), if (rules_state == .sending) i18n.tr("Enviando…", "Sending…") else i18n.tr("Enviar", "Submit"), ok, "rules-close", "rules-submit");
    if (blocked) {
        footNote(ctx, dl, r, ctx.col(.danger), i18n.tr("Um item só dá para responder no app oficial.", "One item can only be answered in the official app."));
    } else if (rules_state == .send_failed) {
        footNote(ctx, dl, r, ctx.col(.danger), i18n.tr("Não deu para enviar. Tente de novo.", "Couldn't submit. Try again."));
    } else if (!ok and rules_state != .sending) {
        footNote(ctx, dl, r, ctx.col(.faint), i18n.tr("Responda os itens com *.", "Answer the items marked *."));
    }
    if (pressed[0]) return popup.close(ctx);
    if (pressed[1]) {
        const out = core.buildJoinRequest(ca, f.?, ans) catch return;
        rules_state = .sending;
        ctx.act(.{ .entrada = .{ .send_form = .{ .guild = guild, .body = out } } });
    }
}

fn fields(ctx: *d.Ctx, body: d.Rect, f: *const core.Form) void {
    const fam = ctx.ui;
    const dl = d.beginRegion(ctx, "##rules-body", body, 0);
    const o = c.ImGui_GetCursorScreenPos();
    var y = o.y + 14;
    const x = body.x + 17;
    const w = body.w - 34 - 10;
    const regular = fam.get(.regular);
    const semibold = fam.get(.semibold);
    if (f.description.len > 0) y += wrap(regular, dl, x, y, w, 13, ctx.col(.muted), f.description) + 14;
    for (f.fields, 0..) |*fd, i| {
        if (fd.required) d.text(dl, semibold, 14, x - 11, y, ctx.col(.danger), "*");
        y += wrap(semibold, dl, x, y, w, 14, ctx.col(.text), fd.label) + 2;
        if (fd.description.len > 0) y += wrap(regular, dl, x, y, w, 12.5, ctx.col(.muted), fd.description);
        y += 8;
        switch (fd.kind) {
            .terms => {
                const radius = @max(ctx.th.radius + 2, 4);
                var h: f32 = 12;
                for (fd.values) |rule| h += wrap(regular, null, 0, 0, w - 50, 13.5, ctx.col(.text), rule) + 8;
                const box: d.Rect = .{ .x = x, .y = y, .w = w, .h = h };
                d.rect(dl, box, ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
                d.border(dl, box, ctx.col(.border), radius, 1);
                var ry = y + 10;
                for (fd.values, 0..) |rule, k| {
                    var nb: [8]u8 = undefined;
                    d.text(dl, semibold, 13.5, x + 14, ry, ctx.col(.faint), std.fmt.bufPrint(&nb, "{d}.", .{k + 1}) catch "");
                    ry += wrap(regular, dl, x + 38, ry, w - 50, 13.5, ctx.col(.text), rule) + 8;
                }
                y += h + 10;
                const cb: d.Rect = .{ .x = x, .y = y, .w = w, .h = 26 };
                qa.mark(cb, "rules-agree:{d}", .{i});
                if (d.hit(ctx, 0x71b0 + i, cb).clicked) agreed[i] = !agreed[i];
                checkbox(ctx, dl, cb.x, cb.y + 4, agreed[i]);
                _ = d.textClipped(dl, fam.get(.medium), 13.5, cb.x + 28, d.centerY(cb, 13.5), ctx.col(.text), i18n.tr("Li e concordo com as regras", "I've read and agree to the rules"), w - 30);
                y += 26;
            },
            .text_input, .paragraph => {
                const par = fd.kind == .paragraph;
                const max = core.limit(fd.kind);
                // Até o limite em letras de 4 bytes (o ImGui conta bytes); quem confere as
                // letras é `core.ready`.
                const cap: usize = max * 4 + 1;
                const tbuf = texts[i][0..cap];
                var hb: [200]u8 = undefined;
                const hint = std.fmt.bufPrintSentinel(&hb, "{s}", .{d.utf8Prefix(fd.placeholder, 190)}, 0) catch "";
                const ir: d.Rect = .{ .x = x, .y = y, .w = w, .h = if (par) 96 else 36 };
                qa.mark(ir, "rules-text:{d}", .{i});
                c.ImGui_PushIDInt(@intCast(i));
                if (par) {
                    d.rect(dl, ir, ctx.col(.rail).mix(ctx.col(.surface), 0.35), @max(ctx.th.radius, 2));
                    c.ImGui_PushFontFloat(regular, 14);
                    c.ImGui_SetCursorScreenPos(d.v(ir.x + 6, ir.y + 6));
                    if (tbuf[0] == 0 and hint.len > 0) d.text(dl, regular, 14, ir.x + 11, ir.y + 9, ctx.col(.faint), hint);
                    _ = c.ImGui_InputTextMultilineEx("##rules-par", tbuf.ptr, tbuf.len, d.v(ir.w - 12, ir.h - 12), c.ImGuiInputTextFlags_WordWrap, null, null);
                    c.ImGui_PopFont();
                } else _ = forum.textInput(ctx, dl, ir, "##rules-text", hint.ptr, tbuf, 0);
                c.ImGui_PopID();
                y += ir.h + 4;
                const used = core.letters(std.mem.trim(u8, std.mem.sliceTo(tbuf, 0), " \t\r\n"));
                var cb: [24]u8 = undefined;
                const count = std.fmt.bufPrint(&cb, "{d}/{d}", .{ used, max }) catch "";
                d.text(dl, regular, 11.5, x + w - d.width(regular, 11.5, count), y, if (used > max) ctx.col(.danger) else ctx.col(.faint), count);
                y += 16;
            },
            .multiple_choice => for (fd.choices, 0..) |ch, k| {
                const cr: d.Rect = .{ .x = x, .y = y, .w = w, .h = 30 };
                qa.mark(cr, "rules-choice:{d}:{d}", .{ i, k });
                const hb = d.hit(ctx, 0x7200 + i * 256 + k, cr);
                if (hb.clicked) choice[i] = @intCast(k);
                const on = choice[i] != null and choice[i].? == k;
                if (hb.hovered) d.rect(dl, cr, ctx.col(.hover), @max(ctx.th.radius, 4));
                d.circle(dl, cr.x + 15, cr.y + 15, 8, if (on) ctx.col(.accent) else ctx.col(.border));
                d.circle(dl, cr.x + 15, cr.y + 15, 6.5, if (on) ctx.col(.accent) else ctx.col(.rail).mix(ctx.col(.surface), 0.25));
                if (on) d.circle(dl, cr.x + 15, cr.y + 15, 3, ctx.col(.accent_text));
                _ = d.textClipped(dl, regular, 13.5, cr.x + 32, d.centerY(cr, 13.5), ctx.col(.text), ch, cr.w - 40);
                y += 32;
            },
            .unknown => y += wrap(regular, dl, x, y, w, 13, ctx.col(.faint), i18n.tr("Este item só dá para responder no app oficial do Discord.", "This item can only be answered in the official Discord app.")),
        }
        y += 20;
    }
    d.endRegion(ctx, y, body.x);
}

// --- Boas-vindas (onboarding) -------------------------------------------------------------

const OnbState = enum { idle, loading, ready, failed, empty, sending, send_failed, done };

var onb_guild: Id = 0;
var onb_state: OnbState = .idle;
var onb_err: core.Status = .failed;
var onb: ?core.Onboarding = null;
var onb_sel: std.ArrayList(Id) = .empty;

fn freeOnboarding() void {
    if (onb) |*o| o.deinit();
    onb = null;
    onb_sel.clearAndFree(ca);
}

fn loadOnboarding(ctx: *d.Ctx, guild: Id) void {
    freeOnboarding();
    onb_guild = guild;
    onb_state = .loading;
    ctx.act(.{ .entrada = .{ .onboarding = guild } });
}

/// Para o QA: as opções marcadas agora.
pub fn qaSelected() []const Id {
    return onb_sel.items;
}

pub fn drawOnboarding(ctx: *d.Ctx, guild: Id) void {
    if (onb_guild != guild or onb_state == .idle or (popup.appearing and (onb_state == .failed or onb_state == .done))) loadOnboarding(ctx, guild);
    const r = forum.dialogRect(ctx, 580, 620);
    const dl = popup.beginWindow("##onboarding", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    const fam = ctx.ui;
    var tb: [200]u8 = undefined;
    const gname = if (ctx.store.guild(guild)) |g| g.name else "";
    _ = d.textClipped(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.fmt(&tb, "Boas-vindas de {s}", "Welcome to {s}", .{gname}), r.w - 36);
    _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + 18, r.y + 42, ctx.col(.muted), i18n.tr("O que você escolher muda os canais e cargos que recebe aqui.", "What you pick changes the channels and roles you get here."), r.w - 36);
    const body: d.Rect = .{ .x = r.x + 1, .y = r.y + 68, .w = r.w - 2, .h = r.h - 68 - 64 };
    d.line(dl, r.x + 18, body.y - 0.5, r.right() - 18, body.y - 0.5, ctx.col(.border), 1);

    switch (onb_state) {
        .idle, .loading => centered(ctx, dl, body, ctx.col(.muted), i18n.tr("carregando as perguntas…", "loading the questions…")),
        .failed => centered(ctx, dl, body, ctx.col(.danger), if (onb_err == .forbidden or onb_err == .not_found)
            i18n.tr("Este servidor não mostrou perguntas de boas-vindas para esta conta.", "This server didn't show onboarding questions to this account.")
        else
            i18n.tr("Não consegui carregar as perguntas.", "Couldn't load the questions.")),
        .empty => centered(ctx, dl, body, ctx.col(.muted), i18n.tr("Este servidor não tem perguntas de boas-vindas agora.", "This server has no onboarding questions right now.")),
        .done => centered(ctx, dl, body, ctx.col(.text), i18n.tr("Pronto: suas escolhas foram salvas.", "Done: your choices are saved.")),
        .ready, .sending, .send_failed => if (onb) |*o| prompts(ctx, body, o),
    }

    const answering = onb != null and (onb_state == .ready or onb_state == .sending or onb_state == .send_failed);
    if (!answering) {
        const failed = onb_state == .failed;
        const pressed = footer(ctx, dl, r, 0x7300, if (failed) i18n.tr("Fechar", "Close") else null, if (failed) i18n.tr("Tentar de novo", "Try again") else i18n.tr("Fechar", "Close"), true, "onb-close", "onb-ok");
        if (pressed[0]) return popup.close(ctx);
        if (pressed[1]) {
            if (onb_state == .failed) return loadOnboarding(ctx, guild);
            return popup.close(ctx);
        }
        return;
    }
    const o = &onb.?;
    const ok = onb_state != .sending and core.onboardingReady(o, onb_sel.items);
    const pressed = footer(ctx, dl, r, 0x7300, i18n.tr("Cancelar", "Cancel"), if (onb_state == .sending) i18n.tr("Salvando…", "Saving…") else i18n.tr("Salvar", "Save"), ok, "onb-close", "onb-submit");
    if (onb_state == .send_failed) {
        footNote(ctx, dl, r, ctx.col(.danger), i18n.tr("Não deu para salvar. Tente de novo.", "Couldn't save. Try again."));
    } else if (!ok and onb_state != .sending) {
        footNote(ctx, dl, r, ctx.col(.faint), i18n.tr("Responda as perguntas com *.", "Answer the questions marked *."));
    }
    if (pressed[0]) return popup.close(ctx);
    if (pressed[1]) {
        const out = core.buildOnboarding(ca, o, onb_sel.items, ctx.now_ms) catch return;
        onb_state = .sending;
        ctx.act(.{ .entrada = .{ .send_onboarding = .{ .guild = guild, .body = out, .first = o.chosen.len == 0 } } });
    }
}

fn prompts(ctx: *d.Ctx, body: d.Rect, o: *const core.Onboarding) void {
    const fam = ctx.ui;
    const dl = d.beginRegion(ctx, "##onboarding-body", body, 0);
    const pos = c.ImGui_GetCursorScreenPos();
    var y = pos.y + 14;
    const x = body.x + 17;
    const w = body.w - 34 - 10;
    const semibold = fam.get(.semibold);
    const regular = fam.get(.regular);
    const gap: f32 = 8;
    const cw = (w - gap) / 2;
    for (o.prompts, 0..) |*p, pi| {
        if (p.required and p.in_onboarding) d.text(dl, semibold, 14.5, x - 11, y, ctx.col(.danger), "*");
        y += wrap(semibold, dl, x, y, w, 14.5, ctx.col(.text), p.title) + 1;
        d.text(dl, regular, 12, x, y, ctx.col(.faint), if (p.single) i18n.tr("Escolha uma", "Pick one") else i18n.tr("Escolha quantas quiser", "Pick as many as you like"));
        y += 24;
        var has_desc = false;
        for (p.options) |op| has_desc = has_desc or op.description.len > 0;
        const ch: f32 = if (has_desc) 54 else 38;
        for (p.options, 0..) |op, oi| {
            const col_i: f32 = @floatFromInt(oi % 2);
            const row_y = y + @as(f32, @floatFromInt(oi / 2)) * (ch + gap);
            const cr: d.Rect = .{ .x = x + col_i * (cw + gap), .y = row_y, .w = cw, .h = ch };
            qa.mark(cr, "onb-option:{d}:{d}", .{ pi, oi });
            const hb = d.hit(ctx, 0x7400 + pi * 512 + oi, cr);
            if (hb.clicked and onb_state != .sending) core.toggle(ca, &onb_sel, o, op.id) catch {};
            const on = std.mem.indexOfScalar(Id, onb_sel.items, op.id) != null;
            const radius = @max(ctx.th.radius + 2, 4);
            d.rect(dl, cr, if (on) ctx.col(.accent).alpha(0.2) else if (hb.hovered) ctx.col(.hover) else ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
            d.border(dl, cr, if (on) ctx.col(.accent) else ctx.col(.border), radius, if (on) 1.5 else 1);
            var tx = cr.x + 12;
            const ty = if (has_desc) cr.y + 9 else d.centerY(cr, 13.5);
            if (op.emoji.len > 0) {
                d.text(dl, regular, 14, tx, ty, ctx.col(.text), op.emoji);
                tx += d.width(regular, 14, op.emoji) + 7;
            }
            _ = d.textClipped(dl, semibold, 13.5, tx, ty, ctx.col(.text), op.title, cr.right() - tx - 10);
            if (op.description.len > 0) _ = d.textClipped(dl, regular, 12, cr.x + 12, cr.y + 31, ctx.col(.muted), op.description, cr.w - 22);
        }
        const rows: f32 = @floatFromInt((p.options.len + 1) / 2);
        y += rows * (ch + gap) + 18;
    }
    d.endRegion(ctx, y, body.x);
}

// --- Respostas da rede --------------------------------------------------------------------

/// O que chegou da rede para as janelas (o `pending` em si fica no Store). Libera o corpo.
pub fn deliver(e: core.Event) void {
    defer core.freeEvent(ca, e);
    switch (e) {
        .pending => |p| if (!p.pending and waiting_guild == p.guild) {
            waiting_guild = 0;
        },
        .form => |f| {
            if (f.guild != rules_guild or rules_state != .loading) return;
            if (f.status != .ok) {
                rules_err = f.status;
                rules_state = .failed;
                return;
            }
            form = core.parseForm(ca, f.body) catch {
                rules_err = .failed;
                rules_state = .failed;
                return;
            };
            rules_state = .ready;
        },
        .form_sent => |s| {
            if (s.guild != rules_guild or rules_state != .sending) return;
            if (s.status != .ok) {
                rules_state = .send_failed;
                return;
            }
            switch (s.application) {
                .submitted => {
                    rules_state = .waiting;
                    waiting_guild = s.guild;
                },
                .rejected => rules_state = .rejected,
                // Aprovado: o membro chega sem `pending` pelo gateway e a caixa volta.
                else => rules_state = .done,
            }
            freeForm();
        },
        .onboarding => |ob| {
            if (ob.guild != onb_guild or onb_state != .loading) return;
            if (ob.status != .ok) {
                onb_err = ob.status;
                onb_state = .failed;
                return;
            }
            onb = core.parseOnboarding(ca, ob.body) catch {
                onb_err = .failed;
                onb_state = .failed;
                return;
            };
            const o = &onb.?;
            if (!o.enabled or o.prompts.len == 0) {
                onb_state = .empty;
                return;
            }
            // O que a própria conta já tinha escolhido antes (nada novo vem marcado).
            onb_sel.appendSlice(ca, o.chosen) catch {};
            onb_state = .ready;
        },
        .onboarding_sent => |s| {
            if (s.guild != onb_guild or onb_state != .sending) return;
            if (s.status != .ok) {
                onb_state = .send_failed;
                return;
            }
            onb_state = .done;
            freeOnboarding();
        },
    }
}
