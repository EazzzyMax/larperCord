//! Som escolhido pela pessoa (Configurações → Voz → Sons): WAV PCM ou Ogg
//! Opus curto, decodificado de uma vez para o formato da saída (48 kHz,
//! estéreo, 16 bits). Todo tamanho que vem do arquivo é conferido contra o
//! que sobrou: arquivo grande, longo, estragado ou de outro formato vira erro,
//! nunca leitura fora do lugar. A duração é conferida pelo cabeçalho, antes de
//! alocar o resultado. Nada de libopus aqui (dá para testar sem ela): quem
//! decodifica cada pacote Opus vem de fora (a libopus no app, um falso nos
//! testes); o Ogg é o mesmo de core/ogg_opus.zig, das mensagens de voz.
const std = @import("std");
const ogg = @import("ogg_opus.zig");

pub const out_rate: u32 = 48_000;
/// Teto do arquivo: um aviso de 5 s em WAV de 16 bits estéreo a 48 kHz tem
/// menos de 1 MB; um toque de 15 s cabe em Ogg Opus com folga.
pub const max_bytes: usize = 2 << 20;
/// Taxas aceitas no WAV (fora disso é quase certo que o cabeçalho mente).
pub const min_rate: u32 = 8_000;
pub const max_rate: u32 = 192_000;
pub const max_channels: u16 = 8;
/// Fim do som em rampa (3 ms): um arquivo cortado seco não estala no fim.
const fade_frames: usize = 144;

pub const Error = error{
    /// Passa de `max_bytes`.
    TooBig,
    /// Passa da duração do evento.
    TooLong,
    /// Não é WAV PCM nem Ogg Opus (MP3, ADPCM, Vorbis, 12 bits, 9 canais…).
    Unsupported,
    /// É WAV ou Ogg, mas o cabeçalho está quebrado ou o arquivo acaba antes.
    Corrupt,
    /// Não tem nenhuma amostra.
    Empty,
    OutOfMemory,
};

pub const Format = enum { wav, ogg };

/// Pelo começo do arquivo (a extensão pode mentir).
pub fn sniff(b: []const u8) ?Format {
    if (b.len >= 12 and std.mem.eql(u8, b[0..4], "RIFF") and std.mem.eql(u8, b[8..12], "WAVE")) return .wav;
    if (b.len >= 4 and std.mem.eql(u8, b[0..4], "OggS")) return .ogg;
    return null;
}

// --- WAV -----------------------------------------------------------------------

pub const Sample = enum {
    u8,
    s16,
    s24,
    s32,
    f32,
    f64,

    pub fn bytes(s: Sample) usize {
        return switch (s) {
            .u8 => 1,
            .s16 => 2,
            .s24 => 3,
            .s32, .f32 => 4,
            .f64 => 8,
        };
    }
};

pub const Wav = struct {
    channels: u16,
    rate: u32,
    sample: Sample,
    /// Só quadros inteiros (o resto de um arquivo cortado fica de fora).
    data: []const u8,

    pub fn frameBytes(w: *const Wav) usize {
        return @as(usize, w.channels) * w.sample.bytes();
    }

    pub fn frames(w: *const Wav) usize {
        return w.data.len / w.frameBytes();
    }

    pub fn durationMs(w: *const Wav) u64 {
        return @as(u64, w.frames()) * 1000 / w.rate;
    }

    fn value(w: *const Wav, frame: usize, ch: usize) f32 {
        const sb = w.sample.bytes();
        const p = w.data[(frame * w.channels + ch) * sb ..][0..sb];
        return switch (w.sample) {
            .u8 => (@as(f32, @floatFromInt(p[0])) - 128) / 128,
            .s16 => @as(f32, @floatFromInt(std.mem.readInt(i16, p[0..2], .little))) / 32768,
            .s24 => @as(f32, @floatFromInt(std.mem.readInt(i24, p[0..3], .little))) / 8388608,
            .s32 => @floatCast(@as(f64, @floatFromInt(std.mem.readInt(i32, p[0..4], .little))) / 2147483648),
            .f32 => finite(@bitCast(std.mem.readInt(u32, p[0..4], .little))),
            .f64 => finite(@floatCast(@as(f64, @bitCast(std.mem.readInt(u64, p[0..8], .little))))),
        };
    }

    /// O quadro em estéreo: mono vai nos dois lados; com mais canais, os de
    /// número par vão para a esquerda e os ímpares para a direita.
    pub fn stereo(w: *const Wav, frame: usize) [2]f32 {
        if (w.channels == 1) {
            const v = w.value(frame, 0);
            return .{ v, v };
        }
        if (w.channels == 2) return .{ w.value(frame, 0), w.value(frame, 1) };
        var l: f32 = 0;
        var r: f32 = 0;
        for (0..w.channels) |ch| {
            if (ch % 2 == 0) l += w.value(frame, ch) else r += w.value(frame, ch);
        }
        const nl: f32 = @floatFromInt((w.channels + 1) / 2);
        const nr: f32 = @floatFromInt(w.channels / 2);
        return .{ l / nl, r / nr };
    }
};

/// NaN e infinito (arquivo de float estragado) viram silêncio, não um estouro.
fn finite(v: f32) f32 {
    return if (std.math.isFinite(v)) v else 0;
}

fn rd16(b: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, b[at..][0..2], .little);
}
fn rd32(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, b[at..][0..4], .little);
}

/// Lê o cabeçalho e acha as amostras. Os pedaços ("chunks") podem vir em
/// qualquer ordem, com outros no meio (LIST, fact…). O tamanho do "data" é o
/// único que pode passar do fim do arquivo (gravação interrompida, ou quem
/// escreve sem saber o tamanho): vale o que existe.
pub fn parseWav(b: []const u8) Error!Wav {
    if (b.len > max_bytes) return error.TooBig;
    if ((sniff(b) orelse return error.Unsupported) != .wav) return error.Unsupported;
    var fmt: ?[]const u8 = null;
    var data: ?[]const u8 = null;
    var at: usize = 12;
    while (b.len - at >= 8) {
        const id = b[at..][0..4];
        const size: usize = rd32(b, at + 4);
        const body = at + 8;
        const avail = b.len - body;
        if (std.mem.eql(u8, id, "fmt ")) {
            if (size > avail or size < 16) return error.Corrupt;
            fmt = b[body..][0..size];
        } else if (std.mem.eql(u8, id, "data")) {
            data = b[body..][0..@min(size, avail)];
        }
        // O próximo começa no par seguinte; tamanho que passa do fim encerra.
        if (size > avail) break;
        const next = body + size + (size & 1);
        if (next > b.len) break;
        at = next;
    }
    const f = fmt orelse return error.Corrupt;
    const d = data orelse return error.Corrupt;

    var tag = rd16(f, 0);
    const channels = rd16(f, 2);
    const rate = rd32(f, 4);
    const block_align = rd16(f, 12);
    const bits = rd16(f, 14);
    // WAVE_FORMAT_EXTENSIBLE: o formato de verdade está no começo do GUID.
    if (tag == 0xFFFE) {
        if (f.len < 40) return error.Corrupt;
        tag = rd16(f, 24);
    }
    const sample: Sample = switch (tag) {
        1 => switch (bits) {
            8 => .u8,
            16 => .s16,
            24 => .s24,
            32 => .s32,
            else => return error.Unsupported,
        },
        3 => switch (bits) {
            32 => .f32,
            64 => .f64,
            else => return error.Unsupported,
        },
        // ADPCM, µ-law, A-law, MP3 dentro do WAV…
        else => return error.Unsupported,
    };
    if (channels == 0 or channels > max_channels) return error.Unsupported;
    if (rate < min_rate or rate > max_rate) return error.Unsupported;
    if (block_align != @as(usize, channels) * sample.bytes()) return error.Corrupt;
    const whole = d.len - d.len % block_align;
    if (whole == 0) return error.Empty;
    return .{ .channels = channels, .rate = rate, .sample = sample, .data = d[0..whole] };
}

/// O WAV inteiro, já a 48 kHz estéreo. `max_ms`: duração máxima aceita.
pub fn decodeWav(gpa: std.mem.Allocator, b: []const u8, max_ms: u32) Error![]i16 {
    const w = try parseWav(b);
    const n = w.frames();
    if (@as(u64, n) * 1000 > @as(u64, max_ms) * w.rate) return error.TooLong;
    const out_frames = outFrames(n, w.rate);
    const out = try gpa.alloc(i16, out_frames * 2);
    resample(&w, n, w.rate, out);
    fadeOut(out);
    return out;
}

/// Quadros a 48 kHz de `n` quadros a `rate` (pelo menos um).
pub fn outFrames(n: usize, rate: u32) usize {
    return @max(@as(usize, @intCast(@as(u64, n) * out_rate / rate)), 1);
}

fn toI16(v: f32) i16 {
    return @intFromFloat(std.math.clamp(@round(v * 32767), -32768, 32767));
}

/// Passa `n` quadros de `src` (qualquer coisa com `stereo(i) [2]f32`, de -1 a 1)
/// a `src_rate` para 48 kHz em `out` (intercalado; `out.len / 2` quadros).
/// Subindo a taxa, interpola em linha reta entre os vizinhos; descendo, faz a
/// média de cada trecho (sem isso, os agudos acima de 24 kHz voltariam como
/// chiado). Avisos curtos não precisam de mais que isso.
pub fn resample(src: anytype, n: usize, src_rate: u32, out: []i16) void {
    const n_out = out.len / 2;
    if (n == 0) return @memset(out, 0);
    if (src_rate == out_rate) {
        for (0..n_out) |j| {
            const v = src.stereo(@min(j, n - 1));
            out[j * 2] = toI16(v[0]);
            out[j * 2 + 1] = toI16(v[1]);
        }
        return;
    }
    const step = @as(f64, @floatFromInt(src_rate)) / @as(f64, @floatFromInt(out_rate));
    for (0..n_out) |j| {
        const pos = @as(f64, @floatFromInt(j)) * step;
        var v: [2]f32 = undefined;
        if (step < 1) {
            const i: usize = @min(@as(usize, @intFromFloat(pos)), n - 1);
            const frac: f32 = @floatCast(pos - @as(f64, @floatFromInt(i)));
            const a = src.stereo(i);
            const b = src.stereo(@min(i + 1, n - 1));
            v = .{ a[0] + (b[0] - a[0]) * frac, a[1] + (b[1] - a[1]) * frac };
        } else {
            const lo: usize = @min(@as(usize, @intFromFloat(pos)), n - 1);
            const hi: usize = @max(@min(@as(usize, @intFromFloat(pos + step)), n), lo + 1);
            var acc: [2]f32 = .{ 0, 0 };
            for (lo..hi) |i| {
                const x = src.stereo(i);
                acc[0] += x[0];
                acc[1] += x[1];
            }
            const k: f32 = @floatFromInt(hi - lo);
            v = .{ acc[0] / k, acc[1] / k };
        }
        out[j * 2] = toI16(v[0]);
        out[j * 2 + 1] = toI16(v[1]);
    }
}

fn fadeOut(out: []i16) void {
    const frames = out.len / 2;
    const k = @min(fade_frames, frames);
    for (0..k) |i| {
        const f = frames - k + i;
        const g = @as(f32, @floatFromInt(k - i - 1)) / @as(f32, @floatFromInt(k));
        out[f * 2] = @intFromFloat(@as(f32, @floatFromInt(out[f * 2])) * g);
        out[f * 2 + 1] = @intFromFloat(@as(f32, @floatFromInt(out[f * 2 + 1])) * g);
    }
}

/// Um WAV PCM de 16 bits (o QA monta os arquivos de teste com isto).
pub fn writeWav16(gpa: std.mem.Allocator, channels: u16, rate: u32, samples: []const i16) ![]u8 {
    const data_len: u32 = @intCast(samples.len * 2);
    var out = try gpa.alloc(u8, 44 + data_len);
    @memcpy(out[0..4], "RIFF");
    std.mem.writeInt(u32, out[4..8], 36 + data_len, .little);
    @memcpy(out[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, out[16..20], 16, .little);
    std.mem.writeInt(u16, out[20..22], 1, .little);
    std.mem.writeInt(u16, out[22..24], channels, .little);
    std.mem.writeInt(u32, out[24..28], rate, .little);
    std.mem.writeInt(u32, out[28..32], rate * channels * 2, .little);
    std.mem.writeInt(u16, out[32..34], channels * 2, .little);
    std.mem.writeInt(u16, out[34..36], 16, .little);
    @memcpy(out[36..40], "data");
    std.mem.writeInt(u32, out[40..44], data_len, .little);
    for (samples, 0..) |s, i| std.mem.writeInt(i16, out[44 + i * 2 ..][0..2], s, .little);
    return out;
}

// --- Ogg Opus ------------------------------------------------------------------

/// O índice do Ogg Opus, com a duração já conferida (antes de decodificar).
pub fn openOgg(gpa: std.mem.Allocator, b: []const u8, max_ms: u32) Error!ogg.Stream {
    if (b.len > max_bytes) return error.TooBig;
    var s = ogg.index(gpa, b) catch |e| return switch (e) {
        error.NotOgg, error.Corrupt => error.Corrupt,
        // Ogg de outra coisa (Vorbis, FLAC, vídeo) ou Opus com mais de 2 canais.
        error.NotOpus => error.Unsupported,
        error.TooBig => error.TooBig,
        error.OutOfMemory => error.OutOfMemory,
    };
    errdefer s.deinit(gpa);
    if (s.end <= s.pre_skip) return error.Empty;
    if (s.end - s.pre_skip > @as(u64, max_ms) * (out_rate / 1000)) return error.TooLong;
    return s;
}

/// Decodifica o Ogg de `openOgg` para 48 kHz estéreo. `dec.decode(pacote,
/// pcm)` devolve quantas amostras por canal pôs em `pcm` (intercaladas, com
/// `s.channels` canais), ou null se o pacote não decodifica.
pub fn decodeOgg(gpa: std.mem.Allocator, b: []const u8, s: *const ogg.Stream, dec: anytype) Error![]i16 {
    const total: usize = @intCast(s.end - s.pre_skip);
    const out = try gpa.alloc(i16, total * 2);
    errdefer gpa.free(out);
    @memset(out, 0);
    const ch: usize = s.channels;
    var pcm: [5760 * 2]i16 = undefined;
    for (s.packets, 0..) |pk, i| {
        // O que vem depois do fim declarado não toca: nem decodifica.
        if (pk.start >= s.end) break;
        const got = dec.decode(s.data(b, pk), pcm[0 .. 5760 * ch]) orelse return error.Corrupt;
        const next_start = if (i + 1 < s.packets.len) s.packets[i + 1].start else s.end;
        const p0 = pk.start;
        const p1 = @min(p0 + @min(got, 5760), s.end, @max(next_start, p0 + 1));
        const from = @max(p0, s.pre_skip);
        if (p1 <= from) continue;
        const first: usize = @intCast(from - p0);
        const last: usize = @intCast(p1 - p0);
        const dst0: usize = @intCast(from - s.pre_skip);
        for (first..last, dst0..) |src, dst| {
            const l = pcm[src * ch];
            out[dst * 2] = l;
            out[dst * 2 + 1] = if (ch == 2) pcm[src * ch + 1] else l;
        }
    }
    fadeOut(out);
    return out;
}

// --- Testes ----------------------------------------------------------------

const t = std.testing;

/// WAV de teste com qualquer cabeçalho (o `writeWav16` só faz o caso comum).
const WavSpec = struct {
    tag: u16 = 1,
    channels: u16 = 1,
    rate: u32 = 48000,
    bits: u16 = 16,
    block_align: ?u16 = null,
    extensible: ?u16 = null,
    /// Tamanho declarado do "data" (null = o certo).
    data_size: ?u32 = null,
    /// Um "LIST" antes do "fmt " (ordem fora do comum, mas válida).
    list_first: bool = false,
};

fn buildWav(gpa: std.mem.Allocator, spec: WavSpec, data: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "RIFF\x00\x00\x00\x00WAVE");
    if (spec.list_first) try out.appendSlice(gpa, "LIST\x05\x00\x00\x00abcde\x00");
    var fmt: [40]u8 = @splat(0);
    const fmt_len: usize = if (spec.extensible != null) 40 else 16;
    std.mem.writeInt(u16, fmt[0..2], if (spec.extensible != null) 0xFFFE else spec.tag, .little);
    std.mem.writeInt(u16, fmt[2..4], spec.channels, .little);
    std.mem.writeInt(u32, fmt[4..8], spec.rate, .little);
    const ba = spec.block_align orelse spec.channels * (spec.bits / 8);
    std.mem.writeInt(u32, fmt[8..12], spec.rate * ba, .little);
    std.mem.writeInt(u16, fmt[12..14], ba, .little);
    std.mem.writeInt(u16, fmt[14..16], spec.bits, .little);
    if (spec.extensible) |sub| {
        std.mem.writeInt(u16, fmt[16..18], 22, .little);
        std.mem.writeInt(u16, fmt[18..20], spec.bits, .little);
        std.mem.writeInt(u16, fmt[24..26], sub, .little);
    }
    try out.appendSlice(gpa, "fmt ");
    var b4: [4]u8 = undefined;
    std.mem.writeInt(u32, &b4, @intCast(fmt_len), .little);
    try out.appendSlice(gpa, &b4);
    try out.appendSlice(gpa, fmt[0..fmt_len]);
    try out.appendSlice(gpa, "data");
    std.mem.writeInt(u32, &b4, spec.data_size orelse @intCast(data.len), .little);
    try out.appendSlice(gpa, &b4);
    try out.appendSlice(gpa, data);
    std.mem.writeInt(u32, out.items[4..8], @intCast(out.items.len - 8), .little);
    return out.toOwnedSlice(gpa);
}

fn sineI16(buf: []i16, hz: f32, rate: u32, amp: f32) void {
    for (buf, 0..) |*x, i| x.* = @intFromFloat(@sin(2 * std.math.pi * hz * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rate))) * amp);
}

fn crossings(pcm: []const i16) usize {
    var count: usize = 0;
    var i: usize = 2;
    while (i < pcm.len) : (i += 2) {
        if ((pcm[i - 2] < 0) != (pcm[i] < 0)) count += 1;
    }
    return count;
}

test "WAV de 16 bits a 48 kHz passa igual (só o fim em rampa)" {
    const gpa = t.allocator;
    var src: [2400 * 2]i16 = undefined;
    for (&src, 0..) |*x, i| x.* = @intCast(@as(i32, @intCast(i % 2000)) - 1000);
    const file = try writeWav16(gpa, 2, 48000, &src);
    defer gpa.free(file);
    try t.expectEqual(Format.wav, sniff(file).?);
    const w = try parseWav(file);
    try t.expectEqual(@as(usize, 2400), w.frames());
    try t.expectEqual(@as(u64, 50), w.durationMs());
    const out = try decodeWav(gpa, file, 5000);
    defer gpa.free(out);
    try t.expectEqual(src.len, out.len);
    // 1000/32768*32767 arredonda para o mesmo número.
    try t.expectEqualSlices(i16, src[0 .. src.len - fade_frames * 2], out[0 .. out.len - fade_frames * 2]);
    try t.expectEqual(@as(i16, 0), out[out.len - 1]);
}

test "WAV: 8, 24 e 32 bits, float, extensível, mono, 6 canais e pedaço extra antes" {
    const gpa = t.allocator;
    // Meio da escala em cada formato (≈ 0,5).
    const cases = [_]struct { spec: WavSpec, frame: []const u8 }{
        .{ .spec = .{ .bits = 8 }, .frame = &.{192} },
        .{ .spec = .{ .bits = 24 }, .frame = &.{ 0, 0, 0x40 } },
        .{ .spec = .{ .bits = 32 }, .frame = &.{ 0, 0, 0, 0x40 } },
        .{ .spec = .{ .tag = 3, .bits = 32 }, .frame = &.{ 0, 0, 0, 0x3f } },
        .{ .spec = .{ .tag = 3, .bits = 64 }, .frame = &.{ 0, 0, 0, 0, 0, 0, 0xe0, 0x3f } },
        .{ .spec = .{ .extensible = 1, .bits = 16 }, .frame = &.{ 0, 0x40 } },
        .{ .spec = .{ .extensible = 3, .bits = 32 }, .frame = &.{ 0, 0, 0, 0x3f } },
        .{ .spec = .{ .list_first = true }, .frame = &.{ 0, 0x40 } },
    };
    for (cases) |cs| {
        var data: [400 * 8]u8 = undefined;
        const fb = cs.frame.len;
        for (0..400) |i| @memcpy(data[i * fb ..][0..fb], cs.frame);
        const file = try buildWav(gpa, cs.spec, data[0 .. 400 * fb]);
        defer gpa.free(file);
        const out = try decodeWav(gpa, file, 5000);
        defer gpa.free(out);
        try t.expectEqual(@as(usize, 400 * 2), out.len);
        try t.expect(@abs(@as(i32, out[10]) - 16384) < 200);
        try t.expectEqual(out[10], out[11]);
    }
    // 6 canais: os pares à esquerda, os ímpares à direita.
    var six: [100 * 6 * 2]u8 = undefined;
    for (0..100) |i| for (0..6) |ch| std.mem.writeInt(i16, six[(i * 6 + ch) * 2 ..][0..2], if (ch % 2 == 0) 8192 else -8192, .little);
    const file = try buildWav(gpa, .{ .channels = 6 }, &six);
    defer gpa.free(file);
    const out = try decodeWav(gpa, file, 5000);
    defer gpa.free(out);
    try t.expect(out[0] > 8000 and out[1] < -8000);
}

test "WAV: o que não é PCM simples é recusado com o motivo certo" {
    const gpa = t.allocator;
    const data: [64]u8 = @splat(0);
    const unsupported = [_]WavSpec{
        .{ .tag = 2, .bits = 4, .block_align = 1 }, // ADPCM
        .{ .tag = 7, .bits = 8 }, // µ-law
        .{ .tag = 0x55, .bits = 16 }, // MP3 dentro do WAV
        .{ .bits = 12, .block_align = 2 },
        .{ .tag = 3, .bits = 16 },
        .{ .channels = 0, .block_align = 2 },
        .{ .channels = 9 },
        .{ .rate = 4000 },
        .{ .rate = 384000 },
        .{ .extensible = 2, .bits = 16 },
    };
    for (unsupported) |spec| {
        const file = try buildWav(gpa, spec, &data);
        defer gpa.free(file);
        try t.expectError(error.Unsupported, parseWav(file));
    }
    try t.expectError(error.Unsupported, parseWav("ID3\x04\x00\x00\x00\x00\x00\x00 mp3 de verdade"));
    try t.expectError(error.Unsupported, parseWav("RIFX\x00\x00\x00\x00WAVEfmt "));
    try t.expectError(error.Unsupported, parseWav(""));
    // Cabeçalho que se contradiz.
    const bad_align = try buildWav(gpa, .{ .channels = 2, .block_align = 3 }, &data);
    defer gpa.free(bad_align);
    try t.expectError(error.Corrupt, parseWav(bad_align));
    try t.expectError(error.Corrupt, parseWav("RIFF\x04\x00\x00\x00WAVE"));
    try t.expectError(error.Corrupt, parseWav("RIFF\x10\x00\x00\x00WAVEfmt \x08\x00\x00\x00\x01\x00\x01\x00\x80\xbb\x00\x00"));
    // Só o fmt, sem data.
    const no_data = try buildWav(gpa, .{}, &.{});
    defer gpa.free(no_data);
    try t.expectError(error.Empty, parseWav(no_data));
    const no_data_chunk = no_data[0 .. no_data.len - 8];
    try t.expectError(error.Corrupt, parseWav(no_data_chunk));
    // Extensível sem o resto do cabeçalho.
    const short_ext = try buildWav(gpa, .{}, &data);
    defer gpa.free(short_ext);
    std.mem.writeInt(u16, short_ext[20..22], 0xFFFE, .little);
    try t.expectError(error.Corrupt, parseWav(short_ext));
}

test "WAV cortado em qualquer ponto: erro ou o pedaço que sobrou, nunca leitura fora" {
    const gpa = t.allocator;
    var src: [300 * 2]i16 = undefined;
    sineI16(&src, 440, 22050, 9000);
    const file = try buildWav(gpa, .{ .channels = 2, .rate = 22050, .list_first = true }, std.mem.sliceAsBytes(&src));
    defer gpa.free(file);
    var cut: usize = 0;
    while (cut <= file.len) : (cut += 1) {
        // Uma cópia do tamanho exato: o leitor não tem como ver além.
        const part = try gpa.dupe(u8, file[0..cut]);
        defer gpa.free(part);
        if (decodeWav(gpa, part, 5000)) |out| {
            defer gpa.free(out);
            // Só quadros inteiros do que veio.
            try t.expect(cut > 44);
            try t.expect(out.len > 0 and out.len <= outFrames(300, 22050) * 2);
        } else |e| try t.expect(e == error.Corrupt or e == error.Empty or e == error.Unsupported);
    }
    // "data" declarado maior que o arquivo (gravação interrompida): vale o que existe.
    const liar = try buildWav(gpa, .{ .data_size = 0xFFFF_FFF0 }, std.mem.sliceAsBytes(src[0..100]));
    defer gpa.free(liar);
    const w = try parseWav(liar);
    try t.expectEqual(@as(usize, 100), w.frames());
}

test "limites: 2 MB, 5 s (o toque até 15 s) e arquivo vazio" {
    const gpa = t.allocator;
    // 5 s exatos passam; um quadro a mais, não.
    const five = try gpa.alloc(i16, 8000 * 5);
    defer gpa.free(five);
    sineI16(five, 300, 8000, 8000);
    const ok = try writeWav16(gpa, 1, 8000, five);
    defer gpa.free(ok);
    const out = try decodeWav(gpa, ok, 5000);
    gpa.free(out);
    const longer = try gpa.alloc(i16, 8000 * 5 + 1);
    defer gpa.free(longer);
    @memset(longer, 100);
    const long_file = try writeWav16(gpa, 1, 8000, longer);
    defer gpa.free(long_file);
    try t.expectError(error.TooLong, decodeWav(gpa, long_file, 5000));
    // O toque aceita mais.
    const ring = try decodeWav(gpa, long_file, 15_000);
    defer gpa.free(ring);
    try t.expectEqual(@as(usize, outFrames(8000 * 5 + 1, 8000) * 2), ring.len);
    // Mais de 2 MB: recusado antes de olhar dentro.
    const big = try gpa.alloc(u8, max_bytes + 1);
    defer gpa.free(big);
    @memset(big, 0);
    @memcpy(big[0..ok.len], ok);
    try t.expectError(error.TooBig, parseWav(big));
    try t.expectError(error.TooBig, openOgg(gpa, big, 15_000));
    // Sem nenhuma amostra.
    const empty = try writeWav16(gpa, 2, 48000, &.{});
    defer gpa.free(empty);
    try t.expectError(error.Empty, decodeWav(gpa, empty, 5000));
}

test "conversão de taxa: a frequência e o volume ficam, o tamanho acompanha" {
    const gpa = t.allocator;
    // 0,5 s de 1 kHz em várias taxas: ~1000 cruzamentos por zero em 0,5 s, amplitude igual.
    for ([_]u32{ 8000, 22050, 44100, 48000, 96000, 192000 }) |rate| {
        const n = rate / 2;
        const mono = try gpa.alloc(i16, n);
        defer gpa.free(mono);
        sineI16(mono, 1000, rate, 16000);
        const file = try writeWav16(gpa, 1, rate, mono);
        defer gpa.free(file);
        const out = try decodeWav(gpa, file, 5000);
        defer gpa.free(out);
        try t.expectEqual(@as(usize, 24000 * 2), out.len);
        const zc = crossings(out);
        try t.expect(zc >= 990 and zc <= 1010);
        var peak: i32 = 0;
        for (out) |x| peak = @max(peak, @as(i32, @intCast(@abs(x))));
        // Descer a taxa tira um pouco do pico (a média); nunca estoura.
        try t.expect(peak > 14000 and peak <= 16100);
    }
    // Constante continua constante, nos dois sentidos.
    var flat: [1000]i16 = @splat(12000);
    const up = try writeWav16(gpa, 1, 11025, &flat);
    defer gpa.free(up);
    const up_out = try decodeWav(gpa, up, 5000);
    defer gpa.free(up_out);
    for (up_out[0 .. up_out.len - fade_frames * 2]) |x| try t.expect(@abs(@as(i32, x) - 12000) <= 1);
    const down = try writeWav16(gpa, 1, 96000, &flat);
    defer gpa.free(down);
    const down_out = try decodeWav(gpa, down, 5000);
    defer gpa.free(down_out);
    try t.expectEqual(@as(usize, 500 * 2), down_out.len);
    for (down_out[0 .. down_out.len - fade_frames * 2]) |x| try t.expect(@abs(@as(i32, x) - 12000) <= 1);
}

/// Decodificador falso: cada pacote vira o valor do seu segundo byte vezes
/// 100, em todas as amostras (os dois canais iguais, ou só um).
const FakeOpus = struct {
    channels: usize,
    fail_on: ?u8 = null,

    pub fn decode(f: *FakeOpus, packet: []const u8, pcm: []i16) ?usize {
        const samples = ogg.packetSamples(packet) orelse return null;
        if (packet.len < 2 or f.fail_on == packet[1]) return null;
        @memset(pcm[0 .. samples * f.channels], @as(i16, packet[1]) * 100);
        return samples;
    }
};

fn oggOf(gpa: std.mem.Allocator, channels: u8, pre_skip: u16, n_packets: usize, end: u64) !std.ArrayList(u8) {
    var w: ogg.Writer = .{ .gpa = gpa };
    errdefer w.out.deinit(gpa);
    var hb: [19]u8 = undefined;
    try w.packets(ogg.flag_bos, 0, &.{ogg.opusHead(&hb, channels, pre_skip)});
    try w.packets(0, 0, &.{"OpusTags\x00\x00\x00\x00\x00\x00\x00\x00"});
    var list: [64][2]u8 = undefined;
    var slices: [64][]const u8 = undefined;
    for (0..n_packets) |i| {
        // 20 ms (SILK, config 1), e o valor no segundo byte.
        list[i] = .{ 1 << 3, @intCast(i + 1) };
        slices[i] = &list[i];
    }
    try w.packets(ogg.flag_eos, end, slices[0..n_packets]);
    return w.out;
}

test "Ogg Opus: tira o pre-skip e o fim cortado, mono vira estéreo" {
    const gpa = t.allocator;
    // 5 pacotes de 20 ms (4800 amostras), 312 de pre-skip, fim cortado em 4500.
    var file = try oggOf(gpa, 1, 312, 5, 4500);
    defer file.deinit(gpa);
    try t.expectEqual(Format.ogg, sniff(file.items).?);
    var s = try openOgg(gpa, file.items, 5000);
    defer s.deinit(gpa);
    var dec: FakeOpus = .{ .channels = 1 };
    const out = try decodeOgg(gpa, file.items, &s, &dec);
    defer gpa.free(out);
    try t.expectEqual(@as(usize, (4500 - 312) * 2), out.len);
    // A primeira amostra é a 312ª do primeiro pacote; a 960-312 já é do segundo.
    try t.expectEqual(@as(i16, 100), out[0]);
    try t.expectEqual(out[0], out[1]);
    try t.expectEqual(@as(i16, 200), out[(960 - 312) * 2]);
    try t.expectEqual(@as(i16, 500), out[(3840 - 312) * 2]);
    // O fim em rampa chega a zero.
    try t.expectEqual(@as(i16, 0), out[out.len - 1]);
}

test "Ogg Opus: longo, estragado, de outra coisa ou que não decodifica é recusado" {
    const gpa = t.allocator;
    // 60 pacotes de 20 ms = 1,2 s: passa de 1 s.
    var long = try oggOf(gpa, 2, 0, 60, 60 * 960);
    defer long.deinit(gpa);
    try t.expectError(error.TooLong, openOgg(gpa, long.items, 1000));
    var s = try openOgg(gpa, long.items, 5000);
    defer s.deinit(gpa);
    var dec: FakeOpus = .{ .channels = 2 };
    const out = try decodeOgg(gpa, long.items, &s, &dec);
    gpa.free(out);
    // Um pacote que a libopus recusaria: o arquivo todo é recusado.
    var bad_dec: FakeOpus = .{ .channels = 2, .fail_on = 7 };
    try t.expectError(error.Corrupt, decodeOgg(gpa, long.items, &s, &bad_dec));
    // Um byte trocado: o CRC do Ogg pega.
    const flipped = try gpa.dupe(u8, long.items);
    defer gpa.free(flipped);
    flipped[flipped.len - 3] ^= 0x55;
    try t.expectError(error.Corrupt, openOgg(gpa, flipped, 5000));
    // Cortado no meio.
    try t.expectError(error.Corrupt, openOgg(gpa, long.items[0 .. long.items.len / 2], 5000));
    // Ogg de Vorbis: não é Opus.
    var v: ogg.Writer = .{ .gpa = gpa };
    defer v.out.deinit(gpa);
    try v.packets(ogg.flag_bos | ogg.flag_eos, 0, &.{"\x01vorbis\x00\x00\x00\x00\x02\x44\xac\x00\x00"});
    try t.expectError(error.Unsupported, openOgg(gpa, v.out.items, 5000));
    // Só o cabeçalho, nenhum som (pre-skip maior que tudo).
    var nothing = try oggOf(gpa, 1, 3000, 2, 1920);
    defer nothing.deinit(gpa);
    try t.expectError(error.Empty, openOgg(gpa, nothing.items, 5000));
}
