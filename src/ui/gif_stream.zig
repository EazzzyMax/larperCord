//! Animação que não cabe inteira no limite de cada GIF (ver core/gif_quadros.zig):
//! toca decodificando do arquivo comprimido, `ring_len` quadros à frente, todos os
//! quadros no tempo de cada um. Uma thread só serve todas: nasce quando alguma
//! animação precisa de quadros e termina depois de 2 s sem pedido. Parada (sem o mouse
//! em cima, com "tocar sozinho" desligado) ou fora da tela, ninguém pede quadro e nada
//! roda. GIF (stb_image, quadro a quadro) e WebP animado (WebPAnimDecoder).
const std = @import("std");
const c = @import("c");
const quadros = @import("../core/gif_quadros.zig");
const images = @import("images.zig");
const platform = @import("../platform/window.zig");

const alloc = std.heap.c_allocator;
const ring_len = quadros.ring_len;
/// Sem pedido por esse tempo, a thread termina.
const idle_exit_ms: i32 = 2000;

/// O arquivo comprimido de uma animação que vai tocar aos poucos (vem da thread de
/// mídia) e o tamanho da tela dela antes de reduzir.
pub const Seed = struct { data: []u8, kind: quadros.Kind, src_w: u16, src_h: u16 };

const Slot = struct { px: []u8, delay_ms: u32 = 0, seq: u32 = 0 };

pub const Stream = struct {
    // Só da thread que decodifica (uma vez por vez: enquanto `queued`).
    data: []u8,
    kind: quadros.Kind,
    gif: ?*c.larper_gif = null,
    webp: ?*c.WebPAnimDecoder = null,
    webp_w: usize = 0,
    webp_h: usize = 0,
    webp_ts: c_int = 0,
    /// Quadros já decodificados desta volta.
    pass: u32 = 0,

    // Com o mutex. Os pixels de um quadro no anel (de `head` a `head + count`) só a
    // thread principal lê; o próximo lugar livre só a que decodifica escreve.
    slots: [ring_len]Slot,
    block: []u8,
    ring: quadros.Ring = .{},
    queued: bool = false,
    dead: bool = false,
    failed: bool = false,
    /// A tela quis um quadro e o anel estava vazio: a thread acorda o app no próximo.
    starving: bool = false,
    /// Quadros da última volta completa (o QA confere que nenhum se perdeu).
    loop_frames: u32 = 0,

    // Só da thread principal.
    w: u16,
    h: u16,
    tex: *c.SDL_Texture,
    pace: quadros.Pace = .{},
    has_frame: bool = false,
    /// Memória que esta animação ocupa (conta no limite do cache).
    bytes: usize,
    /// Para o QA: quadros mostrados, os que vieram fora da sequência e o maior tempo de um.
    shown: u32 = 0,
    out_of_order: u32 = 0,
    max_delay_ms: u32 = 0,
    last_seq: u32 = 0,

    /// O quadro de agora (todo pedido de quadro passa por aqui). false = nenhum ainda:
    /// quem chama mostra o primeiro, parado. Marca em `next_ms` quando o próximo vence.
    pub fn frame(s: *Stream, now: i64, next_ms: *i64) bool {
        c.SDL_LockMutex(mutex);
        defer c.SDL_UnlockMutex(mutex);
        if (s.ring.count > 0 and s.pace.ready(now)) {
            const slot = &s.slots[s.ring.head];
            _ = c.SDL_UpdateTexture(s.tex, null, slot.px.ptr, @as(c_int, s.w) * 4);
            s.pace.shown(now, slot.delay_ms);
            if (s.shown > 0 and slot.seq != 0 and slot.seq != s.last_seq +% 1) s.out_of_order += 1;
            s.last_seq = slot.seq;
            s.shown +%= 1;
            s.max_delay_ms = @max(s.max_delay_ms, slot.delay_ms);
            s.ring.pop();
            s.has_frame = true;
        }
        if (s.ring.count > 0) next_ms.* = @min(next_ms.*, s.pace.due_ms) else s.starving = true;
        if (s.ring.wantsFill()) request(s);
        return s.has_frame;
    }

    pub fn loopFrames(s: *Stream) u32 {
        c.SDL_LockMutex(mutex);
        defer c.SDL_UnlockMutex(mutex);
        return s.loop_frames;
    }
};

var mutex: ?*c.SDL_Mutex = null;
var cond: ?*c.SDL_Condition = null;
var queue: std.ArrayList(*Stream) = .empty;
var thread: ?*c.SDL_Thread = null;
var running = false;
var stopping = false;
var wake_type: u32 = 0;

pub fn init(wake: u32) !void {
    wake_type = wake;
    if (mutex == null) mutex = c.SDL_CreateMutex() orelse return error.SdlMutex;
    if (cond == null) cond = c.SDL_CreateCondition() orelse return error.SdlCondition;
}

/// Thread principal. Fica com `seed.data` (solta se não der para criar).
pub fn create(renderer: *c.SDL_Renderer, seed: Seed, w: u16, h: u16) ?*Stream {
    const frame_bytes = @as(usize, w) * h * 4;
    const s = alloc.create(Stream) catch {
        alloc.free(seed.data);
        return null;
    };
    const block = alloc.alloc(u8, frame_bytes * ring_len) catch {
        alloc.destroy(s);
        alloc.free(seed.data);
        return null;
    };
    const tex = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STREAMING, w, h) orelse {
        alloc.free(block);
        alloc.destroy(s);
        alloc.free(seed.data);
        return null;
    };
    _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
    var slots: [ring_len]Slot = undefined;
    for (&slots, 0..) |*sl, i| sl.* = .{ .px = block[i * frame_bytes ..][0..frame_bytes] };
    s.* = .{
        .data = seed.data,
        .kind = seed.kind,
        .slots = slots,
        .block = block,
        .w = w,
        .h = h,
        .tex = tex,
        .bytes = quadros.streamBytes(seed.data.len, seed.kind, seed.src_w, seed.src_h, w, h),
    };
    return s;
}

/// Thread principal: a entrada do cache saiu. Na fila ou decodificando, a thread
/// solta quando terminar.
pub fn release(s: *Stream) void {
    c.SDL_DestroyTexture(s.tex);
    c.SDL_LockMutex(mutex);
    defer c.SDL_UnlockMutex(mutex);
    s.dead = true;
    if (!s.queued) destroy(s);
}

/// Ao fechar o app, antes de soltar as entradas do cache.
pub fn deinit() void {
    if (mutex == null) return;
    c.SDL_LockMutex(mutex);
    stopping = true;
    c.SDL_BroadcastCondition(cond);
    const t = thread;
    thread = null;
    c.SDL_UnlockMutex(mutex);
    if (t) |th| c.SDL_WaitThread(th, null);
    c.SDL_LockMutex(mutex);
    defer c.SDL_UnlockMutex(mutex);
    // O que ficou na fila volta para as entradas do cache, que soltam logo depois.
    for (queue.items) |s| {
        s.queued = false;
        if (s.dead) destroy(s);
    }
    queue.clearAndFree(alloc);
}

/// Com o mutex.
fn destroy(s: *Stream) void {
    if (s.gif) |g| c.larper_gif_close(g);
    if (s.webp) |d| c.WebPAnimDecoderDelete(d);
    alloc.free(s.block);
    alloc.free(s.data);
    alloc.destroy(s);
}

/// Com o mutex: põe na fila e acorda (ou cria) a thread.
fn request(s: *Stream) void {
    if (s.queued or s.failed or s.dead or stopping) return;
    queue.append(alloc, s) catch return;
    s.queued = true;
    if (running) {
        c.SDL_SignalCondition(cond);
        return;
    }
    // A anterior terminou (ou está terminando, já sem o mutex): recolhe antes de criar outra.
    if (thread) |t| c.SDL_WaitThread(t, null);
    thread = c.SDL_CreateThread(run, "gif", null);
    running = thread != null;
    if (!running) {
        _ = queue.pop();
        s.queued = false;
    }
}

fn run(_: ?*anyopaque) callconv(.c) c_int {
    // Mídia nunca disputa a CPU com a interface.
    _ = c.SDL_SetCurrentThreadPriority(c.SDL_THREAD_PRIORITY_LOW);
    c.SDL_LockMutex(mutex);
    defer c.SDL_UnlockMutex(mutex);
    while (!stopping) {
        if (queue.items.len == 0) {
            _ = c.SDL_WaitConditionTimeout(cond, mutex, idle_exit_ms);
            if (queue.items.len == 0) break;
            continue;
        }
        const s = queue.orderedRemove(0);
        fill(s);
        s.queued = false;
        if (s.dead) destroy(s);
    }
    running = false;
    return 0;
}

/// Com o mutex (solto enquanto decodifica): completa o anel.
fn fill(s: *Stream) void {
    while (!s.dead and !stopping and !s.ring.full()) {
        const slot = &s.slots[s.ring.writeIndex()];
        var ended: ?u32 = null;
        c.SDL_UnlockMutex(mutex);
        const ok = decodeNext(s, slot, &ended);
        c.SDL_LockMutex(mutex);
        if (ended) |n| s.loop_frames = n;
        if (!ok) {
            s.failed = true;
            return;
        }
        s.ring.push();
        if (s.starving) {
            s.starving = false;
            platform.Window.wake(wake_type, .media);
        }
    }
}

/// Sem o mutex: o próximo quadro, reduzido, em `slot`. No fim do arquivo volta ao
/// começo (`ended` recebe quantos quadros a volta teve). false = não decodifica.
fn decodeNext(s: *Stream, slot: *Slot, ended: *?u32) bool {
    var rewound = false;
    while (true) {
        var fw: c_int = 0;
        var fh: c_int = 0;
        var delay: c_int = 0;
        const got = switch (s.kind) {
            .gif => nextGif(s, &fw, &fh, &delay),
            .webp => nextWebp(s, &fw, &fh, &delay),
        };
        if (got) |p| {
            if (fw <= 0 or fh <= 0 or fw > 4096 or fh > 4096) return false;
            const sw: usize = @intCast(fw);
            const sh: usize = @intCast(fh);
            const src = p[0 .. sw * sh * 4];
            if (sw == s.w and sh == s.h) @memcpy(slot.px, src) else images.resize(src, sw, sh, slot.px, s.w, s.h);
            slot.delay_ms = images.gifDelay(delay);
            slot.seq = s.pass;
            s.pass += 1;
            return true;
        }
        // Uma volta sem nenhum quadro é arquivo estragado.
        if (s.pass == 0 or rewound) return false;
        ended.* = s.pass;
        s.pass = 0;
        rewound = true;
        rewind(s);
    }
}

fn nextGif(s: *Stream, w: *c_int, h: *c_int, delay: *c_int) ?[*]const u8 {
    if (s.gif == null) s.gif = c.larper_gif_open(s.data.ptr, @intCast(s.data.len));
    const g = s.gif orelse return null;
    return c.larper_gif_next(g, w, h, delay);
}

fn nextWebp(s: *Stream, w: *c_int, h: *c_int, delay: *c_int) ?[*]const u8 {
    if (s.webp == null) {
        var opts: c.WebPAnimDecoderOptions = undefined;
        if (c.WebPAnimDecoderOptionsInit(&opts) == 0) return null;
        opts.color_mode = c.MODE_RGBA;
        opts.use_threads = 0;
        const wd: c.WebPData = .{ .bytes = s.data.ptr, .size = s.data.len };
        const dec = c.WebPAnimDecoderNew(&wd, &opts) orelse return null;
        var info: c.WebPAnimInfo = undefined;
        if (c.WebPAnimDecoderGetInfo(dec, &info) == 0) {
            c.WebPAnimDecoderDelete(dec);
            return null;
        }
        s.webp = dec;
        s.webp_w = info.canvas_width;
        s.webp_h = info.canvas_height;
        s.webp_ts = 0;
    }
    const dec = s.webp.?;
    if (c.WebPAnimDecoderHasMoreFrames(dec) == 0) return null;
    var buf: [*c]u8 = null;
    var ts: c_int = 0;
    if (c.WebPAnimDecoderGetNext(dec, &buf, &ts) == 0 or buf == null) return null;
    delay.* = ts - s.webp_ts;
    s.webp_ts = ts;
    w.* = @intCast(s.webp_w);
    h.* = @intCast(s.webp_h);
    return buf;
}

/// Volta ao primeiro quadro.
fn rewind(s: *Stream) void {
    switch (s.kind) {
        .gif => if (s.gif) |g| {
            c.larper_gif_close(g);
            s.gif = null;
        },
        .webp => if (s.webp) |d| {
            c.WebPAnimDecoderReset(d);
            s.webp_ts = 0;
        },
    }
}
