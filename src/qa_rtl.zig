//! QA do texto da direita para a esquerda (entra na bateria por tema do qa_runner.zig): as
//! mensagens em árabe e hebraico do #música da demonstração (net/fake_gateway.zig) aparecem
//! com as letras ligadas e sem "?" no lugar de letra, em todo tema (o terminal usa uma fonte
//! mono sem árabe: as letras vêm das fontes reserva). Selecionar e copiar devolvem o texto
//! como foi escrito, não a ordem da tela.
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
/// sem fonte nenhuma da escrita (procurou e não achou) não tem o que mesclar.
fn noQuestionMarks(app: *App) bool {
    for ([_][]const u8{ gw.rtl_arabic, gw.rtl_hebrew, mixed_rtl }) |t| {
        const v = bidi.visual(t) orelse return false;
        var it = (std.unicode.Utf8View.init(v) catch return false).iterator();
        while (it.nextCodepoint()) |cp| {
            if (!bidi.isRtl(cp) or noSystemFont(app, cp)) continue;
            for (app.fonts.faces.items) |e| if (!c.ImFont_IsGlyphInFont(e.font, cp)) return false;
        }
    }
    for (fonts.missingLetters()) |cp| if (bidi.isRtl(cp) and !noSystemFont(app, cp)) return false;
    return true;
}

fn noSystemFont(app: *App, cp: u32) bool {
    const g = fonts.groupOf(cp) orelse return false;
    return app.fonts.triedGroup(g) and !app.fonts.hasGroup(g);
}

/// Arrastar da direita da frase até depois do fim dela, à esquerda, pega a mensagem inteira:
/// na tela o começo está à direita, mas os índices são os do texto.
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

fn clearToast(app: *App) void {
    app.st.toast.len = 0;
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
    .{ .shot = "rtl" },
    run(clearToast),
    .{ .drag = .{ .from = .{ .dyn_at = .{ .f = tArabic, .fx = 1.02, .fy = 0.5 } }, .to = .{ .dyn_at = .{ .f = tArabic, .fx = -0.02, .fy = 0.5 } } } },
    expect("arrastar da direita para a esquerda seleciona a mensagem inteira", wholeSelected),
    .{ .shot = "rtl-selecao" },
    .{ .key = .{ .key = c.ImGuiKey_C, .ctrl = true } },
    expect("copiar devolve o texto como foi escrito", copiedLogical),
    .{ .key = .{ .key = c.ImGuiKey_Escape } },
    run(goHome),
    expect("volta para o canal de antes", atHome),
};
