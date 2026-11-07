//! A primeira busca de fonte do fontconfig lê a configuração e o cache de todas as
//! fontes do sistema (15 a 20 ms). Isso começa aqui numa thread, enquanto o SDL
//! cria a janela e o renderizador, e a abertura não espera duas vezes.
//! No Windows não há fontconfig: não faz nada.
const c = @import("c");
const sys = @import("sys.zig");

pub const Warm = ?*c.SDL_Thread;

pub fn start() Warm {
    // Sem thread (falhou ou Windows): a primeira busca prepara tudo, como antes.
    return if (sys.windows) null else c.SDL_CreateThread(run, "fontes", null);
}

fn run(_: ?*anyopaque) callconv(.c) c_int {
    if (!sys.windows) _ = c.FcInit();
    return 0;
}

/// Antes da primeira busca de fonte na thread da interface.
pub fn join(w: Warm) void {
    if (w) |t| c.SDL_WaitThread(t, null);
}
