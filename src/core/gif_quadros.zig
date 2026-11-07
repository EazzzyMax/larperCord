//! Quanto de uma animação cabe na memória e como ela toca sem perder quadros
//! (sem dependências: testado no `zig build test`; quem decodifica é ui/gif_stream.zig).
//!
//! Animação que cabe no limite de cada GIF fica inteira na memória, já reduzida. A que
//! não cabe (longa ou grande) toca decodificando do arquivo comprimido, alguns quadros
//! à frente, num anel pequeno: todos os quadros, no tempo de cada um, gastando só o
//! anel. Pular quadros (juntar dois em um) fica para quando nem isso cabe no limite.
const std = @import("std");

/// Quadros prontos à frente do que está na tela.
pub const ring_len = 6;

pub const Mode = enum {
    /// Todos os quadros na memória.
    full,
    /// Decodificando aos poucos, num anel de `ring_len` quadros.
    stream,
    /// Juntando quadros dois a dois até caber (fica menos fluido).
    halve,
};

pub const Kind = enum { gif, webp };

/// Memória para tocar decodificando aos poucos: o arquivo comprimido, o decodificador
/// (no GIF, a tela cheia, o fundo, o histórico e as duas anteriores que o descarte
/// "restaurar ao anterior" pede; no WebP, a tela e a anterior) e os quadros já
/// reduzidos (o anel, o parado e a textura que toca).
pub fn streamBytes(compressed: usize, kind: Kind, src_w: usize, src_h: usize, w: usize, h: usize) usize {
    const per_src: usize = switch (kind) {
        .gif => 4 * 4 + 1,
        .webp => 4 * 2,
    };
    return compressed +| src_w *| src_h *| per_src +| (ring_len + 2) *| w *| h *| 4;
}

/// O que fazer com uma animação de `frames` quadros que somam `frames_bytes`.
/// `stream_bytes` = null quando o formato não toca aos poucos (APNG, vídeo).
pub fn decide(frames_bytes: usize, frames: usize, limit: usize, max_frames: usize, stream_bytes: ?usize) Mode {
    if (frames_bytes <= limit and frames <= max_frames) return .full;
    if (stream_bytes) |s| if (s <= limit) return .stream;
    return .halve;
}

/// Índices do anel: a thread que decodifica escreve em `writeIndex`, a da tela lê
/// em `head`. Quem usa protege com um mutex.
pub const Ring = struct {
    head: u8 = 0,
    count: u8 = 0,

    pub fn writeIndex(r: Ring) usize {
        return (@as(usize, r.head) + r.count) % ring_len;
    }

    pub fn full(r: Ring) bool {
        return r.count >= ring_len;
    }

    pub fn push(r: *Ring) void {
        std.debug.assert(!r.full());
        r.count += 1;
    }

    pub fn pop(r: *Ring) void {
        std.debug.assert(r.count > 0);
        r.head = @intCast((@as(usize, r.head) + 1) % ring_len);
        r.count -= 1;
    }

    /// Pede mais quando sobra metade: a thread acorda menos e o anel nunca seca
    /// enquanto ela dá conta.
    pub fn wantsFill(r: Ring) bool {
        return r.count <= ring_len / 2;
    }
};

/// O relógio de uma animação tocando aos poucos. Cada quadro fica o tempo dele; um
/// atraso pequeno (o quadro da tela saiu um pouco depois) é compensado no próximo,
/// para o ritmo médio ficar certo. Atraso grande (o app dormiu, a animação saiu da
/// tela) recomeça a contar de agora: nunca pula quadro para alcançar o relógio.
pub const Pace = struct {
    /// Quando o quadro na tela acaba (0 = nenhum ainda).
    due_ms: i64 = 0,

    pub const late_ms: i64 = 250;

    pub fn ready(p: Pace, now: i64) bool {
        return p.due_ms == 0 or now >= p.due_ms;
    }

    /// Acabou de mostrar um quadro de `delay_ms`.
    pub fn shown(p: *Pace, now: i64, delay_ms: u32) void {
        const base = if (p.due_ms == 0 or now - p.due_ms > late_ms) now else p.due_ms;
        p.due_ms = base + @max(delay_ms, 1);
    }
};

// --- GIF longo da demonstração ---------------------------------------------------

/// Um GIF de verdade (para passar pelo decodificador de verdade), sem compressão: com
/// códigos de 8 bits e um "limpar" a cada 120 pixels, cada código é um byte e a
/// tabela do LZW nunca cresce. Paleta de 128 cores; faixas que andam a cada quadro.
pub fn demoGif(gpa: std.mem.Allocator, w: u16, h: u16, frames: u16, delay_cs: u16) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const px: usize = @as(usize, w) * h;
    // Pixels + um "limpar" a cada 120 + o tamanho de cada sub-bloco de 255.
    const per_frame = px + px / 120 + 2;
    try out.ensureTotalCapacity(gpa, 1024 + @as(usize, frames) * (per_frame + per_frame / 255 + 32));
    // (o cabeçalho cabe nos primeiros 1024 bytes)
    const le = std.mem.nativeToLittle;
    out.appendSliceAssumeCapacity("GIF89a");
    out.appendSliceAssumeCapacity(&std.mem.toBytes(le(u16, w)));
    out.appendSliceAssumeCapacity(&std.mem.toBytes(le(u16, h)));
    // Paleta global de 128 cores, fundo 0, sem proporção.
    out.appendSliceAssumeCapacity(&.{ 0xF6, 0, 0 });
    for (0..128) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / 128.0 * std.math.tau;
        for ([_]f32{ 0, 2.1, 4.2 }) |ph| out.appendAssumeCapacity(@intFromFloat(127.5 + 127.5 * @sin(t + ph)));
    }
    // Repetir para sempre.
    out.appendSliceAssumeCapacity("\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00");
    var block: [256]u8 = undefined;
    for (0..frames) |f| {
        // Controle: sem descarte, o tempo do quadro.
        try out.appendSlice(gpa, &.{ 0x21, 0xF9, 0x04, 0x04 });
        try out.appendSlice(gpa, &std.mem.toBytes(le(u16, delay_cs)));
        try out.appendSlice(gpa, &.{ 0, 0 });
        // A tela toda, sem paleta própria; códigos de 7+1 bits.
        try out.appendSlice(gpa, &.{ 0x2C, 0, 0, 0, 0 });
        try out.appendSlice(gpa, &std.mem.toBytes(le(u16, w)));
        try out.appendSlice(gpa, &std.mem.toBytes(le(u16, h)));
        try out.appendSlice(gpa, &.{ 0, 7 });
        var n: usize = 0;
        var run: usize = 120;
        var i: usize = 0;
        while (i <= px) {
            // Um código: "limpar" (128) a cada 120 pixels, o pixel, ou o fim (129).
            const code: u8 = if (i == px) 129 else if (run == 120) 128 else blk: {
                const x = i % w;
                const y = i / w;
                break :blk @intCast((x / 6 + y / 6 + f * 3) & 127);
            };
            if (code == 128) run = 0 else {
                if (code != 129) run += 1;
                i += 1;
            }
            block[1 + n] = code;
            n += 1;
            if (n == 255 or i > px) {
                block[0] = @intCast(n);
                try out.appendSlice(gpa, block[0 .. n + 1]);
                n = 0;
            }
        }
        try out.append(gpa, 0);
    }
    try out.append(gpa, 0x3B);
    return out.toOwnedSlice(gpa);
}

test "o que fica inteiro, o que toca aos poucos e o que ainda pula quadros" {
    const mb = 1024 * 1024;
    // Cabe: inteiro.
    try std.testing.expectEqual(Mode.full, decide(10 * mb, 100, 32 * mb, 300, 5 * mb));
    // Passa do limite de memória ou de quadros: aos poucos, se o anel couber.
    try std.testing.expectEqual(Mode.stream, decide(40 * mb, 100, 32 * mb, 300, 12 * mb));
    try std.testing.expectEqual(Mode.stream, decide(10 * mb, 301, 32 * mb, 300, 12 * mb));
    // Nem o anel cabe (arquivo enorme), ou o formato não toca aos poucos: pula quadros.
    try std.testing.expectEqual(Mode.halve, decide(40 * mb, 100, 32 * mb, 300, 33 * mb));
    try std.testing.expectEqual(Mode.halve, decide(40 * mb, 100, 32 * mb, 300, null));
}

test "custo de tocar aos poucos conta o arquivo, o decodificador e o anel" {
    // GIF 480×270 de 9 MB mostrado em 400×225: bem menos que os quadros todos.
    const gif = streamBytes(9_000_000, .gif, 480, 270, 400, 225);
    try std.testing.expectEqual(9_000_000 + 480 * 270 * 17 + 8 * 400 * 225 * 4, gif);
    try std.testing.expect(gif < 32 * 1024 * 1024);
    try std.testing.expect(streamBytes(0, .webp, 100, 100, 50, 50) < streamBytes(0, .gif, 100, 100, 50, 50));
    // Números absurdos saturam em vez de estourar.
    try std.testing.expectEqual(std.math.maxInt(usize), streamBytes(std.math.maxInt(usize), .gif, 4096, 4096, 4096, 4096));
}

test "anel: escreve na frente, lê do começo, dá a volta" {
    var r: Ring = .{};
    try std.testing.expect(r.wantsFill());
    for (0..ring_len) |i| {
        try std.testing.expectEqual(i, r.writeIndex());
        r.push();
    }
    try std.testing.expect(r.full() and !r.wantsFill());
    r.pop();
    r.pop();
    try std.testing.expectEqual(@as(usize, 0), r.writeIndex());
    try std.testing.expectEqual(@as(u8, 2), r.head);
    r.pop();
    try std.testing.expect(r.wantsFill());
    for (0..3) |_| r.push();
    try std.testing.expect(r.full());
    try std.testing.expectEqual(@as(usize, 3), r.head);
}

test "relógio: cada quadro o seu tempo, sem pular para alcançar" {
    var p: Pace = .{};
    try std.testing.expect(p.ready(1000));
    p.shown(1000, 40);
    try std.testing.expect(!p.ready(1039));
    try std.testing.expect(p.ready(1040));
    // Saiu 10 ms atrasado: o próximo compensa (o ritmo médio continua 40 ms).
    p.shown(1050, 40);
    try std.testing.expectEqual(@as(i64, 1080), p.due_ms);
    // O app dormiu um segundo: recomeça de agora, mostrando o quadro seguinte.
    p.shown(2100, 40);
    try std.testing.expectEqual(@as(i64, 2140), p.due_ms);
    // Tempo zero não trava o relógio.
    p.shown(2140, 0);
    try std.testing.expectEqual(@as(i64, 2141), p.due_ms);
}

test "GIF da demonstração: cabeçalho, quadros e fim no lugar" {
    const gpa = std.testing.allocator;
    const data = try demoGif(gpa, 33, 7, 3, 4);
    defer gpa.free(data);
    try std.testing.expect(std.mem.startsWith(u8, data, "GIF89a\x21\x00\x07\x00\xF6"));
    try std.testing.expectEqual(@as(u8, 0x3B), data[data.len - 1]);
    // Três controles de quadro, com 40 ms cada.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, data, "\x21\xF9\x04\x04\x04\x00"));
    // O primeiro código de cada quadro é "limpar" e nunca passam 120 pixels sem outro.
    const first = std.mem.indexOf(u8, data, "\x21\xF9\x04\x04").? + 8;
    try std.testing.expectEqual(@as(u8, 0x2C), data[first]);
    try std.testing.expectEqual(@as(u8, 7), data[first + 10]);
    try std.testing.expectEqual(@as(u8, 128), data[first + 12]);
    var run: usize = 0;
    var pixels: usize = 0;
    for (data[first + 12 .. first + 12 + data[first + 11]]) |code| {
        if (code == 128) run = 0 else if (code < 128) {
            run += 1;
            pixels += 1;
        }
        try std.testing.expect(run <= 120);
    }
    try std.testing.expect(pixels > 0);
}
