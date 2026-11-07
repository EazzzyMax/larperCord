//! Configurações → Minha conta → Perfil: nome que aparece, pronomes e
//! "sobre mim", gravados na conta (PATCH /users/@me e /users/@me/profile).
//! Foto e banner continuam pelo app oficial. Mesmo visual das outras
//! páginas (ui/settings.zig).
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const conta = @import("../core/conta.zig");
const Id = @import("../core/types.zig").Id;

var name_buf: [conta.max_global_name * 4 + 1]u8 = @splat(0);
var pronouns_buf: [conta.max_pronouns * 4 + 1]u8 = @splat(0);
var bio_buf: [conta.max_bio * 4 + 1]u8 = @splat(0);
/// De quem são os textos nas caixas e se o perfil (pronomes, bio) já veio.
var seeded_user: Id = 0;
var seeded_profile = false;
/// A pessoa mexeu: o que chegar do Discord não apaga o que ela escreveu.
var dirty = false;

fn fill(buf: []u8, s: []const u8) void {
    @memset(buf, 0);
    const n = d.utf8Prefix(s, buf.len - 1).len;
    @memcpy(buf[0..n], s[0..n]);
}

fn chars(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

/// Rótulo com o contador à direita (vermelho quando passa do limite).
fn label(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: f32, wd: f32, t: []const u8, text: []const u8, max: usize) bool {
    const fam = ctx.ui;
    var up: [64]u8 = undefined;
    d.text(dl, fam.get(.bold), 12, x, y, ctx.col(.muted), d.upper(&up, t));
    const n = chars(text);
    var cb: [24]u8 = undefined;
    const count = std.fmt.bufPrint(&cb, "{d}/{d}", .{ n, max }) catch "";
    d.text(dl, fam.get(.regular), 11.5, x + wd - d.width(fam.get(.regular), 11.5, count), y + 1, if (n > max) ctx.col(.danger) else ctx.col(.faint), count);
    return n <= max;
}

fn box(ctx: *d.Ctx, dl: *c.ImDrawList, r: d.Rect) void {
    const radius = @max(ctx.th.radius, 4);
    d.rect(dl, r, ctx.col(.elevated), radius);
    d.border(dl, r, ctx.col(.border), radius, 1);
}

pub fn profile(ctx: *d.Ctx, dl: *c.ImDrawList, x: f32, y: *f32, wd: f32) void {
    const me = ctx.store.me;
    const u = ctx.store.user(me) orelse return;
    // O perfil (pronomes, bio) só é pedido quando a página abre.
    ctx.act(.{ .want_profile = me });
    const pf = ctx.store.profiles.get(me);
    if (seeded_user != me) {
        seeded_user = me;
        seeded_profile = false;
        dirty = false;
        fill(&name_buf, u.name);
    }
    if (!seeded_profile and pf != null and !dirty) {
        seeded_profile = true;
        fill(&pronouns_buf, pf.?.pronouns);
        fill(&bio_buf, pf.?.bio);
    }
    const fam = ctx.ui;
    var yy = y.*;
    var up: [64]u8 = undefined;
    const head = d.upper(&up, i18n.tr("Perfil", "Profile"));
    d.text(dl, fam.get(.bold), 12, x, yy + 8, ctx.col(.muted), head);
    yy += 34;
    const fw = @min(wd, 460);

    var ok = label(ctx, dl, x, yy, fw, i18n.tr("Nome de exibição", "Display name"), std.mem.sliceTo(&name_buf, 0), conta.max_global_name);
    const nr: d.Rect = .{ .x = x, .y = yy + 20, .w = fw, .h = 34 };
    box(ctx, dl, nr);
    c.ImGui_PushFontFloat(fam.get(.regular), 14);
    c.ImGui_SetCursorScreenPos(d.v(nr.x + 10, nr.y + 6));
    c.ImGui_SetNextItemWidth(nr.w - 20);
    if (c.ImGui_InputTextWithHint("##acc-name", i18n.trZ("vazio = o nome de usuário", "empty = your username"), &name_buf, name_buf.len, 0)) dirty = true;
    c.ImGui_PopFont();
    qa.mark(nr, "account-name", .{});
    yy += 66;

    ok = label(ctx, dl, x, yy, fw, i18n.tr("Pronomes", "Pronouns"), std.mem.sliceTo(&pronouns_buf, 0), conta.max_pronouns) and ok;
    const pr: d.Rect = .{ .x = x, .y = yy + 20, .w = fw, .h = 34 };
    box(ctx, dl, pr);
    c.ImGui_PushFontFloat(fam.get(.regular), 14);
    c.ImGui_SetCursorScreenPos(d.v(pr.x + 10, pr.y + 6));
    c.ImGui_SetNextItemWidth(pr.w - 20);
    if (c.ImGui_InputTextWithHint("##acc-pronouns", i18n.trZ("ela/dela, ele/dele…", "she/her, he/him…"), &pronouns_buf, pronouns_buf.len, 0)) dirty = true;
    c.ImGui_PopFont();
    qa.mark(pr, "account-pronouns", .{});
    yy += 66;

    ok = label(ctx, dl, x, yy, fw, i18n.tr("Sobre mim", "About me"), std.mem.sliceTo(&bio_buf, 0), conta.max_bio) and ok;
    const br: d.Rect = .{ .x = x, .y = yy + 20, .w = fw, .h = 96 };
    box(ctx, dl, br);
    c.ImGui_PushFontFloat(fam.get(.regular), 14);
    c.ImGui_SetCursorScreenPos(d.v(br.x + 6, br.y + 6));
    if (c.ImGui_InputTextMultilineEx("##acc-bio", &bio_buf, bio_buf.len, d.v(br.w - 12, br.h - 12), c.ImGuiInputTextFlags_WordWrap, null, null)) dirty = true;
    c.ImGui_PopFont();
    qa.mark(br, "account-bio", .{});
    yy += 128;

    if (pf == null and !ctx.store.demo) {
        d.text(dl, fam.get(.regular), 12.5, x, yy, ctx.col(.faint), i18n.tr("carregando o perfil…", "loading the profile…"));
        yy += 22;
    }

    const busy = ctx.st.conta.profile_busy;
    const lbl = if (busy) i18n.tr("Salvando…", "Saving…") else i18n.tr("Salvar perfil", "Save profile");
    const sr: d.Rect = .{ .x = x, .y = yy, .w = d.width(fam.get(.semibold), 14, lbl) + 32, .h = 36 };
    const hb = d.hit(ctx, 0x5E100, sr);
    qa.mark(sr, "account-save", .{});
    const can = ok and !busy and (seeded_profile or ctx.store.demo);
    const radius = ctx.th.radius;
    d.rect(dl, sr, if (!can) ctx.col(.hover) else if (hb.hovered) ctx.col(.accent).mix(d.Rgba.black, 0.12) else ctx.col(.accent), radius);
    d.text(dl, fam.get(.semibold), 14, sr.x + 16, d.centerY(sr, 14), if (can) ctx.col(.accent_text) else ctx.col(.faint), lbl);
    if (hb.clicked and can) {
        const gpa = ctx.st.gpa;
        const n = gpa.dupe(u8, std.mem.sliceTo(&name_buf, 0)) catch return;
        const p = gpa.dupe(u8, std.mem.sliceTo(&pronouns_buf, 0)) catch {
            gpa.free(n);
            return;
        };
        const b = gpa.dupe(u8, std.mem.sliceTo(&bio_buf, 0)) catch {
            gpa.free(n);
            gpa.free(p);
            return;
        };
        ctx.act(.{ .conta = .{ .save_profile = .{ .name = n, .pronouns = p, .bio = b } } });
        dirty = false;
    }
    yy += 52;
    y.* = yy;
}
