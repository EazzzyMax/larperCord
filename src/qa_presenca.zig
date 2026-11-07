//! QA do Rich Presence: a opção liga o discord-ipc (no XDG_RUNTIME_DIR do QA), um
//! jogo de mentira conecta, faz o handshake e manda a atividade, e o gateway de
//! mentira recebe o op 3. Null, desconexão e desligar limpam. Só no Linux (o
//! cliente daqui fala pelo socket Unix). tools/qa.sh dá um XDG_RUNTIME_DIR só do
//! QA: o cliente fala com o caminho que o servidor escolheu, nunca com um
//! Discord de verdade que esteja aberto.
const std = @import("std");
const c = @import("c");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const rpc = @import("net/rpc_ipc.zig");
const proto = @import("net/rpc_proto.zig");

fn s(name: []const u8) Op {
    return .{ .section = name };
}
fn click(k: []const u8) Op {
    return .{ .click = .{ .mark = k } };
}
fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 5000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

const toggle = "toggle:Compartilhar minha atividade (Rich Presence)";
const client_id = "1234567890";

// --- O jogo de mentira -----------------------------------------------------------

var fd: c_int = -1;
var rx: [32 * 1024]u8 = undefined;
var rx_len: usize = 0;
/// Onde o servidor escutou (o QA confere que o arquivo some ao desligar).
var path_buf: [256]u8 = @splat(0);
var path_len: usize = 0;

fn sockPath() [:0]const u8 {
    return path_buf[0..path_len :0];
}

fn connectClient() void {
    closeClient();
    const p = sockPath();
    var addr: extern struct { family: u16, path: [108]u8 } = .{ .family = c.AF_UNIX, .path = @splat(0) };
    if (p.len == 0 or p.len >= addr.path.len) return;
    @memcpy(addr.path[0..p.len], p);
    const f = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0);
    if (f < 0) return;
    if (c.connect(f, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) != 0) {
        _ = c.close(f);
        return;
    }
    _ = c.fcntl(f, c.F_SETFL, c.O_NONBLOCK);
    fd = f;
    rx_len = 0;
}

fn closeClient() void {
    if (fd >= 0) _ = c.close(fd);
    fd = -1;
}

fn sendRaw(bytes: []const u8) void {
    if (fd < 0) return;
    _ = c.send(fd, bytes.ptr, bytes.len, 0x4000);
}

fn sendFrame(op: u32, json: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.c_allocator);
    proto.writeFrame(&out, std.heap.c_allocator, op, json) catch return;
    sendRaw(out.items);
}

/// O que o servidor respondeu até agora (sem bloquear).
fn received() []const u8 {
    while (fd >= 0 and rx_len < rx.len) {
        const r = c.recv(fd, rx[rx_len..].ptr, rx.len - rx_len, 0);
        if (r <= 0) break;
        rx_len += @intCast(r);
    }
    return rx[0..rx_len];
}

fn got(needle: []const u8) bool {
    return std.mem.indexOf(u8, received(), needle) != null;
}

// --- Passos ------------------------------------------------------------------------

fn fileMode() ?u32 {
    const p = sockPath();
    if (p.len == 0) return null;
    var st: c.struct_stat = undefined;
    if (c.lstat(p.ptr, &st) != 0) return null;
    return @intCast(st.st_mode);
}

fn offNothing(_: *App) bool {
    return !rpc.running() and rpc.path().len == 0;
}

fn openPrivacy(app: *App) void {
    app.st.settings.page = .privacidade;
    app.st.settings.open = true;
}

fn closeSettings(app: *App) void {
    app.st.settings.open = false;
}

fn onSocket(app: *App) bool {
    if (!rpc.running()) return false;
    const p = rpc.path();
    if (p.len >= path_buf.len) return false;
    @memcpy(path_buf[0..p.len], p);
    path_buf[p.len] = 0;
    path_len = p.len;
    const dir = std.mem.span(c.SDL_getenv("XDG_RUNTIME_DIR") orelse return false);
    const mode = fileMode() orelse return false;
    // Socket (S_IFSOCK) só do dono, em $XDG_RUNTIME_DIR/discord-ipc-N, com a opção salva.
    return app.st.settings.rich_presence and std.mem.startsWith(u8, p, dir) and std.mem.indexOf(u8, p[dir.len..], "/discord-ipc-") != null and
        mode & 0o170000 == 0o140000 and mode & 0o777 == 0o600;
}

fn handshake(_: *App) void {
    connectClient();
    sendFrame(proto.op_handshake, "{\"v\":1,\"client_id\":\"" ++ client_id ++ "\"}");
}

fn readyReply(app: *App) bool {
    var b: [64]u8 = undefined;
    const id = std.fmt.bufPrint(&b, "\"user\":{{\"id\":\"{d}\"", .{app.store.me}) catch return false;
    return got("\"evt\":\"READY\"") and got(id) and got("\"discriminator\":\"0\"");
}

var presences_before: u64 = 0;
fn notePresences() void {
    presences_before = gw.sent.presences.load(.acquire);
}

fn lastOp3() []const u8 {
    return gw.sent.presence[0..gw.sent.presence_len.load(.acquire)];
}

fn op3Has(needles: []const []const u8) bool {
    if (gw.sent.presences.load(.acquire) <= presences_before) return false;
    for (needles) |n| if (std.mem.indexOf(u8, lastOp3(), n) == null) return false;
    return true;
}

fn activityFrame(nonce: []const u8, details: []const u8) void {
    var b: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&b, "{{\"cmd\":\"SET_ACTIVITY\",\"nonce\":\"{s}\",\"args\":{{\"pid\":{d},\"activity\":{{\"details\":\"{s}\",\"state\":\"No menu\",\"timestamps\":{{\"start\":1700000000}},\"assets\":{{\"large_image\":\"logo\",\"large_text\":\"Logo do jogo\"}}}}}}}}", .{ nonce, c.getpid(), details }) catch return;
    sendFrame(proto.op_frame, json);
}

fn setActivity(_: *App) void {
    notePresences();
    activityFrame("qa-1", "Fase 3");
}

fn activityReply(_: *App) bool {
    return got("\"cmd\":\"SET_ACTIVITY\",\"data\":{") and got("\"nonce\":\"qa-1\"");
}

fn op3Activity(_: *App) bool {
    return op3Has(&.{ "\"status\":\"online\"", "\"name\":\"Jogo de Teste\"", "\"application_id\":\"" ++ client_id ++ "\"", "\"details\":\"Fase 3\"", "\"start\":1700000000000", "\"large_image\":\"4242\"" });
}

fn myActivities(app: *App) []const @import("core/types.zig").Activity {
    return app.store.activities.get(app.store.me) orelse &.{};
}

fn panelShows(app: *App) bool {
    const acts = myActivities(app);
    const me = app.store.user(app.store.me) orelse return false;
    return acts.len == 1 and std.mem.eql(u8, acts[0].details, "Fase 3") and std.mem.eql(u8, acts[0].name, "Jogo de Teste") and
        me.activity != null and std.mem.endsWith(u8, me.activity.?, "Jogo de Teste") and qa.find("me-activity") != null;
}

fn unknownCmd(_: *App) void {
    sendFrame(proto.op_frame, "{\"cmd\":\"SUBSCRIBE\",\"nonce\":\"qa-2\",\"evt\":\"ACTIVITY_JOIN\",\"args\":{}}");
}

fn unknownReply(_: *App) bool {
    return got("{\"cmd\":\"SUBSCRIBE\",\"evt\":\"ERROR\",\"data\":{\"code\":4000,\"message\":\"not supported\"},\"nonce\":\"qa-2\"}");
}

fn clearActivity(_: *App) void {
    notePresences();
    sendFrame(proto.op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"nonce\":\"qa-3\",\"args\":{\"pid\":1,\"activity\":null}}");
}

fn cleared(app: *App) bool {
    const me = app.store.user(app.store.me) orelse return false;
    return op3Has(&.{ "\"activities\":[]", "\"status\":\"online\"" }) and myActivities(app).len == 0 and me.activity == null and qa.find("me-activity") == null;
}

fn setAgain(_: *App) void {
    notePresences();
    activityFrame("qa-4", "Fase 4");
}

fn op3Again(_: *App) bool {
    return op3Has(&.{"\"details\":\"Fase 4\""});
}

fn disconnect(_: *App) void {
    notePresences();
    closeClient();
}

fn clearedAfterDisconnect(app: *App) bool {
    return op3Has(&.{"\"activities\":[]"}) and myActivities(app).len == 0;
}

fn garbage(_: *App) void {
    connectClient();
    // Op desconhecido e tamanho absurdo: a conexão cai, o servidor fica.
    sendRaw("\x09\x00\x00\x00\xff\xff\xff\xff{lixo");
}

fn garbageDropped(_: *App) bool {
    if (!rpc.running()) return false;
    // O servidor fechou: o recv dá 0 (fim) depois do quadro de CLOSE.
    var junk: [256]u8 = undefined;
    const r = c.recv(fd, &junk, junk.len, 0);
    return r == 0 or (r > 0 and junk[0] == proto.op_close);
}

fn dndActivity(app: *App) void {
    app.handle(.{ .set_status = .dnd });
    handshake(app);
    notePresences();
    activityFrame("qa-5", "Fase 5");
}

fn op3KeepsStatus(_: *App) bool {
    return op3Has(&.{ "\"status\":\"dnd\"", "\"details\":\"Fase 5\"" });
}

fn turnOff(app: *App) void {
    notePresences();
    openPrivacy(app);
}

fn offCleared(app: *App) bool {
    return !app.st.settings.rich_presence and offNothing(app) and path_len > 0 and fileMode() == null and op3Has(&.{"\"activities\":[]"});
}

fn restore(app: *App) void {
    closeClient();
    closeSettings(app);
    app.handle(.{ .set_status = .online });
}

pub const ops = [_]Op{
    s("presenca"),
    expect("desligado: nenhum socket, nenhuma thread", offNothing),
    run(openPrivacy),
    click(toggle),
    expect("ligado: socket só do dono em $XDG_RUNTIME_DIR/discord-ipc-N", onSocket),
    run(closeSettings),
    run(handshake),
    expect("handshake responde READY com o nosso usuário", readyReply),
    run(setActivity),
    expect("SET_ACTIVITY responde com o mesmo nonce", activityReply),
    expect("o gateway recebe o op 3 com o nome da aplicação e a imagem resolvida", op3Activity),
    expect("a atividade aparece no nosso painel e no perfil", panelShows),
    .{ .shot = "presenca-painel" },
    run(unknownCmd),
    expect("comando sem suporte responde ERROR 4000 com o nonce", unknownReply),
    run(clearActivity),
    expect("atividade null limpa (op 3 sem atividades, painel volta ao status)", cleared),
    run(setAgain),
    expect("a atividade volta", op3Again),
    run(disconnect),
    expect("o jogo desconectar limpa a atividade", clearedAfterDisconnect),
    run(garbage),
    expect("lixo derruba só aquela conexão", garbageDropped),
    run(dndActivity),
    expect("a atividade vai junto com o status escolhido (não perturbe)", op3KeepsStatus),
    run(turnOff),
    click(toggle),
    expect("desligar apaga o socket, para a thread e limpa a atividade", offCleared),
    run(restore),
};
