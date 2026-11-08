//! Menu rápido de dispositivos de voz, como no Discord: botão direito (ou a
//! setinha que aparece ao passar o mouse) no microfone ou no fone abre a lista
//! de entradas ou de saídas, o volume e o atalho para Configurações → Voz.
//! Trocar vale na hora e fica gravado, igual à página de voz: quem reabre o
//! áudio, mesmo no meio de uma call, é net/voz_audio.zig, que vê o nome novo
//! em `Settings`.
//!
//! Aqui também ficam os botões de mudo e ensurdecer com a setinha, os mesmos no
//! painel do usuário e na barra de status (o zen não tem painel).
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const icons = @import("icons.zig");
const i18n = @import("i18n.zig");
const state = @import("state.zig");
const S = @import("settings_state.zig");
const voz_audio = @import("../net/voz_audio.zig");
const popup = @import("popup.zig");
const pick = @import("device_pick.zig");

pub const Which = state.DeviceMenu;

/// Ids de `d.hit` do menu (longe dos dos outros popups).
const base_id: usize = 0x6D000;

// Medidas do cartão.
const menu_w: f32 = 268;
const pad: f32 = 6;
const head_h: f32 = 26;
const row_h: f32 = 30;
const vol_h: f32 = 50;
const sep_h: f32 = 9;
const link_h: f32 = 32;

/// Cópia da lista que a thread de áudio leu por último (a página de voz tem a dela).
var mic_list: voz_audio.DeviceList = .{};
var out_list: voz_audio.DeviceList = .{};
var list_gen: u32 = 0;
/// O volume estava sendo arrastado no quadro anterior: grava ao soltar.
var held_prev: [2]bool = .{ false, false };
var qa_fake = false;
/// Até quando esperar (acordando a interface) pela lista pedida ao abrir.
var wait_until: i64 = 0;

/// Abre o menu acima de `anchor` (o botão que foi clicado).
pub fn open(ctx: *d.Ctx, which: Which, anchor: d.Rect) void {
    voz_audio.requestList();
    wait_until = ctx.now_ms + 1500;
    ctx.popup(.{ .devices = .{ .which = which, .x = anchor.x, .y = anchor.y } });
}

fn refresh() void {
    if (qa_fake) return;
    const gen = voz_audio.sh.list_gen.load(.acquire);
    if (gen == list_gen) return;
    list_gen = gen;
    voz_audio.copyDevices(&mic_list, &out_list);
}

const visibleRows = pick.visibleRows;
const gainAt = pick.gainAt;

fn missing(list: *const voz_audio.DeviceList, saved: []const u8) bool {
    return pick.missing(list, saved);
}

const Side = enum(u1) { mic, out };

/// Linhas que a lista ocupa no cartão (com o "+N" se não couber).
fn linesOf(side: Side, s: *const S.Settings, cap: usize) f32 {
    const list = if (side == .mic) &mic_list else &out_list;
    const saved = if (side == .mic) s.voice_mic.slice() else s.voice_out.slice();
    const vis = visibleRows(1 + @as(usize, list.n) + @intFromBool(missing(list, saved)), cap);
    return @floatFromInt(vis.shown + @intFromBool(vis.more > 0));
}

pub fn draw(ctx: *d.Ctx, which: Which, x: f32, y: f32) void {
    refresh();
    // A lista chega pela thread de áudio, sem evento na janela: acorda só até
    // ela chegar (no máximo 1,5 s), parado não custa nada.
    if (!qa_fake and ctx.now_ms < wait_until and
        (voz_audio.sh.list_req.load(.acquire) or voz_audio.sh.list_gen.load(.acquire) != list_gen)) anim.every(50);
    const s = &ctx.st.settings;
    const n_sec: usize = if (which == .both) 2 else 1;
    const fsec: f32 = @floatFromInt(n_sec);
    const fixed = pad * 2 + fsec * (head_h + vol_h + sep_h) + link_h;
    const max_h = @max(ctx.win.h - 16, 200);
    const cap: usize = @intFromFloat(@max(@floor((max_h - fixed) / row_h / fsec), 2));
    var h = fixed;
    if (which != .out) h += linesOf(.mic, s, cap) * row_h;
    if (which != .mic) h += linesOf(.out, s, cap) * row_h;
    const r = popup.fit(ctx, x, y - h - 6, menu_w, h);
    const dl = popup.beginWindow("##devices", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    qa.mark(r, "device-menu", .{});
    const radius = @max(ctx.th.radius, 4);
    d.shadow(dl, r, radius, 14, ctx.col(.shadow));
    d.rect(dl, r, ctx.col(.overlay), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);

    var yy = r.y + pad;
    if (which != .out) if (section(ctx, dl, r, &yy, .mic, cap)) return;
    if (which != .mic) if (section(ctx, dl, r, &yy, .out, cap)) return;

    // Atalho para a página inteira.
    const lr: d.Rect = .{ .x = r.x + pad, .y = yy, .w = r.w - pad * 2, .h = link_h - 2 };
    const lh = d.hit(ctx, base_id + 900, lr);
    qa.mark(lr, "device-settings", .{});
    const rr = @max(ctx.th.radius - 2, 2);
    if (lh.hovered) d.rect(dl, lr, ctx.col(.accent), rr);
    const ink = if (lh.hovered) ctx.col(.accent_text) else ctx.col(.text).mix(ctx.col(.muted), 0.15);
    _ = d.textClipped(dl, ctx.ui.get(.medium), 14, lr.x + 10, d.centerY(lr, 14), ink, i18n.tr("Configurações de voz", "Voice Settings"), lr.w - 44);
    icons.gear(dl, lr.right() - 18, lr.y + lr.h / 2, ink.u());
    if (lh.clicked) {
        ctx.st.settings.page = .voz;
        ctx.act(.open_settings);
        popup.close(ctx);
    }
}

/// Uma lista (entrada ou saída) e o volume dela. true = escolheu e fechou.
fn section(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, y: *f32, side: Side, cap: usize) bool {
    const s = &ctx.st.settings;
    const list = if (side == .mic) &mic_list else &out_list;
    const value = if (side == .mic) &s.voice_mic else &s.voice_out;
    const tag = if (side == .mic) "mic" else "out";
    const ids = base_id + @as(usize, @intFromEnum(side)) * 0x100;
    const fam = ctx.ui;
    const rr = @max(ctx.th.radius - 2, 2);

    d.text(dl, fam.get(.semibold), 11.5, r.x + 16, y.* + 8, ctx.col(.muted), if (side == .mic) i18n.tr("DISPOSITIVO DE ENTRADA", "INPUT DEVICE") else i18n.tr("DISPOSITIVO DE SAÍDA", "OUTPUT DEVICE"));
    y.* += head_h;

    const saved = value.slice();
    const lost = missing(list, saved);
    const total = 1 + @as(usize, list.n) + @intFromBool(lost);
    const vis = visibleRows(total, cap);
    for (0..vis.shown) |i| {
        // 0 = padrão do sistema, depois a lista, e por último o escolhido que sumiu.
        const is_lost = lost and i == total - 1;
        const name = if (i == 0) i18n.tr("Padrão do sistema", "System default") else if (is_lost) saved else list.slice(i - 1);
        const sel = if (i == 0) saved.len == 0 else is_lost or std.mem.eql(u8, saved, name);
        const ir: d.Rect = .{ .x = r.x + pad, .y = y.*, .w = r.w - pad * 2, .h = row_h - 2 };
        const hb = d.hit(ctx, ids + i, ir);
        qa.mark(ir, "device-opt:{s}:{d}", .{ tag, i });
        if (sel) qa.mark(ir, "device-sel:{s}:{d}", .{ tag, i });
        if (hb.hovered) d.rect(dl, ir, ctx.col(.accent), rr);
        const tc = if (hb.hovered) ctx.col(.accent_text) else if (sel) ctx.col(.text) else ctx.col(.text).mix(ctx.col(.muted), 0.25);
        const tw = d.textClipped(dl, fam.get(if (sel) .semibold else .regular), 14, ir.x + 10, d.centerY(ir, 14), tc, name, ir.w - 40);
        if (is_lost) {
            const lbl = i18n.tr(" · não encontrado", " · not found");
            _ = d.textClipped(dl, fam.get(.regular), 12, ir.x + 10 + tw, d.centerY(ir, 12), if (hb.hovered) ctx.col(.accent_text) else ctx.col(.idle), lbl, @max(ir.w - 40 - tw, 0));
        }
        if (sel) {
            // Visto desenhado (não depende da fonte ter o glifo).
            const cx = ir.right() - 16;
            const cy = ir.y + ir.h / 2;
            const ck = if (hb.hovered) ctx.col(.accent_text) else ctx.col(.accent);
            d.line(dl, cx - 5, cy, cx - 1.5, cy + 3.5, ck, 2);
            d.line(dl, cx - 1.5, cy + 3.5, cx + 5, cy - 4, ck, 2);
        }
        if (hb.clicked) {
            // O que sumiu já é o escolhido: o nome fica guardado para quando ele voltar.
            if (is_lost) {
                popup.close(ctx);
                return true;
            }
            if (i == 0) value.* = .{} else value.set(name);
            ctx.act(.save_settings);
            popup.close(ctx);
            return true;
        }
        y.* += row_h;
    }
    if (vis.more > 0) {
        const mr: d.Rect = .{ .x = r.x + pad, .y = y.*, .w = r.w - pad * 2, .h = row_h - 2 };
        const mh = d.hit(ctx, ids + 0xF0, mr);
        qa.mark(mr, "device-more:{s}", .{tag});
        if (mh.hovered) d.rect(dl, mr, ctx.col(.hover), rr);
        var b: [64]u8 = undefined;
        const t = i18n.fmt(&b, "+{d} em Configurações → Voz", "+{d} in Settings → Voice", .{vis.more});
        _ = d.textClipped(dl, fam.get(.medium), 13, mr.x + 10, d.centerY(mr, 13), ctx.col(.muted), t, mr.w - 20);
        if (mh.clicked) {
            s.page = .voz;
            ctx.act(.open_settings);
            popup.close(ctx);
            return true;
        }
        y.* += row_h;
    }

    // Volume: o mesmo número da página de voz (100% = sem mudança).
    const gain = if (side == .mic) &s.voice_in_gain else &s.voice_out_gain;
    const vx = r.x + 16;
    const vw = r.w - 32;
    d.text(dl, fam.get(.medium), 13, vx, y.* + 4, ctx.col(.text).mix(ctx.col(.muted), 0.15), if (side == .mic) i18n.tr("Volume de entrada", "Input volume") else i18n.tr("Volume de saída", "Output volume"));
    var pb: [8]u8 = undefined;
    const pct = std.fmt.bufPrint(&pb, "{d}%", .{gain.*}) catch "";
    d.text(dl, fam.get(.semibold), 12, vx + vw - d.width(fam.get(.semibold), 12, pct), y.* + 5, ctx.col(.muted), pct);
    const tr: d.Rect = .{ .x = vx + 4, .y = y.* + 30, .w = vw - 8, .h = 6 };
    const hr: d.Rect = .{ .x = tr.x - 6, .y = tr.y - 9, .w = tr.w + 12, .h = 24 };
    const hb = d.hit(ctx, ids + 0xF8, hr);
    qa.mark(hr, "device-vol:{s}", .{tag});
    const si = @intFromEnum(side);
    if (hb.held) gain.* = gainAt(ctx.mouse.x, tr.x, tr.w);
    // Grava ao soltar, não a cada quadro do arrasto.
    if (held_prev[si] and !hb.held) ctx.act(.save_settings);
    held_prev[si] = hb.held;
    const k = @as(f32, @floatFromInt(@min(gain.*, 200))) / 200;
    d.rect(dl, tr, ctx.col(.elevated).mix(ctx.col(.text), 0.1), 3);
    d.rect(dl, .{ .x = tr.x, .y = tr.y, .w = tr.w * k, .h = tr.h }, if (gain.* == 0) ctx.col(.faint) else ctx.col(.accent), 3);
    d.line(dl, tr.x + tr.w / 2, tr.y - 2, tr.x + tr.w / 2, tr.bottom() + 2, ctx.col(.faint).alpha(0.7), 1);
    const kx = tr.x + tr.w * k;
    d.rect(dl, .{ .x = kx - 5, .y = tr.y - 5, .w = 10, .h = 16 }, d.Rgba.white, 3);
    d.border(dl, .{ .x = kx - 5, .y = tr.y - 5, .w = 10, .h = 16 }, ctx.col(.border), 3, 1);
    y.* += vol_h;
    d.line(dl, r.x + 10, y.* + 4, r.right() - 10, y.* + 4, ctx.col(.border), 1);
    y.* += sep_h;
    return false;
}

// --- Botões de mudo e ensurdecer --------------------------------------------

pub const Kind = enum { mic, deaf };
/// `icon`: ícone desenhado; `tty`: rótulo em texto ([mic] [fone]).
pub const Look = enum { icon, tty };

/// Largura da setinha que abre o menu.
pub const chev_w: f32 = 11;

pub fn ttyLabel(kind: Kind) []const u8 {
    return switch (kind) {
        .mic => i18n.tr("[mic]", "[mic]"),
        .deaf => i18n.tr("[fone]", "[audio]"),
    };
}

/// Largura do botão no estilo texto, já com a setinha.
pub fn ttyWidth(font: *c.ImFont, fs: f32, kind: Kind) f32 {
    return @round(d.width(font, fs, ttyLabel(kind)) + 8 + chev_w);
}

/// Mudo (`mic`) ou ensurdecer (`deaf`) em `br`: clicar alterna; o botão direito
/// ou a setinha da direita abrem o menu de dispositivos. Usa os ids `id` e
/// `id + 1000` de `d.hit`. Devolve se quem impôs foi o servidor (o cadeado).
pub fn toggle(ctx: *d.Ctx, dl: *c.ImDrawList, font: *c.ImFont, fs: f32, kind: Kind, br: d.Rect, look: Look, id: usize, tag: []const u8) bool {
    const vf = ctx.store.voiceFlags(ctx.store.me);
    const forced = ctx.st.voice != null and switch (kind) {
        .mic => vf.serverMuted(),
        .deaf => vf.deaf,
    };
    const on = switch (kind) {
        .mic => ctx.st.muted,
        .deaf => ctx.st.deafened,
    };
    const active = on or forced;
    const which: Which = if (kind == .mic) .mic else .out;
    // Duas áreas lado a lado (sem sobrepor): o botão e a setinha.
    const mr: d.Rect = .{ .x = br.x, .y = br.y, .w = br.w - chev_w, .h = br.h };
    const cr: d.Rect = .{ .x = br.right() - chev_w, .y = br.y, .w = chev_w, .h = br.h };
    const mh = d.hit(ctx, id, mr);
    const ch = d.hit(ctx, id + 1000, cr);
    qa.mark(cr, "{s}-menu", .{tag});
    const menu_open = switch (ctx.st.popup) {
        .devices => |dv| dv.which == which,
        else => false,
    };
    const hovered = mh.hovered or ch.hovered;
    if (mh.clicked) ctx.act(if (kind == .mic) .toggle_mute else .toggle_deafen);
    if (ch.clicked or mh.right or ch.right) open(ctx, which, br);

    if (forced) {
        d.tip(ctx, mr, if (kind == .mic) i18n.tr("Mudo pelo servidor: ninguém te ouve", "Server muted: nobody can hear you") else i18n.tr("Surdo pelo servidor", "Server deafened"), mh.hovered);
    } else d.tip(ctx, mr, switch (kind) {
        .mic => if (on) i18n.tr3("Desmutar  (Ctrl+Shift+M)", "Unmute  (Ctrl+Shift+M)", "ミュート解除  (Ctrl+Shift+M)") else i18n.tr3("Mutar microfone  (Ctrl+Shift+M)", "Mute  (Ctrl+Shift+M)", "マイクをミュート  (Ctrl+Shift+M)"),
        .deaf => if (on) i18n.tr3("Voltar a ouvir  (Ctrl+Shift+D)", "Undeafen  (Ctrl+Shift+D)", "スピーカーを元に戻す  (Ctrl+Shift+D)") else i18n.tr3("Ensurdecer  (Ctrl+Shift+D)", "Deafen  (Ctrl+Shift+D)", "スピーカーをミュート  (Ctrl+Shift+D)"),
    }, mh.hovered);
    d.tip(ctx, cr, if (kind == .mic) i18n.tr("Microfone e volume de entrada", "Input device and volume") else i18n.tr("Saída e volume", "Output device and volume"), ch.hovered);

    const k = anim.to(anim.id("vbtn", id), if (hovered or menu_open) 1 else 0, 24);
    const ink = if (active) ctx.col(.danger) else ctx.col(.muted).mix(ctx.col(.text), k);
    const cy = br.y + br.h / 2;
    switch (look) {
        .tty => {
            if (hovered or menu_open) d.rect(dl, br, ctx.col(.hover), 0);
            const label = ttyLabel(kind);
            const lw = d.width(font, fs, label);
            const lx = mr.x + 4;
            d.text(dl, font, fs, lx, d.centerY(br, fs), ink, label);
            // Ligado: risco desenhado por cima (o tachado combinante nem toda fonte tem).
            if (active) d.line(dl, lx - 1, cy + 0.5, lx + lw + 1, cy + 0.5, ctx.col(.danger), 1.6);
        },
        .icon => {
            d.rect(dl, br, ctx.col(.hover).alpha(k * 1.5), ctx.th.radius);
            // O ícone abre espaço para a setinha quando ela aparece.
            const cx = br.x + (br.w - chev_w * k * 0.6) / 2;
            switch (kind) {
                .mic => icons.mic(dl, cx, cy, ink.u()),
                .deaf => icons.headset(dl, cx, cy, ink.u()),
            }
            if (active) d.line(dl, cx - 9, cy - 9, cx + 9, cy + 9, ctx.col(.danger), 2.2);
            // Quem impôs foi o servidor: o clique aqui não resolve.
            if (forced) {
                d.circle(dl, cx + 8, cy + 9, 7, ctx.col(.sidebar));
                icons.lock(dl, cx + 8, cy + 8, ctx.col(.danger).u());
            }
        },
    }
    if (k > 0.02) {
        const cc = (if (ch.hovered or menu_open) ctx.col(.text) else ctx.col(.muted)).alpha(k);
        icons.chevron(dl, cr.x + cr.w / 2 - 1, cy + (if (look == .icon) @as(f32, 3) else 0), cc.u(), 1);
    }
    return forced;
}

// --- QA -----------------------------------------------------------------------

/// Lista de mentira para o QA (o driver mudo só tem um dispositivo). 0 volta à de verdade.
pub fn qaFake(n: u8) void {
    if (!qa.compiled) return;
    if (n == 0) {
        qa_fake = false;
        voz_audio.copyDevices(&mic_list, &out_list);
        return;
    }
    qa_fake = true;
    const m = @min(n, voz_audio.max_devices);
    mic_list.n = m;
    out_list.n = m;
    for (0..m) |i| {
        var b: [32]u8 = undefined;
        mic_list.names[i].set(std.fmt.bufPrint(&b, "Microfone de teste {d}", .{i + 1}) catch "");
        out_list.names[i].set(std.fmt.bufPrint(&b, "Saída de teste {d}", .{i + 1}) catch "");
    }
}
