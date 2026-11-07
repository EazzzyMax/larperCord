//! O painel da busca de mensagens (ver search.zig): fica à direita, com a conversa ao lado,
//! como no Discord. Aqui só se desenha e se recebem os cliques; o estado e as consultas são
//! de search.zig. Funciona igual em qualquer tema: tudo sai das cores do tema.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const anim = @import("anim.zig");
const icons = @import("icons.zig");
const i18n = @import("i18n.zig");
const w = @import("widgets.zig");
const sq = @import("../core/search_query.zig");
const search = @import("search.zig");
const sugg = @import("search_sugg.zig");

const pad: f32 = 14;
const input_h: f32 = 40;
const page_size: u32 = 25;
const max_offset: u32 = 9975;

// Cartão de um resultado.
const avatar_size: f32 = 34;
const line_h: f32 = 20;
const text_fs: f32 = 14;
const group_h: f32 = 28;
const card_gap: f32 = 6;
const max_lines: u8 = 3;

/// Rolagem da lista, em pontos.
pub var scroll_y: f32 = 0;
/// O mouse está sobre as sugestões: o que fica embaixo delas não recebe clique.
var blocked = false;

const no_hit: d.Hit = .{ .hovered = false, .clicked = false, .held = false, .middle = false, .right = false, .ctrl = false };

fn hit(ctx: *d.Ctx, id: usize, r: d.Rect) d.Hit {
    return if (blocked) no_hit else d.hit(ctx, id, r);
}

pub fn draw(ctx: *d.Ctx) void {
    if (!search.open) return;
    // As configurações cobrem a janela inteira: a busca dá lugar.
    if (ctx.st.settings.open) return search.close();
    search.frame(ctx);
    if (!search.open) return;
    const k = anim.to(anim.id("msg-search", search.openingKey()), 1, 22);
    const box = search.panel;
    c.ImGui_SetNextWindowPos(d.v(box.x, box.y), 0);
    c.ImGui_SetNextWindowSize(d.v(box.w, box.h), 0);
    if (search.takeAppearing()) c.ImGui_SetNextWindowFocus();
    _ = c.ImGui_Begin("##search", null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoBackground |
        c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoScrollWithMouse);
    defer c.ImGui_End();
    const dl = c.ImGui_GetWindowDrawList();
    const saved_dl = ctx.dl;
    ctx.dl = dl;
    defer ctx.dl = saved_dl;

    d.rect(dl, box, ctx.col(.overlay).mix(ctx.col(.elevated), 0.35), 0);
    d.line(dl, box.x + 0.5, box.y, box.x + 0.5, box.bottom(), ctx.col(.border), 1);
    // Entra deslizando um pouco; a conversa já está no lugar.
    const b: d.Rect = .{ .x = box.x + (1 - k) * 18, .y = box.y, .w = box.w, .h = box.h };
    const anchor: d.Rect = .{ .x = b.x + pad, .y = b.y + 12, .w = b.w - pad * 2, .h = input_h };

    const popover = sugg.rect(anchor);
    const showing = sugg.visible(ctx, popover);
    blocked = showing and ctx.hovering(popover);

    var y = inputRow(ctx, dl, anchor);
    y = chips(ctx, dl, b, y);
    y = statusRow(ctx, dl, b, y);
    const foot = footerHeight();
    const list: d.Rect = .{ .x = b.x, .y = y, .w = b.w, .h = @max(0, b.bottom() - foot - y) };
    body(ctx, dl, list);
    footer(ctx, dl, b, foot);
    blocked = false;
    if (showing) sugg.draw(ctx, dl, popover);
    search.keys(ctx);
}

// --- Caixa de texto ---------------------------------------------------------------------

fn inputRow(ctx: *d.Ctx, dl: *c.ImDrawList, ir: d.Rect) f32 {
    const ring = anim.to(anim.id("msg-search-ring", 0), if (search.input_active) 1 else 0, 18);
    const radius = @max(ctx.th.radius + 4, 4);
    d.rect(dl, ir, ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
    d.border(dl, ir, ctx.col(.border).mix(ctx.col(.accent), ring), radius, 1 + ring * 0.5);
    icons.search(dl, ir.x + 20, ir.y + input_h / 2, ctx.col(.muted).mix(ctx.col(.accent), ring).u());
    qa.mark(ir, "search-input", .{});
    search.inputField(ctx, ir.x + 38, ir.y + 6, ir.w - 38 - 36);
    if (search.text().len > 0) {
        const xr: d.Rect = .{ .x = ir.right() - 34, .y = ir.y + 6, .w = 28, .h = 28 };
        const xh = hit(ctx, 0x5d00, xr);
        qa.mark(xr, "search-clear", .{});
        if (xh.hovered) d.rect(dl, xr, ctx.col(.hover), 14);
        cross(dl, xr.x + 14, xr.y + 14, 4, if (xh.hovered) ctx.col(.text) else ctx.col(.muted));
        d.tip(ctx, xr, i18n.tr("Limpar", "Clear"), xh.hovered);
        if (xh.clicked) search.setText(ctx, "");
    }
    return ir.bottom() + 8;
}

fn cross(dl: *c.ImDrawList, cx: f32, cy: f32, r: f32, col: d.Rgba) void {
    d.line(dl, cx - r, cy - r, cx + r, cy + r, col, 1.6);
    d.line(dl, cx - r, cy + r, cx + r, cy - r, col, 1.6);
}

// --- Filtros como etiquetas -------------------------------------------------------------

fn filterLabel(f: sq.Filter) []const u8 {
    return switch (f) {
        .from => i18n.tr("de", "from"),
        .mentions => i18n.tr("menciona", "mentions"),
        .in => i18n.tr("em", "in"),
        .has => i18n.tr("tem", "has"),
        .before => i18n.tr("antes de", "before"),
        .after => i18n.tr("depois de", "after"),
        .during => i18n.tr("no dia", "during"),
        .pinned => i18n.tr("fixada", "pinned"),
        .none => "",
    };
}

/// Cada filtro da consulta vira uma etiqueta; clicar tira ele do texto.
fn chips(ctx: *d.Ctx, dl: *c.ImDrawList, b: d.Rect, y0: f32) f32 {
    const src = search.text();
    const font = ctx.ui.get(.regular);
    const bold = ctx.ui.get(.semibold);
    const h: f32 = 24;
    var x = b.x + pad;
    var y = y0;
    var pos: usize = 0;
    var count: usize = 0;
    var remove: ?[2]usize = null;
    while (sq.nextToken(src, &pos)) |t| {
        const f = sq.filterOf(t.key);
        if (f == .none or t.val.len == 0) continue;
        const label = filterLabel(f);
        const lw = d.width(font, 12, label);
        const vw = @min(d.width(bold, 12.5, t.val), 170);
        const cw = 10 + lw + 5 + vw + 8 + 10 + 7;
        if (count > 0 and x + cw > b.right() - pad) {
            x = b.x + pad;
            y += h + 6;
        }
        const r: d.Rect = .{ .x = x, .y = y, .w = cw, .h = h };
        const hb = hit(ctx, 0x5d10 + count, r);
        qa.mark(r, "search-chip:{d}", .{count});
        d.rect(dl, r, ctx.col(.accent).alpha(if (hb.hovered) 0.28 else 0.16), h / 2);
        d.text(dl, font, 12, x + 10, d.centerY(r, 12), ctx.col(.muted), label);
        _ = d.textClipped(dl, bold, 12.5, x + 10 + lw + 5, d.centerY(r, 12.5), ctx.col(.text), t.val, vw);
        cross(dl, r.right() - 12, r.y + h / 2, 3, if (hb.hovered) ctx.col(.text) else ctx.col(.muted));
        d.tip(ctx, r, i18n.tr("Tirar este filtro", "Remove this filter"), hb.hovered);
        if (hb.clicked) remove = .{ t.start, t.end };
        x += cw + 6;
        count += 1;
    }
    if (remove) |rm| search.removeRange(ctx, rm[0], rm[1]);
    return if (count > 0) y + h + 8 else y0;
}

// --- Linha de situação ------------------------------------------------------------------

fn statusRow(ctx: *d.Ctx, dl: *c.ImDrawList, b: d.Rect, y: f32) f32 {
    if (search.text().len == 0 and search.source == .local) {
        d.line(dl, b.x, y + 1, b.right(), y + 1, ctx.col(.border), 1);
        return y + 2;
    }
    const h: f32 = 36;
    const r: d.Rect = .{ .x = b.x + pad, .y = y, .w = b.w - pad * 2, .h = h };
    const bold = ctx.ui.get(.semibold);
    var buf: [120]u8 = undefined;
    var right_x = r.right();
    if (search.source == .server) {
        if (search.server == .done) right_x = sortControl(ctx, dl, r);
        const label: []const u8 = switch (search.server) {
            .loading, .indexing => i18n.tr("Buscando no Discord…", "Searching Discord…"),
            .done => if (search.total == 1)
                i18n.tr("1 resultado", "1 result")
            else
                i18n.fmt(&buf, "{d} resultados", "{d} results", .{search.total}),
            else => i18n.tr("Busca no Discord", "Discord search"),
        };
        _ = d.textClipped(dl, bold, 13.5, r.x, d.centerY(r, 13.5), ctx.col(.text), label, right_x - r.x - 8);
    } else {
        right_x = runButton(ctx, dl, r);
        const label = if (search.serverOnly())
            i18n.tr("Esse filtro só o Discord resolve", "Only Discord can apply this filter")
        else
            i18n.fmt(&buf, "{d} neste computador", "{d} on this computer", .{search.found});
        _ = d.textClipped(dl, ctx.ui.get(.medium), 13, r.x, d.centerY(r, 13), ctx.col(.muted), label, right_x - r.x - 8);
    }
    d.line(dl, b.x, y + h, b.right(), y + h, ctx.col(.border), 1);
    return y + h + 1;
}

/// Buscar no Discord, com a tecla ao lado. Devolve onde começa.
fn runButton(ctx: *d.Ctx, dl: *c.ImDrawList, row: d.Rect) f32 {
    const font = ctx.ui.get(.medium);
    const label = i18n.tr("Buscar no Discord", "Search Discord");
    const key = "Enter";
    const lw = d.width(font, 12.5, label);
    const kw = d.width(font, 10.5, key) + 10;
    const bw = 10 + lw + 7 + kw + 6;
    const r: d.Rect = .{ .x = row.right() - bw, .y = row.y + 6, .w = bw, .h = row.h - 12 };
    const hb = hit(ctx, 0x5d40, r);
    qa.mark(r, "search-run", .{});
    d.rect(dl, r, ctx.col(.accent).alpha(if (hb.hovered) 1 else 0.85), @max(ctx.th.radius, 4));
    d.text(dl, font, 12.5, r.x + 10, d.centerY(r, 12.5), ctx.col(.accent_text), label);
    const kr: d.Rect = .{ .x = r.x + 10 + lw + 7, .y = r.y + 4, .w = kw, .h = r.h - 8 };
    d.rect(dl, kr, d.Rgba.black.alpha(0.2), 3);
    d.text(dl, font, 10.5, kr.x + 5, d.centerY(kr, 10.5), ctx.col(.accent_text), key);
    if (hb.clicked) search.askServer(ctx);
    return r.x;
}

/// Mais recentes, mais antigas ou relevância. Devolve onde começa.
fn sortControl(ctx: *d.Ctx, dl: *c.ImDrawList, row: d.Rect) f32 {
    const Opt = struct { sort: sq.Sort, tag: []const u8, label: []const u8 };
    const opts = [_]Opt{
        .{ .sort = .newest, .tag = "newest", .label = i18n.tr("Recentes", "Newest") },
        .{ .sort = .oldest, .tag = "oldest", .label = i18n.tr("Antigas", "Oldest") },
        .{ .sort = .relevance, .tag = "relevance", .label = i18n.tr("Relevância", "Relevant") },
    };
    const font = ctx.ui.get(.medium);
    const h: f32 = 24;
    var total_w: f32 = 4;
    for (opts) |o| total_w += d.width(font, 12, o.label) + 16;
    const r: d.Rect = .{ .x = row.right() - total_w, .y = row.y + (row.h - h) / 2, .w = total_w, .h = h };
    const radius = @max(ctx.th.radius, 4);
    d.rect(dl, r, ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
    var x = r.x + 2;
    for (opts, 0..) |o, i| {
        const ow = d.width(font, 12, o.label) + 16;
        const pill: d.Rect = .{ .x = x, .y = r.y + 2, .w = ow, .h = h - 4 };
        const hb = hit(ctx, 0x5d50 + i, pill);
        qa.mark(pill, "search-sort:{s}", .{o.tag});
        const on = search.sort == o.sort;
        if (on) d.rect(dl, pill, ctx.col(.elevated).mix(ctx.col(.text), 0.08), radius - 1);
        d.text(dl, font, 12, x + 8, d.centerY(pill, 12), if (on or hb.hovered) ctx.col(.text) else ctx.col(.muted), o.label);
        if (hb.clicked and !on) search.changeSort(ctx, o.sort);
        x += ow;
    }
    return r.x;
}

// --- O corpo do painel ------------------------------------------------------------------

fn body(ctx: *d.Ctx, dl: *c.ImDrawList, list_in: d.Rect) void {
    var list = list_in;
    if (search.problem().len > 0) return message(ctx, dl, list, i18n.tr("Não deu para buscar", "Couldn't search"), search.problem());
    if (search.source == .server) switch (search.server) {
        .loading => return skeleton(ctx, dl, list),
        .indexing => {
            var buf: [160]u8 = undefined;
            const sub = if (search.indexed > 0)
                i18n.fmt(&buf, "{d} mensagens prontas até agora. A busca tenta de novo sozinha.", "{d} messages ready so far. The search retries on its own.", .{search.indexed})
            else
                i18n.tr("A busca tenta de novo sozinha, em instantes.", "The search retries on its own in a moment.");
            return message(ctx, dl, list, i18n.tr("O Discord está preparando a busca aqui", "Discord is preparing search here"), sub);
        },
        .forbidden => return message(ctx, dl, list, i18n.tr("Sem permissão para buscar aqui", "No permission to search here"), i18n.tr("O Discord não deixou esta conta buscar neste servidor ou conversa.", "Discord didn't let this account search this server or conversation.")),
        else => {},
    };
    if (search.server == .failed) list = failedBanner(ctx, dl, list);
    if (search.results.items.len == 0) return emptyState(ctx, dl, list);
    resultList(ctx, dl, list);
}

fn failedBanner(ctx: *d.Ctx, dl: *c.ImDrawList, list: d.Rect) d.Rect {
    const r: d.Rect = .{ .x = list.x + 10, .y = list.y + 8, .w = list.w - 20, .h = 52 };
    const radius = ctx.th.radius + 2;
    d.rect(dl, r, ctx.col(.danger).alpha(0.14), radius);
    d.border(dl, r, ctx.col(.danger).alpha(0.4), radius, 1);
    const font = ctx.ui.get(.regular);
    const bold = ctx.ui.get(.semibold);
    const label = i18n.tr("Tentar de novo", "Try again");
    const lw = d.width(bold, 12.5, label);
    const br: d.Rect = .{ .x = r.right() - lw - 30, .y = r.y + 12, .w = lw + 20, .h = 28 };
    const hb = hit(ctx, 0x5d62, br);
    qa.mark(br, "search-retry", .{});
    d.rect(dl, br, ctx.col(.text).alpha(if (hb.hovered) 0.16 else 0.09), @max(ctx.th.radius, 4));
    d.text(dl, bold, 12.5, br.x + 10, d.centerY(br, 12.5), ctx.col(.text), label);
    if (hb.clicked) search.askServer(ctx);
    const room = br.x - r.x - 22;
    _ = d.textClipped(dl, bold, 13, r.x + 12, r.y + 8, ctx.col(.text), i18n.tr("Sem resposta do Discord", "No answer from Discord"), room);
    _ = d.textClipped(dl, font, 12.5, r.x + 12, r.y + 28, ctx.col(.muted), i18n.tr("Mostrando o que está neste computador.", "Showing what's on this computer."), room);
    return .{ .x = list.x, .y = r.bottom() + 2, .w = list.w, .h = list.bottom() - r.bottom() - 2 };
}

/// Um título e uma explicação, no meio da lista.
fn message(ctx: *d.Ctx, dl: *c.ImDrawList, list: d.Rect, title: []const u8, sub: []const u8) void {
    const bold = ctx.ui.get(.semibold);
    const font = ctx.ui.get(.regular);
    const cx = list.x + list.w / 2;
    const cy = list.y + @min(list.h * 0.32, 150);
    const disc = 56.0;
    d.rect(dl, .{ .x = cx - disc / 2, .y = cy - disc / 2, .w = disc, .h = disc }, ctx.col(.rail).mix(ctx.col(.surface), 0.25), disc / 2);
    icons.search(dl, cx, cy, ctx.col(.muted).u());
    const tw = d.width(bold, 15, title);
    const max_w = list.w - 40;
    _ = d.textClipped(dl, bold, 15, cx - @min(tw, max_w) / 2, cy + disc / 2 + 14, ctx.col(.text), title, max_w);
    // A explicação quebra em linhas, centrada.
    var rest = sub;
    var y = cy + disc / 2 + 38;
    var lines: u8 = 0;
    while (rest.len > 0 and lines < 4) : (lines += 1) {
        const n = nextLine(font, 13, rest, max_w);
        if (n == 0) break;
        const line = std.mem.trimEnd(u8, rest[0..n], " ");
        d.text(dl, font, 13, cx - d.width(font, 13, line) / 2, y, ctx.col(.muted), line);
        rest = rest[n..];
        y += 19;
    }
}

fn skeleton(ctx: *d.Ctx, dl: *c.ImDrawList, list: d.Rect) void {
    // Cartões vazios que pulsam: o lugar dos resultados, enquanto o Discord responde.
    const t: f32 = @floatFromInt(@mod(ctx.now_ms, 6283));
    const pulse = 0.5 + 0.5 * @sin(t / 260);
    anim.at(ctx.now_ms + 33);
    const col = ctx.col(.text).alpha(0.05 + 0.05 * pulse);
    const widths = [_][3]f32{ .{ 0.9, 0.7, 0 }, .{ 0.8, 0, 0 }, .{ 0.95, 0.85, 0.4 }, .{ 0.6, 0, 0 }, .{ 0.85, 0.5, 0 }, .{ 0.75, 0, 0 } };
    var y = list.y + 12;
    const card_x = list.x + 10;
    const card_w = list.w - 20;
    const text_x = card_x + 12 + avatar_size + 10;
    const text_w = card_w - 12 - avatar_size - 10 - 12;
    for (widths) |row| {
        var lines: f32 = 0;
        for (row) |rw| {
            if (rw > 0) lines += 1;
        }
        const h = 10 + 22 + lines * line_h + 10;
        if (y + h > list.bottom()) break;
        d.rect(dl, .{ .x = card_x, .y = y, .w = card_w, .h = h }, ctx.col(.text).alpha(0.025), ctx.th.radius + 2);
        d.rect(dl, .{ .x = card_x + 12, .y = y + 10, .w = avatar_size, .h = avatar_size }, col, avatar_size / 2);
        d.rect(dl, .{ .x = text_x, .y = y + 12, .w = 110, .h = 11 }, col, 5);
        var ly = y + 34;
        for (row) |rw| {
            if (rw == 0) continue;
            d.rect(dl, .{ .x = text_x, .y = ly, .w = text_w * rw, .h = 10 }, col, 5);
            ly += line_h;
        }
        y += h + card_gap;
    }
}

const FilterTip = struct { insert: []const u8, label: []const u8 };

/// Sem nada digitado: os filtros e as últimas buscas. Com texto: por que a lista está vazia.
fn emptyState(ctx: *d.Ctx, dl: *c.ImDrawList, list: d.Rect) void {
    if (search.text().len > 0) {
        if (search.source == .server) return message(ctx, dl, list, i18n.tr("Nenhum resultado", "No results"), i18n.tr("Tente outras palavras ou menos filtros.", "Try other words or fewer filters."));
        if (search.scanning) return message(ctx, dl, list, i18n.tr("Procurando neste computador…", "Looking on this computer…"), i18n.tr("Aperte Enter para buscar no Discord.", "Press Enter to search Discord."));
        return message(ctx, dl, list, i18n.tr("Nada neste computador", "Nothing on this computer"), i18n.tr("Aperte Enter para buscar em todo o histórico, no Discord.", "Press Enter to search the whole history on Discord."));
    }
    const font = ctx.ui.get(.regular);
    const bold = ctx.ui.get(.semibold);
    const mono = ctx.mono.get(.regular);
    var y = list.y + 14;
    d.text(dl, bold, 11.5, list.x + pad, y, ctx.col(.faint), i18n.tr("FILTROS", "FILTERS"));
    y += 22;
    const tips = [_]FilterTip{
        .{ .insert = "from:", .label = i18n.tr("mensagens de uma pessoa", "messages from someone") },
        .{ .insert = "mentions:", .label = i18n.tr("que mencionam uma pessoa", "that mention someone") },
        .{ .insert = "has:", .label = i18n.tr("com link, imagem, arquivo, vídeo…", "with a link, image, file, video…") },
        .{ .insert = "in:", .label = i18n.tr("em um canal", "in a channel") },
        .{ .insert = "before:", .label = i18n.tr("antes de uma data", "before a date") },
        .{ .insert = "after:", .label = i18n.tr("depois de uma data", "after a date") },
        .{ .insert = "during:", .label = i18n.tr("em um dia", "on a day") },
        .{ .insert = "pinned:", .label = i18n.tr("fixadas ou não", "pinned or not") },
    };
    const row_h: f32 = 34;
    for (tips, 0..) |t, i| {
        const rr: d.Rect = .{ .x = list.x + 8, .y = y, .w = list.w - 16, .h = row_h };
        if (rr.bottom() > list.bottom()) return;
        const hb = hit(ctx, 0x5d70 + i, rr);
        qa.mark(rr, "search-tip:{s}", .{t.insert});
        if (hb.hovered) d.rect(dl, rr, ctx.col(.hover), ctx.th.radius + 2);
        const kw = d.width(mono, 12.5, t.insert) + 14;
        const kr: d.Rect = .{ .x = rr.x + 6, .y = rr.y + 6, .w = kw, .h = rr.h - 12 };
        d.rect(dl, kr, ctx.col(.accent).alpha(0.14), @max(ctx.th.radius, 4));
        d.text(dl, mono, 12.5, kr.x + 7, d.centerY(kr, 12.5), ctx.col(.accent).mix(ctx.col(.text), 0.35), t.insert);
        _ = d.textClipped(dl, font, 13, kr.right() + 10, d.centerY(rr, 13), ctx.col(.muted), t.label, rr.right() - kr.right() - 16);
        if (hb.clicked) search.appendText(ctx, t.insert);
        y += row_h;
    }
    const n = search.recentCount();
    if (n == 0) return;
    y += 12;
    if (y + 24 > list.bottom()) return;
    d.text(dl, bold, 11.5, list.x + pad, y, ctx.col(.faint), i18n.tr("BUSCAS RECENTES", "RECENT SEARCHES"));
    y += 22;
    for (0..n) |i| {
        const rr: d.Rect = .{ .x = list.x + 8, .y = y, .w = list.w - 16, .h = 32 };
        if (rr.bottom() > list.bottom()) return;
        const hb = hit(ctx, 0x5d90 + i, rr);
        qa.mark(rr, "search-recent:{d}", .{i});
        if (hb.hovered) d.rect(dl, rr, ctx.col(.hover), ctx.th.radius + 2);
        icons.search(dl, rr.x + 16, rr.y + 16, ctx.col(.faint).u());
        const recent = search.recent(i);
        _ = d.textClipped(dl, font, 13.5, rr.x + 32, d.centerY(rr, 13.5), ctx.col(.text).mix(ctx.col(.muted), 0.2), recent, rr.w - 42);
        if (hb.clicked) {
            search.setText(ctx, recent);
            search.askServer(ctx);
            return;
        }
        y += 32;
    }
}

// --- A lista de resultados --------------------------------------------------------------

/// Quantos bytes de `s` cabem numa linha, quebrando no espaço quando dá.
fn nextLine(font: *c.ImFont, fs: f32, s: []const u8, max_w: f32) usize {
    var n = d.fitBytes(font, fs, s, max_w);
    if (n == 0 or n >= s.len) return n;
    if (std.mem.lastIndexOfScalar(u8, s[0..n], ' ')) |sp| {
        if (sp > 0) n = sp + 1;
    }
    return n;
}

fn countLines(font: *c.ImFont, s: []const u8, max_w: f32) u8 {
    var rest = s;
    var lines: u8 = 0;
    while (rest.len > 0 and lines < max_lines) {
        const n = nextLine(font, text_fs, rest, max_w);
        if (n == 0) break;
        rest = rest[n..];
        lines += 1;
    }
    return @max(lines, 1);
}

fn cardH(r: *const search.Result) f32 {
    return 10 + 22 + @as(f32, @floatFromInt(r.lines)) * line_h + 8;
}

fn startsGroup(items: []const search.Result, i: usize) bool {
    return i == 0 or items[i - 1].channel != items[i].channel;
}

fn resultList(ctx: *d.Ctx, dl: *c.ImDrawList, list: d.Rect) void {
    const items = search.results.items;
    const font = ctx.ui.get(.regular);
    const card_w = list.w - 24;
    const text_w = card_w - 12 - avatar_size - 10 - 12;
    var content: f32 = 8;
    var selected_top: f32 = 0;
    var selected_h: f32 = 0;
    for (items, 0..) |*r, i| {
        if (r.wrap_w != text_w) {
            r.wrap_w = text_w;
            r.lines = countLines(font, r.snippet, text_w);
        }
        if (startsGroup(items, i)) content += group_h;
        if (i == search.selected) {
            selected_top = content;
            selected_h = cardH(r);
        }
        content += cardH(r) + card_gap;
    }
    const max_scroll = @max(0, content - list.h);
    if (!blocked and ctx.hovering(list) and ctx.io.*.MouseWheel != 0) scroll_y -= ctx.io.*.MouseWheel * 72;
    if (search.scroll_to_selected) {
        search.scroll_to_selected = false;
        if (selected_top - group_h < scroll_y) scroll_y = selected_top - group_h;
        if (selected_top + selected_h + 8 > scroll_y + list.h) scroll_y = selected_top + selected_h + 8 - list.h;
    }
    scroll_y = std.math.clamp(scroll_y, 0, max_scroll);

    c.ImDrawList_PushClipRect(dl, d.v(list.x, list.y), d.v(list.right(), list.bottom()), true);
    defer c.ImDrawList_PopClipRect(dl);
    var y = list.y + 8 - scroll_y;
    for (items, 0..) |*r, i| {
        if (startsGroup(items, i)) {
            const gr: d.Rect = .{ .x = list.x + 14, .y = y, .w = list.w - 28, .h = group_h };
            if (gr.bottom() > list.y and gr.y < list.bottom()) groupHeader(ctx, dl, gr, r, i, list);
            y += group_h;
        }
        const h = cardH(r);
        const rr: d.Rect = .{ .x = list.x + 10, .y = y, .w = card_w, .h = h };
        if (rr.bottom() > list.y and rr.y < list.bottom()) resultCard(ctx, dl, rr, r, i, list);
        y += h + card_gap;
    }
    if (max_scroll > 0) {
        const track_h = list.h - 8;
        const thumb_h = @max(28, track_h * list.h / content);
        const thumb_y = list.y + 4 + (track_h - thumb_h) * scroll_y / max_scroll;
        d.rect(dl, .{ .x = list.right() - 7, .y = thumb_y, .w = 4, .h = thumb_h }, ctx.col(.text).alpha(0.16), 2);
    }
}

fn clipTo(r: d.Rect, list: d.Rect) d.Rect {
    const top = @max(r.y, list.y);
    const bottom = @min(r.bottom(), list.bottom());
    return .{ .x = r.x, .y = top, .w = r.w, .h = @max(1, bottom - top) };
}

fn groupHeader(ctx: *d.Ctx, dl: *c.ImDrawList, gr: d.Rect, r: *const search.Result, i: usize, list: d.Rect) void {
    const hb = hit(ctx, 0x6000 + i * 2 + 1, clipTo(gr, list));
    qa.mark(clipTo(gr, list), "search-group:{d}", .{i});
    const col = if (hb.hovered) ctx.col(.text) else ctx.col(.muted);
    _ = d.textClipped(dl, ctx.ui.get(.semibold), 12.5, gr.x, d.centerY(gr, 12.5), col, r.where, gr.w);
    d.tip(ctx, gr, i18n.tr("Abrir este canal", "Open this channel"), hb.hovered);
    if (hb.clicked) ctx.act(.{ .select_channel = r.channel });
}

fn resultCard(ctx: *d.Ctx, dl: *c.ImDrawList, rr: d.Rect, r: *const search.Result, i: usize, list: d.Rect) void {
    const vis = clipTo(rr, list);
    const hb = hit(ctx, 0x6000 + i * 2, vis);
    qa.mark(vis, "search-result:{d}", .{i});
    if (hb.hovered and (ctx.io.*.MouseDelta.x != 0 or ctx.io.*.MouseDelta.y != 0)) search.selected = i;
    if (hb.clicked) {
        search.selected = i;
        search.choose(ctx, r.*);
    }
    const sel = i == search.selected;
    const radius = ctx.th.radius + 2;
    const base = ctx.col(.rail).mix(ctx.col(.surface), 0.25);
    d.rect(dl, rr, if (sel) ctx.col(.accent).alpha(0.15) else if (hb.hovered) ctx.col(.hover) else base.alpha(0.55), radius);
    if (sel) d.rect(dl, .{ .x = rr.x, .y = rr.y + 10, .w = 3, .h = rr.h - 20 }, ctx.col(.accent), 2);

    w.avatar(ctx, dl, rr.x + 12 + avatar_size / 2, rr.y + 10 + avatar_size / 2, avatar_size, r.author_id, .circle, null, 1);
    const font = ctx.ui.get(.regular);
    const bold = ctx.ui.get(.semibold);
    const tx = rr.x + 12 + avatar_size + 10;
    const right = rr.right() - 12;

    var tb: [48]u8 = undefined;
    const when = w.stamp(&tb, r.ts, @divTrunc(ctx.now_ms, 1000));
    const ww = d.width(font, 12, when);
    // À direita: "cache" (veio do disco) e, com o mouse em cima, "Ir".
    var slot = right;
    if (hb.hovered) {
        const jump = i18n.tr("Ir", "Jump");
        const jw = d.width(bold, 11.5, jump) + 14;
        const jr: d.Rect = .{ .x = slot - jw, .y = rr.y + 8, .w = jw, .h = 20 };
        d.rect(dl, jr, ctx.col(.elevated).mix(ctx.col(.text), 0.1), @max(ctx.th.radius, 4));
        d.text(dl, bold, 11.5, jr.x + 7, d.centerY(jr, 11.5), ctx.col(.text), jump);
        slot = jr.x - 6;
    }
    if (r.disk) {
        const tag = i18n.tr("cache", "cache");
        const tw = d.width(font, 11, tag) + 12;
        const tr: d.Rect = .{ .x = slot - tw, .y = rr.y + 9, .w = tw, .h = 18 };
        d.rect(dl, tr, ctx.col(.faint).alpha(0.18), 4);
        d.text(dl, font, 11, tr.x + 6, d.centerY(tr, 11), ctx.col(.muted), tag);
        slot = tr.x - 6;
    }
    const name_room = @max(0, slot - tx - ww - 8);
    const guild = if (ctx.store.channel(r.channel)) |cs| cs.info.guild else 0;
    const nw = d.textClipped(dl, bold, 14.5, tx, rr.y + 9, w.nameColor(ctx, guild, r.author_id), r.author, name_room);
    d.text(dl, font, 12, tx + nw + 8, rr.y + 12, ctx.col(.faint), when);

    // O texto, em até três linhas, com tudo o que casou em destaque.
    var rest = r.snippet;
    var y = rr.y + 10 + 22;
    var lines: u8 = 0;
    const col = ctx.col(.text).mix(ctx.col(.muted), 0.18);
    while (rest.len > 0 and lines < r.lines) : (lines += 1) {
        const n = nextLine(font, text_fs, rest, right - tx);
        if (n == 0) break;
        highlighted(ctx, dl, tx, y, col, rest[0..n]);
        rest = rest[n..];
        y += line_h;
    }
}

/// Uma linha de texto, com os termos da busca marcados.
fn highlighted(ctx: *d.Ctx, dl: *c.ImDrawList, x0: f32, y: f32, col: d.Rgba, line: []const u8) void {
    const font = ctx.ui.get(.regular);
    const bold = ctx.ui.get(.semibold);
    const q = &search.view_query;
    // Árabe ou hebraico: a ordem da tela não é a do texto, e desenhar pedaço por pedaço
    // embaralharia as palavras. A linha vai inteira (ui/bidi.zig), sem a marcação.
    if (@import("bidi.zig").hasRtl(line)) return d.text(dl, font, text_fs, x0, y, col, line);
    var x = x0;
    var rest = line;
    while (rest.len > 0) {
        var best: ?[2]usize = null;
        for (0..q.n_terms) |i| {
            if (sq.findFold(rest, q.term(i))) |m| {
                if (m[1] > m[0] and (best == null or m[0] < best.?[0])) best = m;
            }
        }
        const m = best orelse {
            d.text(dl, font, text_fs, x, y, col, rest);
            return;
        };
        const before = rest[0..m[0]];
        d.text(dl, font, text_fs, x, y, col, before);
        x += d.width(font, text_fs, before);
        const piece = rest[m[0]..m[1]];
        const pw = d.width(bold, text_fs, piece);
        d.rect(dl, .{ .x = x - 1, .y = y - 1, .w = pw + 2, .h = text_fs * 1.3 }, ctx.col(.accent).alpha(0.26), 3);
        d.text(dl, bold, text_fs, x, y, ctx.col(.text), piece);
        x += pw;
        rest = rest[m[1]..];
    }
}

// --- Rodapé -----------------------------------------------------------------------------

fn paged() bool {
    return search.source == .server and search.server == .done and search.total > page_size;
}

fn footerHeight() f32 {
    if (paged()) return 46;
    return if (search.text().len > 0) 30 else 0;
}

fn footer(ctx: *d.Ctx, dl: *c.ImDrawList, b: d.Rect, h: f32) void {
    if (h == 0) return;
    const fy = b.bottom() - h;
    const row: d.Rect = .{ .x = b.x, .y = fy, .w = b.w, .h = h };
    d.line(dl, b.x, fy, b.right(), fy, ctx.col(.border), 1);
    const font = ctx.ui.get(.regular);
    if (!paged()) {
        const keys = if (search.source == .local)
            i18n.tr("↑↓ escolher  ·  Enter buscar no Discord  ·  Esc fechar", "↑↓ pick  ·  Enter search Discord  ·  Esc close")
        else
            i18n.tr("↑↓ escolher  ·  Enter abrir  ·  Esc fechar", "↑↓ pick  ·  Enter open  ·  Esc close");
        _ = d.textClipped(dl, font, 12, b.x + pad, d.centerY(row, 12), ctx.col(.faint), keys, b.w - pad * 2);
        return;
    }
    const page = search.offset / page_size + 1;
    const pages = @min(search.total, max_offset + page_size) / page_size + @intFromBool(@min(search.total, max_offset + page_size) % page_size != 0);
    var buf: [64]u8 = undefined;
    const label = i18n.fmt(&buf, "Página {d} de {d}", "Page {d} of {d}", .{ page, pages });
    const lw = d.width(font, 12.5, label);
    d.text(dl, font, 12.5, b.x + (b.w - lw) / 2, d.centerY(row, 12.5), ctx.col(.muted), label);
    if (pageButton(ctx, dl, 0x5d60, .{ .x = b.x + pad, .y = fy + 9, .w = 96, .h = 28 }, i18n.tr("‹  Anterior", "‹  Previous"), "search-page:prev", search.offset > 0))
        search.changePage(ctx, search.offset -| page_size);
    if (pageButton(ctx, dl, 0x5d61, .{ .x = b.right() - pad - 96, .y = fy + 9, .w = 96, .h = 28 }, i18n.tr("Próxima  ›", "Next  ›"), "search-page:next", page < pages))
        search.changePage(ctx, search.offset + page_size);
}

fn pageButton(ctx: *d.Ctx, dl: *c.ImDrawList, id: usize, r: d.Rect, label: []const u8, mark: []const u8, enabled: bool) bool {
    const font = ctx.ui.get(.medium);
    const lw = d.width(font, 12.5, label);
    const x = r.x + (r.w - lw) / 2;
    if (!enabled) {
        d.text(dl, font, 12.5, x, d.centerY(r, 12.5), ctx.col(.faint).alpha(0.6), label);
        return false;
    }
    const hb = hit(ctx, id, r);
    qa.mark(r, "{s}", .{mark});
    d.rect(dl, r, if (hb.hovered) ctx.col(.hover) else ctx.col(.rail).mix(ctx.col(.surface), 0.25), @max(ctx.th.radius, 4));
    d.text(dl, font, 12.5, x, d.centerY(r, 12.5), ctx.col(.text), label);
    return hb.clicked;
}
