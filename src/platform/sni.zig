//! O ícone da bandeja no Linux falando StatusNotifierItem direto pelo D-Bus, no
//! processo do ícone (`--tray-helper`). O libappindicator (por trás do
//! SDL_CreateTray) diz ao painel que o ícone é só um menu (ItemIsMenu) e não atende
//! o Activate: o clique esquerdo nunca chegava ao app. Aqui o Activate alterna a
//! janela, o menu (Abrir/Sair) vai pelo com.canonical.dbusmenu e não entra GTK
//! nenhum: o processo fica parado no poll até o painel ou o app falarem.
//!
//! A libdbus-1 é aberta na hora (como em sys.trayHostAvailable), sem dependência
//! nova no build. Sem ela, sem sessão D-Bus ou com o nome recusado, `run` volta e o
//! processo do ícone fica com o SDL_CreateTray de antes.
const std = @import("std");
const c = @import("c");
const bandeja = @import("../core/bandeja.zig");
const janela = @import("../core/janela.zig");
const resample = @import("../core/resample.zig");
const platform = @import("window.zig");

const watcher = "org.kde.StatusNotifierWatcher";
const item_path = "/StatusNotifierItem";
const menu_path = "/MenuBar";
const props_iface = "org.freedesktop.DBus.Properties";
const intro_iface = "org.freedesktop.DBus.Introspectable";
const menu_iface = "com.canonical.dbusmenu";

const Conn = opaque {};
const Msg = opaque {};
const Pending = opaque {};
/// DBusMessageIter tem 72 bytes e DBusError, 32: os dois com folga.
const Iter = [16]u64;
const Err = extern struct { name: ?[*:0]const u8, message: ?[*:0]const u8, rest: [6]usize };

const Filter = *const fn (*Conn, *Msg, ?*anyopaque) callconv(.c) c_int;
const Notify = *const fn (*Pending, ?*anyopaque) callconv(.c) void;

/// Os nomes dos campos são os das funções da libdbus.
const Fns = struct {
    dbus_error_init: *const fn (*Err) callconv(.c) void,
    dbus_error_free: *const fn (*Err) callconv(.c) void,
    dbus_bus_get_private: *const fn (c_int, *Err) callconv(.c) ?*Conn,
    dbus_bus_request_name: *const fn (*Conn, [*:0]const u8, c_uint, *Err) callconv(.c) c_int,
    dbus_bus_add_match: *const fn (*Conn, [*:0]const u8, *Err) callconv(.c) void,
    dbus_connection_set_exit_on_disconnect: *const fn (*Conn, u32) callconv(.c) void,
    dbus_connection_close: *const fn (*Conn) callconv(.c) void,
    dbus_connection_unref: *const fn (*Conn) callconv(.c) void,
    dbus_connection_add_filter: *const fn (*Conn, Filter, ?*anyopaque, ?*const anyopaque) callconv(.c) u32,
    dbus_connection_get_unix_fd: *const fn (*Conn, *c_int) callconv(.c) u32,
    dbus_connection_read_write: *const fn (*Conn, c_int) callconv(.c) u32,
    dbus_connection_dispatch: *const fn (*Conn) callconv(.c) c_int,
    dbus_connection_get_dispatch_status: *const fn (*Conn) callconv(.c) c_int,
    dbus_connection_flush: *const fn (*Conn) callconv(.c) void,
    dbus_connection_get_is_connected: *const fn (*Conn) callconv(.c) u32,
    dbus_connection_send: *const fn (*Conn, *Msg, ?*u32) callconv(.c) u32,
    dbus_connection_send_with_reply: *const fn (*Conn, *Msg, *?*Pending, c_int) callconv(.c) u32,
    dbus_pending_call_set_notify: *const fn (*Pending, Notify, ?*anyopaque, ?*const anyopaque) callconv(.c) u32,
    dbus_pending_call_steal_reply: *const fn (*Pending) callconv(.c) ?*Msg,
    dbus_pending_call_cancel: *const fn (*Pending) callconv(.c) void,
    dbus_pending_call_unref: *const fn (*Pending) callconv(.c) void,
    dbus_message_new_method_call: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) ?*Msg,
    dbus_message_new_method_return: *const fn (*Msg) callconv(.c) ?*Msg,
    dbus_message_new_error: *const fn (*Msg, [*:0]const u8, [*:0]const u8) callconv(.c) ?*Msg,
    dbus_message_unref: *const fn (*Msg) callconv(.c) void,
    dbus_message_get_type: *const fn (*Msg) callconv(.c) c_int,
    dbus_message_get_path: *const fn (*Msg) callconv(.c) ?[*:0]const u8,
    dbus_message_get_interface: *const fn (*Msg) callconv(.c) ?[*:0]const u8,
    dbus_message_get_member: *const fn (*Msg) callconv(.c) ?[*:0]const u8,
    dbus_message_get_sender: *const fn (*Msg) callconv(.c) ?[*:0]const u8,
    dbus_message_get_error_name: *const fn (*Msg) callconv(.c) ?[*:0]const u8,
    dbus_message_get_no_reply: *const fn (*Msg) callconv(.c) u32,
    dbus_message_iter_init: *const fn (*Msg, *Iter) callconv(.c) u32,
    dbus_message_iter_get_arg_type: *const fn (*Iter) callconv(.c) c_int,
    dbus_message_iter_get_basic: *const fn (*Iter, *anyopaque) callconv(.c) void,
    dbus_message_iter_next: *const fn (*Iter) callconv(.c) u32,
    dbus_message_iter_recurse: *const fn (*Iter, *Iter) callconv(.c) void,
    dbus_message_iter_init_append: *const fn (*Msg, *Iter) callconv(.c) void,
    dbus_message_iter_append_basic: *const fn (*Iter, c_int, *const anyopaque) callconv(.c) u32,
    dbus_message_iter_append_fixed_array: *const fn (*Iter, c_int, *const anyopaque, c_int) callconv(.c) u32,
    dbus_message_iter_open_container: *const fn (*Iter, c_int, ?[*:0]const u8, *Iter) callconv(.c) u32,
    dbus_message_iter_close_container: *const fn (*Iter, *Iter) callconv(.c) u32,
};
var d: Fns = undefined;

const msg_method_call = 1;
const msg_method_return = 2;
const msg_signal = 4;
const handled: c_int = 0;
const not_yet: c_int = 1;
const dispatch_data_remains: c_int = 0;
const timeout_infinite: c_int = 0x7fffffff;
const name_do_not_queue: c_uint = 4;
const name_primary_owner: c_int = 1;

var conn: *Conn = undefined;
var bus_name_buf: [64]u8 = undefined;
var bus_name: [:0]const u8 = "";
var open_label: [*:0]const u8 = "";
var quit_label: [*:0]const u8 = "";
/// O pedido de registro ao painel que ainda não voltou.
var pending: ?*Pending = null;
var told_ready = false;
var last_activate_ms: i64 = -1;
/// O painel tinha o nome mas recusou o registro (ainda montando o objeto dele):
/// tenta de novo daqui a pouco, umas poucas vezes.
var retry_at_ms: i64 = -1;
var retries: u8 = 0;
/// Até quando o primeiro registro pode demorar. Sem o "pronto" até lá (painel que não
/// responde, que recusa ou que sumiu), o processo avisa a falha e sai: o app tenta de
/// novo mais tarde sem ficar esperando (o waitReady dele é de 5 s).
const ready_timeout_ms: i64 = 4000;
var ready_deadline_ms: i64 = -1;

const Pixmap = struct { size: i32, argb: []u8 };
var pixmaps_buf: [3]Pixmap = undefined;
var pixmaps: []const Pixmap = &.{};

fn load() bool {
    const lib = c.SDL_LoadObject("libdbus-1.so.3") orelse return false;
    inline for (@typeInfo(Fns).@"struct".field_names) |fname| {
        const sym = c.SDL_LoadFunction(lib, fname.ptr) orelse return false;
        @field(d, fname) = @ptrCast(sym);
    }
    return true;
}

/// Põe o ícone e atende o painel até a entrada fechar (o app mandou sair ou morreu).
/// Só volta se não deu para começar.
pub fn run(open: [*:0]const u8, quit: [*:0]const u8) void {
    if (!load()) {
        std.log.info("bandeja: sem libdbus-1, fica o SDL_CreateTray", .{});
        return;
    }
    open_label = open;
    quit_label = quit;
    var err: Err = undefined;
    d.dbus_error_init(&err);
    const cn = d.dbus_bus_get_private(0, &err) orelse {
        std.log.info("bandeja: sem sessão D-Bus ({s}), fica o SDL_CreateTray", .{err.message orelse "?"});
        d.dbus_error_free(&err);
        return;
    };
    conn = cn;
    // Por padrão a libdbus derruba o processo quando a conexão cai; aqui quem sai é o laço.
    d.dbus_connection_set_exit_on_disconnect(cn, 0);
    bus_name = std.fmt.bufPrintSentinel(&bus_name_buf, "org.kde.StatusNotifierItem-{d}-1", .{c.getpid()}, 0) catch unreachable;
    const got = d.dbus_bus_request_name(cn, bus_name.ptr, name_do_not_queue, &err);
    var fd: c_int = -1;
    if (got != name_primary_owner or d.dbus_connection_add_filter(cn, &filter, null, null) == 0 or
        d.dbus_connection_get_unix_fd(cn, &fd) == 0)
    {
        std.log.info("bandeja: o D-Bus recusou o ícone ({s}), fica o SDL_CreateTray", .{err.message orelse "?"});
        d.dbus_error_free(&err);
        d.dbus_connection_close(cn);
        d.dbus_connection_unref(cn);
        return;
    }
    // O painel que (re)começa depois: registra de novo (sem painel agora, o ícone espera por ele).
    d.dbus_bus_add_match(cn, "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='" ++ watcher ++ "'", &err);
    d.dbus_error_free(&err);
    loadIcons();
    ready_deadline_ms = nowMs() + ready_timeout_ms;
    register();
    loop(fd);
}

/// Parado no poll: acorda só com o painel (D-Bus) ou com a entrada fechando.
fn loop(bus_fd: c_int) noreturn {
    while (true) {
        // O flush também lê do socket: o que chegou durante ele fica na fila do
        // libdbus sem acordar o poll, então despacha de novo até a fila esvaziar.
        while (true) {
            while (d.dbus_connection_dispatch(conn) == dispatch_data_remains) {}
            d.dbus_connection_flush(conn);
            if (d.dbus_connection_get_dispatch_status(conn) != dispatch_data_remains) break;
        }
        // A sessão D-Bus caiu: sai, e o app refaz o ícone num processo novo.
        if (d.dbus_connection_get_is_connected(conn) == 0) std.process.exit(1);
        var fds = [2]c.struct_pollfd{
            .{ .fd = 0, .events = c.POLLIN, .revents = 0 },
            .{ .fd = bus_fd, .events = c.POLLIN, .revents = 0 },
        };
        var next: i64 = retry_at_ms;
        if (!told_ready and (next < 0 or ready_deadline_ms < next)) next = ready_deadline_ms;
        const wait: c_int = if (next < 0) -1 else @intCast(std.math.clamp(next - nowMs(), 0, 1000));
        if (c.poll(&fds, 2, wait) < 0) continue;
        if (fds[0].revents != 0) std.process.exit(0);
        if (fds[1].revents != 0) _ = d.dbus_connection_read_write(conn, 0);
        if (!told_ready and nowMs() >= ready_deadline_ms) giveUp();
        if (retry_at_ms >= 0 and nowMs() >= retry_at_ms) {
            retry_at_ms = -1;
            register();
        }
    }
}

/// O ícone não entrou no painel: o app fica sabendo na hora e tenta de novo depois.
fn giveUp() noreturn {
    say(&.{bandeja.msg_failed});
    std.process.exit(1);
}

fn nowMs() i64 {
    return @intCast(c.SDL_GetTicks());
}

fn say(bytes: []const u8) void {
    _ = c.write(1, bytes.ptr, bytes.len);
}

// --- Registro no painel ----------------------------------------------------------

fn register() void {
    if (pending) |p| {
        d.dbus_pending_call_cancel(p);
        d.dbus_pending_call_unref(p);
        pending = null;
    }
    const msg = d.dbus_message_new_method_call(watcher, "/StatusNotifierWatcher", watcher, "RegisterStatusNotifierItem") orelse return;
    defer d.dbus_message_unref(msg);
    var out: Out = .{};
    d.dbus_message_iter_init_append(msg, &out.it);
    out.str(bus_name.ptr);
    // Sem esperar a resposta: um painel que pergunta pelo ícone antes de responder
    // não pode travar aqui.
    var p: ?*Pending = null;
    if (d.dbus_connection_send_with_reply(conn, msg, &p, timeout_infinite) == 0) return;
    const pc = p orelse return;
    if (d.dbus_pending_call_set_notify(pc, &onRegistered, null, null) == 0) {
        d.dbus_pending_call_cancel(pc);
        d.dbus_pending_call_unref(pc);
        return;
    }
    pending = pc;
}

fn onRegistered(p: *Pending, _: ?*anyopaque) callconv(.c) void {
    if (pending == p) pending = null;
    defer d.dbus_pending_call_unref(p);
    const reply = d.dbus_pending_call_steal_reply(p) orelse return;
    defer d.dbus_message_unref(reply);
    if (d.dbus_message_get_type(reply) != msg_method_return) {
        const name = span(d.dbus_message_get_error_name(reply)) orelse "?";
        std.log.info("bandeja: o painel não registrou o ícone: {s}", .{name});
        // Sem painel agora: o ícone entra quando o StatusNotifierWatcher aparecer.
        if (eql(name, "org.freedesktop.DBus.Error.ServiceUnknown") or eql(name, "org.freedesktop.DBus.Error.NameHasNoOwner")) return;
        if (retries < 3) {
            retries += 1;
            retry_at_ms = nowMs() + 1000;
        } else if (!told_ready) giveUp();
        return;
    }
    retries = 0;
    // O app só esconde a janela com o ícone no painel: o "pronto" vem daqui.
    if (!told_ready) {
        told_ready = true;
        say(&.{bandeja.msg_ready});
    }
}

// --- Ícone ---------------------------------------------------------------------

/// O ícone embutido em 22 (o comum nas barras), 32 e 64 pixels, no ARGB do protocolo.
fn loadIcons() void {
    const gpa = std.heap.c_allocator;
    var n: usize = 0;
    var w: c_int = 0;
    var h: c_int = 0;
    var comp: c_int = 0;
    // Ficam carregados até o processo sair: o painel pede de novo quando quiser.
    const big_px = c.stbi_load_from_memory(platform.icon_64.ptr, @intCast(platform.icon_64.len), &w, &h, &comp, 4);
    const big: ?[]u8 = if (big_px != null and w == 64 and h == 64) big_px[0 .. 64 * 64 * 4] else null;
    // O de 22 sai do de 64 ainda em RGBA: antes de converter o de 64 no lugar.
    if (big) |src| small: {
        const s = gpa.alloc(u8, 22 * 22 * 4) catch break :small;
        resample.bicubic(gpa, src, 64, 64, s, 22, 22) catch break :small;
        bandeja.argb(s, s);
        pixmaps_buf[n] = .{ .size = 22, .argb = s };
        n += 1;
    }
    const mid_px = c.stbi_load_from_memory(platform.icon_32.ptr, @intCast(platform.icon_32.len), &w, &h, &comp, 4);
    if (mid_px != null and w == 32 and h == 32) {
        const s = mid_px[0 .. 32 * 32 * 4];
        bandeja.argb(s, s);
        pixmaps_buf[n] = .{ .size = 32, .argb = s };
        n += 1;
    }
    if (big) |s| {
        bandeja.argb(s, s);
        pixmaps_buf[n] = .{ .size = 64, .argb = s };
        n += 1;
    }
    pixmaps = pixmaps_buf[0..n];
}

// --- Mensagens -----------------------------------------------------------------

/// Escreve os argumentos de uma mensagem.
const Out = struct {
    it: Iter = undefined,

    fn basic(o: *Out, t: u8, v: *const anyopaque) void {
        _ = d.dbus_message_iter_append_basic(&o.it, t, v);
    }
    fn str(o: *Out, s: [*:0]const u8) void {
        o.basic('s', @ptrCast(&s));
    }
    fn objPath(o: *Out, s: [*:0]const u8) void {
        o.basic('o', @ptrCast(&s));
    }
    fn int(o: *Out, v: i32) void {
        o.basic('i', @ptrCast(&v));
    }
    fn uint(o: *Out, v: u32) void {
        o.basic('u', @ptrCast(&v));
    }
    fn boolean(o: *Out, v: bool) void {
        const x: u32 = @intFromBool(v);
        o.basic('b', @ptrCast(&x));
    }
    fn open(o: *Out, sub: *Out, t: u8, sig: ?[*:0]const u8) void {
        _ = d.dbus_message_iter_open_container(&o.it, t, sig, &sub.it);
    }
    fn close(o: *Out, sub: *Out) void {
        _ = d.dbus_message_iter_close_container(&o.it, &sub.it);
    }
    fn bytes(o: *Out, data: []const u8) void {
        var arr: Out = .{};
        o.open(&arr, 'a', "y");
        const p: [*]const u8 = data.ptr;
        _ = d.dbus_message_iter_append_fixed_array(&arr.it, 'y', @ptrCast(&p), @intCast(data.len));
        o.close(&arr);
    }
    fn variantStr(o: *Out, s: [*:0]const u8) void {
        var v: Out = .{};
        o.open(&v, 'v', "s");
        v.str(s);
        o.close(&v);
    }
    fn variantBool(o: *Out, b: bool) void {
        var v: Out = .{};
        o.open(&v, 'v', "b");
        v.boolean(b);
        o.close(&v);
    }
    /// Uma entrada {sv} de um dicionário de propriedades: abre e escreve a chave; o
    /// valor (variante) vai em `e`, e `close(e)` fecha a entrada.
    fn entry(o: *Out, e: *Out, key: [*:0]const u8) void {
        o.open(e, 'e', null);
        e.str(key);
    }
    fn pixmapList(o: *Out, list: []const Pixmap) void {
        var arr: Out = .{};
        o.open(&arr, 'a', "(iiay)");
        for (list) |p| {
            var st: Out = .{};
            arr.open(&st, 'r', null);
            st.int(p.size);
            st.int(p.size);
            st.bytes(p.argb);
            arr.close(&st);
        }
        o.close(&arr);
    }
};

/// Lê os argumentos de uma mensagem.
const In = struct {
    it: Iter = undefined,

    fn start(i: *In, msg: *Msg) bool {
        return d.dbus_message_iter_init(msg, &i.it) != 0;
    }
    fn kind(i: *In) u8 {
        return @truncate(@as(c_uint, @bitCast(d.dbus_message_iter_get_arg_type(&i.it))));
    }
    fn next(i: *In) void {
        _ = d.dbus_message_iter_next(&i.it);
    }
    fn recurse(i: *In, sub: *In) void {
        d.dbus_message_iter_recurse(&i.it, &sub.it);
    }
    fn str(i: *In) ?[]const u8 {
        if (i.kind() != 's' and i.kind() != 'o') return null;
        var p: [*:0]const u8 = undefined;
        d.dbus_message_iter_get_basic(&i.it, @ptrCast(&p));
        return std.mem.span(p);
    }
    fn int(i: *In) ?i32 {
        if (i.kind() != 'i') return null;
        var v: i32 = 0;
        d.dbus_message_iter_get_basic(&i.it, @ptrCast(&v));
        return v;
    }
};

/// Os nomes de propriedade pedidos (vazio: todos).
const Names = struct {
    list: [16][]const u8 = undefined,
    n: usize = 0,

    fn read(i: *In) Names {
        var names: Names = .{};
        if (i.kind() != 'a') return names;
        var sub: In = .{};
        i.recurse(&sub);
        while (sub.str()) |s| : (sub.next()) {
            // Mais do que cabe: responde tudo, que é sempre válido.
            if (names.n == names.list.len) return .{};
            names.list[names.n] = s;
            names.n += 1;
        }
        return names;
    }
    fn slice(s: *const Names) []const []const u8 {
        return s.list[0..s.n];
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn span(p: ?[*:0]const u8) ?[]const u8 {
    return if (p) |s| std.mem.span(s) else null;
}

/// Sem interface na chamada vale qualquer uma (o membro decide).
fn isIface(iface: ?[]const u8, want: []const u8) bool {
    return iface == null or eql(iface.?, want);
}

fn isSniIface(iface: ?[]const u8) bool {
    // org.freedesktop: o nome de alguns painéis mais antigos.
    return isIface(iface, "org.kde.StatusNotifierItem") or eql(iface.?, "org.freedesktop.StatusNotifierItem");
}

fn ok(msg: *Msg) ?*Msg {
    return d.dbus_message_new_method_return(msg);
}

fn failMsg(msg: *Msg, name: [*:0]const u8, text: [*:0]const u8) ?*Msg {
    return d.dbus_message_new_error(msg, name, text);
}

fn filter(_: *Conn, msg: *Msg, _: ?*anyopaque) callconv(.c) c_int {
    switch (d.dbus_message_get_type(msg)) {
        msg_signal => {
            onSignal(msg);
            return not_yet;
        },
        msg_method_call => {},
        else => return not_yet,
    }
    const path = span(d.dbus_message_get_path(msg)) orelse return not_yet;
    const member = span(d.dbus_message_get_member(msg)) orelse return not_yet;
    const iface = span(d.dbus_message_get_interface(msg));
    // Nulo: não é nosso, e a libdbus responde que o método não existe.
    const reply = answer(msg, path, iface, member) orelse return not_yet;
    if (d.dbus_message_get_no_reply(msg) == 0) _ = d.dbus_connection_send(conn, reply, null);
    d.dbus_message_unref(reply);
    return handled;
}

fn onSignal(msg: *Msg) void {
    const sender = span(d.dbus_message_get_sender(msg)) orelse return;
    const iface = span(d.dbus_message_get_interface(msg)) orelse return;
    const member = span(d.dbus_message_get_member(msg)) orelse return;
    if (!eql(sender, "org.freedesktop.DBus") or !eql(iface, "org.freedesktop.DBus") or !eql(member, "NameOwnerChanged")) return;
    var in: In = .{};
    if (!in.start(msg)) return;
    const name = in.str() orelse return;
    in.next();
    in.next();
    const new = in.str() orelse return;
    // O painel (re)começou: o registro antigo foi com ele.
    if (eql(name, watcher) and new.len > 0) {
        retries = 0;
        retry_at_ms = -1;
        register();
    }
}

fn answer(msg: *Msg, path: []const u8, iface: ?[]const u8, member: []const u8) ?*Msg {
    if (eql(member, "Introspect") and isIface(iface, intro_iface)) return introspect(msg, path);
    if (eql(path, item_path)) {
        if (isIface(iface, props_iface)) {
            if (eql(member, "Get")) return propGet(msg, .item);
            if (eql(member, "GetAll")) return propGetAll(msg, .item);
            if (eql(member, "Set")) return failMsg(msg, "org.freedesktop.DBus.Error.PropertyReadOnly", "somente leitura");
        }
        if (isSniIface(iface)) {
            if (eql(member, "Activate") or eql(member, "SecondaryActivate")) {
                activate();
                return ok(msg);
            }
            // O menu o painel abre sozinho, pelo Menu; a rolagem não faz nada.
            if (eql(member, "ContextMenu") or eql(member, "Scroll")) return ok(msg);
            if (eql(member, "ProvideXdgActivationToken")) {
                provideToken(msg);
                return ok(msg);
            }
        }
        return null;
    }
    if (eql(path, menu_path)) {
        if (isIface(iface, props_iface)) {
            if (eql(member, "Get")) return propGet(msg, .menu);
            if (eql(member, "GetAll")) return propGetAll(msg, .menu);
            if (eql(member, "Set")) return failMsg(msg, "org.freedesktop.DBus.Error.PropertyReadOnly", "somente leitura");
        }
        if (isIface(iface, menu_iface)) {
            if (eql(member, "GetLayout")) return getLayout(msg);
            if (eql(member, "GetGroupProperties")) return getGroupProperties(msg);
            if (eql(member, "GetProperty")) return getProperty(msg);
            if (eql(member, "Event")) return event(msg);
            if (eql(member, "EventGroup")) return eventGroup(msg);
            if (eql(member, "AboutToShow")) {
                const r = ok(msg) orelse return null;
                var out: Out = .{};
                d.dbus_message_iter_init_append(r, &out.it);
                out.boolean(false);
                return r;
            }
            if (eql(member, "AboutToShowGroup")) {
                const r = ok(msg) orelse return null;
                var out: Out = .{};
                d.dbus_message_iter_init_append(r, &out.it);
                var a: Out = .{};
                out.open(&a, 'a', "i");
                out.close(&a);
                out.open(&a, 'a', "i");
                out.close(&a);
                return r;
            }
        }
        return null;
    }
    return null;
}

// --- org.kde.StatusNotifierItem ------------------------------------------------

/// O clique no ícone. Um clique duplo manda dois Activate: o segundo, logo depois,
/// não desfaz o primeiro (como no Windows).
fn activate() void {
    const now = nowMs();
    if (!janela.trayClickCounts(if (last_activate_ms < 0) -1 else now - last_activate_ms, 400)) return;
    last_activate_ms = now;
    say(&.{bandeja.msg_toggle});
}

/// A ficha do xdg-activation que o painel manda antes do Activate: vai para o app,
/// que a passa ao SDL para a janela voltar com o foco no Wayland.
fn provideToken(msg: *Msg) void {
    var in: In = .{};
    if (!in.start(msg)) return;
    const token = in.str() orelse return;
    var buf: [2 + bandeja.token_max]u8 = undefined;
    if (bandeja.tokenMsg(&buf, token)) |m| say(m);
}

const Obj = enum { item, menu };

/// As propriedades, com o nome exato do protocolo.
const ItemProp = enum {
    Category,
    Id,
    Title,
    Status,
    WindowId,
    IconName,
    IconThemePath,
    IconPixmap,
    OverlayIconName,
    OverlayIconPixmap,
    AttentionIconName,
    AttentionIconPixmap,
    AttentionMovieName,
    ToolTip,
    ItemIsMenu,
    Menu,
};
const MenuProp = enum { Version, TextDirection, Status, IconThemePath };

fn itemValue(o: *Out, p: ItemProp) void {
    var v: Out = .{};
    switch (p) {
        .Category => o.variantStr("Communications"),
        .Id => o.variantStr("larpercord"),
        .Title => o.variantStr("larperCord"),
        .Status => o.variantStr("Active"),
        // Sem nome de tema de ícones: o desenho vai inteiro em IconPixmap.
        .IconName, .IconThemePath, .OverlayIconName, .AttentionIconName, .AttentionMovieName => o.variantStr(""),
        .WindowId => {
            o.open(&v, 'v', "i");
            v.int(0);
            o.close(&v);
        },
        .IconPixmap, .OverlayIconPixmap, .AttentionIconPixmap => {
            o.open(&v, 'v', "a(iiay)");
            v.pixmapList(if (p == .IconPixmap) pixmaps else &.{});
            o.close(&v);
        },
        .ToolTip => {
            o.open(&v, 'v', "(sa(iiay)ss)");
            var st: Out = .{};
            v.open(&st, 'r', null);
            st.str("");
            st.pixmapList(&.{});
            st.str("larperCord");
            st.str("");
            v.close(&st);
            o.close(&v);
        },
        // Falso: o clique esquerdo vem como Activate, e o menu fica no botão direito.
        .ItemIsMenu => o.variantBool(false),
        .Menu => {
            o.open(&v, 'v', "o");
            v.objPath(menu_path);
            o.close(&v);
        },
    }
}

fn menuValue(o: *Out, p: MenuProp) void {
    var v: Out = .{};
    switch (p) {
        .Version => {
            o.open(&v, 'v', "u");
            v.uint(3);
            o.close(&v);
        },
        .TextDirection => o.variantStr("ltr"),
        .Status => o.variantStr("normal"),
        .IconThemePath => {
            o.open(&v, 'v', "as");
            var a: Out = .{};
            v.open(&a, 'a', "s");
            v.close(&a);
            o.close(&v);
        },
    }
}

/// O valor da propriedade como variante. Falso: não existe.
fn propValue(o: *Out, obj: Obj, name: []const u8) bool {
    switch (obj) {
        .item => itemValue(o, std.meta.stringToEnum(ItemProp, name) orelse return false),
        .menu => menuValue(o, std.meta.stringToEnum(MenuProp, name) orelse return false),
    }
    return true;
}

fn ifaceOf(obj: Obj, iface: []const u8) bool {
    return switch (obj) {
        .item => isSniIface(iface),
        .menu => eql(iface, menu_iface),
    };
}

fn propGet(msg: *Msg, obj: Obj) ?*Msg {
    var in: In = .{};
    if (!in.start(msg)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "faltam argumentos");
    const iface = in.str() orelse return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "interface");
    in.next();
    const name = in.str() orelse return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "propriedade");
    if (!ifaceOf(obj, iface)) return failMsg(msg, "org.freedesktop.DBus.Error.UnknownInterface", "interface desconhecida");
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    if (!propValue(&out, obj, name)) {
        d.dbus_message_unref(r);
        return failMsg(msg, "org.freedesktop.DBus.Error.UnknownProperty", "propriedade desconhecida");
    }
    return r;
}

fn propGetAll(msg: *Msg, obj: Obj) ?*Msg {
    var in: In = .{};
    const iface = if (in.start(msg)) in.str() orelse "" else "";
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    var dict: Out = .{};
    out.open(&dict, 'a', "{sv}");
    var e: Out = .{};
    // Outra interface: dicionário vazio.
    if (ifaceOf(obj, iface)) switch (obj) {
        .item => for (std.enums.values(ItemProp)) |p| {
            dict.entry(&e, @tagName(p));
            itemValue(&e, p);
            dict.close(&e);
        },
        .menu => for (std.enums.values(MenuProp)) |p| {
            dict.entry(&e, @tagName(p));
            menuValue(&e, p);
            dict.close(&e);
        },
    };
    out.close(&dict);
    return r;
}

// --- com.canonical.dbusmenu ----------------------------------------------------

fn menuValid(id: i32) bool {
    return id == 0 or bandeja.menuClick(id) != null;
}

/// As propriedades de um item, só as pedidas.
fn menuProps(o: *Out, id: i32, names: []const []const u8) void {
    var dict: Out = .{};
    o.open(&dict, 'a', "{sv}");
    var e: Out = .{};
    if (id == 0) {
        if (bandeja.wanted(names, "children-display")) {
            dict.entry(&e, "children-display");
            e.variantStr("submenu");
            dict.close(&e);
        }
    } else {
        if (bandeja.wanted(names, "label")) {
            dict.entry(&e, "label");
            e.variantStr(if (id == bandeja.menu_open) open_label else quit_label);
            dict.close(&e);
        }
        if (bandeja.wanted(names, "enabled")) {
            dict.entry(&e, "enabled");
            e.variantBool(true);
            dict.close(&e);
        }
        if (bandeja.wanted(names, "visible")) {
            dict.entry(&e, "visible");
            e.variantBool(true);
            dict.close(&e);
        }
    }
    o.close(&dict);
}

/// (ia{sv}av): o item, as propriedades e os filhos até `depth` (-1: todos).
fn menuItem(o: *Out, id: i32, depth: i32, names: []const []const u8) void {
    var st: Out = .{};
    o.open(&st, 'r', null);
    st.int(id);
    menuProps(&st, id, names);
    var kids: Out = .{};
    st.open(&kids, 'a', "v");
    if (id == 0 and depth != 0) {
        for ([_]i32{ bandeja.menu_open, bandeja.menu_quit }) |k| {
            var v: Out = .{};
            kids.open(&v, 'v', "(ia{sv}av)");
            menuItem(&v, k, if (depth > 0) depth - 1 else -1, names);
            kids.close(&v);
        }
    }
    st.close(&kids);
    o.close(&st);
}

fn getLayout(msg: *Msg) ?*Msg {
    var in: In = .{};
    if (!in.start(msg)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "faltam argumentos");
    const parent = in.int() orelse 0;
    in.next();
    const depth = in.int() orelse -1;
    in.next();
    const names = Names.read(&in);
    if (!menuValid(parent)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "item desconhecido");
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    // O menu nunca muda dentro do processo: os rótulos novos vêm num processo novo.
    out.uint(1);
    menuItem(&out, parent, depth, names.slice());
    return r;
}

fn getGroupProperties(msg: *Msg) ?*Msg {
    var in: In = .{};
    var ids_buf: [16]i32 = undefined;
    var n_ids: usize = 0;
    var names: Names = .{};
    if (in.start(msg)) {
        if (in.kind() == 'a') {
            var sub: In = .{};
            in.recurse(&sub);
            while (sub.int()) |id| : (sub.next()) {
                if (n_ids == ids_buf.len) break;
                ids_buf[n_ids] = id;
                n_ids += 1;
            }
        }
        in.next();
        names = Names.read(&in);
    }
    const all = [_]i32{ 0, bandeja.menu_open, bandeja.menu_quit };
    const ids: []const i32 = if (n_ids == 0) &all else ids_buf[0..n_ids];
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    var arr: Out = .{};
    out.open(&arr, 'a', "(ia{sv})");
    for (ids) |id| {
        if (!menuValid(id)) continue;
        var st: Out = .{};
        arr.open(&st, 'r', null);
        st.int(id);
        menuProps(&st, id, names.slice());
        arr.close(&st);
    }
    out.close(&arr);
    return r;
}

fn getProperty(msg: *Msg) ?*Msg {
    var in: In = .{};
    if (!in.start(msg)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "faltam argumentos");
    const id = in.int() orelse -1;
    in.next();
    const name = in.str() orelse "";
    if (!menuValid(id)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "item desconhecido");
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    if (id == 0 and eql(name, "children-display")) out.variantStr("submenu") //
    else if (id != 0 and eql(name, "label")) out.variantStr(if (id == bandeja.menu_open) open_label else quit_label) //
    else if (id != 0 and (eql(name, "enabled") or eql(name, "visible"))) out.variantBool(true) //
    else {
        d.dbus_message_unref(r);
        return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "propriedade desconhecida");
    }
    return r;
}

/// "clicked" num item: Abrir ou Sair vão para o app.
fn menuEvent(id: i32, kind: []const u8) bool {
    if (!menuValid(id)) return false;
    if (eql(kind, "clicked")) if (bandeja.menuClick(id)) |m| say(&.{m});
    return true;
}

fn event(msg: *Msg) ?*Msg {
    var in: In = .{};
    if (!in.start(msg)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "faltam argumentos");
    const id = in.int() orelse -1;
    in.next();
    const kind = in.str() orelse "";
    if (!menuEvent(id, kind)) return failMsg(msg, "org.freedesktop.DBus.Error.InvalidArgs", "item desconhecido");
    return ok(msg);
}

fn eventGroup(msg: *Msg) ?*Msg {
    var bad_buf: [16]i32 = undefined;
    var n_bad: usize = 0;
    var in: In = .{};
    if (in.start(msg) and in.kind() == 'a') {
        var arr: In = .{};
        in.recurse(&arr);
        while (arr.kind() == 'r') : (arr.next()) {
            var st: In = .{};
            arr.recurse(&st);
            const id = st.int() orelse continue;
            st.next();
            const kind = st.str() orelse "";
            if (!menuEvent(id, kind) and n_bad < bad_buf.len) {
                bad_buf[n_bad] = id;
                n_bad += 1;
            }
        }
    }
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    var a: Out = .{};
    out.open(&a, 'a', "i");
    for (bad_buf[0..n_bad]) |id| a.int(id);
    out.close(&a);
    return r;
}

// --- Introspecção --------------------------------------------------------------

const xml_head =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\ "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\
;
const xml_common =
    \\  <interface name="org.freedesktop.DBus.Properties">
    \\    <method name="Get"><arg name="interface_name" type="s" direction="in"/><arg name="property_name" type="s" direction="in"/><arg name="value" type="v" direction="out"/></method>
    \\    <method name="GetAll"><arg name="interface_name" type="s" direction="in"/><arg name="properties" type="a{sv}" direction="out"/></method>
    \\    <method name="Set"><arg name="interface_name" type="s" direction="in"/><arg name="property_name" type="s" direction="in"/><arg name="value" type="v" direction="in"/></method>
    \\    <signal name="PropertiesChanged"><arg name="interface_name" type="s"/><arg name="changed_properties" type="a{sv}"/><arg name="invalidated_properties" type="as"/></signal>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Introspectable">
    \\    <method name="Introspect"><arg name="xml_data" type="s" direction="out"/></method>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Peer">
    \\    <method name="Ping"/>
    \\    <method name="GetMachineId"><arg name="machine_uuid" type="s" direction="out"/></method>
    \\  </interface>
    \\
;
const xml_item = xml_head ++
    \\<node>
    \\  <interface name="org.kde.StatusNotifierItem">
    \\    <property name="Category" type="s" access="read"/>
    \\    <property name="Id" type="s" access="read"/>
    \\    <property name="Title" type="s" access="read"/>
    \\    <property name="Status" type="s" access="read"/>
    \\    <property name="WindowId" type="i" access="read"/>
    \\    <property name="IconName" type="s" access="read"/>
    \\    <property name="IconThemePath" type="s" access="read"/>
    \\    <property name="IconPixmap" type="a(iiay)" access="read"/>
    \\    <property name="OverlayIconName" type="s" access="read"/>
    \\    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    \\    <property name="AttentionIconName" type="s" access="read"/>
    \\    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    \\    <property name="AttentionMovieName" type="s" access="read"/>
    \\    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    \\    <property name="ItemIsMenu" type="b" access="read"/>
    \\    <property name="Menu" type="o" access="read"/>
    \\    <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    \\    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    \\    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    \\    <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
    \\    <method name="ProvideXdgActivationToken"><arg name="token" type="s" direction="in"/></method>
    \\    <signal name="NewTitle"/>
    \\    <signal name="NewIcon"/>
    \\    <signal name="NewAttentionIcon"/>
    \\    <signal name="NewOverlayIcon"/>
    \\    <signal name="NewToolTip"/>
    \\    <signal name="NewStatus"><arg name="status" type="s"/></signal>
    \\  </interface>
    \\
++ xml_common ++ "</node>\n";
const xml_menu = xml_head ++
    \\<node>
    \\  <interface name="com.canonical.dbusmenu">
    \\    <property name="Version" type="u" access="read"/>
    \\    <property name="TextDirection" type="s" access="read"/>
    \\    <property name="Status" type="s" access="read"/>
    \\    <property name="IconThemePath" type="as" access="read"/>
    \\    <method name="GetLayout"><arg name="parentId" type="i" direction="in"/><arg name="recursionDepth" type="i" direction="in"/><arg name="propertyNames" type="as" direction="in"/><arg name="revision" type="u" direction="out"/><arg name="layout" type="(ia{sv}av)" direction="out"/></method>
    \\    <method name="GetGroupProperties"><arg name="ids" type="ai" direction="in"/><arg name="propertyNames" type="as" direction="in"/><arg name="properties" type="a(ia{sv})" direction="out"/></method>
    \\    <method name="GetProperty"><arg name="id" type="i" direction="in"/><arg name="name" type="s" direction="in"/><arg name="value" type="v" direction="out"/></method>
    \\    <method name="Event"><arg name="id" type="i" direction="in"/><arg name="eventId" type="s" direction="in"/><arg name="data" type="v" direction="in"/><arg name="timestamp" type="u" direction="in"/></method>
    \\    <method name="EventGroup"><arg name="events" type="a(isvu)" direction="in"/><arg name="idErrors" type="ai" direction="out"/></method>
    \\    <method name="AboutToShow"><arg name="id" type="i" direction="in"/><arg name="needUpdate" type="b" direction="out"/></method>
    \\    <method name="AboutToShowGroup"><arg name="ids" type="ai" direction="in"/><arg name="updatesNeeded" type="ai" direction="out"/><arg name="idErrors" type="ai" direction="out"/></method>
    \\    <signal name="ItemsPropertiesUpdated"><arg name="updatedProps" type="a(ia{sv})"/><arg name="removedProps" type="a(ias)"/></signal>
    \\    <signal name="LayoutUpdated"><arg name="revision" type="u"/><arg name="parent" type="i"/></signal>
    \\    <signal name="ItemActivationRequested"><arg name="id" type="i"/><arg name="timestamp" type="u"/></signal>
    \\  </interface>
    \\
++ xml_common ++ "</node>\n";
const xml_root = xml_head ++
    \\<node>
    \\  <node name="StatusNotifierItem"/>
    \\  <node name="MenuBar"/>
    \\</node>
    \\
;

fn introspect(msg: *Msg, path: []const u8) ?*Msg {
    const xml: [:0]const u8 = if (eql(path, item_path)) xml_item else if (eql(path, menu_path)) xml_menu else if (eql(path, "/")) xml_root else return null;
    const r = ok(msg) orelse return null;
    var out: Out = .{};
    d.dbus_message_iter_init_append(r, &out.it);
    out.str(xml.ptr);
    return r;
}
