//! QA da pasta do FFmpeg escolhida à mão e do diagnóstico sem FFmpeg (Configurações →
//! Chat → Vídeos). Roda na bateria "extras", com LARPER_NO_FFMPEG: as pastas em
//! qa-out/ffmpeg têm só arquivos vazios com os nomes das bibliotecas, nada carrega, e
//! o diagnóstico olha `ffmpeg.qa_path` em vez do PATH da máquina.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const ffmpeg = @import("platform/ffmpeg.zig");
const busca = @import("platform/ffmpeg_busca.zig");
const video = @import("ui/settings_video.zig");

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 3000 } };
}

const page_marks = [_][]const u8{ "pg:", "button:", "toggle:", "select:", "slider:", "seg:", "radio:" };
fn noOverlap(_: *App) bool {
    return qa.overlapping(&page_marks) == null;
}

const root = "qa-out/ffmpeg";
/// FFmpeg 6: uma versão que o app não conhece.
const old_set: busca.Set = .{ .lavf = 60, .lavc = 60, .lavu = 58, .sws = 7 };

fn touch(dir: []const u8, name: []const u8) void {
    var b: [256]u8 = undefined;
    const p = std.fmt.bufPrintSentinel(&b, "{s}/{s}/{s}", .{ root, dir, name }, 0) catch return;
    _ = c.SDL_SaveFile(p.ptr, "", 0);
}

fn addSet(dir: []const u8, set: busca.Set) void {
    for (std.enums.values(busca.Lib)) |lib| {
        var nb: [48]u8 = undefined;
        touch(dir, busca.libFile(&nb, busca.native, @tagName(lib), busca.major(set, lib)) orelse continue);
    }
}

/// estatico: só o ffmpeg; antigo: FFmpeg 6 inteiro; shared: FFmpeg 8 inteiro.
fn fixtures(_: *App) void {
    for ([_][:0]const u8{ root ++ "/estatico", root ++ "/antigo", root ++ "/shared" }) |dir| _ = c.SDL_CreateDirectory(dir.ptr);
    const exe = busca.exeName(busca.native);
    touch("estatico", exe);
    addSet("antigo", old_set);
    touch("antigo", exe);
    addSet("shared", busca.sets[1]);
    touch("shared", exe);
}

/// O que o seletor do sistema devolveria (no QA ele não abre).
fn pick(app: *App, comptime dir: []const u8) void {
    const z = std.heap.c_allocator.dupeSentinel(u8, root ++ "/" ++ dir, 0) catch return;
    app.picked.push(z);
}
fn pickStatic(app: *App) void {
    pick(app, "estatico");
}
fn pickOld(app: *App) void {
    pick(app, "antigo");
}
fn pickShared(app: *App) void {
    pick(app, "shared");
}

fn picking(_: *App) bool {
    return video.qaPicking();
}
fn refusedStatic(app: *App) bool {
    return app.st.settings.ffmpeg_dir.len == 0 and qa.find("ffmpeg-escolha:static_exe") != null;
}
fn refusedOld(app: *App) bool {
    return app.st.settings.ffmpeg_dir.len == 0 and qa.find("ffmpeg-escolha:unsupported") != null;
}
/// Guardada, ela é o primeiro lugar da procura: o diagnóstico já fala dela.
fn savedShared(app: *App) bool {
    return std.mem.eql(u8, app.st.settings.ffmpeg_dir.slice(), root ++ "/shared") and qa.find("ffmpeg-pasta") != null and
        qa.find("button:Esquecer a pasta") != null and qa.find("ffmpeg-diag:pasta:ok") != null and ffmpeg.known() == false;
}
fn forgotDir(app: *App) bool {
    return app.st.settings.ffmpeg_dir.len == 0 and qa.find("ffmpeg-pasta") == null and qa.find("ffmpeg-diag:pasta:ok") == null and ffmpeg.known() == false;
}

/// O PATH do diagnóstico: uma pasta só, pelo caminho inteiro (o relativo não conta).
var path_buf: [600]u8 = undefined;
fn pathTo(comptime dir: []const u8) void {
    const cwd = c.SDL_GetCurrentDirectory() orelse return;
    defer c.SDL_free(cwd);
    ffmpeg.qa_path = std.fmt.bufPrint(&path_buf, "{s}{s}/{s}", .{ std.mem.span(cwd), root, dir }) catch return;
    ffmpeg.forget();
    _ = ffmpeg.get();
}
fn staticOnPath(_: *App) void {
    pathTo("estatico");
}
fn oldOnPath(_: *App) void {
    pathTo("antigo");
}
fn noPath(_: *App) void {
    ffmpeg.qa_path = null;
    ffmpeg.forget();
    _ = ffmpeg.get();
}
fn diagStatic(_: *App) bool {
    return qa.find("ffmpeg-diag:estatico") != null and qa.find("ffmpeg-diag:procurei") != null and qa.find("button:Baixar FFmpeg") != null;
}
fn diagOld(_: *App) bool {
    return qa.find("ffmpeg-diag:versao:60") != null and qa.find("ffmpeg-diag:estatico") == null;
}
fn diagPlain(_: *App) bool {
    return qa.find("ffmpeg-diag:procurei") != null and qa.find("ffmpeg-diag:versao:60") == null and qa.find("ffmpeg-diag:estatico") == null;
}

/// Começa com Configurações → Chat aberto e o FFmpeg já procurado (sem achar).
pub const ops = [_]Op{
    s("pasta do FFmpeg escolhida à mão"),
    .{ .run = fixtures },
    click("button:Escolher a pasta do FFmpeg…"),
    expect("o botão pede a pasta ao sistema", picking),
    .{ .run = pickStatic },
    expect("só o ffmpeg: recusa e explica que é uma versão estática", refusedStatic),
    .{ .shot = "ffmpeg-pasta-estatica" },
    expect("nada se sobrepõe", noOverlap),
    click("button:Escolher a pasta do FFmpeg…"),
    .{ .run = pickOld },
    expect("FFmpeg 6: recusa e diz a versão e as que o app usa", refusedOld),
    click("button:Escolher a pasta do FFmpeg…"),
    .{ .run = pickShared },
    expect("versão shared conferida: guarda a pasta, que vira o primeiro lugar da procura", savedShared),
    .{ .shot = "ffmpeg-pasta-guardada" },
    expect("nada se sobrepõe", noOverlap),
    click("button:Esquecer a pasta"),
    expect("esquecer a pasta tira das configurações e da procura", forgotDir),

    s("diagnóstico sem FFmpeg"),
    .{ .run = staticOnPath },
    expect("o ffmpeg do PATH sem bibliotecas é explicado como versão estática, com o Baixar", diagStatic),
    .{ .shot = "ffmpeg-path-estatico" },
    expect("nada se sobrepõe", noOverlap),
    .{ .run = oldOnPath },
    expect("FFmpeg 6 no PATH: diz a versão e as que o app usa", diagOld),
    .{ .run = noPath },
    expect("sem nada: só os nomes procurados", diagPlain),
};
