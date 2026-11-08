//! QA sem fonte nenhuma no sistema (QA_SUITE=sem-fontes). O tools/qa.sh roda com o
//! fontconfig numa configuração sem pasta de fontes; no Windows, WINDIR numa pasta sem
//! Fonts faz o mesmo. O app abre com a fonte que vem dentro do ImGui, mostra a conversa
//! e escreve nela, em vez de cair ao montar o primeiro quadro.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const fonts = @import("ui/fonts.zig");

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 5000 } };
}

/// Nenhuma família do sistema carregou, e a interface (texto e código) usa a embutida.
fn builtinInUse(app: *App) bool {
    const th = app.themes.theme_();
    if (app.fonts.families.items.len != 0) return false;
    const ui = app.uiFamily(th.font_ui);
    return std.mem.eql(u8, ui.name, fonts.builtin_name) and ui == app.uiFamily(th.font_mono);
}

/// A última mensagem da conversa aberta aparece desenhada (com a fonte embutida).
fn messageDrawn(app: *App) bool {
    const id = app.st.activeChannel() orelse return false;
    const cs = app.store.channel(id) orelse return false;
    const items = cs.messages.items;
    if (items.len == 0) return false;
    var b: [48]u8 = undefined;
    const mark = std.fmt.bufPrint(&b, "msgtext:{d}", .{items[items.len - 1].msg.id}) catch return false;
    return R.hasInk(app, mark);
}

const typed = "sem fontes, mas abre";

fn typedShown(app: *App) bool {
    return std.mem.eql(u8, std.mem.sliceTo(&app.st.input, 0), typed) and R.hasInk(app, "composer");
}

pub const ops = [_]Op{
    .{ .section = "sem fonte nenhuma no sistema" },
    expect("sem fonte do sistema, a do ImGui no lugar (texto e código)", builtinInUse),
    expect("a conversa aparece desenhada", messageDrawn),
    .{ .click = .{ .mark = "composer" } },
    .{ .text = typed },
    expect("o que é digitado aparece na caixa", typedShown),
    .{ .shot = "sem-fontes" },
    .{ .key = .{ .key = c.ImGuiKey_A, .ctrl = true } },
    .{ .key = .{ .key = c.ImGuiKey_Backspace } },
};
