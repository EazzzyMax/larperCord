//! A demonstração no navegador: o larperCord de verdade com os dados de mentira
//! (net/fake_gateway.zig), sem rede, sem conta e sem threads. O Emscripten liga isto
//! ao canvas da página e chama `quadro` a cada requestAnimationFrame (ver
//! `App.webFrame`); o `App.run` de sempre, que dorme esperando evento, não entra.
//! Fora do Emscripten (zig build web-sim) o mesmo caminho roda numa janela comum,
//! para conferir sem navegador. Ver tools/web/README.md.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const app_mod = @import("app.zig");
const App = app_mod.App;

/// Liga `sys.web` em todo o app (ver platform/sys.zig).
pub const larper_web = true;

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = @import("platform/debug_log.zig").logFn,
};
pub const panic = if (builtin.mode == .debug) std.debug.FullPanic(std.debug.defaultPanic) else std.debug.simple_panic;

const emscripten = builtin.os.tag == .emscripten;

/// Onde ficam as fontes da página: /fonts no sistema de arquivos do Emscripten
/// (o --preload-file do passo `web`), ou a pasta do --fonts no web-sim.
pub var fonts_dir: []const u8 = "/fonts";

var app: ?*App = null;
var loop: App.WebLoop = .{};

fn quadro() callconv(.c) void {
    const a = app orelse return;
    if (!a.webFrame(&loop)) {
        if (emscripten) c.emscripten_cancel_main_loop();
    }
}

/// A página mudou o espaço do canvas (em pixels CSS).
export fn larper_web_resize(w: c_int, h: c_int) void {
    const a = app orelse return;
    if (w > 0 and h > 0) _ = c.SDL_SetWindowSize(a.win.window, w, h);
}

pub fn main(init: std.process.Init.Minimal) !void {
    // A página e o web-sim são sempre a demonstração: não existe outro jeito de abrir.
    var opts: app_mod.Options = .{ .demo = true };
    var it = std.process.Args.Iterator.init(init.args);
    _ = it.skip();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--lang")) {
            const l = it.next() orelse break;
            opts.lang = if (std.mem.startsWith(u8, l, "pt")) .pt else if (std.mem.startsWith(u8, l, "ja")) .ja else .en;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            const m = it.next() orelse break;
            opts.mode = if (std.mem.eql(u8, m, "light") or std.mem.eql(u8, m, "claro")) .light else .dark;
        } else if (std.mem.eql(u8, arg, "--theme")) {
            opts.theme = it.next() orelse break;
        } else if (std.mem.startsWith(u8, arg, "--fonts=")) {
            fonts_dir = arg["--fonts=".len..];
        } else if (!emscripten and std.mem.eql(u8, arg, "--shot")) {
            loop.shot = (it.next() orelse break).ptr;
            opts.live = false;
        }
    }
    if (emscripten) {
        // O teclado só vai para o app com o canvas em foco: as teclas da página (rolar,
        // Tab) continuam da página. O canvas é o #canvas de site/try.html.
        _ = c.SDL_SetHint(c.SDL_HINT_EMSCRIPTEN_KEYBOARD_ELEMENT, "#canvas");
        _ = c.SDL_SetHint(c.SDL_HINT_EMSCRIPTEN_CANVAS_SELECTOR, "#canvas");
    }
    const a = try App.create(std.heap.c_allocator, opts);
    app = a;
    if (emscripten) {
        // 0 qps: um quadro por requestAnimationFrame. `main` volta e o runtime fica
        // (EXIT_RUNTIME=0); o app vive no heap.
        c.emscripten_set_main_loop(quadro, 0, false);
        return;
    }
    // web-sim: o requestAnimationFrame vira uma espera de ~16 ms.
    defer a.destroy();
    while (a.webFrame(&loop)) c.SDL_Delay(16);
}
