//! Configurações → Rede: o proxy (tipo, endereço, porta, login e senha) e "usar
//! em tudo". O mesmo formulário aparece no cartão da tela de entrada (ui/login.zig),
//! para quem só chega ao Discord por um proxy poder entrar sem passar pela
//! demonstração. As configurações guardam uma URL só; `proxy.Form` monta e desmonta.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const S = @import("settings_state.zig");
const proxy = @import("../net/proxy.zig");

pub const Where = enum { settings, login };

/// Os campos do proxy (o QA confere o que foi preenchido).
pub var proxy_form: proxy.Form = .{};
/// A senha aparece em texto (o olho dentro do campo).
pub var proxy_show = false;
/// O valor das configurações que está nos campos (se mudar por fora, eles acompanham).
var proxy_seen: S.Text = .{};
var proxy_err: ?proxy.BuildError = null;

/// A página inteira.
pub fn page(p: anytype) void {
    p.title(i18n.tr("Rede", "Network"));
    p.heading("Proxy");
    form(p, .settings);
}

/// Colar a URL inteira no endereço espalha tudo pelos campos na hora. Digitando,
/// só ao salvar (senão "socks5h://h" já viraria campos no meio da digitação).
fn proxyAddressEdit(data: [*c]c.ImGuiInputTextCallbackData) callconv(.c) c_int {
    const len: usize = @intCast(data.*.BufTextLen);
    const before = std.mem.sliceTo(&proxy_form.host, 0).len;
    const io = c.ImGui_GetIO();
    const pasted = len >= before + 2 or ((io.*.KeyCtrl or io.*.KeySuper) and c.ImGui_IsKeyPressed(c.ImGuiKey_V)) or (io.*.KeyShift and c.ImGui_IsKeyPressed(c.ImGuiKey_Insert));
    if (!pasted) return 0;
    const text = data.*.Buf[0..len];
    if (std.mem.indexOf(u8, text, "://") == null and std.mem.indexOfScalar(u8, text, '@') == null) return 0;
    var tmp: [256]u8 = undefined;
    const n = @min(len, tmp.len);
    @memcpy(tmp[0..n], text[0..n]);
    if (!proxy_form.fill(tmp[0..n])) return 0;
    // No campo ativo, o texto é o do ImGui: troca por só o host.
    c.ImGuiInputTextCallbackData_DeleteChars(data, 0, data.*.BufTextLen);
    c.ImGuiInputTextCallbackData_InsertChars(data, 0, &proxy_form.host, null);
    proxy_err = null;
    return 0;
}

/// Um campo do formulário: rótulo em cima, caixa nas cores e nos cantos do tema.
/// `trail` reserva espaço à direita dentro da caixa (o olho da senha). true = Enter.
fn proxyField(p: anytype, r: d.Rect, label: []const u8, id: [:0]const u8, hint: [:0]const u8, buf: []u8, flags: c_int, bad: bool, mark: []const u8, trail: f32, cb: c.ImGuiInputTextCallback) bool {
    const ctx = p.ctx;
    d.text(p.dl, p.font(.bold), 12, r.x, r.y - 20, ctx.col(.muted), label);
    p.markText(.{ .x = r.x, .y = r.y - 20, .w = @min(d.width(p.font(.bold), 12, label), r.w), .h = 16 });
    d.rect(p.dl, r, ctx.col(.elevated), ctx.th.radius);
    c.ImGui_SetCursorScreenPos(d.v(r.x + 10, r.y + 3));
    c.ImGui_SetNextItemWidth(r.w - 20 - trail);
    const enter = c.ImGui_InputTextWithHintEx(id.ptr, hint.ptr, buf.ptr, buf.len, flags | c.ImGuiInputTextFlags_EnterReturnsTrue, cb, null);
    const active = c.ImGui_IsItemActive();
    d.border(p.dl, r, if (bad) ctx.col(.danger) else if (active) ctx.col(.accent).alpha(0.7) else ctx.col(.border), ctx.th.radius, 1);
    qa.mark(r, "{s}", .{mark});
    return enter;
}

fn eyeIcon(dl: *c.ImDrawList, cx: f32, cy: f32, col: d.Rgba, open: bool) void {
    c.ImDrawList_PathLineTo(dl, d.v(cx - 8, cy));
    c.ImDrawList_PathBezierQuadraticCurveTo(dl, d.v(cx, cy - 8), d.v(cx + 8, cy), 0);
    c.ImDrawList_PathBezierQuadraticCurveTo(dl, d.v(cx, cy + 8), d.v(cx - 8, cy), 0);
    c.ImDrawList_PathStroke(dl, col.u(), 1.6, 0);
    d.circle(dl, cx, cy, 2.4, col);
    if (!open) d.line(dl, cx - 6, cy - 6, cx + 6, cy + 6, col, 1.6);
}

/// O formulário. Na tela de entrada não há sessão para escolher o que passa pelo
/// proxy: salvar lá liga "usar em tudo", que é o que leva o login até o Discord.
pub fn form(p: anytype, where: Where) void {
    const ctx = p.ctx;
    const s = &ctx.st.settings;
    p.note(i18n.tr("Proxy HTTP, HTTPS, SOCKS5 ou SOCKS5h, com login e senha se ele pedir. Tor: SOCKS5h, 127.0.0.1, porta 9050. Colar a URL inteira no endereço preenche todos os campos.", "HTTP, HTTPS, SOCKS5 or SOCKS5h proxy, with a login and password if it asks for one. Tor: SOCKS5h, 127.0.0.1, port 9050. Pasting the full URL into the address fills in every field."));
    if (where == .login) p.note(i18n.tr("Aqui o proxy vale para tudo, inclusive para entrar no Discord. Depois dá para mudar em Configurações → Rede.", "Here the proxy is used for everything, including signing in to Discord. You can change it later in Settings → Network."));
    if (!std.mem.eql(u8, proxy_seen.slice(), s.proxy.slice())) {
        proxy_seen = s.proxy;
        proxy_form.load(s.proxy.slice());
        proxy_err = null;
    }
    const total = @min(p.w, 560);
    const gap: f32 = 12;

    // Tipo: o seletor tem a largura dos campos.
    d.text(p.dl, p.font(.bold), 12, p.x, p.y, ctx.col(.muted), i18n.tr("Tipo", "Type"));
    p.markText(.{ .x = p.x, .y = p.y, .w = d.width(p.font(.bold), 12, i18n.tr("Tipo", "Type")), .h = 16 });
    p.y += 22;
    const tor_wide = "SOCKS5h (Tor)";
    const tor = if (d.width(p.font(.semibold), 15, tor_wide) + 24 <= (total - 24) / 4) tor_wide else "SOCKS5h";
    const full_w = p.w;
    p.w = total;
    p.segmented(&.{ "HTTP", "HTTPS", "SOCKS5", tor }, &proxy_form.kind);
    p.w = full_w;

    // Endereço e porta (o campo com problema fica com a borda de perigo).
    const kind = proxy_form.kindOf();
    const err: proxy.BuildError = proxy_err orelse error.TooLong;
    const has_err = proxy_err != null;
    const port_w: f32 = if (total < 420) 84 else 110;
    p.y += 20;
    var row: d.Rect = .{ .x = p.x, .y = p.y, .w = total - gap - port_w, .h = 32 };
    var enter = proxyField(p, row, i18n.tr("Endereço", "Address"), "##proxy-host", "127.0.0.1", &proxy_form.host, c.ImGuiInputTextFlags_CharsNoBlank | c.ImGuiInputTextFlags_CallbackEdit, has_err and (err == error.NoHost or err == error.BadHost or err == error.TooLong), "proxy-input", 0, proxyAddressEdit);
    // A dica da porta é a que o curl usa quando ela fica vazia.
    var hint_buf: [8]u8 = undefined;
    const port_hint = std.fmt.bufPrintSentinel(&hint_buf, "{d}", .{kind.defaultPort()}, 0) catch "1080";
    const port_r: d.Rect = .{ .x = row.right() + gap, .y = p.y, .w = port_w, .h = 32 };
    enter = proxyField(p, port_r, i18n.tr("Porta", "Port"), "##proxy-port", port_hint, &proxy_form.port, c.ImGuiInputTextFlags_CharsDecimal | c.ImGuiInputTextFlags_CharsNoBlank, has_err and err == error.BadPort, "proxy-port", 0, null) or enter;
    p.y += 32 + 34;

    // Login e senha (a senha escondida, com o olho para conferir).
    const half = (total - gap) / 2;
    row = .{ .x = p.x, .y = p.y, .w = half, .h = 32 };
    enter = proxyField(p, row, i18n.tr("Login (opcional)", "Login (optional)"), "##proxy-user", "", &proxy_form.user, 0, has_err and err == error.PassWithoutUser, "proxy-user", 0, null) or enter;
    const pass_r: d.Rect = .{ .x = row.right() + gap, .y = p.y, .w = half, .h = 32 };
    const eye_w: f32 = 28;
    enter = proxyField(p, pass_r, i18n.tr("Senha (opcional)", "Password (optional)"), "##proxy-pass", "", &proxy_form.pass, if (proxy_show) 0 else c.ImGuiInputTextFlags_Password, false, "proxy-pass", eye_w, null) or enter;
    const eye_r: d.Rect = .{ .x = pass_r.right() - eye_w - 4, .y = pass_r.y + 2, .w = eye_w, .h = 28 };
    const he = d.hit(ctx, p.id(), eye_r);
    qa.mark(eye_r, "proxy-show", .{});
    if (he.clicked) proxy_show = !proxy_show;
    if (he.hovered) d.rect(p.dl, eye_r, ctx.col(.hover), ctx.th.radius);
    eyeIcon(p.dl, eye_r.x + eye_w / 2, eye_r.y + 14, if (he.hovered) ctx.col(.text) else ctx.col(.muted), proxy_show);
    d.tip(ctx, eye_r, if (proxy_show) i18n.tr("Esconder a senha", "Hide the password") else i18n.tr("Mostrar a senha", "Show the password"), he.hovered);
    p.y += 32 + 14;

    if (proxy_form.hidden_login) p.note(i18n.tr("O login e a senha salvos não couberam nos campos e ficaram escondidos. Para mudar o proxy, digite os dois de novo.", "The saved login and password didn't fit in the fields and are hidden. To change the proxy, type both again."));
    if (proxy_err) |e| p.note(switch (e) {
        error.NoHost => i18n.tr("Falta o endereço do proxy.", "The proxy address is missing."),
        error.BadHost => i18n.tr("Endereço inválido: só o nome ou o IP do proxy, ou cole a URL inteira (esquema://host:porta, com http, https, socks5 ou socks5h).", "Invalid address: just the proxy's name or IP, or paste the full URL (scheme://host:port, with http, https, socks5 or socks5h)."),
        error.BadPort => i18n.tr("Porta inválida: um número de 1 a 65535.", "Invalid port: a number from 1 to 65535."),
        error.PassWithoutUser => i18n.tr("Senha sem login: preencha o login também.", "Password without a login: fill in the login too."),
        error.TooLong => i18n.tr("Longo demais: a URL do proxy passa de 255 caracteres.", "Too long: the proxy URL goes over 255 characters."),
    });
    var nbuf: [360]u8 = undefined;
    if (s.proxy.len > 0 and !proxy.valid(s.proxy.slice())) {
        p.note(i18n.tr("O proxy salvo é inválido e está sendo ignorado.", "The saved proxy is invalid and is being ignored."));
    } else if (s.proxy.len > 0) {
        const scope = if (s.proxy_all) i18n.tr("todas as conexões", "every connection") else i18n.tr("só GIFs e mídia de fora do Discord", "only GIFs and media from outside Discord");
        // Sem usuário e senha na tela.
        const u = s.proxy.slice();
        var shown_buf: [256]u8 = undefined;
        const shown = if (std.mem.lastIndexOfScalar(u8, u, '@')) |at| (if (std.mem.indexOf(u8, u, "://")) |sch| std.fmt.bufPrint(&shown_buf, "{s}…@{s}", .{ u[0 .. sch + 3], u[at + 1 ..] }) catch u else u) else u;
        p.note(i18n.fmt(&nbuf, "Em uso: {s} ({s}).", "In use: {s} ({s}).", .{ shown, scope }));
    } else p.note(i18n.tr("Sem proxy: conexão direta.", "No proxy: direct connection."));
    const save_click = p.button(i18n.tr("Salvar proxy", "Save proxy"), false);
    if (s.proxy.len > 0) {
        p.sameLine();
        if (p.button(i18n.tr("Remover proxy", "Remove proxy"), true)) {
            s.proxy = .{};
            // Na tela de entrada não há "Fechar" que grave: grava agora.
            if (where == .login) ctx.act(.save_settings);
        }
    }
    if (enter or save_click) {
        // Endereço com a porta junto ou com a URL inteira digitada: vai para os campos.
        _ = proxy_form.absorbHost();
        var ub: proxy.Buf = undefined;
        if (proxy_form.empty()) {
            s.proxy = .{};
            proxy_err = null;
        } else if (proxy_form.build(&ub)) |url| {
            s.proxy.set(url);
            proxy_err = null;
            if (where == .login) s.proxy_all = true;
            ctx.st.showToast(ctx.now_ms, false, "proxy salvo", "proxy saved", .{});
        } else |e| {
            proxy_err = e;
            ctx.st.showToast(ctx.now_ms, true, "proxy inválido", "invalid proxy", .{});
        }
        if (where == .login) ctx.act(.save_settings);
    }
    if (where == .settings) p.toggle(i18n.tr("Usar o proxy em tudo", "Use the proxy for everything"), i18n.tr("Também o Discord: API, imagens, vídeos e o gateway (este a partir da próxima conexão). As calls de voz sempre conectam direto.", "Discord too: API, images, videos and the gateway (from the next connection). Voice calls always connect directly."), &s.proxy_all);
}
