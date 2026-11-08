//! QA do texto da direita para a esquerda (entra na bateria por tema do qa_runner.zig): as
//! mensagens em árabe e hebraico do #música da demonstração (net/fake_gateway.zig) aparecem
//! com as letras ligadas e sem "?" no lugar de letra, em todo tema (o terminal usa uma fonte
//! mono sem árabe: as letras vêm das fontes reserva). O parágrafo da direita para a esquerda
//! termina na borda direita da coluna do texto (no balão, na do balão) e o latino continua à
//! esquerda, também numa mensagem com os dois. Selecionar e copiar devolvem o texto como foi
//! escrito, não a ordem da tela, e o link no meio do árabe abre.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const bidi = @import("ui/bidi.zig");
const fonts = @import("ui/fonts.zig");
const types = @import("core/types.zig");
const StoredMessage = @import("core/store.zig").StoredMessage;
const Rect = @import("theme/layout.zig").Rect;
const att = @import("ui/attachments.zig");

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

/// O trecho em árabe da frase em português (a do embed tem o mesmo nome e título).
const mixed_rtl = "فيروز - كيفك إنت";

/// O canal em que a bateria estava, para voltar no fim.
var home: types.Id = 0;

fn toMusic(app: *App) void {
    home = app.st.activeChannel() orelse 0;
    app.handle(.{ .open_message = .{ .channel = gw.rtl_channel, .id = 0 } });
    app.st.scrollOf(gw.rtl_channel).stick_bottom = true;
}

fn musicReady(app: *App) bool {
    if (app.st.activeChannel() != gw.rtl_channel) return false;
    const cs = app.store.channel(gw.rtl_channel) orelse return false;
    return cs.history == .loaded;
}

fn msgWith(app: *App, text: []const u8) ?*const StoredMessage {
    const cs = app.store.channel(gw.rtl_channel) orelse return null;
    for (cs.messages.items) |*m| if (std.mem.eql(u8, m.msg.content, text)) return m;
    return null;
}

fn textMark(app: *App, buf: []u8, text: []const u8) []const u8 {
    const m = msgWith(app, text) orelse return "";
    return std.fmt.bufPrint(buf, "msgtext:{d}", .{m.msg.id}) catch "";
}

fn tArabic(app: *App, buf: []u8) []const u8 {
    return textMark(app, buf, gw.rtl_arabic);
}

/// As duas mensagens estão desenhadas neste quadro.
fn bothShown(app: *App) bool {
    var b: [64]u8 = undefined;
    if (qa.find(textMark(app, &b, gw.rtl_arabic)) == null) return false;
    return qa.find(textMark(app, &b, gw.rtl_hebrew)) != null;
}

/// O que vai para a tela tem as formas ligadas do árabe (lam-alef, inicial, medial, final).
fn shaped(_: *App) bool {
    const v = bidi.visual(gw.rtl_arabic) orelse return false;
    return std.mem.indexOf(u8, v, "\u{FEFC}") != null and std.mem.indexOf(u8, v, "\u{FEDF}") != null;
}

/// Toda letra RTL que vai para a tela existe em todas as fontes do atlas (a do tema mais as
/// reservas), e nenhuma ficou na lista das sem fonte: nada de "?". Como no CJK: um sistema
/// sem fonte nenhuma da escrita (procurou e não achou) não tem o que mesclar. Uma face que
/// nenhum texto da tela usou e que não tem a letra (no Windows, o itálico do Segoe UI sem o
/// árabe que o normal tem) pede as reservas como o desenho pediria, e a conferência espera
/// o próximo quadro: depois disso, ou a letra está lá, ou a escrita já foi procurada e falha.
fn noQuestionMarks(app: *App) bool {
    for ([_][]const u8{ gw.rtl_arabic, gw.rtl_hebrew, mixed_rtl }) |t| {
        const v = bidi.visual(t) orelse return false;
        var it = (std.unicode.Utf8View.init(v) catch return false).iterator();
        while (it.nextCodepoint()) |cp| {
            if (!bidi.isRtl(cp) or noSystemFont(app, cp)) continue;
            for (app.fonts.faces.items) |e| if (!c.ImFont_IsGlyphInFont(e.font, cp)) {
                fonts.request(cp);
                return false;
            };
        }
    }
    for (fonts.missingLetters()) |cp| if (bidi.isRtl(cp) and !noSystemFont(app, cp)) return false;
    return true;
}

fn noSystemFont(app: *App, cp: u32) bool {
    const g = fonts.groupOf(cp) orelse return false;
    return app.fonts.triedGroup(g) and !app.fonts.hasGroup(g);
}

/// Arrastar do começo da frase (à direita) até depois do fim dela, à esquerda, pega a
/// mensagem inteira: na tela o começo está à direita, mas os índices são os do texto.
fn wholeSelected(app: *App) bool {
    const m = msgWith(app, gw.rtl_arabic) orelse return false;
    const sel = &app.st.selection;
    if (sel.a_id != m.msg.id or sel.b_id != m.msg.id) return false;
    return @min(sel.a_off, sel.b_off) == 0 and @max(sel.a_off, sel.b_off) == m.msg.content.len;
}

/// O que foi copiado é o texto como foi escrito (ordem lógica, sem as formas de apresentação).
fn copiedLogical(_: *App) bool {
    const got = c.SDL_GetClipboardText() orelse return false;
    defer c.SDL_free(got);
    return std.mem.eql(u8, std.mem.span(got), gw.rtl_arabic);
}

/// Tira o aviso (o "copiado ✓") da tela de uma vez: sem texto e já saindo.
fn clearToast(app: *App) void {
    app.st.toast.len = 0;
    app.st.toast.until_ms = 0;
}

// --- Alinhamento -------------------------------------------------------------------------

/// A coluna do texto da mensagem: de onde ele começa até a borda direita (ui/comp_messages.zig).
fn colOf(id: types.Id) ?Rect {
    var b: [64]u8 = undefined;
    return qa.find(std.fmt.bufPrint(&b, "msgcol:{d}", .{id}) catch return null);
}

/// A linha `n` do texto, onde foi desenhada (ui/rich.zig marca as de texto com letra RTL).
fn lineOf(id: types.Id, n: usize) ?Rect {
    var b: [64]u8 = undefined;
    return qa.find(std.fmt.bufPrint(&b, "text-line:{d}:{d}", .{ id, n }) catch return null);
}

fn near(a: f32, b: f32) bool {
    return @abs(a - b) <= 1;
}

/// Toda linha da mensagem a partir da `from` termina na borda direita da coluna (até 1 px).
fn linesRight(id: types.Id, from: usize) bool {
    const col = colOf(id) orelse return false;
    var n = from;
    while (lineOf(id, n)) |l| : (n += 1) {
        if (!near(l.right(), col.right())) return false;
    }
    return n > from;
}

fn rightAligned(app: *App, text: []const u8) bool {
    const m = msgWith(app, text) orelse return false;
    return linesRight(m.msg.id, 0);
}

fn arabicRight(app: *App) bool {
    return rightAligned(app, gw.rtl_arabic);
}

fn hebrewRight(app: *App) bool {
    return rightAligned(app, gw.rtl_hebrew);
}

/// A mensagem sem letra RTL mais recente na tela fica como sempre: começando na coluna, sem
/// passar pela ordem visual.
fn latinLeft(app: *App) bool {
    const cs = app.store.channel(gw.rtl_channel) orelse return false;
    var i = cs.messages.items.len;
    while (i > 0) {
        i -= 1;
        const m = &cs.messages.items[i];
        if (m.msg.content.len == 0 or bidi.hasRtl(m.msg.content)) continue;
        var b: [64]u8 = undefined;
        const t = qa.find(std.fmt.bufPrint(&b, "msgtext:{d}", .{m.msg.id}) catch return false) orelse continue;
        const col = colOf(m.msg.id) orelse continue;
        return near(t.x, col.x) and lineOf(m.msg.id, 0) == null;
    }
    return false;
}

/// A barra de ações da mensagem em árabe está na tela e não cobre o começo dela (a ponta
/// direita da primeira linha): nos temas de terminal ela fica em cima da linha do texto.
fn startUncovered(app: *App) bool {
    const m = msgWith(app, gw.rtl_arabic) orelse return false;
    const l = lineOf(m.msg.id, 0) orelse return false;
    const px = l.right() - 2;
    const py = l.y + l.h / 2;
    var seen = false;
    var b: [64]u8 = undefined;
    for (0..8) |k| {
        const r = qa.find(std.fmt.bufPrint(&b, "tb:{d}:{d}", .{ m.msg.id, k }) catch return false) orelse continue;
        seen = true;
        if (r.contains(px, py)) return false;
    }
    return seen;
}

/// A mensagem com um parágrafo latino e outro em árabe (com o link no meio).
fn mixedMsg(app: *App) ?*const StoredMessage {
    const cs = app.store.channel(gw.rtl_channel) orelse return null;
    for (cs.messages.items) |*m| if (std.mem.endsWith(u8, m.msg.content, gw.rtl_mixed_arabic)) return m;
    return null;
}

fn tMixed(app: *App, buf: []u8) []const u8 {
    const m = mixedMsg(app) orelse return "";
    return std.fmt.bufPrint(buf, "msgtext:{d}", .{m.msg.id}) catch "";
}

fn showMixed(app: *App) void {
    if (mixedMsg(app)) |m| app.st.jump = m.msg.id;
}

fn mixedShown(app: *App) bool {
    const m = mixedMsg(app) orelse return false;
    return app.st.jump == 0 and lineOf(m.msg.id, 1) != null;
}

/// O parágrafo latino (a primeira linha) começa na coluna; cada linha do árabe termina na
/// borda direita.
fn mixedAligned(app: *App) bool {
    const m = mixedMsg(app) orelse return false;
    const col = colOf(m.msg.id) orelse return false;
    const first = lineOf(m.msg.id, 0) orelse return false;
    return near(first.x, col.x) and linesRight(m.msg.id, 1);
}

fn mixedSelected(app: *App) bool {
    const m = mixedMsg(app) orelse return false;
    const sel = &app.st.selection;
    if (sel.a_id != m.msg.id or sel.b_id != m.msg.id) return false;
    return @min(sel.a_off, sel.b_off) == 0 and @max(sel.a_off, sel.b_off) == m.msg.content.len;
}

fn mixedCopied(app: *App) bool {
    const m = mixedMsg(app) orelse return false;
    const got = c.SDL_GetClipboardText() orelse return false;
    defer c.SDL_free(got);
    return std.mem.eql(u8, std.mem.span(got), m.msg.content);
}

fn tMixedLink(_: *App, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "link:{s}", .{gw.rtl_link}) catch "";
}

fn clearOpened(_: *App) void {
    att.last_opened_len = 0;
}

fn linkOpened(_: *App) bool {
    return std.mem.eql(u8, att.last_opened[0..att.last_opened_len], gw.rtl_link);
}

fn goHome(app: *App) void {
    if (home != 0) app.handle(.{ .open_message = .{ .channel = home, .id = 0 } });
}

fn atHome(app: *App) bool {
    return home == 0 or app.st.activeChannel() == home;
}

pub const ops_theme = [_]Op{
    .{ .section = "árabe e hebraico" },
    run(toMusic),
    expect("o #música abre", musicReady),
    .{ .wait = 400 },
    expect("as mensagens em árabe e hebraico aparecem", bothShown),
    expect("o árabe vai para a tela com as letras ligadas", shaped),
    expect("nenhuma letra árabe ou hebraica sem fonte (nada de ?)", noQuestionMarks),
    expect("o árabe termina na borda direita da coluna", arabicRight),
    expect("o hebraico termina na borda direita da coluna", hebrewRight),
    expect("a mensagem em português continua à esquerda", latinLeft),
    .{ .hover = .{ .dyn_at = .{ .f = tArabic, .fx = 0.5, .fy = 0.5 } } },
    expect("com o mouse em cima, a barra de ações não cobre o começo do árabe", startUncovered),
    // Para o print: o mouse acima da janela, sem a barra de ações de uma mensagem por cima.
    .{ .hover = .{ .dyn_at = .{ .f = tArabic, .fx = 0.5, .fy = -60 } } },
    .{ .shot = "rtl" },
    run(clearToast),
    // Da borda direita da frase (onde ela começa; logo à direita, nos temas de terminal, já é
    // a faixa da barra de rolagem) até depois do fim, à esquerda.
    .{ .drag = .{ .from = .{ .dyn_at = .{ .f = tArabic, .fx = 1.0, .fy = 0.5 } }, .to = .{ .dyn_at = .{ .f = tArabic, .fx = -0.02, .fy = 0.5 } } } },
    expect("arrastar da direita para a esquerda seleciona a mensagem inteira", wholeSelected),
    .{ .shot = "rtl-selecao" },
    .{ .key = .{ .key = c.ImGuiKey_C, .ctrl = true } },
    expect("copiar devolve o texto como foi escrito", copiedLogical),
    .{ .key = .{ .key = c.ImGuiKey_Escape } },
    run(showMixed),
    expect("a mensagem com um parágrafo latino e outro árabe aparece", mixedShown),
    .{ .wait = 600 },
    expect("na mensagem mista, o latino fica à esquerda e o árabe termina na direita", mixedAligned),
    // Do começo do latino (à esquerda da primeira linha) até o fim do árabe (à esquerda da
    // última linha, que é onde ele acaba na tela).
    .{ .drag = .{ .from = .{ .dyn_at = .{ .f = tMixed, .fx = -0.02, .fy = 0.12 } }, .to = .{ .dyn_at = .{ .f = tMixed, .fx = -0.02, .fy = 0.92 } } } },
    expect("arrastar seleciona a mensagem mista inteira", mixedSelected),
    .{ .key = .{ .key = c.ImGuiKey_C, .ctrl = true } },
    expect("copiar a mista devolve o texto como foi escrito", mixedCopied),
    .{ .key = .{ .key = c.ImGuiKey_Escape } },
    run(clearOpened),
    .{ .click = .{ .dyn = tMixedLink } },
    expect("o link no meio do árabe abre", linkOpened),
    // Print sem o aviso do copiar, sem o mouse em cima e depois do destaque do pulo (1,6 s).
    run(clearToast),
    .{ .hover = .{ .dyn_at = .{ .f = tMixed, .fx = 0.5, .fy = -60 } } },
    .{ .wait = 1000 },
    .{ .shot = "rtl-mista" },
    run(goHome),
    expect("volta para o canal de antes", atHome),
};
