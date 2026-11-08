//! QA das primitivas novas dos temas (entra na bateria por tema do qa_runner.zig):
//! textura gerada uma vez, tema parado que não pede quadros, movimento lento que
//! obedece a "reduzir movimento" e as marcas de cada tema que usa alguma coisa.
//! Também a prévia da resposta a uma mensagem sem texto, em cada tema.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const fx = @import("ui/fx.zig");
const anim = @import("ui/anim.zig");
const extra = @import("ui/comp_extra.zig");
const messages = @import("ui/comp_messages.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const reply_preview = @import("core/reply_preview.zig");

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f } };
}

var generated0: u32 = 0;
var wakes0: u32 = 0;

fn remember(_: *App) void {
    generated0 = fx.generated;
    wakes0 = fx.motion_wakes;
}

fn noNewTexture(_: *App) bool {
    return fx.generated == generated0;
}

fn noMotionWake(_: *App) bool {
    return fx.motion_wakes == wakes0;
}

/// Ao redimensionar, refaz só o que depende do tamanho: uma vez, não por quadro.
fn fewNewTextures(_: *App) bool {
    return fx.generated -% generated0 <= 4;
}

fn themeIs(app: *App, name: []const u8) bool {
    return std.mem.eql(u8, app.themes.name(), name);
}

/// Os prints deste tema usam mesmo as primitivas (se ele for um dos que usam).
fn themeMarks(app: *App) bool {
    if (themeIs(app, "orbital")) {
        const word = qa.find("display:ORBITAL") orelse return false;
        // Tracking de verdade: 7 letras mono de 15 px mais 6 × 8 de espaço.
        if (word.w < 95) return false;
        const run = qa.find("display:01") orelse return false;
        if (run.w < 60) return false; // "01" grande + "CANAIS" espaçado na mesma linha
        return qa.find("backdrop:starfield") != null and qa.find("backdrop:orbit") != null and
            qa.find("shape:arc") != null and qa.find("rule:dashed") != null and fx.live_entries > 0;
    }
    if (themeIs(app, "editorial")) {
        return qa.find("display:larperCord") != null and qa.find("rule:oxford") != null and
            qa.find("rule:double") != null and fx.live_entries > 0;
    }
    if (themeIs(app, "cupertino")) {
        return qa.find("backdrop:dunes") != null and qa.find("winctl:close") != null and
            qa.find("winctl:minimize") != null and qa.find("winctl:zoom") != null;
    }
    if (themeIs(app, "vidro")) return qa.find("backdrop:aurora") != null and fx.live_entries > 0;
    return true;
}

fn setMotion(app: *App, on: bool) void {
    if (!themeIs(app, "orbital")) return;
    if (app.themes.setOption("movimento", on)) {}
}

fn motionOn(app: *App) void {
    setMotion(app, true);
    wakes0 = fx.motion_wakes;
}

fn motionOff(app: *App) void {
    setMotion(app, false);
    wakes0 = fx.motion_wakes;
}

/// Pediu quadro, e não mais que 15 por segundo.
fn motionWakes(app: *App) bool {
    if (!themeIs(app, "orbital")) return true;
    if (fx.motion_wakes == wakes0) return false;
    return anim.next_wake_ms - anim.now_ms <= 100 and fx.last_period_ms >= 66;
}

fn reduceOn(app: *App) void {
    app.st.settings.reduce_motion = true;
}

fn reduceOff(app: *App) void {
    app.st.settings.reduce_motion = false;
}

fn reducedStill(app: *App) bool {
    _ = app;
    return fx.motion_wakes == wakes0;
}

fn rememberWakes(_: *App) void {
    wakes0 = fx.motion_wakes;
}

/// `hover-bg` do painel do orbital acende com o mouse em cima.
fn hoverLit(app: *App) bool {
    return !themeIs(app, "orbital") or fx.hover_seen > 0.9;
}

// Os botões da janela: fechar conta (no QA não sai de verdade), maximizar pede
// ao sistema e não pode quebrar a tela. Outros temas não têm a marca: o robô pula.
var closes0: u32 = 0;

fn rememberCloses(_: *App) void {
    closes0 = extra.qa_close_requests;
}

fn tWinClose(app: *App, b: []u8) []const u8 {
    if (!themeIs(app, "cupertino")) return "";
    return std.fmt.bufPrint(b, "winctl:close", .{}) catch "";
}

fn tWinZoom(app: *App, b: []u8) []const u8 {
    if (!themeIs(app, "cupertino")) return "";
    return std.fmt.bufPrint(b, "winctl:zoom", .{}) catch "";
}

fn closeRequested(app: *App) bool {
    return !themeIs(app, "cupertino") or extra.qa_close_requests == closes0 + 1;
}

fn stillUsable(app: *App) bool {
    return app.store.ready and qa.find("composer") != null;
}

pub const ops_window = [_]Op{
    .{ .run = rememberCloses },
    .{ .click = .{ .dyn = tWinClose } },
    expect("o botão de fechar pede para sair", closeRequested),
    .{ .click = .{ .dyn = tWinZoom } },
    .{ .wait = 150 },
    expect("maximizar não quebra a tela", stillUsable),
    .{ .click = .{ .dyn = tWinZoom } },
    .{ .wait = 150 },
    expect("restaurar não quebra a tela", stillUsable),
};

fn settingsInReach(_: *App) bool {
    return qa.find("user-btn:2") != null or qa.find("header-settings") != null;
}

pub const ops_static = [_]Op{
    expect("primitivas do tema estão na tela", themeMarks),
    expect("o botão de configurações está à vista", settingsInReach),
    .{ .hover = .{ .mark = "composer" } },
    .{ .wait = 400 },
    expect("fundo no hover acende", hoverLit),
    .{ .run = remember },
    .{ .wait = 250 },
    expect("textura gerada uma vez, não por quadro", noNewTexture),
    expect("tema parado não pede quadros", noMotionWake),
};

pub const ops_motion = [_]Op{
    .{ .run = motionOn },
    .{ .wait = 120 },
    expect("fundo em movimento pede no máximo 15 quadros/s", motionWakes),
    .{ .run = reduceOn },
    .{ .wait = 50 },
    .{ .run = rememberWakes },
    .{ .wait = 150 },
    expect("\"reduzir movimento\" para o fundo", reducedStill),
    .{ .run = reduceOff },
    .{ .run = motionOff },
    .{ .wait = 50 },
    .{ .run = remember },
    .{ .wait = 120 },
    expect("desligou o movimento: parado de novo", noMotionWake),
};

pub const ops_resize_before = [_]Op{.{ .run = remember }};
pub const ops_resize_after = [_]Op{expect("redimensionar refaz só o que depende do tamanho", fewNewTextures)};

// --- Prévia da resposta a uma mensagem sem texto -----------------------------------
// No #zig da demonstração (fake_gateway.zig `demoReplyPreviews`) há respostas a um
// arquivo sozinho, a uma mensagem de voz, a uma figurinha, a uma imagem e a um
// cartão de bot. A linha da resposta mostra o ícone e o que a original tem (nos
// temas de terminal, a etiqueta entre colchetes), e o clique nela leva à original.

var reply_id: types.Id = 0;
var orig_id: types.Id = 0;

fn zigLoaded(app: *App) bool {
    const cs = app.store.channel(gw.reply_preview_channel) orelse return false;
    return app.st.activeChannel() == gw.reply_preview_channel and cs.history == .loaded;
}

/// Temas só de texto: a prévia vem sem ícone.
fn textOnly(app: *App) bool {
    return themeIs(app, "terminal") or themeIs(app, "subsolo");
}

/// Vai até a resposta cuja original (sem texto) é do tipo `kind`.
fn jumpToReply(app: *App, kind: reply_preview.Kind) void {
    reply_id = 0;
    const cs = app.store.channel(gw.reply_preview_channel) orelse return;
    for (cs.messages.items) |*m| {
        if (m.msg.reply_to == 0) continue;
        const f = app.store.find(cs, m.msg.reply_to) orelse continue;
        const lb = reply_preview.of(&f.msg);
        if (lb.kind != kind) continue;
        if (kind == .file and !std.mem.eql(u8, lb.text, gw.reply_preview_file)) continue;
        reply_id = m.msg.id;
        orig_id = f.msg.id;
        app.handle(.{ .jump_to = reply_id });
        return;
    }
}
fn toFile(app: *App) void {
    jumpToReply(app, .file);
}
fn toVoice(app: *App) void {
    jumpToReply(app, .voice);
}
fn toSticker(app: *App) void {
    jumpToReply(app, .sticker);
}
fn toImage(app: *App) void {
    jumpToReply(app, .image);
}
fn toEmbed(app: *App) void {
    jumpToReply(app, .embed);
}

/// A linha da resposta tem a marca do tipo e o ícone desenhado (no terminal,
/// sem ícone e com a etiqueta em texto).
fn kindShown(app: *App, kind: reply_preview.Kind) bool {
    if (reply_id == 0) return false;
    var kb: [64]u8 = undefined;
    const k = std.fmt.bufPrint(&kb, "reply-kind:{d}:{s}", .{ reply_id, @tagName(kind) }) catch return false;
    if (qa.find(k) == null) return false;
    var ib: [48]u8 = undefined;
    const icon = std.fmt.bufPrint(&ib, "reply-icon:{d}", .{reply_id}) catch return false;
    const has_icon = qa.find(icon) != null;
    // Embed mostra o título, sem ícone.
    if (kind == .embed or textOnly(app)) return !has_icon and R.hasInk(app, k);
    return has_icon and R.hasInk(app, icon);
}
fn fileShown(app: *App) bool {
    return kindShown(app, .file);
}
fn voiceShown(app: *App) bool {
    return kindShown(app, .voice);
}
fn stickerShown(app: *App) bool {
    return kindShown(app, .sticker);
}
fn imageShown(app: *App) bool {
    return kindShown(app, .image);
}
fn embedShown(app: *App) bool {
    return kindShown(app, .embed);
}

fn tReplyLine(_: *App, b: []u8) []const u8 {
    return std.fmt.bufPrint(b, "reply-line:{d}", .{reply_id}) catch "";
}
fn jumpedToOriginal(app: *App) bool {
    var b: [40]u8 = undefined;
    const m = std.fmt.bufPrint(&b, "msg:{d}", .{orig_id}) catch return false;
    return app.st.jump == 0 and messages.jumpedTo() == orig_id and qa.find(m) != null;
}
fn backToBottom(app: *App) void {
    app.st.scrollOf(gw.reply_preview_channel).stick_bottom = true;
}

pub const ops_reply = [_]Op{
    .{ .expect = .{ .name = "o #zig abre com as respostas da demonstração", .check = zigLoaded, .timeout_ms = 4000 } },
    .{ .run = toVoice },
    expect("resposta a uma mensagem de voz: microfone e \"Mensagem de voz\"", voiceShown),
    .{ .run = toSticker },
    expect("resposta a uma figurinha: ícone e o nome dela", stickerShown),
    .{ .run = toImage },
    expect("resposta a uma imagem: ícone e \"Clique para ver o anexo\"", imageShown),
    .{ .run = toEmbed },
    expect("resposta a um cartão de bot: o título dele", embedShown),
    .{ .run = toFile },
    expect("resposta a um arquivo sozinho: ícone e o nome do arquivo", fileShown),
    // O destaque do pulo apaga antes do print.
    .{ .wait = 1700 },
    .{ .shot = "resposta" },
    .{ .click = .{ .dyn = tReplyLine } },
    expect("o clique na prévia leva ao arquivo", jumpedToOriginal),
    .{ .run = backToBottom },
};
