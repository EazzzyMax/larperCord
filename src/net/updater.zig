//! Atualização: pergunta ao GitHub qual é a última versão, baixa os arquivos
//! desta plataforma, confere o SHA256SUMS (assinado) e troca o executável que
//! está rodando (no caminho e com o nome dele) e as DLLs ao lado. Quem pede o
//! reinício é a interface. Roda numa thread só dela, e nada aqui existe enquanto
//! ninguém pede. Nenhum dado da conta vai junto.
const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");
const version = @import("../core/version.zig");
const at = @import("../core/atualizacao.zig");
const sys = @import("../platform/sys.zig");
const proxy = @import("proxy.zig");

const alloc = std.heap.c_allocator;

pub const current: []const u8 = build_options.version;
const latest_url = "https://api.github.com/repos/RshaCuDeVidro/larperCord/releases/latest";
pub const releases_page = "https://github.com/RshaCuDeVidro/larperCord/releases";

/// Arquivos publicados desta plataforma e onde cada um fica (core/atualizacao.zig).
const files = at.files(sys.windows);

/// O executável que está rodando, num caminho que existe: depois da troca, o
/// nome dele já é o da versão nova. null se o sistema não disser.
fn selfPath(buf: []u8) ?[]const u8 {
    const raw = sys.selfExe(buf) orelse return null;
    const p = at.liveExe(raw);
    return if (p.len == 0) null else p;
}

pub const Phase = enum { idle, checking, up_to_date, available, downloading, ready, failed };
pub const Error = enum { none, network, no_release, bad_signature, bad_hash, read_only, disk };

pub const Status = struct {
    phase: Phase = .idle,
    err: Error = .none,
    /// De 0 a 100, enquanto baixa.
    percent: u8 = 0,
    latest_buf: [32]u8 = @splat(0),
    latest_len: u8 = 0,

    pub fn latest(s: *const Status) []const u8 {
        return s.latest_buf[0..s.latest_len];
    }
};

var mutex: ?*c.SDL_Mutex = null;
var status: Status = .{};
var busy = std.atomic.Value(bool).init(false);
/// QA: nada de rede; só mostra o que a tela faria.
pub var offline = false;
var wake_fn: ?*const fn () void = null;
/// Aviso de "tem versão nova" que a interface ainda não mostrou.
var notice_pending = std.atomic.Value(bool).init(false);
/// Links dos arquivos da última resposta (nome -> URL).
var assets: std.StringHashMapUnmanaged([]u8) = .empty;

pub fn setup(wake: *const fn () void) void {
    wake_fn = wake;
    if (mutex == null) mutex = c.SDL_CreateMutex();
}

pub fn snapshot() Status {
    const m = mutex orelse return .{};
    c.SDL_LockMutex(m);
    defer c.SDL_UnlockMutex(m);
    return status;
}

/// A interface deve avisar que há versão nova? (Uma vez por verificação.)
pub fn takeNotice() bool {
    return notice_pending.swap(false, .acq_rel);
}

fn set(phase: Phase, err: Error, percent: u8) void {
    const m = mutex orelse return;
    c.SDL_LockMutex(m);
    status.phase = phase;
    status.err = err;
    status.percent = percent;
    c.SDL_UnlockMutex(m);
    if (wake_fn) |w| w();
}

/// Só para o QA: mostra um estado sem rede nenhuma.
pub fn qaSet(phase: Phase, tag: []const u8) void {
    const m = mutex orelse return;
    c.SDL_LockMutex(m);
    status = .{ .phase = phase };
    const n = @min(tag.len, status.latest_buf.len);
    @memcpy(status.latest_buf[0..n], tag[0..n]);
    status.latest_len = @intCast(n);
    c.SDL_UnlockMutex(m);
}

fn start(f: *const fn (?*anyopaque) callconv(.c) c_int) void {
    if (mutex == null or busy.swap(true, .acq_rel)) return;
    if (c.SDL_CreateThread(f, "update", null)) |t| c.SDL_DetachThread(t) else busy.store(false, .release);
}

/// Pergunta se há versão nova (não bloqueia).
pub fn check() void {
    if (offline) return qaSet(.up_to_date, current);
    start(checkThread);
}

/// Baixa e instala a versão que `check` achou (não bloqueia).
pub fn install() void {
    if (offline) return qaSet(.ready, snapshot().latest());
    start(installThread);
}

fn checkThread(_: ?*anyopaque) callconv(.c) c_int {
    defer busy.store(false, .release);
    set(.checking, .none, 0);
    runCheck() catch |e| set(.failed, errorOf(e), 0);
    return 0;
}

fn installThread(_: ?*anyopaque) callconv(.c) c_int {
    defer busy.store(false, .release);
    set(.downloading, .none, 0);
    runInstall() catch |e| set(.failed, errorOf(e), 0);
    return 0;
}

fn errorOf(e: anyerror) Error {
    return switch (e) {
        error.NoRelease => .no_release,
        error.BadSignature => .bad_signature,
        error.BadHash => .bad_hash,
        error.ReadOnly => .read_only,
        error.Disk => .disk,
        else => .network,
    };
}

const Sink = struct {
    out: *std.ArrayList(u8),
    max: usize,
    progress: ?*std.atomic.Value(usize) = null,
    last_wake: usize = 0,
    fn write(ptr: [*c]u8, size: usize, n: usize, ud: ?*anyopaque) callconv(.c) usize {
        const s: *Sink = @ptrCast(@alignCast(ud.?));
        const total = size * n;
        if (s.out.items.len + total > s.max) return 0;
        s.out.appendSlice(alloc, ptr[0..total]) catch return 0;
        if (s.progress) |p| {
            p.store(s.out.items.len, .monotonic);
            // Uma atualização de tela a cada MB, não uma por pacote.
            if (s.out.items.len - s.last_wake >= 1024 * 1024) {
                s.last_wake = s.out.items.len;
                wakeUi();
            }
        }
        return total;
    }
};

pub fn wakeUi() void {
    if (wake_fn) |w| w();
}

pub fn fetch(url: [:0]const u8, out: *std.ArrayList(u8), max: usize, progress: ?*std.atomic.Value(usize)) !void {
    const h = c.curl_easy_init() orelse return error.Network;
    defer c.curl_easy_cleanup(h);
    var sink: Sink = .{ .out = out, .max = max, .progress = progress };
    var ua_buf: [48]u8 = undefined;
    const ua = std.fmt.bufPrintSentinel(&ua_buf, "larperCord/{s}", .{current}, 0) catch "larperCord";
    _ = c.curl_easy_setopt(h, c.CURLOPT_URL, url.ptr);
    _ = c.curl_easy_setopt(h, c.CURLOPT_USERAGENT, ua.ptr);
    _ = c.curl_easy_setopt(h, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = c.curl_easy_setopt(h, c.CURLOPT_MAXREDIRS, @as(c_long, 5));
    // Só HTTPS, inclusive nos redirecionamentos.
    _ = c.curl_easy_setopt(h, c.CURLOPT_PROTOCOLS_STR, "https");
    _ = c.curl_easy_setopt(h, c.CURLOPT_REDIR_PROTOCOLS_STR, "https");
    _ = c.curl_easy_setopt(h, c.CURLOPT_CONNECTTIMEOUT, @as(c_long, 15));
    _ = c.curl_easy_setopt(h, c.CURLOPT_LOW_SPEED_LIMIT, @as(c_long, 1024));
    _ = c.curl_easy_setopt(h, c.CURLOPT_LOW_SPEED_TIME, @as(c_long, 30));
    _ = c.curl_easy_setopt(h, c.CURLOPT_WRITEFUNCTION, Sink.write);
    _ = c.curl_easy_setopt(h, c.CURLOPT_WRITEDATA, &sink);
    sys.curlTls(h);
    var pb: proxy.Buf = undefined;
    if (proxy.forUrl(&pb, url)) |p| _ = c.curl_easy_setopt(h, c.CURLOPT_PROXY, p.ptr);
    if (c.curl_easy_perform(h) != c.CURLE_OK) return error.Network;
    var code: c_long = 0;
    _ = c.curl_easy_getinfo(h, c.CURLINFO_RESPONSE_CODE, &code);
    if (code == 404) return error.NoRelease;
    if (code != 200) return error.Network;
}

fn runCheck() !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(alloc);
    try fetch(latest_url, &body, 2 * 1024 * 1024, null);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body.items, .{});
    if (v != .object) return error.Network;
    const tag_v = v.object.get("tag_name") orelse return error.NoRelease;
    if (tag_v != .string) return error.NoRelease;
    const tag = tag_v.string;
    var it = assets.iterator();
    while (it.next()) |e| {
        alloc.free(e.key_ptr.*);
        alloc.free(e.value_ptr.*);
    }
    assets.clearRetainingCapacity();
    if (v.object.get("assets")) |list| if (list == .array) for (list.array.items) |a| {
        if (a != .object) continue;
        const name = a.object.get("name") orelse continue;
        const url = a.object.get("browser_download_url") orelse continue;
        if (name != .string or url != .string) continue;
        const nk = try alloc.dupe(u8, name.string);
        const uk = try alloc.dupe(u8, url.string);
        try assets.put(alloc, nk, uk);
    };
    const m = mutex orelse return;
    c.SDL_LockMutex(m);
    const n = @min(tag.len, status.latest_buf.len);
    @memcpy(status.latest_buf[0..n], tag[0..n]);
    status.latest_len = @intCast(n);
    c.SDL_UnlockMutex(m);
    if (version.newer(tag, current)) {
        notice_pending.store(true, .release);
        set(.available, .none, 0);
    } else set(.up_to_date, .none, 0);
}

fn assetUrl(buf: []u8, name: []const u8) ![:0]const u8 {
    const u = assets.get(name) orelse return error.NoRelease;
    return std.fmt.bufPrintSentinel(buf, "{s}", .{u}, 0) catch error.NoRelease;
}

/// Instalado por um gerenciador de pacotes (a pasta do programa não é de quem usa): é ele quem
/// atualiza, e trocar o arquivo daqui daria errado de qualquer jeito.
pub fn managedBySystem() bool {
    if (sys.windows) return false;
    const base = c.SDL_GetBasePath() orelse return false;
    return c.access(base, c.W_OK) != 0;
}

fn runInstall() !void {
    var sb: [1024]u8 = undefined;
    const exe = selfPath(&sb) orelse return error.Disk;
    var ub: [1024]u8 = undefined;

    // A lista assinada vem primeiro: sem ela, nada é baixado.
    var sums: std.ArrayList(u8) = .empty;
    defer sums.deinit(alloc);
    var sig: std.ArrayList(u8) = .empty;
    defer sig.deinit(alloc);
    try fetch(try assetUrl(&ub, "SHA256SUMS"), &sums, 64 * 1024, null);
    try fetch(try assetUrl(&ub, "SHA256SUMS.sig"), &sig, 4096, null);
    if (!version.signatureOk(sums.items, sig.items, version.release_key_hex)) return error.BadSignature;

    var dir_buf: [1024]u8 = undefined;
    const stage = at.stageDir(&dir_buf, exe, sys.windows) orelse return error.Disk;
    sys.mkdirPrivate(stage.ptr);
    if (!sys.exists(stage.ptr)) return error.ReadOnly;

    // Baixa tudo antes de trocar qualquer coisa: uma falha aqui não estraga nada.
    for (files, 0..) |f, i| {
        const want = version.sumFor(sums.items, f.asset) orelse return error.BadHash;
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(alloc);
        try fetch(try assetUrl(&ub, f.asset), &data, 128 * 1024 * 1024, null);
        var got: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data.items, &got, .{});
        if (!std.mem.eql(u8, &got, &want)) return error.BadHash;
        var pb: [1100]u8 = undefined;
        const tmp = at.staged(&pb, stage, f) orelse return error.Disk;
        if (!sys.writeNew(tmp.ptr, data.items, true)) return error.Disk;
        set(.downloading, .none, @intCast((i + 1) * 90 / files.len));
    }

    var replaced: usize = 0;
    errdefer {
        // Algo falhou no meio: volta o que já tinha trocado.
        for (files[0..replaced]) |f| {
            var pb: [1100]u8 = undefined;
            const dst = at.place(&pb, exe, f, "", sys.windows) orelse continue;
            sys.restoreOld(dst.ptr);
        }
    }
    for (files) |f| {
        var pa: [1100]u8 = undefined;
        var pb: [1100]u8 = undefined;
        const src = at.staged(&pa, stage, f) orelse return error.Disk;
        const dst = at.place(&pb, exe, f, "", sys.windows) orelse return error.Disk;
        if (!sys.replaceRunning(src.ptr, dst.ptr)) return error.ReadOnly;
        replaced += 1;
    }
    _ = c.SDL_RemovePath(stage.ptr);
    set(.ready, .none, 100);
}

/// Sobras da troca anterior (no Windows o executável velho só sai depois).
pub fn cleanLeftovers() void {
    var sb: [1024]u8 = undefined;
    const exe = selfPath(&sb) orelse return;
    for (files) |f| {
        var pb: [1100]u8 = undefined;
        const old = at.place(&pb, exe, f, ".old", sys.windows) orelse continue;
        _ = c.SDL_RemovePath(old.ptr);
    }
}

/// Abre uma cópia nova do programa (no fim do `main`, depois de fechar tudo): o
/// mesmo arquivo que estava rodando, que depois de uma atualização é a versão nova.
pub fn spawnSelf() void {
    var sb: [1024]u8 = undefined;
    const exe = selfPath(&sb) orelse return;
    var pb: [1100]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&pb, "{s}", .{exe}, 0) catch return;
    const flag: [:0]const u8 = "--restarted";
    var argv = [_:null]?[*:0]const u8{ path.ptr, flag.ptr };
    if (c.SDL_CreateProcess(@ptrCast(&argv), false)) |p| c.SDL_DestroyProcess(p);
}
