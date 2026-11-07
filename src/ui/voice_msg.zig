//! Mensagens de voz: o player na conversa (tocar/pausar, barra com busca,
//! duração e a forma de onda) e quem toca. Tocar baixa o Ogg Opus pelo mesmo
//! caminho das imagens (só domínios do Discord, com o proxy das configurações),
//! monta o índice (core/ogg_opus.zig), decodifica com a libopus e põe num
//! stream do SDL no dispositivo de saída escolhido na página Voz, com o volume
//! de saída de lá. A thread e o stream só existem enquanto toca: pausar fecha
//! os dois e guarda onde parou (o arquivo baixado fica, para continuar sem
//! baixar de novo). Um áudio por vez. Gravar e enviar não existe aqui.
const std = @import("std");
const c = @import("c");
const d = @import("draw.zig");
const anim = @import("anim.zig");
const qa = @import("qa.zig");
const i18n = @import("i18n.zig");
const images = @import("images.zig");
const types = @import("../core/types.zig");
const ogg = @import("../core/ogg_opus.zig");
const media_refresh = @import("../core/media_refresh.zig");
const voz_audio = @import("../net/voz_audio.zig");

const alloc = std.heap.c_allocator;
const Atomic = std.atomic.Value;

/// Teto do download (uma mensagem de voz de vários minutos tem poucos MB).
const max_download: usize = 8 << 20;
/// Quanto áudio fica na fila do SDL à frente do que está tocando.
const ahead_samples: usize = ogg.rate * 3 / 10;

// --- Quem toca (thread curta) -------------------------------------------------

/// O arquivo baixado, dividido entre a interface (para continuar depois de
/// pausar) e a thread que toca.
const Blob = struct {
    refs: Atomic(u32),
    data: []u8,

    fn retain(b: *Blob) *Blob {
        _ = b.refs.fetchAdd(1, .monotonic);
        return b;
    }

    fn release(b: *Blob) void {
        if (b.refs.fetchSub(1, .acq_rel) != 1) return;
        alloc.free(b.data);
        alloc.destroy(b);
    }
};

const RunState = enum(u8) { loading, playing, done, failed };

/// Uma vez tocando, da interface e da thread (cada uma solta a sua parte).
const Run = struct {
    refs: Atomic(u32) = .init(2),
    stop: Atomic(bool) = .init(false),
    url: []u8,
    /// O arquivo que a interface já tinha (null = a thread baixa).
    blob: ?*Blob,
    /// O que a thread baixou, com uma parte para a interface guardar.
    fresh: Atomic(?*Blob) = .init(null),
    start_ms: u32,
    pos_ms: Atomic(u32),
    dur_ms: Atomic(u32) = .init(0),
    state: Atomic(RunState) = .init(.loading),
    /// Pedido de busca (ms; -1 = nenhum).
    seek_ms: Atomic(i64) = .init(-1),

    fn release(r: *Run) void {
        if (r.refs.fetchSub(1, .acq_rel) != 1) return;
        if (r.blob) |b| b.release();
        if (r.fresh.swap(null, .acq_rel)) |b| b.release();
        alloc.free(r.url);
        alloc.destroy(r);
    }
};

/// Threads vivas (o app espera por elas ao fechar).
var live: Atomic(u32) = .init(0);

fn worker(p: ?*anyopaque) callconv(.c) c_int {
    const r: *Run = @ptrCast(@alignCast(p.?));
    defer {
        r.release();
        _ = live.fetchSub(1, .release);
    }
    play(r) catch {
        r.state.store(.failed, .release);
        return 0;
    };
    if (r.state.load(.acquire) != .failed) r.state.store(.done, .release);
    return 0;
}

const ListSink = struct {
    list: std.ArrayList(u8) = .empty,
    too_big: bool = false,

    fn write(ud: *anyopaque, chunk: []const u8, total: i64) bool {
        const s: *ListSink = @ptrCast(@alignCast(ud));
        if (s.list.items.len + chunk.len > max_download or total > @as(i64, @intCast(max_download))) {
            s.too_big = true;
            return false;
        }
        s.list.appendSlice(alloc, chunk) catch return false;
        return true;
    }
};

fn download(r: *Run) !*Blob {
    var data: []u8 = undefined;
    if (std.mem.startsWith(u8, r.url, "demo:")) {
        data = try demoVoice(r.url);
    } else {
        var sink: ListSink = .{};
        errdefer sink.list.deinit(alloc);
        var ubuf: [2100]u8 = undefined;
        const z = std.fmt.bufPrintSentinel(&ubuf, "{s}", .{r.url}, 0) catch return error.Url;
        var curl: ?*c.CURL = null;
        defer if (curl) |h| c.curl_easy_cleanup(h);
        if (!images.fetch(&curl, z, .{ .ctx = &sink, .write = ListSink.write }, &r.stop, 30) or sink.list.items.len == 0) return error.Download;
        data = try sink.list.toOwnedSlice(alloc);
    }
    errdefer alloc.free(data);
    const b = try alloc.create(Blob);
    b.* = .{ .refs = .init(1), .data = data };
    return b;
}

fn play(r: *Run) !void {
    const file = if (r.blob) |b| b.retain() else blk: {
        const b = try download(r);
        // Uma parte fica para a interface (continuar sem baixar de novo).
        r.fresh.store(b.retain(), .release);
        break :blk b;
    };
    defer file.release();
    if (r.stop.load(.acquire)) return;
    var stream = try ogg.index(alloc, file.data);
    defer stream.deinit(alloc);
    const dur = stream.durationMs();
    r.dur_ms.store(dur, .release);

    if (!voz_audio.acquire()) return error.Audio;
    defer voz_audio.release();
    const spec: c.SDL_AudioSpec = .{ .format = c.SDL_AUDIO_S16, .channels = stream.channels, .freq = @intCast(ogg.rate) };
    const out = c.SDL_OpenAudioDeviceStream(voz_audio.outputDevice(), &spec, null, null) orelse
        c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, null, null) orelse return error.Audio;
    defer c.SDL_DestroyAudioStream(out);
    _ = c.SDL_SetAudioStreamGain(out, voz_audio.sh.out_gain.load(.monotonic));

    var err: c_int = 0;
    var dec = c.opus_decoder_create(@intCast(ogg.rate), stream.channels, &err) orelse return error.Opus;
    defer c.opus_decoder_destroy(dec);

    const ch: usize = stream.channels;
    const bytes_per_sample = ch * @sizeOf(i16);
    var begin_ms = @min(r.start_ms, dur -| 1);
    var idx = stream.seekIndex(begin_ms);
    // Instante (amostras decodificadas) de onde começa o que se ouve e do fim
    // do que já foi para a fila.
    var skip_to: u64 = stream.pre_skip + @as(u64, begin_ms) * (ogg.rate / 1000);
    var pushed_end: u64 = skip_to;
    var pcm: [5760 * 2]i16 = undefined;
    var resumed = false;
    r.state.store(.playing, .release);

    while (!r.stop.load(.acquire)) {
        const want = r.seek_ms.swap(-1, .acq_rel);
        if (want >= 0) {
            // Busca: esvazia a fila e recomeça o decodificador do ponto novo.
            _ = c.SDL_ClearAudioStream(out);
            c.opus_decoder_destroy(dec);
            dec = c.opus_decoder_create(@intCast(ogg.rate), stream.channels, &err) orelse return error.Opus;
            begin_ms = @min(@as(u32, @intCast(@min(want, std.math.maxInt(u32)))), dur -| 1);
            idx = stream.seekIndex(begin_ms);
            skip_to = stream.pre_skip + @as(u64, begin_ms) * (ogg.rate / 1000);
            pushed_end = skip_to;
        }
        var queued: usize = @intCast(@max(c.SDL_GetAudioStreamQueued(out), 0));
        queued /= bytes_per_sample;
        // Põe áudio até ter uns 300 ms na fila.
        while (queued < ahead_samples and idx < stream.packets.len) : (idx += 1) {
            const pk = stream.packets[idx];
            const next_start = if (idx + 1 < stream.packets.len) stream.packets[idx + 1].start else stream.end;
            const n = c.opus_decode(dec, stream.data(file.data, pk).ptr, @intCast(pk.len), &pcm, 5760, 0);
            if (n <= 0) continue;
            // Só o que está entre o ponto de começo e o fim do áudio.
            const p0 = pk.start;
            const p1 = @min(p0 + @as(u64, @intCast(n)), stream.end, @max(next_start, p0 + 1));
            const from = @max(p0, skip_to);
            if (p1 <= from) continue;
            const off: usize = @intCast(from - p0);
            const cnt: usize = @intCast(p1 - from);
            if (!c.SDL_PutAudioStreamData(out, &pcm[off * ch], @intCast(cnt * bytes_per_sample))) return error.Audio;
            pushed_end = p1;
            queued += cnt;
        }
        if (!resumed) {
            resumed = true;
            _ = c.SDL_ResumeAudioStreamDevice(out);
        }
        const now_pos = pushed_end -| queued;
        r.pos_ms.store(@intCast(@min((now_pos -| stream.pre_skip) / (ogg.rate / 1000), dur)), .release);
        if (idx >= stream.packets.len and queued == 0) {
            r.pos_ms.store(dur, .release);
            return;
        }
        c.SDL_Delay(20);
    }
}

/// A mensagem de voz da demonstração: uma voz sintética de 4 s, codificada
/// em Opus aqui mesmo e posta num Ogg (passa pelo mesmo caminho da de verdade).
fn demoVoice(url: []const u8) ![]u8 {
    _ = url;
    var err: c_int = 0;
    const enc = c.opus_encoder_create(@intCast(ogg.rate), 1, c.OPUS_APPLICATION_VOIP, &err) orelse return error.Opus;
    defer c.opus_encoder_destroy(enc);
    var w: ogg.Writer = .{ .gpa = alloc };
    errdefer w.out.deinit(alloc);
    var hb: [19]u8 = undefined;
    const pre_skip: u16 = 312;
    try w.packets(ogg.flag_bos, 0, &.{ogg.opusHead(&hb, 1, pre_skip)});
    try w.packets(0, 0, &.{"OpusTags\x0a\x00\x00\x00larperCord\x00\x00\x00\x00"});
    const frame = 960;
    const frames = 200;
    var pcm: [frame]i16 = undefined;
    var pkts: [10][400]u8 = undefined;
    var lens: [10]usize = undefined;
    var phase: f32 = 0;
    var granule: u64 = 0;
    var k: usize = 0;
    while (k < frames) : (k += 10) {
        for (0..10) |j| {
            const fi = k + j;
            for (&pcm, 0..) |*s, i| {
                // Sílabas: um tom que sobe e desce, com pausas entre elas.
                const t = @as(f32, @floatFromInt(fi * frame + i)) / @as(f32, @floatFromInt(ogg.rate));
                const syl = @abs(@sin(t * std.math.pi * 2.6));
                const f0 = 170 + 60 * @sin(t * 3.1);
                phase += 2 * std.math.pi * f0 / @as(f32, @floatFromInt(ogg.rate));
                const v = (@sin(phase) + 0.4 * @sin(phase * 2) + 0.2 * @sin(phase * 3)) * syl * syl * 0.35;
                s.* = @intFromFloat(std.math.clamp(v, -1, 1) * 32767);
            }
            const n = c.opus_encode(enc, &pcm, frame, &pkts[j], pkts[j].len);
            if (n <= 0) return error.Opus;
            lens[j] = @intCast(n);
            granule += frame;
        }
        var list: [10][]const u8 = undefined;
        for (0..10) |j| list[j] = pkts[j][0..lens[j]];
        try w.packets(if (k + 10 >= frames) ogg.flag_eos else 0, granule, &list);
    }
    return w.out.toOwnedSlice(alloc);
}

// --- O que a interface lembra -------------------------------------------------

/// O áudio escolhido (mensagem + índice do anexo) e onde está.
var active: u64 = 0;
var run: ?*Run = null;
var blob: ?*Blob = null;
var pos_ms: u32 = 0;
var dur_ms: u32 = 0;
/// Arrastando na barra: a posição que o dedo mostra.
var scrubbing = false;
/// O último que falhou (mostra o aviso no lugar da duração).
var failed_key: u64 = 0;

fn keyOf(msg_id: types.Id, index: usize) u64 {
    return std.hash.Wyhash.hash(msg_id, std.mem.asBytes(&index));
}

/// Começa (ou continua de `from_ms`) a tocar o áudio de `url`.
fn start(key: u64, url: []const u8, from_ms: u32) bool {
    stopRun();
    if (key != active) {
        if (blob) |b| b.release();
        blob = null;
        active = key;
    }
    failed_key = 0;
    // No QA o som vai para o driver mudo, como o vídeo.
    if (qa.on()) voz_audio.force_dummy = true;
    const r = alloc.create(Run) catch return false;
    r.* = .{
        .url = alloc.dupe(u8, url) catch {
            alloc.destroy(r);
            return false;
        },
        .blob = if (blob) |b| b.retain() else null,
        .start_ms = from_ms,
        .pos_ms = .init(from_ms),
    };
    _ = live.fetchAdd(1, .acq_rel);
    const t = c.SDL_CreateThread(worker, "voz-msg", r) orelse {
        _ = live.fetchSub(1, .release);
        r.refs.store(1, .monotonic);
        r.release();
        return false;
    };
    c.SDL_DetachThread(t);
    run = r;
    pos_ms = from_ms;
    return true;
}

/// Para a thread (pausa): ela fecha o stream e solta o que é dela.
fn stopRun() void {
    const r = run orelse return;
    run = null;
    r.stop.store(true, .release);
    if (r.fresh.swap(null, .acq_rel)) |b| {
        if (blob == null) blob = b else b.release();
    }
    r.release();
}

/// O estado da thread chega na interface (só para o áudio ativo, desenhado).
fn sync(ctx: *d.Ctx, a: *const types.Attachment) void {
    const r = run orelse return;
    if (r.fresh.swap(null, .acq_rel)) |b| {
        if (blob == null) blob = b else b.release();
    }
    const dm = r.dur_ms.load(.acquire);
    if (dm > 0) dur_ms = dm;
    switch (r.state.load(.acquire)) {
        .loading, .playing => {
            if (!scrubbing) pos_ms = r.pos_ms.load(.acquire);
            // Só enquanto toca: a barra anda uns 20 quadros por segundo.
            anim.every(50);
        },
        .done => {
            run = null;
            r.release();
            pos_ms = 0;
        },
        .failed => {
            run = null;
            r.release();
            pos_ms = 0;
            const res = &media_refresh.global;
            // Link vencido: pede o novo e toca de novo quando chegar (uma vez).
            const ro = res.requestOpen(a.url, @divTrunc(ctx.now_ms, 1000));
            if (ro.pending) {
                if (ro.notify) ctx.act(.refresh_media);
                return;
            }
            failed_key = active;
            ctx.st.showToast(ctx.now_ms, true, "não deu para tocar a mensagem de voz", "couldn't play the voice message", .{});
        },
    }
}

/// Fecha tudo ao sair do app (antes do libcurl e do SDL).
pub fn shutdown() void {
    stopRun();
    if (blob) |b| b.release();
    blob = null;
    var waited: u32 = 0;
    while (live.load(.acquire) > 0 and waited < 3000) : (waited += 5) c.SDL_Delay(5);
}

/// Para o QA: tocando agora, a posição e a duração (ms).
pub const Info = struct { active: u64, playing: bool, pos_ms: u32, dur_ms: u32, has_file: bool };
pub fn info() Info {
    return .{ .active = active, .playing = run != null, .pos_ms = pos_ms, .dur_ms = dur_ms, .has_file = blob != null };
}

// --- O player na conversa ------------------------------------------------------

fn fmtTime(buf: []u8, ms: u32) []const u8 {
    const s = ms / 1000;
    return std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ s / 60, s % 60 }) catch "";
}

pub fn draw(ctx: *d.Ctx, dl: *c.ImDrawList, a: *const types.Attachment, r: d.Rect, msg_id: types.Id, index: usize, alpha: f32) void {
    const key = keyOf(msg_id, index);
    const res = &media_refresh.global;
    const url = res.resolve(a.url);
    const mine = key == active;
    if (mine) sync(ctx, a);
    // O link novo chegou depois de uma falha: toca de novo, do começo.
    if (mine and res.open_ready and res.takeOpen(a.url)) _ = start(key, url, 0);
    const playing = mine and run != null;
    const loading = playing and run.?.state.load(.acquire) == .loading;
    const total: u32 = if (mine and dur_ms > 0) dur_ms else a.voice_ms;
    const at: u32 = if (mine) @min(pos_ms, @max(total, 1)) else 0;

    const radius = @max(ctx.th.radius, 6);
    d.rect(dl, r, ctx.col(.elevated).alpha(alpha), radius);
    d.border(dl, r, ctx.col(.border).alpha(alpha), radius, 1);

    // Tocar / pausar.
    const br: d.Rect = .{ .x = r.x + 12, .y = r.y + (r.h - 34) / 2, .w = 34, .h = 34 };
    const bh = d.hit(ctx, @truncate(key ^ 0x701CE), br);
    qa.mark(br, "voice-play:{d}", .{msg_id});
    const bk = anim.to(anim.id("voice-btn", @truncate(key)), if (bh.hovered) 1 else 0, 20);
    d.circle(dl, br.x + 17, br.y + 17, 17, ctx.col(.accent).mix(d.Rgba.white, 0.1 * bk).alpha(alpha));
    const ink = ctx.col(.accent_text).alpha(alpha);
    const cx = br.x + 17;
    const cy = br.y + 17;
    if (loading) {
        const t = @as(f32, @floatFromInt(@mod(ctx.now_ms, 100_000))) / 1000.0;
        c.ImDrawList_PathArcTo(dl, d.v(cx, cy), 8, t * 6, t * 6 + 4.2, 20);
        c.ImDrawList_PathStroke(dl, ink.u(), 2, 0);
    } else if (playing) {
        d.rect(dl, .{ .x = cx - 6, .y = cy - 7, .w = 4, .h = 14 }, ink, 1);
        d.rect(dl, .{ .x = cx + 2, .y = cy - 7, .w = 4, .h = 14 }, ink, 1);
    } else {
        c.ImDrawList_AddTriangleFilled(dl, d.v(cx - 4.5, cy - 7.5), d.v(cx - 4.5, cy + 7.5), d.v(cx + 8, cy), ink.u());
    }
    d.tip(ctx, br, if (playing) i18n.tr("Pausar", "Pause") else i18n.tr("Ouvir a mensagem de voz", "Play voice message"), bh.hovered);
    if (bh.clicked) {
        if (playing) {
            stopRun();
        } else {
            const from = if (mine and at < total -| 250) at else 0;
            if (!start(key, url, from)) ctx.st.showToast(ctx.now_ms, true, "não deu para tocar a mensagem de voz", "couldn't play the voice message", .{});
        }
    }

    // Tempo à direita: o que já tocou enquanto toca; senão a duração.
    var tb: [24]u8 = undefined;
    const f = ctx.ui.get(.medium);
    const shown_ms = if (playing or (mine and at > 0)) at else total;
    const tlabel = if (failed_key == key) i18n.tr("indisponível", "unavailable") else fmtTime(&tb, shown_ms);
    const tw = d.width(f, 12.5, tlabel);
    d.text(dl, f, 12.5, r.right() - 14 - tw, d.centerY(r, 12.5), ctx.col(.muted).alpha(alpha), tlabel);

    // A forma de onda é a barra: clicar ou arrastar leva até ali.
    const wr: d.Rect = .{ .x = br.right() + 12, .y = r.y + 10, .w = @max(r.right() - 14 - tw - 12 - (br.right() + 12), 20), .h = r.h - 20 };
    const wh = d.hit(ctx, @truncate(key ^ 0x3A7E), wr);
    qa.mark(wr, "voice-wave:{d}", .{msg_id});
    const frac: f32 = if (total > 0) @as(f32, @floatFromInt(at)) / @as(f32, @floatFromInt(total)) else 0;
    const n: usize = types.wave_bars;
    const step = wr.w / @as(f32, @floatFromInt(n));
    const bw = @max(step * 0.55, 1.5);
    const has_wave = std.mem.max(u8, &a.wave) > 0;
    for (0..n) |i| {
        const v: f32 = if (has_wave) @as(f32, @floatFromInt(a.wave[i])) / 255 else 0.25;
        const bh_px = @max(3, v * wr.h);
        const bx = wr.x + step * @as(f32, @floatFromInt(i)) + (step - bw) / 2;
        const played = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(n)) <= frac;
        const col = if (played) ctx.col(.accent) else ctx.col(.faint).mix(ctx.col(.muted), if (wh.hovered) 0.4 else 0);
        d.rect(dl, .{ .x = bx, .y = wr.y + (wr.h - bh_px) / 2, .w = bw, .h = bh_px }, col.alpha(alpha), bw / 2);
    }
    if (wh.hovered) c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
    if ((wh.held or wh.clicked) and total > 0) {
        const fx = std.math.clamp((ctx.mouse.x - wr.x) / wr.w, 0, 1);
        const target: u32 = @intFromFloat(fx * @as(f32, @floatFromInt(total)));
        if (!mine) {
            // Outro áudio: este passa a ser o escolhido, parado no ponto.
            stopRun();
            if (blob) |b| b.release();
            blob = null;
            active = key;
            dur_ms = total;
        }
        pos_ms = target;
        scrubbing = wh.held and !wh.clicked;
        if (run) |rr| {
            if (!scrubbing) rr.seek_ms.store(target, .release);
        }
    } else if (mine) scrubbing = false;
    if (bh.right or wh.right) if (msg_id != 0) ctx.popup(.{ .menu = .{ .kind = .message, .id = msg_id, .x = ctx.mouse.x, .y = ctx.mouse.y } });
}
