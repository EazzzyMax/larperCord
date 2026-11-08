//! Rich Presence: o servidor local que faz o papel do Discord do computador para
//! jogos e apps (discord-ipc-N). Só existe com a opção ligada: desligada, não há
//! thread, socket nem arquivo. Linux: socket Unix em $XDG_RUNTIME_DIR (só do
//! dono); macOS: o mesmo, em $TMPDIR; Windows: o pipe \\.\pipe\discord-ipc-N. O
//! protocolo está em rpc_proto.zig.
//!
//! A thread daqui não fala com o gateway: entrega a atividade para a thread da
//! interface (`take`), que manda o comando para a conta conectada.
const std = @import("std");
const c = @import("c");
const sys = @import("../platform/sys.zig");
const proto = @import("rpc_proto.zig");

/// Relógio do ritmo e da vigia de processos (monotônico: mudar a hora não atrapalha).
fn nowMs() i64 {
    return @intCast(c.SDL_GetTicks());
}

const alloc = std.heap.c_allocator;
const windows = sys.windows;

/// Programas ao mesmo tempo (o resto é recusado na porta).
const max_conns = 4;
/// De quanto em quanto tempo confere se o jogo da atividade ainda existe.
const pid_check_ms: i64 = 5000;
/// Entre duas mudanças de presença (o Discord limita o op 3). O QA encurta.
pub var throttle_ms: i64 = 15_000;

pub const Update = struct { app: u64, activity: ?*proto.Activity };
pub const Notify = struct { ctx: *anyopaque, f: *const fn (*anyopaque) void };

var thread: ?*c.SDL_Thread = null;
var stopping: std.atomic.Value(bool) = .init(false);
var me: proto.Me = .{};
var notify: ?Notify = null;

// Caixa de saída para a thread da interface: só a mais nova importa.
var out_mutex: ?*c.SDL_Mutex = null;
var out_ready: std.atomic.Value(bool) = .init(false);
var out_value: ?Update = null;

// Linux: o socket que escuta e o caminho dele (apagado ao desligar).
var listen_fd: c_int = -1;
var wake: sys.Wake = .{};
var sock_path: [256]u8 = undefined;
var sock_path_len: usize = 0;

// Windows: o nome do pipe, a primeira instância (que reserva o nome) e o
// evento de parar.
var pipe_name: [64]u8 = undefined;
var first_pipe: ?*anyopaque = null;
var stop_event: ?*anyopaque = null;

pub fn running() bool {
    return thread != null;
}

/// Onde o socket está (Linux) ou o nome do pipe (QA, registro).
pub fn path() []const u8 {
    if (!running()) return "";
    return if (windows) std.mem.sliceTo(&pipe_name, 0) else sock_path[0..sock_path_len];
}

/// Liga o servidor. `who`: o nosso usuário, para o READY do handshake.
pub fn start(who: proto.Me, n: Notify) bool {
    if (running()) return true;
    me = who;
    notify = n;
    out_mutex = out_mutex orelse c.SDL_CreateMutex() orelse return false;
    if (!(if (windows) listenWindows() else listenPosix())) return false;
    stopping.store(false, .release);
    if (!windows) wake = sys.Wake.open();
    thread = c.SDL_CreateThread(threadMain, "rpc", null);
    if (thread == null) {
        closeListener();
        if (!windows) wake.close();
        return false;
    }
    std.log.info("Rich Presence: escutando em {s}", .{path()});
    return true;
}

/// Desliga: fecha as conexões, apaga o socket e espera a thread.
pub fn stop() void {
    const t = thread orelse return;
    stopping.store(true, .release);
    if (windows) {
        _ = c.SetEvent(stop_event);
    } else if (sys.valid(wake.write)) sys.wakeSignal(wake.write);
    c.SDL_WaitThread(t, null);
    thread = null;
    closeListener();
    if (!windows) wake.close();
    // O que não foi entregue fica para trás: quem desliga já manda limpar.
    if (take()) |u| if (u.activity) |a| alloc.destroy(a);
}

/// Thread da interface: a atividade nova, se houver (só um atômico quando não).
pub fn take() ?Update {
    if (!out_ready.load(.acquire)) return null;
    const m = out_mutex orelse return null;
    c.SDL_LockMutex(m);
    defer c.SDL_UnlockMutex(m);
    out_ready.store(false, .release);
    const v = out_value;
    out_value = null;
    return v;
}

fn deliver(u: proto.Hub.Update) void {
    var copy: ?*proto.Activity = null;
    if (u.activity) |a| {
        copy = alloc.create(proto.Activity) catch return;
        copy.?.* = a;
    }
    const m = out_mutex orelse return;
    c.SDL_LockMutex(m);
    if (out_value) |old| if (old.activity) |a| alloc.destroy(a);
    out_value = .{ .app = u.app, .activity = copy };
    out_ready.store(true, .release);
    c.SDL_UnlockMutex(m);
    if (notify) |n| n.f(n.ctx);
}

// --- O que é igual nos dois sistemas ---------------------------------------------

const Slot = struct {
    conn: proto.Conn = .{},
    fd: c_int = -1,
    pipe: ?*anyopaque = null,
    /// Leitura e escrita assíncronas do pipe (Windows).
    rov: if (windows) c.OVERLAPPED else void = if (windows) std.mem.zeroes(c.OVERLAPPED) else {},
    wev: ?*anyopaque = null,
    reading: bool = false,
    rbuf: [4096]u8 = undefined,
    /// O processo existia quando pediu a atividade: se sumir, a atividade some.
    /// (Um jogo no Wine manda o PID do Windows, que aqui não existe: esse não
    /// é vigiado, e vale a desconexão.)
    watch_pid: bool = false,
};

const State = struct {
    slots: [max_conns]?*Slot = @splat(null),
    hub: proto.Hub,
    next_pid_check: i64 = 0,
    out: std.ArrayList(u8) = .empty,

    fn live(s: *State, buf: *[max_conns]*const proto.Conn) []const *const proto.Conn {
        var n: usize = 0;
        for (s.slots) |sl| if (sl) |x| {
            buf[n] = &x.conn;
            n += 1;
        };
        return buf[0..n];
    }

    fn refresh(s: *State) void {
        var buf: [max_conns]*const proto.Conn = undefined;
        s.hub.update(s.live(&buf));
    }

    fn freeSlot(s: *State) ?usize {
        for (s.slots, 0..) |sl, i| if (sl == null) return i;
        return null;
    }

    /// Bytes chegaram numa conexão. false = fechar.
    fn onBytes(s: *State, sl: *Slot, bytes: []const u8) bool {
        s.out.clearRetainingCapacity();
        const r = sl.conn.feed(alloc, bytes, &me, &s.out);
        const sent = s.out.items.len == 0 or sendAll(sl, s.out.items);
        if (s.out.capacity > 16 * 1024) s.out.clearAndFree(alloc);
        if (r == .changed) {
            if (sl.conn.activity != null) {
                sl.conn.seq = s.hub.nextSeq();
                sl.watch_pid = sl.conn.pid > 0 and pidAlive(sl.conn.pid);
            } else sl.watch_pid = false;
            s.refresh();
        }
        return sent and r != .close;
    }

    fn drop(s: *State, i: usize) void {
        const sl = s.slots[i] orelse return;
        s.slots[i] = null;
        closeSlot(sl);
        s.refresh();
    }

    /// Jogo fechou sem avisar: a atividade dele some.
    fn checkPids(s: *State, now: i64) void {
        if (now < s.next_pid_check) return;
        s.next_pid_check = now + pid_check_ms;
        var changed = false;
        for (s.slots) |sl| if (sl) |x| if (x.watch_pid and x.conn.activity != null and !pidAlive(x.conn.pid)) {
            x.conn.activity = null;
            x.watch_pid = false;
            changed = true;
        };
        if (changed) s.refresh();
    }

    fn watching(s: *const State) bool {
        for (s.slots) |sl| if (sl) |x| if (x.watch_pid and x.conn.activity != null) return true;
        return false;
    }

    /// Quanto o laço pode dormir (-1 = até chegar algo).
    fn timeout(s: *State, now: i64) i64 {
        var t: i64 = -1;
        if (s.hub.throttle.waitMs(now)) |w| t = w;
        if (s.watching()) {
            if (s.next_pid_check == 0) s.next_pid_check = now + pid_check_ms;
            const w = @max(0, s.next_pid_check - now);
            t = if (t < 0) w else @min(t, w);
        }
        return t;
    }

    fn flush(s: *State, now: i64) void {
        if (s.hub.take(now)) |u| deliver(u);
    }

    fn deinit(s: *State) void {
        for (&s.slots) |*sl| if (sl.*) |x| {
            closeSlot(x);
            sl.* = null;
        };
        s.out.deinit(alloc);
    }
};

fn closeSlot(sl: *Slot) void {
    if (windows) {
        if (sl.pipe) |p| {
            // A leitura pendente escreve em `rov`/`rbuf`: cancela e espera antes de liberar.
            if (sl.reading) {
                _ = c.CancelIo(p);
                var n: c.DWORD = 0;
                _ = c.GetOverlappedResult(p, &sl.rov, &n, 1);
            }
            // Sem DisconnectNamedPipe: ele descarta o que o cliente ainda não leu, e o CLOSE
            // com o código e o motivo (net/rpc_proto.zig) nunca chegava. Fechando só esta ponta,
            // o cliente lê o que já está no pipe e depois recebe ERROR_BROKEN_PIPE. Cada conexão
            // tem a própria instância, que nunca é reaproveitada: não há o que desconectar.
            // FlushFileBuffers esperaria o cliente ler, sem prazo, e travaria a thread.
            _ = c.CloseHandle(p);
        }
        if (sl.rov.hEvent) |e| _ = c.CloseHandle(e);
        if (sl.wev) |e| _ = c.CloseHandle(e);
    } else if (sl.fd >= 0) _ = c.close(sl.fd);
    sl.conn.deinit(alloc);
    alloc.destroy(sl);
}

fn threadMain(_: ?*anyopaque) callconv(.c) c_int {
    var s: State = .{ .hub = .{ .throttle = .{ .interval_ms = throttle_ms } } };
    defer s.deinit();
    if (windows) runWindows(&s) else runPosix(&s);
    return 0;
}

fn sendAll(sl: *Slot, data: []const u8) bool {
    return if (windows) sendWindows(sl, data) else sendPosix(sl, data);
}

fn pidAlive(pid: i64) bool {
    if (windows) {
        const p = std.math.cast(c.DWORD, pid) orelse return false;
        // 0x00100000 = SYNCHRONIZE.
        const h = c.OpenProcess(0x00100000, 0, p) orelse return c.GetLastError() != 87;
        defer _ = c.CloseHandle(h);
        return c.WaitForSingleObject(h, 0) != c.WAIT_OBJECT_0;
    }
    const p = std.math.cast(c.pid_t, pid) orelse return false;
    if (c.kill(p, 0) == 0) return true;
    return std.c._errno().* != @intFromEnum(std.c.E.SRCH);
}

fn closeListener() void {
    if (windows) {
        if (first_pipe) |p| _ = c.CloseHandle(p);
        first_pipe = null;
        if (stop_event) |e| _ = c.CloseHandle(e);
        stop_event = null;
        return;
    }
    if (listen_fd >= 0) _ = c.close(listen_fd);
    listen_fd = -1;
    if (sock_path_len > 0) {
        sock_path[sock_path_len] = 0;
        _ = c.unlink(@ptrCast(&sock_path));
    }
    sock_path_len = 0;
}

// --- Linux e macOS ---------------------------------------------------------------

/// No macOS (BSD), o sockaddr_un começa pelo tamanho e o caminho tem 104 bytes.
pub const SockAddrUn = if (sys.macos) extern struct { len: u8, family: u8, path: [104]u8 } else extern struct { family: u16, path: [108]u8 };
const msg_dontwait = if (sys.macos) 0x80 else 0x40;
/// O macOS não tem MSG_NOSIGNAL: lá o SIGPIPE já é ignorado no processo inteiro (sys.init).
pub const msg_nosignal = if (sys.macos) 0 else 0x4000;

/// Um socket Unix que os filhos não herdam. O macOS não tem SOCK_CLOEXEC: vai pelo fcntl.
pub fn unixSocket() c_int {
    if (!sys.macos) return c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0);
    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM, 0);
    if (fd >= 0 and c.fcntl(fd, c.F_SETFD, c.FD_CLOEXEC) != 0) {
        _ = c.close(fd);
        return -1;
    }
    return fd;
}

fn env(name: [*:0]const u8) ?[]const u8 {
    const v = c.SDL_getenv(name) orelse return null;
    const s = std.mem.span(v);
    return if (s.len > 0) s else null;
}

pub fn unixAddr(p: []const u8) ?SockAddrUn {
    var a: SockAddrUn = if (sys.macos)
        .{ .len = @sizeOf(SockAddrUn), .family = c.AF_UNIX, .path = @splat(0) }
    else
        .{ .family = c.AF_UNIX, .path = @splat(0) };
    if (p.len >= a.path.len) return null;
    @memcpy(a.path[0..p.len], p);
    return a;
}

/// Um socket que sobrou de um processo que morreu (ninguém atende) pode ir
/// embora; um de verdade (o Discord oficial aberto) fica.
fn stale(p: [*:0]const u8, addr: *const SockAddrUn) bool {
    var st: c.struct_stat = undefined;
    if (c.lstat(p, &st) != 0) return false;
    if (st.st_mode & 0o170000 != 0o140000 or st.st_uid != c.getuid()) return false;
    const fd = unixSocket();
    if (fd < 0) return false;
    defer _ = c.close(fd);
    if (c.connect(fd, @ptrCast(addr), @sizeOf(SockAddrUn)) == 0) return false;
    return std.c._errno().* == @intFromEnum(std.c.E.CONNREFUSED);
}

fn listenPosix() bool {
    // Como o Discord: $XDG_RUNTIME_DIR, senão a pasta temporária.
    const dir = env("XDG_RUNTIME_DIR") orelse env("TMPDIR") orelse "/tmp";
    var n: u8 = 0;
    var retried = false;
    while (n < 10) {
        const p = std.fmt.bufPrintSentinel(&sock_path, "{s}/discord-ipc-{d}", .{ std.mem.trimEnd(u8, dir, "/"), n }, 0) catch return false;
        const addr = unixAddr(p) orelse return false;
        const fd = unixSocket();
        if (fd < 0) return false;
        if (c.bind(fd, @ptrCast(&addr), @sizeOf(SockAddrUn)) == 0) {
            // Só o dono conecta. listen() vem depois: antes dele ninguém entra.
            if (c.chmod(p.ptr, 0o600) != 0 or c.listen(fd, 4) != 0) {
                _ = c.close(fd);
                _ = c.unlink(p.ptr);
                return false;
            }
            _ = c.fcntl(fd, c.F_SETFL, c.O_NONBLOCK);
            listen_fd = fd;
            sock_path_len = p.len;
            return true;
        }
        const busy = std.c._errno().* == @intFromEnum(std.c.E.ADDRINUSE);
        _ = c.close(fd);
        if (busy and !retried and stale(p.ptr, &addr)) {
            _ = c.unlink(p.ptr);
            retried = true;
            continue;
        }
        if (!busy) return false;
        retried = false;
        n += 1;
    }
    return false;
}

fn sendPosix(sl: *Slot, data: []const u8) bool {
    var off: usize = 0;
    var waits: u8 = 0;
    while (off < data.len) {
        const r = c.send(sl.fd, data.ptr + off, data.len - off, msg_dontwait | msg_nosignal);
        if (r > 0) {
            off += @intCast(r);
            continue;
        }
        const err = std.c._errno().*;
        if (r < 0 and (err == @intFromEnum(std.c.E.AGAIN) or err == @intFromEnum(std.c.E.INTR)) and waits < 10) {
            // Quem não lê as respostas não segura a thread: no máximo ~1 s.
            waits += 1;
            var pfd: sys.PollFd = .{ .fd = sl.fd, .events = c.POLLOUT, .revents = 0 };
            _ = c.poll(&pfd, 1, 100);
            continue;
        }
        return false;
    }
    return true;
}

fn acceptPosix(s: *State) void {
    const fd = c.accept(listen_fd, null, null);
    if (fd < 0) return;
    _ = c.fcntl(fd, c.F_SETFD, c.FD_CLOEXEC);
    _ = c.fcntl(fd, c.F_SETFL, c.O_NONBLOCK);
    const i = s.freeSlot() orelse {
        _ = c.close(fd);
        return;
    };
    const sl = alloc.create(Slot) catch {
        _ = c.close(fd);
        return;
    };
    sl.* = .{ .fd = fd };
    s.slots[i] = sl;
}

fn runPosix(s: *State) void {
    while (!stopping.load(.acquire)) {
        const now = nowMs();
        const t = s.timeout(now);
        var fds: [2 + max_conns]sys.PollFd = undefined;
        var idx: [max_conns]usize = undefined;
        fds[0] = .{ .fd = wake.read, .events = c.POLLIN, .revents = 0 };
        fds[1] = .{ .fd = listen_fd, .events = c.POLLIN, .revents = 0 };
        var n: usize = 2;
        for (s.slots, 0..) |sl, i| if (sl) |x| {
            fds[n] = .{ .fd = x.fd, .events = c.POLLIN, .revents = 0 };
            idx[n - 2] = i;
            n += 1;
        };
        _ = c.poll(&fds, @intCast(n), @intCast(std.math.clamp(t, -1, 60_000)));
        if (stopping.load(.acquire)) break;
        if (fds[0].revents != 0) wake.drain();
        for (fds[2..n], 0..) |pfd, k| {
            if (pfd.revents == 0) continue;
            const i = idx[k];
            const sl = s.slots[i] orelse continue;
            const r = c.recv(sl.fd, &sl.rbuf, sl.rbuf.len, 0);
            if (r > 0) {
                if (!s.onBytes(sl, sl.rbuf[0..@intCast(r)])) s.drop(i);
            } else if (r == 0 or std.c._errno().* != @intFromEnum(std.c.E.AGAIN)) s.drop(i);
        }
        if (fds[1].revents & c.POLLIN != 0) acceptPosix(s);
        const after = nowMs();
        s.checkPids(after);
        s.flush(after);
    }
}

// --- Windows -------------------------------------------------------------------

const error_io_pending = 997;
const error_pipe_connected = 535;

/// Uma instância do pipe. A primeira reserva o nome: se outro programa (o
/// Discord oficial) já tem esse número, falha e vamos para o próximo.
fn createPipe(first: bool) ?*anyopaque {
    // PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED (| FILE_FLAG_FIRST_PIPE_INSTANCE);
    // modo: bytes, PIPE_REJECT_REMOTE_CLIENTS (só deste computador).
    const open_mode: c.DWORD = 0x00000003 | 0x40000000 | @as(c.DWORD, if (first) 0x00080000 else 0);
    const h = c.CreateNamedPipeA(@ptrCast(&pipe_name), open_mode, 0x00000008, 255, 64 * 1024, 64 * 1024, 0, null);
    if (h == c.INVALID_HANDLE_VALUE) return null;
    return h;
}

fn listenWindows() bool {
    stop_event = c.CreateEventA(null, 1, 0, null) orelse return false;
    for (0..10) |n| {
        _ = std.fmt.bufPrintSentinel(&pipe_name, "\\\\.\\pipe\\discord-ipc-{d}", .{n}, 0) catch break;
        if (createPipe(true)) |h| {
            first_pipe = h;
            return true;
        }
    }
    _ = c.CloseHandle(stop_event);
    stop_event = null;
    return false;
}

const Connect = enum { pending, connected, broken };

fn startConnect(h: ?*anyopaque, ov: *c.OVERLAPPED) Connect {
    _ = c.ResetEvent(ov.hEvent);
    if (c.ConnectNamedPipe(h, ov) != 0) return .connected;
    return switch (c.GetLastError()) {
        error_io_pending => .pending,
        error_pipe_connected => .connected,
        else => .broken,
    };
}

/// Começa a próxima leitura. false = a conexão caiu.
fn startRead(sl: *Slot) bool {
    sl.reading = c.ReadFile(sl.pipe, &sl.rbuf, sl.rbuf.len, null, &sl.rov) != 0 or c.GetLastError() == error_io_pending;
    return sl.reading;
}

fn sendWindows(sl: *Slot, data: []const u8) bool {
    var ov = std.mem.zeroes(c.OVERLAPPED);
    ov.hEvent = sl.wev;
    var off: usize = 0;
    while (off < data.len) {
        const chunk: c.DWORD = @intCast(@min(data.len - off, 64 * 1024));
        if (c.WriteFile(sl.pipe, data.ptr + off, chunk, null, &ov) == 0) {
            if (c.GetLastError() != error_io_pending) return false;
            // Quem não lê as respostas não segura a thread: no máximo 1 s.
            if (c.WaitForSingleObject(sl.wev, 1000) != c.WAIT_OBJECT_0) {
                _ = c.CancelIo(sl.pipe);
                var junk: c.DWORD = 0;
                _ = c.GetOverlappedResult(sl.pipe, &ov, &junk, 1);
                return false;
            }
        }
        var n: c.DWORD = 0;
        if (c.GetOverlappedResult(sl.pipe, &ov, &n, 0) == 0 or n == 0) return false;
        off += n;
    }
    return true;
}

/// Um programa conectou nesta instância: vira uma conexão (ou é recusado).
fn adopt(s: *State, h: ?*anyopaque) void {
    const i = s.freeSlot() orelse return refuse(h);
    const sl = alloc.create(Slot) catch return refuse(h);
    sl.* = .{ .pipe = h };
    sl.rov.hEvent = c.CreateEventA(null, 1, 0, null);
    sl.wev = c.CreateEventA(null, 1, 0, null);
    s.slots[i] = sl;
    if (sl.rov.hEvent == null or sl.wev == null or !startRead(sl)) s.drop(i);
}

fn refuse(h: ?*anyopaque) void {
    _ = c.DisconnectNamedPipe(h);
    _ = c.CloseHandle(h);
}

fn runWindows(s: *State) void {
    var listener: ?*anyopaque = first_pipe;
    // A primeira instância passa a ser da thread (closeListener não fecha de novo).
    first_pipe = null;
    var lov = std.mem.zeroes(c.OVERLAPPED);
    lov.hEvent = c.CreateEventA(null, 1, 0, null);
    var lstate: Connect = .broken;
    defer {
        if (listener) |h| {
            if (lstate == .pending) {
                _ = c.CancelIo(h);
                var junk: c.DWORD = 0;
                _ = c.GetOverlappedResult(h, &lov, &junk, 1);
            }
            _ = c.CloseHandle(h);
        }
        if (lov.hEvent) |e| _ = c.CloseHandle(e);
    }
    if (lov.hEvent == null) return;
    if (listener) |h| lstate = startConnect(h, &lov);
    while (!stopping.load(.acquire)) {
        // Conectou na hora (ou caiu): troca a instância antes de esperar.
        while (lstate != .pending) {
            if (listener) |h| {
                if (lstate == .connected) adopt(s, h) else _ = c.CloseHandle(h);
            }
            listener = createPipe(false);
            lstate = if (listener) |h| startConnect(h, &lov) else break;
        }
        const now = nowMs();
        var t = s.timeout(now);
        // Sem instância (falhou ao criar): tenta de novo daqui a pouco.
        if (listener == null) t = if (t < 0) 1000 else @min(t, 1000);
        var handles: [2 + max_conns]?*anyopaque = undefined;
        var idx: [max_conns]usize = undefined;
        handles[0] = stop_event;
        var n: usize = 1;
        if (listener != null) {
            handles[1] = lov.hEvent;
            n = 2;
        }
        const base = n;
        for (s.slots, 0..) |sl, i| if (sl) |x| {
            handles[n] = x.rov.hEvent;
            idx[n - base] = i;
            n += 1;
        };
        const wait: c.DWORD = if (t < 0) c.INFINITE else @intCast(@min(t, 60_000));
        const r = c.WaitForMultipleObjects(@intCast(n), &handles, 0, wait);
        if (stopping.load(.acquire)) break;
        if (r >= c.WAIT_OBJECT_0 and r < c.WAIT_OBJECT_0 + n) {
            const k: usize = @intCast(r - c.WAIT_OBJECT_0);
            if (k == 1 and listener != null) {
                var junk: c.DWORD = 0;
                lstate = if (c.GetOverlappedResult(listener, &lov, &junk, 0) != 0) .connected else .broken;
            } else if (k >= base) {
                const i = idx[k - base];
                if (s.slots[i]) |sl| {
                    sl.reading = false;
                    var got: c.DWORD = 0;
                    const ok = c.GetOverlappedResult(sl.pipe, &sl.rov, &got, 0) != 0;
                    if (!ok or !s.onBytes(sl, sl.rbuf[0..got]) or !startRead(sl)) s.drop(i);
                }
            }
        }
        const after = nowMs();
        s.checkPids(after);
        s.flush(after);
    }
}

