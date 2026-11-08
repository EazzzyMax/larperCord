//! QA das letras de outras escritas (entra na bateria por tema do qa_runner.zig): as mensagens
//! em tailandês, devanágari, georgiano, armênio, grego, cirílico e amárico do #música do "Zig
//! Brasil" (net/fake_gateway.zig) aparecem sem "?" no lugar de letra, em todo tema. O que a
//! fonte do tema não tem vem de uma fonte do sistema, só com o bloco do Unicode da letra
//! (ui/fonts.zig); duas escritas do mesmo arquivo (tailandês e etíope na FreeSerif) dividem a
//! mesma fonte no atlas. Sem moldagem: o devanágari e o tailandês saem letra a letra, mas com
//! as letras de verdade.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const fonts = @import("ui/fonts.zig");
const types = @import("core/types.zig");

extern fn larper_font_draws(font: *c.ImFont, size: f32, cp: c_uint) bool;

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

/// O canal em que a bateria estava, para voltar no fim.
var home: types.Id = 0;

fn toScripts(app: *App) void {
    home = app.st.activeChannel() orelse 0;
    app.handle(.{ .open_message = .{ .channel = gw.scripts_channel, .id = 0 } });
    app.st.scrollOf(gw.scripts_channel).stick_bottom = true;
}

fn scriptsReady(app: *App) bool {
    if (app.st.activeChannel() != gw.scripts_channel) return false;
    const cs = app.store.channel(gw.scripts_channel) orelse return false;
    return cs.history == .loaded;
}

/// As mensagens das outras escritas estão desenhadas neste quadro.
fn allShown(app: *App) bool {
    const cs = app.store.channel(gw.scripts_channel) orelse return false;
    for (gw.scripts_texts) |text| {
        const m = for (cs.messages.items) |*m| {
            if (std.mem.eql(u8, m.msg.content, text)) break m;
        } else return false;
        var b: [64]u8 = undefined;
        const mark = std.fmt.bufPrint(&b, "msgtext:{d}", .{m.msg.id}) catch return false;
        if (qa.find(mark) == null) return false;
    }
    return true;
}

/// Toda letra das mensagens sai de alguma fonte em todas as fontes do atlas (a do tema mais as
/// reservas, respeitando o bloco de cada uma), e nenhuma ficou na lista das sem fonte: nada de
/// "?". Um sistema sem fonte nenhuma para a escrita (procurou e não achou) não tem o que mesclar.
fn noQuestionMarks(app: *App) bool {
    for (gw.scripts_texts) |t| {
        var it = (std.unicode.Utf8View.init(t) catch return false).iterator();
        while (it.nextCodepoint()) |cp| {
            if (cp < 0x80 or cp == 0xB7 or noSystemFont(app, cp)) continue;
            for (app.fonts.faces.items) |e| if (!larper_font_draws(e.font, 16, cp)) return false;
        }
    }
    for (fonts.missingLetters()) |cp| {
        for (gw.scripts_texts) |t| if (contains(t, cp) and !noSystemFont(app, cp)) return false;
    }
    return true;
}

fn contains(text: []const u8, cp: u32) bool {
    var it = (std.unicode.Utf8View.init(text) catch return false).iterator();
    while (it.nextCodepoint()) |x| if (x == cp) return true;
    return false;
}

fn noSystemFont(app: *App, cp: u32) bool {
    const b = fonts.blockOf(cp) orelse return false;
    return app.fonts.triedBlock(b) and !app.fonts.hasBlock(b);
}

fn goHome(app: *App) void {
    if (home != 0) app.handle(.{ .open_message = .{ .channel = home, .id = 0 } });
}

fn atHome(app: *App) bool {
    return home == 0 or app.st.activeChannel() == home;
}

pub const ops_theme = [_]Op{
    .{ .section = "letras de outras escritas" },
    run(toScripts),
    expect("o #música do Zig Brasil abre", scriptsReady),
    .{ .wait = 400 },
    expect("as mensagens em tailandês, devanágari, georgiano, armênio, grego, cirílico e amárico aparecem", allShown),
    expect("nenhuma dessas letras vira ? quando o sistema tem fonte para ela", noQuestionMarks),
    .{ .shot = "fontes" },
    run(goHome),
    expect("volta para o canal de antes", atHome),
};
