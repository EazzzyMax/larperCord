//! Convites: entrar num servidor pelo link, criar um link e gerar outro com outras regras.
//!
//! Entrar é sempre um clique de quem usa, com o servidor à vista, e com um intervalo entre uma
//! entrada e outra: entrar em muitos servidores em pouco tempo pode pesar para a conta. Se o
//! Discord pedir captcha, o convite abre no navegador; o app não tenta resolver nem contornar.
//!
//! O Discord não edita um convite: "editar" é pedir um link novo, e o anterior segue valendo
//! até expirar. É o que o cliente oficial faz.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const types = @import("../core/types.zig");
const links = @import("../core/links.zig");
const ev = @import("../core/event.zig");
const popup = @import("popup.zig");
const forum = @import("forum.zig");
const inbox = @import("inbox.zig");
const w_ui = @import("widgets.zig");
const att = @import("attachments.zig");
const entrada = @import("entrada.zig");
const Id = types.Id;

// --- Entrar -----------------------------------------------------------------------------

var join_buf: [200]u8 = @splat(0);
/// O link com o `https://` que faltava: o código devolvido por `parseCode` aponta para cá.
var parse_buf: [220]u8 = undefined;
pub var join_state: ev.JoinStatus = .idle;
var join_last_ms: i64 = -join_gap_ms;
/// Entrou, e o servidor ainda não chegou pelo gateway: abre assim que chegar.
pub var pending_guild: Id = 0;
const join_gap_ms: i64 = 30_000;

pub fn openJoin(ctx: *d.Ctx, link: []const u8) void {
    @memset(&join_buf, 0);
    const head = d.utf8Prefix(link, join_buf.len - 1);
    @memcpy(join_buf[0..head.len], head);
    join_state = .idle;
    entrada.warning_open = false;
    ctx.st.popup = .join_invite;
}

fn startJoin(ctx: *d.Ctx, code: []const u8) void {
    join_state = .joining;
    join_last_ms = ctx.now_ms;
    ctx.act(.{ .join_invite = links.InviteCode.init(code) });
}

/// Para o QA: a próxima entrada não espera o intervalo.
pub fn qaResetGap() void {
    join_last_ms = -join_gap_ms;
}

/// O código do que foi colado: o link inteiro, sem o https, ou só o código.
fn parseCode(text_in: []const u8) ?[]const u8 {
    const text = std.mem.trim(u8, text_in, " \t\r\n");
    if (links.parseInvite(text)) |code| return if (code.len > 0) code else null;
    const with_scheme = std.fmt.bufPrint(&parse_buf, "https://{s}", .{text}) catch return null;
    if (links.parseInvite(with_scheme)) |code| return if (code.len > 0) code else null;
    if (text.len < 2 or text.len > 30) return null;
    for (text) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '-') return null;
    return text;
}

pub fn joined(r: ev.InviteJoined) void {
    join_state = r.status;
    if (r.status == .captcha) {
        var b: [64]u8 = undefined;
        att.openUrl(std.fmt.bufPrint(&b, "https://discord.gg/{s}", .{r.code.slice()}) catch return);
    }
}

fn joinMessage() []const u8 {
    return switch (join_state) {
        .captcha => i18n.tr("O Discord pediu um captcha, que só dá para resolver lá: abri o convite no navegador.", "Discord asked for a captcha, which can only be solved there: the invite is open in your browser."),
        .invalid => i18n.tr("Esse convite não existe mais ou expirou.", "This invite no longer exists or has expired."),
        .forbidden => i18n.tr("O Discord não deixou esta conta entrar. Ela pode estar banida do servidor ou precisar de verificação.", "Discord didn't let this account join. It may be banned from the server or need verification."),
        .too_many => i18n.tr("Esta conta já está no máximo de servidores.", "This account is already in the maximum number of servers."),
        .failed => i18n.tr("Não consegui entrar. Tente de novo em instantes.", "Couldn't join. Try again in a moment."),
        .idle, .joining, .ok => "",
    };
}

pub fn drawJoin(ctx: *d.Ctx) void {
    const r = forum.dialogRect(ctx, 460, 330);
    const dl = popup.beginWindow("##join-invite", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    // O aviso de antes de entrar fica no lugar do resto até a pessoa escolher (ui/entrada.zig).
    if (entrada.warning_open) {
        if (entrada.joinWarning(ctx, dl, r) == .join and join_state != .joining) {
            if (parseCode(std.mem.sliceTo(&join_buf, 0))) |cd| startJoin(ctx, cd);
        }
        return;
    }
    const fam = ctx.ui;
    d.text(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.tr("Entrar em um servidor", "Join a server"));
    d.text(dl, fam.get(.semibold), 12.5, r.x + 18, r.y + 50, ctx.col(.muted), i18n.tr("Link do convite", "Invite link"));
    const nr: d.Rect = .{ .x = r.x + 18, .y = r.y + 70, .w = r.w - 36, .h = 36 };
    qa.mark(nr, "join-input", .{});
    if (popup.appearing) c.ImGui_SetKeyboardFocusHere();
    if (forum.textInput(ctx, dl, nr, "##join-input", "https://discord.gg/…", &join_buf, 0)) join_state = .idle;

    const code = parseCode(std.mem.sliceTo(&join_buf, 0));
    if (code) |cd| if (ctx.store.invites.get(cd) == null) ctx.act(.{ .want_invite = links.InviteCode.init(cd) });
    const inv = if (code) |cd| ctx.store.invites.get(cd) else null;
    const preview: d.Rect = .{ .x = r.x + 18, .y = r.y + 118, .w = r.w - 36, .h = 72 };
    previewCard(ctx, dl, preview, code, inv);

    // O que aconteceu, ou o aviso de antes de entrar.
    const msg = joinMessage();
    const gap_left = join_last_ms + join_gap_ms - ctx.now_ms;
    var tb: [120]u8 = undefined;
    var note: []const u8 = msg;
    var note_col = ctx.col(.danger);
    if (msg.len == 0) {
        note_col = ctx.col(.muted);
        note = if (join_state == .joining)
            i18n.tr("Entrando…", "Joining…")
        else if (gap_left > 0)
            i18n.fmt(&tb, "Espere {d} s para entrar em outro: muitas entradas seguidas podem pesar para a conta.", "Wait {d} s to join another one: many joins in a row can count against the account.", .{@divTrunc(gap_left, 1000) + 1})
        else
            i18n.tr("O Discord pode pedir um captcha. Se pedir, o convite abre no navegador.", "Discord may ask for a captcha. If it does, the invite opens in your browser.");
    }
    if (gap_left > 0) @import("anim.zig").at(ctx.now_ms + 1000);
    wrapped(ctx, dl, r.x + 18, r.y + 200, r.w - 36, 12.5, note_col, note);

    const ok = inv != null and inv.?.state == .ok;
    const member = ok and inv.?.guild != 0 and ctx.store.guild(inv.?.guild) != null;
    const lbl = if (member) i18n.tr("Ir para o servidor", "Go to server") else i18n.tr("Entrar", "Join");
    const bw = d.width(fam.get(.semibold), 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - bw, .y = r.bottom() - 50, .w = bw, .h = 34 };
    qa.mark(br, "join-go", .{});
    const can = ok and (member or (join_state != .joining and gap_left <= 0));
    const go = forum.primary(ctx, dl, fam, 0x7100, br, lbl, can);
    const cancel = i18n.tr("Cancelar", "Cancel");
    const cw = inbox.buttonWidth(ctx, cancel);
    const cr: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(cr, "join-cancel", .{});
    if (inbox.button(ctx, dl, 0x7101, cr, cancel, false)) return popup.close(ctx);
    if (go and can) {
        if (member) {
            ctx.act(.{ .select_guild = inv.?.guild });
            return popup.close(ctx);
        }
        // Uma vez, até marcar "não mostrar de novo": o aviso de entrar demais.
        if (entrada.wantsWarning(ctx)) return entrada.openWarning();
        startJoin(ctx, code.?);
    }
}

fn previewCard(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect, code: ?[]const u8, inv: ?types.Invite) void {
    const fam = ctx.ui;
    const radius = @max(ctx.th.radius + 2, 4);
    d.rect(dl, r, ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
    qa.mark(r, "join-preview", .{});
    const ir: d.Rect = .{ .x = r.x + 12, .y = r.y + 12, .w = 48, .h = 48 };
    const state = if (inv) |i| i.state else types.Invite.State.loading;
    const ok = code != null and state == .ok;
    var icon_drawn = false;
    if (ok) if (inv.?.icon) |hash| {
        var ub: [160]u8 = undefined;
        icon_drawn = w_ui.picture(ctx, dl, w_ui.cdnUrl(&ub, .guild, inv.?.guild, hash), ir, 12, 1);
    };
    if (!icon_drawn) {
        d.rect(dl, ir, if (ok) ctx.col(.accent).alpha(0.75) else ctx.col(.text).alpha(0.07), 12);
        if (ok and inv.?.name.len > 0) {
            const g = d.firstGlyph(inv.?.name);
            const gw = d.width(fam.get(.bold), 19, g);
            d.text(dl, fam.get(.bold), 19, ir.x + (ir.w - gw) / 2, d.centerY(ir, 19), d.Rgba.white, g);
        }
    }
    const tx = ir.right() + 12;
    const room = r.right() - tx - 12;
    if (code == null) {
        d.text(dl, fam.get(.regular), 13.5, tx, d.centerY(r, 13.5), ctx.col(.muted), i18n.tr("O servidor aparece aqui antes de você entrar.", "The server shows up here before you join."));
        return;
    }
    switch (state) {
        .loading => d.text(dl, fam.get(.regular), 13.5, tx, d.centerY(r, 13.5), ctx.col(.muted), i18n.tr("carregando…", "loading…")),
        .invalid => d.text(dl, fam.get(.semibold), 13.5, tx, d.centerY(r, 13.5), ctx.col(.danger), i18n.tr("Convite inválido ou expirado", "Invalid or expired invite")),
        .failed => d.text(dl, fam.get(.regular), 13.5, tx, d.centerY(r, 13.5), ctx.col(.muted), i18n.tr("não consegui carregar o convite", "couldn't load the invite")),
        .ok => {
            _ = d.textClipped(dl, fam.get(.bold), 15.5, tx, r.y + 15, ctx.col(.text), inv.?.name, room);
            var cb: [64]u8 = undefined;
            const counts = i18n.fmt(&cb, "{d} online · {d} membros", "{d} online · {d} members", .{ inv.?.online, inv.?.members });
            _ = d.textClipped(dl, fam.get(.regular), 13, tx, r.y + 39, ctx.col(.muted), counts, room);
        },
    }
}

/// Texto curto que quebra em até três linhas.
fn wrapped(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y_in: f32, max_w: f32, fs: f32, col: d.Rgba, s: []const u8) void {
    const font = ctx.ui.get(.regular);
    var rest = s;
    var y = y_in;
    var lines: u8 = 0;
    while (rest.len > 0 and lines < 3) : (lines += 1) {
        var n = d.fitBytes(font, fs, rest, max_w);
        if (n == 0) return;
        if (n < rest.len) if (std.mem.lastIndexOfScalar(u8, rest[0..n], ' ')) |sp| {
            if (sp > 0) n = sp + 1;
        };
        d.text(dl, font, fs, x, y, col, std.mem.trimEnd(u8, rest[0..n], " "));
        rest = rest[n..];
        y += fs * 1.45;
    }
}

// --- Criar e "editar" -------------------------------------------------------------------

const Age = struct { secs: u32, pt: []const u8, en: []const u8 };
const ages = [_]Age{
    .{ .secs = 1800, .pt = "30 min", .en = "30 min" },
    .{ .secs = 3600, .pt = "1 hora", .en = "1 hour" },
    .{ .secs = 21600, .pt = "6 horas", .en = "6 hours" },
    .{ .secs = 43200, .pt = "12 horas", .en = "12 hours" },
    .{ .secs = 86400, .pt = "1 dia", .en = "1 day" },
    .{ .secs = 604800, .pt = "7 dias", .en = "7 days" },
    .{ .secs = 2592000, .pt = "30 dias", .en = "30 days" },
    .{ .secs = 0, .pt = "Nunca", .en = "Never" },
};
const use_limits = [_]u8{ 0, 1, 5, 10, 25, 50, 100 };

/// O que está escolhido na tela, e com o que o link da tela foi feito.
var age_i: usize = 6;
var uses_i: usize = 0;
var temporary = false;
var made_age: usize = 6;
var made_uses: usize = 0;
var made_temporary = false;

var made_code: links.InviteCode = .{};
pub var create_state: ev.InviteStatus = .failed;
var creating = false;
var create_req: u32 = 0;
var create_channel: Id = 0;
var copied_ms: i64 = 0;

pub fn canInvite(ctx: *d.Ctx, ch: *const types.Channel) bool {
    if (ch.guild == 0 or ch.thread != null) return false;
    if (ch.kind != .text and ch.kind != .voice) return false;
    return ctx.store.channelPermissions(ch) & types.perm.create_instant_invite != 0;
}

/// Em qual canal criar o convite do servidor: o aberto, se der; senão o primeiro que der.
pub fn channelFor(ctx: *d.Ctx, guild: Id) ?Id {
    if (ctx.st.activeChannel()) |id| if (ctx.store.channel(id)) |cs| {
        if (cs.info.guild == guild and canInvite(ctx, &cs.info)) return id;
    };
    for (ctx.store.channelsOf(guild)) |id| {
        const cs = ctx.store.channel(id) orelse continue;
        if (canInvite(ctx, &cs.info)) return id;
    }
    return null;
}

pub fn openCreate(ctx: *d.Ctx, channel: Id) void {
    create_channel = channel;
    made_code = .{};
    copied_ms = 0;
    ctx.st.popup = .{ .create_invite = .{ .channel = channel } };
    request(ctx);
}

fn request(ctx: *d.Ctx) void {
    create_req +%= 1;
    creating = true;
    made_age = age_i;
    made_uses = uses_i;
    made_temporary = temporary;
    ctx.act(.{ .create_invite = .{
        .req = create_req,
        .channel = create_channel,
        .max_age = ages[age_i].secs,
        .max_uses = use_limits[uses_i],
        .temporary = temporary,
    } });
}

pub fn created(r: ev.InviteCreated) void {
    if (r.req != create_req) return;
    creating = false;
    create_state = r.status;
    if (r.status == .ok) {
        made_code = r.code;
        copied_ms = 0;
    }
}

/// O link que está na tela (o QA confere).
pub fn madeCode() []const u8 {
    return made_code.slice();
}

fn chip(ctx: *d.Ctx, dl: *c.ImDrawList, id: usize, r: d.Rect, label: []const u8, on: bool) bool {
    const hb = d.hit(ctx, id, r);
    const radius = @max(ctx.th.radius, 4);
    const font = ctx.ui.get(.medium);
    d.rect(dl, r, if (on) ctx.col(.accent).alpha(0.22) else if (hb.hovered) ctx.col(.hover) else ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
    d.border(dl, r, if (on) ctx.col(.accent) else ctx.col(.border), radius, 1);
    d.text(dl, font, 12.5, r.x + (r.w - d.width(font, 12.5, label)) / 2, d.centerY(r, 12.5), if (on or hb.hovered) ctx.col(.text) else ctx.col(.muted), label);
    return hb.clicked;
}

pub fn drawCreate(ctx: *d.Ctx, channel: Id) void {
    const cs = ctx.store.channel(channel) orelse return popup.close(ctx);
    const r = forum.dialogRect(ctx, 500, 412);
    const dl = popup.beginWindow("##create-invite", r);
    defer c.ImGui_End();
    ctx.dl = dl;
    inbox.panelFrame(ctx, dl, r);
    const fam = ctx.ui;
    const bold = fam.get(.semibold);
    var tb: [120]u8 = undefined;
    const gname = if (ctx.store.guild(cs.info.guild)) |g| g.name else "";
    _ = d.textClipped(dl, fam.get(.bold), 17, r.x + 18, r.y + 16, ctx.col(.text), i18n.fmt(&tb, "Convidar pessoas para {s}", "Invite people to {s}", .{gname}), r.w - 36);
    var cb: [120]u8 = undefined;
    _ = d.textClipped(dl, fam.get(.regular), 13, r.x + 18, r.y + 42, ctx.col(.muted), std.fmt.bufPrint(&cb, "#{s}", .{cs.info.name}) catch "", r.w - 36);

    // O link, com o botão de copiar.
    const radius = @max(ctx.th.radius + 2, 4);
    const lr: d.Rect = .{ .x = r.x + 18, .y = r.y + 70, .w = r.w - 36, .h = 42 };
    d.rect(dl, lr, ctx.col(.rail).mix(ctx.col(.surface), 0.25), radius);
    d.border(dl, lr, ctx.col(.border), radius, 1);
    qa.mark(lr, "invite-link", .{});
    var ub: [64]u8 = undefined;
    const has_link = made_code.len > 0;
    const url = if (has_link) std.fmt.bufPrint(&ub, "https://discord.gg/{s}", .{made_code.slice()}) catch "" else "";
    const just_copied = copied_ms != 0 and ctx.now_ms - copied_ms < 2000;
    const copy_lbl = if (just_copied) i18n.tr("Copiado", "Copied") else i18n.tr("Copiar", "Copy");
    const bw = @max(d.width(bold, 13, i18n.tr("Copiado", "Copied")), d.width(bold, 13, i18n.tr("Copiar", "Copy"))) + 26;
    const copy_r: d.Rect = .{ .x = lr.right() - bw - 5, .y = lr.y + 5, .w = bw, .h = lr.h - 10 };
    qa.mark(copy_r, "invite-copy", .{});
    if (forum.primary(ctx, dl, fam, 0x7110, copy_r, copy_lbl, has_link) and has_link) {
        var zb: [64]u8 = undefined;
        if (std.fmt.bufPrintSentinel(&zb, "{s}", .{url}, 0)) |z| {
            _ = c.SDL_SetClipboardText(z.ptr);
            copied_ms = ctx.now_ms;
            @import("anim.zig").at(ctx.now_ms + 2000);
        } else |_| {}
    }
    const link_room = copy_r.x - lr.x - 20;
    if (creating) {
        d.text(dl, fam.get(.regular), 14, lr.x + 12, d.centerY(lr, 14), ctx.col(.muted), i18n.tr("Gerando o link…", "Creating the link…"));
    } else if (has_link) {
        _ = d.textClipped(dl, fam.get(.medium), 14, lr.x + 12, d.centerY(lr, 14), ctx.col(.text), url, link_room);
    } else {
        const err: []const u8 = switch (create_state) {
            .forbidden => i18n.tr("Você não pode criar convites neste canal.", "You can't create invites in this channel."),
            .disabled => i18n.tr("Os convites estão desligados neste servidor.", "Invites are disabled in this server."),
            else => i18n.tr("Não consegui criar o convite.", "Couldn't create the invite."),
        };
        _ = d.textClipped(dl, fam.get(.regular), 13.5, lr.x + 12, d.centerY(lr, 13.5), ctx.col(.danger), err, link_room);
    }

    var y = lr.bottom() + 18;
    d.text(dl, bold, 11.5, r.x + 18, y, ctx.col(.faint), i18n.tr("EXPIRA EM", "EXPIRES AFTER"));
    y += 20;
    const chip_gap: f32 = 6;
    const age_w = (r.w - 36 - chip_gap * 3) / 4;
    for (ages, 0..) |a, i| {
        const row: f32 = @floatFromInt(i / 4);
        const col_i: f32 = @floatFromInt(i % 4);
        const cr: d.Rect = .{ .x = r.x + 18 + col_i * (age_w + chip_gap), .y = y + row * 34, .w = age_w, .h = 28 };
        qa.mark(cr, "invite-age:{d}", .{a.secs});
        if (chip(ctx, dl, 0x7120 + i, cr, i18n.tr(a.pt, a.en), age_i == i)) age_i = i;
    }
    y += 68 + 12;
    d.text(dl, bold, 11.5, r.x + 18, y, ctx.col(.faint), i18n.tr("MÁXIMO DE USOS", "MAX USES"));
    y += 20;
    const use_w = (r.w - 36 - chip_gap * 6) / 7;
    for (use_limits, 0..) |u, i| {
        const col_i: f32 = @floatFromInt(i);
        const cr: d.Rect = .{ .x = r.x + 18 + col_i * (use_w + chip_gap), .y = y, .w = use_w, .h = 28 };
        qa.mark(cr, "invite-uses:{d}", .{u});
        var nb: [8]u8 = undefined;
        const label = if (u == 0) "∞" else std.fmt.bufPrint(&nb, "{d}", .{u}) catch "";
        if (chip(ctx, dl, 0x7130 + i, cr, label, uses_i == i)) uses_i = i;
    }
    y += 40;
    // Entrada temporária: uma caixinha com o texto ao lado.
    const tr: d.Rect = .{ .x = r.x + 18, .y = y, .w = r.w - 36, .h = 26 };
    const th = d.hit(ctx, 0x7140, tr);
    qa.mark(tr, "invite-temporary", .{});
    if (th.clicked) temporary = !temporary;
    const box: d.Rect = .{ .x = tr.x, .y = tr.y + 4, .w = 18, .h = 18 };
    d.rect(dl, box, if (temporary) ctx.col(.accent) else ctx.col(.rail).mix(ctx.col(.surface), 0.25), 4);
    d.border(dl, box, if (temporary) ctx.col(.accent) else ctx.col(.border), 4, 1);
    if (temporary) {
        d.line(dl, box.x + 4, box.y + 9, box.x + 8, box.y + 13, ctx.col(.accent_text), 2);
        d.line(dl, box.x + 8, box.y + 13, box.x + 14, box.y + 5, ctx.col(.accent_text), 2);
    }
    _ = d.textClipped(dl, fam.get(.regular), 13, box.right() + 8, d.centerY(tr, 13), ctx.col(.muted), i18n.tr("Entrada temporária: sai ao desconectar, se não ganhar um cargo", "Temporary: they leave on disconnect unless given a role"), tr.w - 28);

    const changed = age_i != made_age or uses_i != made_uses or temporary != made_temporary;
    const lbl = i18n.tr("Gerar novo link", "Generate a New Link");
    const gw = d.width(bold, 13.5, lbl) + 36;
    const br: d.Rect = .{ .x = r.right() - 18 - gw, .y = r.bottom() - 48, .w = gw, .h = 34 };
    qa.mark(br, "invite-generate", .{});
    if (forum.primary(ctx, dl, fam, 0x7141, br, lbl, changed and !creating) and changed and !creating) request(ctx);
    const close_lbl = i18n.tr("Fechar", "Close");
    const cw = inbox.buttonWidth(ctx, close_lbl);
    const close_r: d.Rect = .{ .x = br.x - cw - 10, .y = br.y + 3, .w = cw, .h = 28 };
    qa.mark(close_r, "invite-close", .{});
    if (inbox.button(ctx, dl, 0x7142, close_r, close_lbl, false)) return popup.close(ctx);
    if (changed) _ = d.textClipped(dl, fam.get(.regular), 12, r.x + 18, d.centerY(br, 12), ctx.col(.faint), i18n.tr("O link anterior segue valendo.", "The previous link stays valid."), close_r.x - r.x - 28);
}
