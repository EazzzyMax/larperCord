//! Moderação na interface: as entradas do menu de alguém (lista de membros,
//! autor da mensagem, perfil, quem está na call), o diálogo de confirmação
//! (expulsar, banir, castigar, com o motivo opcional), a lista de banimentos do
//! servidor e o reloginho de castigo na lista de membros. A regra de quem pode o
//! quê e os pedidos ficam em core/moderacao.zig.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const w = @import("widgets.zig");
const i18n = @import("i18n.zig");
const anim = @import("anim.zig");
const popup = @import("popup.zig");
const inbox = @import("inbox.zig");
const forum = @import("forum.zig");
const invites = @import("invites.zig");
const State = @import("state.zig").State;
const Store = @import("../core/store.zig").Store;
const types = @import("../core/types.zig");
const ev = @import("../core/event.zig");
const mod = @import("../core/moderacao.zig");
const send_limits = @import("composer_limits.zig");
const Id = types.Id;

const ca = std.heap.c_allocator;

// --- Menu ------------------------------------------------------------------------

/// Ids das entradas no menu de contexto (popup.zig).
pub const id_mute: u8 = 160;
pub const id_deaf: u8 = 161;
pub const id_timeout: u8 = 162;
pub const id_kick: u8 = 163;
pub const id_ban: u8 = 164;
pub const id_bans: u8 = 166;

/// `label` (português) é também a marca do QA.
pub const Entrada = struct { label: []const u8, en: []const u8, id: u8, danger: bool = false };

/// O castigo de alguém ainda vale? Fim em ms, ou 0.
pub fn castigoAte(ctx: *const d.Ctx, guild: Id, uid: Id) i64 {
    if (!ctx.store.algum_castigo) return 0;
    const mi = ctx.store.memberInfo(guild, uid) orelse return 0;
    const ms = @as(i64, mi.timeout_s) * 1000;
    return if (ms > ctx.now_ms) ms else 0;
}

/// Nós mesmos de castigo nesse servidor (ui/composer_limits.zig sabe): até
/// acabar, o Discord só deixa ver o canal e ler o histórico, nada de moderar.
fn euDeCastigo(ctx: *const d.Ctx, guild: Id) bool {
    return send_limits.state.member(guild).timeout_until_ms > ctx.now_ms;
}

/// O que dá para fazer com `uid` no servidor aberto, já como entradas do menu.
pub fn entradas(ctx: *d.Ctx, uid: Id, out: *[5]Entrada) []const Entrada {
    const g = ctx.st.guild;
    if (g == 0 or euDeCastigo(ctx, g)) return out[0..0];
    const p = mod.podeNoStore(ctx.store, g, uid);
    var n: usize = 0;
    const vf = ctx.store.voiceFlags(uid);
    if (p.mute) {
        out[n] = if (vf.mute) .{ .label = "Tirar silêncio do servidor", .en = "Server Unmute", .id = id_mute } else .{ .label = "Silenciar no servidor", .en = "Server Mute", .id = id_mute };
        n += 1;
    }
    if (p.deafen) {
        out[n] = if (vf.deaf) .{ .label = "Tirar surdez do servidor", .en = "Server Undeafen", .id = id_deaf } else .{ .label = "Ensurdecer no servidor", .en = "Server Deafen", .id = id_deaf };
        n += 1;
    }
    if (p.timeout) {
        out[n] = if (castigoAte(ctx, g, uid) != 0) .{ .label = "Remover castigo…", .en = "Remove Timeout…", .id = id_timeout } else .{ .label = "Castigar…", .en = "Timeout…", .id = id_timeout, .danger = true };
        n += 1;
    }
    if (p.kick) {
        out[n] = .{ .label = "Expulsar…", .en = "Kick…", .id = id_kick, .danger = true };
        n += 1;
    }
    if (p.ban) {
        out[n] = .{ .label = "Banir…", .en = "Ban…", .id = id_ban, .danger = true };
        n += 1;
    }
    return out[0..n];
}

/// "Banimentos" no menu do servidor: só para quem pode banir.
pub fn podeVerBans(ctx: *const d.Ctx, guild: Id) bool {
    return !euDeCastigo(ctx, guild) and mod.podeBanir(ctx.store.permissions(guild));
}

/// Clicou numa entrada do menu (`id`: a pessoa, ou o servidor em "Banimentos").
pub fn escolheu(ctx: *d.Ctx, id: Id, item: u8) void {
    const g = ctx.st.guild;
    switch (item) {
        id_mute => rapido(ctx, g, id, if (ctx.store.voiceFlags(id).mute) .unmute else .mute),
        id_deaf => rapido(ctx, g, id, if (ctx.store.voiceFlags(id).deaf) .undeafen else .deafen),
        id_timeout => abrir(ctx, g, id, .timeout),
        id_kick => abrir(ctx, g, id, .kick),
        id_ban => abrir(ctx, g, id, .ban),
        id_bans => abrirBans(ctx, id),
        else => {},
    }
}

// --- Pedidos -----------------------------------------------------------------------

var next_req: u32 = 0;

fn novoReq() u32 {
    next_req +%= 1;
    if (next_req == 0) next_req = 1;
    return next_req;
}

/// Manda o pedido; o motivo vai copiado (a rede é dona da cópia).
fn enviar(ctx: *d.Ctx, guild: Id, user: Id, acao: mod.Acao, apagar_s: u32, ate_s: i64, texto: []const u8) u32 {
    const req = novoReq();
    const m = std.mem.trim(u8, texto, " \t\r\n");
    const owned: []const u8 = if (m.len > 0) ca.dupe(u8, m) catch "" else "";
    ctx.act(.{ .moderate = .{ .req = req, .guild = guild, .user = user, .acao = acao, .apagar_s = apagar_s, .ate_s = ate_s, .motivo = owned } });
    return req;
}

/// Silenciar/ensurdecer: na hora, como no Discord (o ícone da call confirma).
fn rapido(ctx: *d.Ctx, guild: Id, user: Id, acao: mod.Acao) void {
    _ = enviar(ctx, guild, user, acao, 0, 0, "");
}

// --- Diálogo de confirmação ------------------------------------------------------------

const Dialogo = enum { kick, ban, timeout };
var dialogo: Dialogo = .kick;
var alvo: Id = 0;
var servidor: Id = 0;
var motivo: [mod.max_motivo + 1]u8 = @splat(0);
var apagar_i: usize = 0;
var castigo_i: usize = 0;
/// No diálogo de castigo: tirar o que já está valendo.
var remover = false;
/// Pedido do diálogo esperando resposta (0 = nenhum).
var dialog_req: u32 = 0;
const Falha = struct { status: u16, code: u32 };
var falha: ?Falha = null;

fn abrir(ctx: *d.Ctx, guild: Id, user: Id, dlg: Dialogo) void {
    if (guild == 0) return;
    abrirEm(ctx.st, guild, user, dlg, dlg == .timeout and castigoAte(ctx, guild, user) != 0);
}

fn abrirEm(st: *State, guild: Id, user: Id, dlg: Dialogo, tirar: bool) void {
    dialogo = dlg;
    alvo = user;
    servidor = guild;
    @memset(&motivo, 0);
    apagar_i = 0;
    castigo_i = 0;
    remover = tirar;
    dialog_req = 0;
    falha = null;
    st.popup = .{ .moderacao = .{ .guild = guild, .user = user } };
}

/// O QA de temas abre o diálogo de expulsar direto (nem todo tema mostra a lista de membros).
pub fn qaAbrirExpulsar(st: *State, guild: Id, user: Id) void {
    abrirEm(st, guild, user, .kick, false);
}

/// Botão de confirmar perigoso (vermelho), como o `primary` dos outros diálogos.
fn perigo(ctx: *d.Ctx, dl: *c.ImDrawList, id: usize, r: d.Rect, txt: []const u8, on: bool, danger: bool) bool {
    const hb = d.hit(ctx, id, r);
    const base = if (danger) ctx.col(.danger) else ctx.col(.accent);
    const radius = @max(ctx.th.radius, 2);
    if (on) {
        d.rect(dl, r, if (hb.hovered) base.mix(d.Rgba.white, 0.12) else base, radius);
    } else d.rect(dl, r, ctx.col(.hover), radius);
    const font = ctx.ui.get(.semibold);
    const tc = if (!on) ctx.col(.faint) else if (danger) d.Rgba.white else ctx.col(.accent_text);
    d.text(dl, font, 13.5, r.x + (r.w - d.width(font, 13.5, txt)) / 2, d.centerY(r, 13.5), tc, txt);
    return on and hb.clicked;
}

fn label(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: f32, pt: []const u8, en: []const u8) void {
    d.text(dl, ctx.ui.get(.semibold), 11.5, x, y, ctx.col(.faint), i18n.tr(pt, en));
}

/// Linha vermelha com o porquê da recusa.
fn erroLinha(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: f32, wd: f32, f: Falha, mark: []const u8) void {
    const e = mod.erro(f.status, f.code);
    var b: [200]u8 = undefined;
    const t = if (f.code != 0)
        std.fmt.bufPrint(&b, "{s} ({d})", .{ i18n.tr(e.pt, e.en), f.code }) catch i18n.tr(e.pt, e.en)
    else if (f.status != 0)
        std.fmt.bufPrint(&b, "{s} (HTTP {d})", .{ i18n.tr(e.pt, e.en), f.status }) catch i18n.tr(e.pt, e.en)
    else
        i18n.tr(e.pt, e.en);
    const h = inbox.wrapText(null, ctx.ui.get(.medium), 13, x, y, wd, t, 2, ctx.col(.danger));
    qa.mark(.{ .x = x, .y = y, .w = wd, .h = h }, "{s}", .{mark});
    _ = inbox.wrapText(dl, ctx.ui.get(.medium), 13, x, y, wd, t, 2, ctx.col(.danger));
}

pub fn draw(ctx: *d.Ctx, guild: Id, user: Id) void {
    if (user == 0) return drawBans(ctx, guild);
    if (user != alvo or guild != servidor) return popup.close(ctx);
    const u = ctx.store.user(user) orelse return popup.close(ctx);
    const g = ctx.store.guild(guild) orelse return popup.close(ctx);
    const fam = ctx.ui;
    const castigado = castigoAte(ctx, guild, user) != 0;
    const extra: f32 = switch (dialogo) {
        .kick => 0,
        .ban => 62,
        .timeout => if (castigado) 96 else 62,
    };
    const r = forum.dialogRect(ctx, 480, 262 + extra);
    const dl = popup.beginWindow("##moderacao", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    qa.mark(r, "mod-dialog", .{});
    const x = r.x + 20;
    const iw = r.w - 40;
    var tb: [160]u8 = undefined;
    const title = switch (dialogo) {
        .kick => i18n.fmt(&tb, "Expulsar {s}?", "Kick {s}?", .{d.utf8Prefix(u.name, 40)}),
        .ban => i18n.fmt(&tb, "Banir {s}?", "Ban {s}?", .{d.utf8Prefix(u.name, 40)}),
        .timeout => if (remover)
            i18n.fmt(&tb, "Remover o castigo de {s}?", "Remove {s}'s timeout?", .{d.utf8Prefix(u.name, 40)})
        else
            i18n.fmt(&tb, "Castigar {s}", "Time out {s}", .{d.utf8Prefix(u.name, 40)}),
    };
    _ = d.textClipped(dl, fam.get(.bold), 17, x, r.y + 18, ctx.col(.text), title, iw);
    var sb: [320]u8 = undefined;
    const gname = d.utf8Prefix(g.name, 48);
    const sub = switch (dialogo) {
        .kick => i18n.fmt(&sb, "Sai de {s}, mas pode voltar com um convite.", "They'll leave {s} but can come back with an invite.", .{gname}),
        .ban => i18n.fmt(&sb, "Sai de {s} e não volta, nem com convite, até o banimento ser revogado.", "They'll leave {s} and can't come back, even with an invite, until the ban is revoked.", .{gname}),
        .timeout => if (remover)
            i18n.fmt(&sb, "Volta a poder falar em {s} na hora.", "They can talk in {s} again right away.", .{gname})
        else
            i18n.fmt(&sb, "Em {s}, não manda mensagens, não reage e não fala em call até o castigo acabar.", "In {s}, they can't send messages, react or speak in voice until it ends.", .{gname}),
    };
    _ = inbox.wrapText(dl, fam.get(.regular), 13.5, x, r.y + 46, iw, sub, 2, ctx.col(.muted));
    var y = r.y + 92;

    const gap: f32 = 6;
    switch (dialogo) {
        .kick => {},
        .ban => {
            label(ctx, dl, x, y, "APAGAR MENSAGENS RECENTES", "DELETE MESSAGE HISTORY");
            y += 20;
            const cw = (iw - gap * @as(f32, mod.apagar.len - 1)) / @as(f32, mod.apagar.len);
            for (mod.apagar, 0..) |p, i| {
                const cr: d.Rect = .{ .x = x + @as(f32, @floatFromInt(i)) * (cw + gap), .y = y, .w = cw, .h = 28 };
                qa.mark(cr, "mod-apagar:{d}", .{p.s});
                if (invites.chip(ctx, dl, 0x7300 + i, cr, i18n.tr(p.pt, p.en), apagar_i == i)) apagar_i = i;
            }
            y += 42;
        },
        .timeout => {
            label(ctx, dl, x, y, "DURAÇÃO", "DURATION");
            y += 20;
            const cw = (iw - gap * @as(f32, mod.castigos.len - 1)) / @as(f32, mod.castigos.len);
            for (mod.castigos, 0..) |p, i| {
                const cr: d.Rect = .{ .x = x + @as(f32, @floatFromInt(i)) * (cw + gap), .y = y, .w = cw, .h = 28 };
                qa.mark(cr, "mod-castigo:{d}", .{p.s});
                if (invites.chip(ctx, dl, 0x7310 + i, cr, i18n.tr(p.pt, p.en), !remover and castigo_i == i)) {
                    castigo_i = i;
                    remover = false;
                }
            }
            y += 34;
            if (castigado) {
                const cr: d.Rect = .{ .x = x, .y = y, .w = iw, .h = 28 };
                qa.mark(cr, "mod-castigo:0", .{});
                var rb: [96]u8 = undefined;
                var stb: [64]u8 = undefined;
                const now_s = @divTrunc(ctx.now_ms, 1000);
                const until = @divTrunc(castigoAte(ctx, guild, user), 1000);
                const t = i18n.fmt(&rb, "Remover castigo (acaba {s})", "Remove timeout (ends {s})", .{w.stamp(&stb, until, now_s)});
                if (invites.chip(ctx, dl, 0x7320, cr, t, remover)) remover = true;
                y += 34;
            }
            y += 8;
        },
    }

    label(ctx, dl, x, y, "MOTIVO (OPCIONAL)", "REASON (OPTIONAL)");
    y += 20;
    const ir: d.Rect = .{ .x = x, .y = y, .w = iw, .h = 36 };
    qa.mark(ir, "mod-motivo", .{});
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    const enter = forum.textInput(ctx, dl, ir, "##mod-motivo", i18n.trZ("Aparece no registro de auditoria", "Shows up in the audit log").ptr, motivo[0..], c.ImGuiInputTextFlags_EnterReturnsTrue);
    y = ir.bottom() + 10;
    if (falha) |f| erroLinha(ctx, dl, x, y, iw, f, "mod-erro");

    const sending = dialog_req != 0;
    const ok_lbl: []const u8 = if (sending) i18n.tr("Enviando…", "Sending…") else switch (dialogo) {
        .kick => i18n.tr("Expulsar", "Kick"),
        .ban => i18n.tr("Banir", "Ban"),
        .timeout => if (remover) i18n.tr("Remover castigo", "Remove Timeout") else i18n.tr("Castigar", "Time Out"),
    };
    const bw = @max(d.width(fam.get(.semibold), 13.5, ok_lbl) + 36, 96);
    const br: d.Rect = .{ .x = r.right() - 20 - bw, .y = r.bottom() - 52, .w = bw, .h = 34 };
    qa.mark(br, "mod-confirm", .{});
    const danger = !(dialogo == .timeout and remover);
    const confirm = perigo(ctx, dl, 0x7330, br, ok_lbl, !sending, danger) or (enter and !sending);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "mod-cancel", .{});
    if (inbox.button(ctx, dl, 0x7331, cr, cancel, false)) return popup.close(ctx);
    if (!confirm) return;
    falha = null;
    const txt = std.mem.sliceTo(&motivo, 0);
    dialog_req = switch (dialogo) {
        .kick => enviar(ctx, guild, user, .kick, 0, 0, txt),
        .ban => enviar(ctx, guild, user, .ban, mod.apagar[apagar_i].s, 0, txt),
        .timeout => if (remover)
            enviar(ctx, guild, user, .untimeout, 0, 0, txt)
        else
            enviar(ctx, guild, user, .timeout, 0, @divTrunc(ctx.now_ms, 1000) + mod.castigos[castigo_i].s, txt),
    };
}

// --- Banimentos --------------------------------------------------------------------------

const Carga = enum { loading, ok, failed };
var bans_guild: Id = 0;
var bans_req: u32 = 0;
var bans_state: Carga = .loading;
var bans_list: []ev.Ban = &.{};
var bans_motivo: [mod.max_motivo + 1]u8 = @splat(0);
var unban_req: u32 = 0;
var unban_user: Id = 0;
var bans_falha: ?Falha = null;

fn freeBans(list: []ev.Ban) void {
    for (list) |b| if (b.motivo.len > 0) ca.free(b.motivo);
    if (list.len > 0) ca.free(list);
}

fn abrirBans(ctx: *d.Ctx, guild: Id) void {
    freeBans(bans_list);
    bans_list = &.{};
    bans_guild = guild;
    bans_state = .loading;
    bans_falha = null;
    unban_req = 0;
    unban_user = 0;
    @memset(&bans_motivo, 0);
    bans_req = novoReq();
    ctx.st.popup = .{ .moderacao = .{ .guild = guild, .user = 0 } };
    ctx.act(.{ .fetch_bans = .{ .req = bans_req, .guild = guild } });
}

/// A lista chegou (fica com ela; uma resposta velha é jogada fora).
pub fn bansDelivered(b: ev.Bans) void {
    if (b.req != bans_req or b.guild != bans_guild) return freeBans(b.list);
    freeBans(bans_list);
    bans_list = b.list;
    bans_state = if (b.ok) .ok else .failed;
}

/// Quem está na lista de banimentos aberta (o QA confere).
pub fn banidos() []const ev.Ban {
    return bans_list;
}

fn drawBans(ctx: *d.Ctx, guild: Id) void {
    if (guild != bans_guild) return popup.close(ctx);
    const g = ctx.store.guild(guild) orelse return popup.close(ctx);
    const fam = ctx.ui;
    const r = forum.dialogRect(ctx, 520, 540);
    const dl = popup.beginWindow("##bans", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    qa.mark(r, "bans-panel", .{});
    const x = r.x + 20;
    const iw = r.w - 40;
    const title = i18n.tr("Banimentos", "Bans");
    d.text(dl, fam.get(.bold), 17, x, r.y + 18, ctx.col(.text), title);
    if (bans_state == .ok) {
        var nb: [16]u8 = undefined;
        d.text(dl, fam.get(.regular), 13, x + d.width(fam.get(.bold), 17, title) + 10, r.y + 22, ctx.col(.faint), std.fmt.bufPrint(&nb, "{d}", .{bans_list.len}) catch "");
    }
    _ = d.textClipped(dl, fam.get(.regular), 13, x, r.y + 44, ctx.col(.muted), g.name, iw);
    var y = r.y + 72;
    label(ctx, dl, x, y, "MOTIVO AO REVOGAR (OPCIONAL)", "REASON FOR UNBANNING (OPTIONAL)");
    y += 20;
    const ir: d.Rect = .{ .x = x, .y = y, .w = iw, .h = 34 };
    qa.mark(ir, "bans-motivo", .{});
    _ = forum.textInput(ctx, dl, ir, "##bans-motivo", i18n.trZ("Aparece no registro de auditoria", "Shows up in the audit log").ptr, bans_motivo[0..], 0);
    y = ir.bottom() + 8;
    if (bans_falha) |f| {
        erroLinha(ctx, dl, x, y, iw, f, "bans-erro");
        y += 38;
    }
    d.line(dl, r.x, y + 4, r.right(), y + 4, ctx.col(.border), 1);

    const close_lbl = i18n.tr("Fechar", "Close");
    const cw = inbox.buttonWidth(ctx, close_lbl);
    const close_r: d.Rect = .{ .x = r.right() - 20 - cw, .y = r.bottom() - 42, .w = cw, .h = 28 };
    const body: d.Rect = .{ .x = r.x + 1, .y = y + 5, .w = r.w - 2, .h = close_r.y - 10 - (y + 5) };
    const bdl = d.beginRegion(ctx, "##bans-body", body, 0);
    popup.track(bdl);
    ctx.dl = bdl;
    const o = c.ImGui_GetCursorScreenPos();
    var by = o.y + 8;
    switch (bans_state) {
        .loading => {
            // Os pontinhos já pedem o próximo quadro no ritmo deles; a lista que chega redesenha.
            w.typingDots(bdl, body.x + body.w / 2 - 7, by + 50, ctx.col(.muted), ctx.now_ms);
            by += 100;
        },
        .failed => {
            d.text(bdl, fam.get(.medium), 14, x, by + 20, ctx.col(.danger), i18n.tr("Não consegui carregar os banimentos.", "Couldn't load the bans."));
            by += 60;
        },
        .ok => {
            if (bans_list.len == 0) {
                const t = i18n.tr("Ninguém banido neste servidor.", "Nobody is banned from this server.");
                const tr: d.Rect = .{ .x = x, .y = by + 20, .w = iw, .h = 20 };
                qa.mark(tr, "bans-empty", .{});
                d.text(bdl, fam.get(.medium), 14, x, tr.y, ctx.col(.muted), t);
                by += 60;
            }
            for (bans_list) |b| {
                const rh: f32 = 52;
                const rr: d.Rect = .{ .x = body.x + 10, .y = by, .w = body.w - 20, .h = rh - 4 };
                if (rr.bottom() < body.y or rr.y > body.bottom()) {
                    by += rh;
                    continue;
                }
                qa.mark(rr, "ban:{d}", .{b.user});
                if (ctx.hovering(rr)) d.rect(bdl, rr, ctx.col(.hover).alpha(0.6), ctx.th.radius);
                w.avatar(ctx, bdl, rr.x + 22, rr.y + rr.h / 2, 32, b.user, .circle, null, 1);
                var idb: [24]u8 = undefined;
                const name = if (ctx.store.user(b.user)) |u| u.name else std.fmt.bufPrint(&idb, "{d}", .{b.user}) catch "";
                const busy = unban_req != 0 and unban_user == b.user;
                const lbl = if (busy) i18n.tr("Revogando…", "Unbanning…") else i18n.tr("Revogar", "Unban");
                const bw = inbox.buttonWidth(ctx, lbl);
                const btn: d.Rect = .{ .x = rr.right() - bw - 8, .y = rr.y + (rr.h - 28) / 2, .w = bw, .h = 28 };
                const room = btn.x - (rr.x + 46) - 10;
                if (b.motivo.len > 0) {
                    _ = d.textClipped(bdl, fam.get(.medium), 14.5, rr.x + 46, rr.y + 6, ctx.col(.text), name, room);
                    _ = d.textClipped(bdl, fam.get(.regular), 12.5, rr.x + 46, rr.y + 26, ctx.col(.faint), b.motivo, room);
                } else _ = d.textClipped(bdl, fam.get(.medium), 14.5, rr.x + 46, d.centerY(rr, 14.5), ctx.col(.text), name, room);
                qa.mark(btn, "unban:{d}", .{b.user});
                if (inbox.button(ctx, bdl, @as(usize, 0x7400) +% @as(usize, @truncate(b.user)), btn, lbl, true) and unban_req == 0) {
                    bans_falha = null;
                    unban_user = b.user;
                    unban_req = enviar(ctx, guild, b.user, .unban, 0, 0, std.mem.sliceTo(&bans_motivo, 0));
                }
                by += rh;
            }
        },
    }
    d.endRegion(ctx, by + 8, body.x);
    ctx.dl = dl;
    qa.mark(close_r, "bans-close", .{});
    if (inbox.button(ctx, dl, 0x7340, close_r, close_lbl, false)) popup.close(ctx);
}

// --- Respostas -----------------------------------------------------------------------------

fn nome(store: *const Store, uid: Id) []const u8 {
    return if (store.user(uid)) |u| d.utf8Prefix(u.name, 40) else "?";
}

/// Resposta de um pedido de moderação: fecha o diálogo com um aviso, ou mostra
/// por que o Discord recusou (no diálogo, se ainda estiver aberto).
pub fn delivered(st: *State, store: *const Store, r: ev.Moderated, now_ms: i64) void {
    if (r.req == unban_req and r.req != 0) {
        unban_req = 0;
        unban_user = 0;
        if (!r.ok) {
            bans_falha = .{ .status = r.status, .code = r.code };
            return;
        }
        for (bans_list, 0..) |b, i| if (b.user == r.user) {
            if (b.motivo.len > 0) ca.free(b.motivo);
            std.mem.copyForwards(ev.Ban, bans_list[i .. bans_list.len - 1], bans_list[i + 1 ..]);
            // Fica com a mesma alocação: o tamanho de verdade é o da lista menos um.
            bans_list = shrink(bans_list);
            break;
        };
        st.showToast(now_ms, false, "banimento de {s} revogado", "{s} was unbanned", .{nome(store, r.user)});
        return;
    }
    const dialog_open = st.popup == .moderacao and st.popup.moderacao.user == r.user and st.popup.moderacao.user != 0;
    if (r.req == dialog_req and r.req != 0) {
        dialog_req = 0;
        if (!r.ok and dialog_open) {
            falha = .{ .status = r.status, .code = r.code };
            return;
        }
        if (r.ok and dialog_open) st.popup = .none;
    }
    if (!r.ok) {
        const e = mod.erro(r.status, r.code);
        st.showToast(now_ms, true, "{s}", "{s}", .{i18n.tr(e.pt, e.en)});
        return;
    }
    const n = nome(store, r.user);
    switch (r.acao) {
        .kick => st.showToast(now_ms, false, "{s} foi expulso do servidor", "{s} was kicked", .{n}),
        .ban => st.showToast(now_ms, false, "{s} foi banido do servidor", "{s} was banned", .{n}),
        .timeout => st.showToast(now_ms, false, "{s} está de castigo", "{s} is timed out", .{n}),
        .untimeout => st.showToast(now_ms, false, "o castigo de {s} acabou", "{s}'s timeout was removed", .{n}),
        // Silenciar/ensurdecer: o ícone na call já mostra.
        else => {},
    }
}

/// Tira o último item mantendo a alocação (realloc para baixo, ou a fatia).
fn shrink(list: []ev.Ban) []ev.Ban {
    if (list.len <= 1) {
        if (list.len == 1) ca.free(list);
        return &.{};
    }
    return ca.realloc(list, list.len - 1) catch list[0 .. list.len - 1];
}

// --- Reloginho de castigo ------------------------------------------------------------------

/// Espaço que o reloginho ocupa ao lado do nome (0 = sem castigo).
pub const relogio_w: f32 = 20;

/// Desenha o reloginho centrado em (cx, cy), com a dica de até quando, e pede
/// um quadro na hora em que o castigo acaba (para sumir sozinho).
pub fn relogio(ctx: *d.Ctx, dl: *c.ImDrawList, cx: f32, cy: f32, until_ms: i64, alpha: f32) void {
    anim.at(until_ms + 50);
    const col = ctx.col(.danger).alpha(alpha);
    c.ImDrawList_AddCircleEx(dl, d.v(cx, cy), 6, col.u(), 0, 1.6, 0);
    d.line(dl, cx, cy, cx, cy - 3.6, col, 1.6);
    d.line(dl, cx, cy, cx + 2.8, cy + 1.2, col, 1.6);
    const hr: d.Rect = .{ .x = cx - 9, .y = cy - 9, .w = 18, .h = 18 };
    qa.mark(hr, "timeout-badge", .{});
    if (ctx.hovering(hr)) {
        var sb: [64]u8 = undefined;
        var tb: [96]u8 = undefined;
        const t = i18n.fmt(&tb, "De castigo · {s}", "Timed out · {s}", .{w.stamp(&sb, @divTrunc(until_ms, 1000), @divTrunc(ctx.now_ms, 1000))});
        d.tip(ctx, hr, t, true);
    }
}
