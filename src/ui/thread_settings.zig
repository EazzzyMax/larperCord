//! Editar uma thread: as entradas do menu dela (editar, arquivar, trancar), o
//! título clicável no cabeçalho e o popup "Editar thread" (nome, tags de um
//! post e quando arquivar sozinha). Cada clique é um pedido só, e o que a
//! pessoa não pode fazer nem aparece (as regras ficam em core/thread_edit.zig).
//! Nada aqui roda com o popup fechado.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const icons = @import("icons.zig");
const i18n = @import("i18n.zig");
const popup = @import("popup.zig");
const inbox = @import("inbox.zig");
const forum = @import("forum.zig");
const sigil = @import("comp_chat.zig").sigil;
const types = @import("../core/types.zig");
const te = @import("../core/thread_edit.zig");
const Id = types.Id;

/// O que dá para fazer nesta thread (nada, se não for uma).
pub fn rightsOf(ctx: *const d.Ctx, ch: *const types.Channel) te.Rights {
    const t = ch.thread orelse return .{};
    if (ch.guild == 0) return .{};
    return te.rights(t, ctx.store.channelPermissions(ch), ctx.store.me, parentTags(ctx, ch).len > 0);
}

/// Tags que o fórum pai oferece (vazio fora de fórum).
fn parentTags(ctx: *const d.Ctx, ch: *const types.Channel) []const types.ForumTag {
    const pcs = ctx.store.channel(ch.parent orelse return &.{}) orelse return &.{};
    return if (pcs.info.kind == .forum) pcs.info.tags else &.{};
}

// --- Menu da thread ------------------------------------------------------------

pub const Entry = struct { label: []const u8, en: []const u8, id: u8 };

pub const Entries = struct {
    items: [3]Entry = undefined,
    n: usize = 0,

    pub fn slice(e: *const Entries) []const Entry {
        return e.items[0..e.n];
    }
    fn add(e: *Entries, it: Entry) void {
        e.items[e.n] = it;
        e.n += 1;
    }
};

/// O que entra no menu de contexto da thread (o `label` é a marca do QA).
pub fn menuEntries(ctx: *const d.Ctx, ch: *const types.Channel) Entries {
    var out: Entries = .{};
    const t = ch.thread orelse return out;
    const r = rightsOf(ctx, ch);
    if (r.edit()) out.add(.{ .label = "Editar thread…", .en = "Edit Thread…", .id = 35 });
    if (r.unarchive) {
        out.add(.{ .label = "Desarquivar thread", .en = "Unarchive Thread", .id = 36 });
    } else if (r.archive) out.add(.{ .label = "Arquivar thread", .en = "Archive Thread", .id = 36 });
    if (r.lock) out.add(if (t.locked)
        .{ .label = "Destrancar thread", .en = "Unlock Thread", .id = 37 }
    else
        .{ .label = "Trancar thread", .en = "Lock Thread", .id = 37 });
    return out;
}

/// Clicou numa das entradas (o menu já fechou). Confere de novo: a permissão
/// pode ter mudado com o menu aberto.
pub fn choose(ctx: *d.Ctx, id: Id, item: u8) void {
    const cs = ctx.store.channel(id) orelse return;
    const t = cs.info.thread orelse return;
    const r = rightsOf(ctx, &cs.info);
    switch (item) {
        35 => if (r.edit()) open(ctx, id),
        36 => if (r.unarchive) {
            ctx.act(.{ .edit_thread = .{ .thread = id, .archived = false } });
        } else if (r.archive) ctx.act(.{ .edit_thread = .{ .thread = id, .archived = true } }),
        37 => if (r.lock) ctx.act(.{ .edit_thread = .{ .thread = id, .locked = !t.locked } }),
        else => {},
    }
}

/// Título de uma thread no cabeçalho: clicar abre o menu dela (com editar,
/// arquivar e trancar). Fora de thread não faz nada.
pub fn headerTitle(ctx: *d.Ctx, dl: *c.ImDrawList, ch: *const types.Channel, r: d.Rect) void {
    if (ch.thread == null or ch.guild == 0) return;
    const hb = d.hit(ctx, @truncate((ch.id *% 0x9E3779B97F4A7C15) ^ 0x7E1), r);
    qa.mark(r, "header-thread", .{});
    if (hb.clicked or hb.right) ctx.popup(.{ .menu = .{ .kind = .channel, .id = ch.id, .x = r.x, .y = r.bottom() + 4 } });
    if (hb.hovered) d.line(dl, r.x, r.bottom() - 1, r.right(), r.bottom() - 1, ctx.col(.muted).alpha(0.6), 1);
    d.tip(ctx, r, i18n.tr("Opções da thread", "Thread options"), hb.hovered);
}

// --- Popup "Editar thread" -----------------------------------------------------

/// 100 caracteres de até 4 bytes, e o zero do fim.
var name_buf: [401]u8 = @splat(0);
var tags: te.Tags = .{};
var duration: u16 = 0;
var for_thread: Id = 0;

pub fn open(ctx: *d.Ctx, id: Id) void {
    const cs = ctx.store.channel(id) orelse return;
    const t = cs.info.thread orelse return;
    @memset(&name_buf, 0);
    const n = d.utf8Prefix(cs.info.name, name_buf.len - 1);
    @memcpy(name_buf[0..n.len], n);
    tags = te.Tags.from(t.tags);
    duration = t.auto_archive;
    for_thread = id;
    ctx.st.popup = .{ .edit_thread = .{ .thread = id } };
}

const pad: f32 = 18;
const chip_h: f32 = 25;
const chip_row: f32 = 31;
/// Onde o conteúdo começa (embaixo do título e do nome da thread).
const head_h: f32 = 76;
/// O topo dos botões, contado de baixo (34 deles e 16 de margem).
const foot_btn: f32 = 50;
/// O rodapé inteiro: os botões e um respiro entre eles e a última seção.
const foot_h: f32 = foot_btn + 6;

fn chipWidth(fam: *d.Family, tag: types.ForumTag) f32 {
    return d.width(fam.get(.medium), 12.5, tag.name) + (if (tag.emoji.len > 0) @as(f32, 18) else 0) + 18;
}

/// Quantas linhas as tags ocupam numa largura (a mesma conta do desenho).
fn tagRows(fam: *d.Family, list: []const types.ForumTag, width: f32) usize {
    if (list.len == 0) return 0;
    var rows: usize = 1;
    var x: f32 = 0;
    for (list) |tag| {
        const tw = chipWidth(fam, tag);
        if (x > 0 and x + tw > width) {
            rows += 1;
            x = 0;
        }
        x += tw + 6;
    }
    return rows;
}

fn label(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: f32, text: []const u8) void {
    d.text(dl, ctx.ui.get(.semibold), 12.5, x, y, ctx.col(.muted), text);
}

pub fn dialog(ctx: *d.Ctx, id: Id) void {
    const cs = ctx.store.channel(id) orelse return popup.close(ctx);
    const t = cs.info.thread orelse return popup.close(ctx);
    const rights = rightsOf(ctx, &cs.info);
    // Perdeu a permissão com o popup aberto (ou a thread é outra): fecha.
    if (!rights.edit() or for_thread != id) return popup.close(ctx);
    const fam = ctx.ui;
    const offered: []const types.ForumTag = if (rights.tags) parentTags(ctx, &cs.info) else &.{};
    const wd: f32 = @min(500, ctx.win.w - 24);
    const inner = wd - 2 * pad;
    const rows = tagRows(fam, offered, inner);
    // O título e a linha de baixo dele (o conteúdo começa em `head_h`), as seções e o
    // rodapé com Salvar e Cancelar (`foot_h`, contado de baixo) logo depois delas.
    var h: f32 = head_h + foot_h;
    if (rights.rename) h += 20 + 36 + 14 + 20 + 30 + 14;
    if (rows > 0) h += 20 + @as(f32, @floatFromInt(rows)) * chip_row + 8;
    if (t.archived) h += 24;
    const r = forum.dialogRect(ctx, wd, h);
    const dl = popup.beginWindow("##edit-thread", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    icons.thread(dl, r.x + 26, r.y + 27, ctx.col(.text).u());
    d.text(dl, fam.get(.bold), 17, r.x + 44, r.y + 16, ctx.col(.text), i18n.tr("Editar thread", "Edit Thread"));
    var pb: [160]u8 = undefined;
    const sub = if (cs.info.parent) |p| (if (ctx.store.channel(p)) |pcs| i18n.fmt(&pb, "{s} em {s}{s}", "{s} in {s}{s}", .{ d.utf8Prefix(cs.info.name, 60), sigil(&pcs.info), pcs.info.name }) else cs.info.name) else cs.info.name;
    _ = d.textClipped(dl, fam.get(.regular), 13, r.x + pad, r.y + 46, ctx.col(.muted), sub, inner);
    var y = r.y + head_h;

    // Nome.
    var enter = false;
    if (rights.rename) {
        label(ctx, dl, r.x + pad, y, i18n.tr("Nome", "Name"));
        y += 20;
        const ir: d.Rect = .{ .x = r.x + pad, .y = y, .w = inner, .h = 36 };
        qa.mark(ir, "thread-edit-name", .{});
        if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
        enter = forum.textInput(ctx, dl, ir, "##thread-edit-name", i18n.trZ("Nome da thread", "Thread name").ptr, &name_buf, c.ImGuiInputTextFlags_EnterReturnsTrue);
        y += 36 + 14;
    }

    // Tags do post: até 5; as moderadas só para quem gerencia threads.
    if (rows > 0) {
        var lb: [64]u8 = undefined;
        label(ctx, dl, r.x + pad, y, i18n.fmt(&lb, "Tags ({d}/{d})", "Tags ({d}/{d})", .{ tags.n, te.max_tags }));
        y += 20;
        var x = r.x + pad;
        for (offered, 0..) |tag, i| {
            const tw = chipWidth(fam, tag);
            if (x > r.x + pad and x + tw > r.x + pad + inner) {
                x = r.x + pad;
                y += chip_row;
            }
            const tr: d.Rect = .{ .x = x, .y = y, .w = tw, .h = chip_h };
            const on = tags.has(tag.id);
            const allowed = !tag.moderated or rights.moderated_tags;
            const can_click = allowed and (on or tags.n < te.max_tags);
            const hb = d.hit(ctx, 100 + i, tr);
            qa.mark(tr, "thread-edit-tag:{d}", .{i});
            if (hb.clicked and can_click) _ = tags.toggle(tag.id);
            const radius = if (ctx.th.radius < 2) @as(f32, 0) else tr.h / 2;
            const fade: f32 = if (can_click) 1 else 0.45;
            if (on) d.rect(dl, tr, ctx.col(.accent).alpha(fade), radius) else d.rect(dl, tr, (if (hb.hovered and can_click) ctx.col(.hover) else ctx.col(.selected)).alpha(fade), radius);
            var tx = tr.x + 9;
            if (tag.emoji.len > 0) {
                d.text(dl, fam.get(.regular), 12.5, tx, d.centerY(tr, 12.5), d.Rgba.white.alpha(fade), tag.emoji);
                tx += 18;
            }
            const tc = if (on) ctx.col(.accent_text) else ctx.col(.text).mix(ctx.col(.muted), 0.2);
            d.text(dl, fam.get(.medium), 12.5, tx, d.centerY(tr, 12.5), tc.alpha(fade), tag.name);
            if (!allowed) d.tip(ctx, tr, i18n.tr("Só quem gerencia threads muda esta tag", "Only members who can manage threads can change this tag"), hb.hovered);
            x += tw + 6;
        }
        y += chip_row + 8;
    }

    // Arquivar sozinha depois de quanto tempo parada.
    if (rights.rename) {
        label(ctx, dl, r.x + pad, y, i18n.tr("Arquivar após inatividade", "Archive after inactivity"));
        y += 20;
        const names = [_][]const u8{ i18n.tr("1 hora", "1 hour"), i18n.tr("24 horas", "24 hours"), i18n.tr("3 dias", "3 days"), i18n.tr("1 semana", "1 week") };
        const gap: f32 = 6;
        const bw = (inner - gap * 3) / 4;
        for (te.durations, names, 0..) |mins, name, i| {
            const br: d.Rect = .{ .x = r.x + pad + @as(f32, @floatFromInt(i)) * (bw + gap), .y = y, .w = bw, .h = 30 };
            const hb = d.hit(ctx, 130 + i, br);
            qa.mark(br, "thread-edit-dur:{d}", .{mins});
            if (hb.clicked) duration = mins;
            const on = duration == mins;
            const radius = @max(ctx.th.radius, 2);
            if (on) d.rect(dl, br, ctx.col(.selected), radius) else if (hb.hovered) d.rect(dl, br, ctx.col(.hover), radius);
            d.border(dl, br, if (on) ctx.col(.accent).alpha(0.7) else ctx.col(.border), radius, 1);
            const font = fam.get(if (on) .semibold else .medium);
            _ = d.textClipped(dl, font, 13, br.x + @max((bw - d.width(font, 13, name)) / 2, 6), d.centerY(br, 13), if (on) ctx.col(.text) else ctx.col(.muted), name, bw - 12);
        }
        y += 30 + 14;
    }

    if (t.archived) {
        _ = d.textClipped(dl, fam.get(.regular), 12.5, r.x + pad, y, ctx.col(.faint), i18n.tr("Está arquivada: salvar também a desarquiva.", "It's archived: saving also unarchives it."), inner);
        y += 24;
    }

    // Salvar só com mudança e nome válido.
    const name = std.mem.trim(u8, std.mem.sliceTo(&name_buf, 0), " \t\r\n");
    const name_ok = !rights.rename or te.nameOk(name);
    const e = te.fromForm(id, cs.info.name, t, if (rights.rename) name else cs.info.name, if (offered.len > 0) tags else null, if (rights.rename) duration else 0);
    const ok = name_ok and !e.empty();
    const lbl = i18n.tr("Salvar", "Save");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - pad - bw, .y = r.bottom() - foot_btn, .w = bw, .h = 34 };
    qa.mark(br, "thread-edit-save", .{});
    const clicked = forum.primary(ctx, dl, fam, 140, br, lbl, ok);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "thread-edit-cancel", .{});
    if (inbox.button(ctx, dl, 141, cr, cancel, false)) return popup.close(ctx);
    if (!name_ok) d.text(dl, fam.get(.regular), 12.5, r.x + pad, d.centerY(br, 12.5), ctx.col(.faint), if (name.len == 0) i18n.tr("Falta o nome.", "A name is required.") else i18n.tr("Até 100 caracteres.", "Up to 100 characters."));
    if ((clicked or (enter and ok)) and ok) {
        var out = e;
        if (e.name) |n| out.name = ctx.st.gpa.dupe(u8, n) catch return;
        ctx.act(.{ .edit_thread = out });
        popup.close(ctx);
    }
}
