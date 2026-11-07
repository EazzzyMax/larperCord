//! Ogg Opus mínimo, para tocar mensagens de voz: lê as páginas do Ogg (com o
//! CRC conferido), junta os pacotes do primeiro fluxo, confere o OpusHead e
//! monta um índice com o instante em que cada pacote começa (amostras a 48 kHz).
//! Todo tamanho é conferido contra o que sobrou: arquivo truncado ou estragado
//! vira erro, nunca leitura fora do lugar. Nada de libopus aqui (dá para testar
//! sem ela); quem decodifica é ui/voice_msg.zig.
const std = @import("std");

/// Tetos (bem acima de uma mensagem de voz: o Discord manda alguns minutos).
pub const max_file: usize = 16 << 20;
pub const max_packets: usize = 1 << 18;
/// Um pacote Opus tem no máximo 120 ms × 1275 bytes por quadro.
pub const max_packet: usize = 64 * 1024;
/// Amostras por segundo de qualquer Ogg Opus (a granule é sempre a 48 kHz).
pub const rate: u32 = 48_000;
/// Antes de um ponto de busca, o decodificador precisa de uns 80 ms para assentar.
pub const preroll: u64 = 3840;

pub const Error = error{ NotOgg, Corrupt, NotOpus, TooBig, OutOfMemory };

pub const flag_continued: u8 = 1;
pub const flag_bos: u8 = 2;
pub const flag_eos: u8 = 4;
pub const no_granule: u64 = std.math.maxInt(u64);

pub const Page = struct {
    flags: u8,
    granule: u64,
    serial: u32,
    lacing: []const u8,
    /// Onde o corpo começa no arquivo e onde a próxima página começa.
    body_off: usize,
    next: usize,
};

const crc_table: [256]u32 = blk: {
    @setEvalBranchQuota(5000);
    var t: [256]u32 = undefined;
    for (0..256) |i| {
        var r: u32 = @as(u32, i) << 24;
        for (0..8) |_| r = if (r & 0x8000_0000 != 0) (r << 1) ^ 0x04C1_1DB7 else r << 1;
        t[i] = r;
    }
    break :blk t;
};

fn crcUpdate(crc: u32, bytes: []const u8) u32 {
    var v = crc;
    for (bytes) |b| v = (v << 8) ^ crc_table[((v >> 24) ^ b) & 0xff];
    return v;
}

/// CRC de uma página inteira, com o campo do CRC contando como zeros.
fn pageCrc(p: []const u8) u32 {
    var v = crcUpdate(0, p[0..22]);
    v = crcUpdate(v, &.{ 0, 0, 0, 0 });
    return crcUpdate(v, p[26..]);
}

/// A página que começa em `at`.
pub fn page(file: []const u8, at: usize) Error!Page {
    if (at > file.len or file.len - at < 27) return error.Corrupt;
    const h = file[at..];
    if (!std.mem.eql(u8, h[0..4], "OggS")) return error.NotOgg;
    if (h[4] != 0) return error.Corrupt;
    const nseg = h[26];
    const hdr: usize = 27 + @as(usize, nseg);
    if (h.len < hdr) return error.Corrupt;
    const lacing = h[27..hdr];
    var body_len: usize = 0;
    for (lacing) |l| body_len += l;
    if (h.len - hdr < body_len) return error.Corrupt;
    const whole = h[0 .. hdr + body_len];
    if (pageCrc(whole) != std.mem.readInt(u32, h[22..26], .little)) return error.Corrupt;
    return .{
        .flags = h[5],
        .granule = std.mem.readInt(u64, h[6..14], .little),
        .serial = std.mem.readInt(u32, h[14..18], .little),
        .lacing = lacing,
        .body_off = at + hdr,
        .next = at + hdr + body_len,
    };
}

/// Amostras (48 kHz) de um pacote Opus, pelo byte TOC (RFC 6716, 3.1).
/// null = pacote inválido.
pub fn packetSamples(p: []const u8) ?u32 {
    if (p.len == 0) return null;
    const toc = p[0];
    const cfg = toc >> 3;
    const per: u32 = if (cfg < 12)
        ([_]u32{ 480, 960, 1920, 2880 })[cfg & 3]
    else if (cfg < 16)
        (if (cfg & 1 == 0) @as(u32, 480) else 960)
    else
        ([_]u32{ 120, 240, 480, 960 })[cfg & 3];
    const frames: u32 = switch (toc & 3) {
        0 => 1,
        1, 2 => 2,
        else => if (p.len < 2) return null else p[1] & 0x3f,
    };
    if (frames == 0) return null;
    const total = per * frames;
    // Mais de 120 ms num pacote não existe.
    if (total > 5760) return null;
    return total;
}

pub const Packet = struct {
    off: u32,
    len: u32,
    /// O pacote atravessava páginas: os bytes estão em `Stream.spill`.
    spill: bool = false,
    /// Onde começa, em amostras a 48 kHz decodificadas desde o começo (as do
    /// pre-skip contam: a granule do Ogg Opus é assim).
    start: u64,
};

pub const Stream = struct {
    channels: u8,
    pre_skip: u16,
    packets: []Packet,
    spill: []u8,
    /// Fim do áudio em amostras (com o pre-skip), pela granule da última página.
    end: u64,

    pub fn deinit(s: *Stream, gpa: std.mem.Allocator) void {
        gpa.free(s.packets);
        gpa.free(s.spill);
        s.* = undefined;
    }

    pub fn data(s: *const Stream, file: []const u8, p: Packet) []const u8 {
        const src = if (p.spill) s.spill else file;
        return src[p.off..][0..p.len];
    }

    /// Duração de verdade (sem o pre-skip do começo).
    pub fn durationMs(s: *const Stream) u32 {
        const n = s.end -| s.pre_skip;
        return @intCast(@min(n / (rate / 1000), std.math.maxInt(u32)));
    }

    /// O pacote de onde começar a decodificar para tocar a partir de `ms` (já
    /// com a folga para o decodificador assentar).
    pub fn seekIndex(s: *const Stream, ms: u32) usize {
        const target = (@as(u64, ms) * (rate / 1000) + s.pre_skip) -| preroll;
        var lo: usize = 0;
        var hi: usize = s.packets.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (s.packets[mid].start <= target) lo = mid + 1 else hi = mid;
        }
        return lo -| 1;
    }
};

/// Lê o arquivo inteiro e monta o índice. Os pacotes apontam para `file`
/// (que precisa continuar vivo) ou para `spill`.
pub fn index(gpa: std.mem.Allocator, file: []const u8) Error!Stream {
    if (file.len > max_file) return error.TooBig;
    var packets: std.ArrayList(Packet) = .empty;
    errdefer packets.deinit(gpa);
    var spill: std.ArrayList(u8) = .empty;
    errdefer spill.deinit(gpa);

    var serial: ?u32 = null;
    var at: usize = 0;
    // O pacote em montagem: no arquivo (contínuo) ou já copiado para `spill`.
    var open = false;
    var cur_off: usize = 0;
    var cur_len: usize = 0;
    var cur_spill = false;
    var n_seen: usize = 0;
    var channels: u8 = 0;
    var pre_skip: u16 = 0;
    var sample: u64 = 0;
    var end: u64 = 0;

    while (at < file.len) {
        const pg = try page(file, at);
        at = pg.next;
        if (serial == null) {
            if (pg.flags & flag_bos == 0) return error.NotOgg;
            serial = pg.serial;
        }
        // Outros fluxos (vídeo, outra trilha): não são nossos.
        if (pg.serial != serial.?) continue;
        // Página nova sem "continua": o pacote pela metade não volta mais.
        if (pg.flags & flag_continued == 0) open = false;
        var off = pg.body_off;
        var skipping = pg.flags & flag_continued != 0 and !open;
        for (pg.lacing) |l| {
            defer off += l;
            if (skipping) {
                // Resto de um pacote cujo começo não vimos.
                if (l < 255) skipping = false;
                continue;
            }
            if (!open) {
                open = true;
                cur_off = off;
                cur_len = l;
                cur_spill = false;
            } else if (!cur_spill and cur_off + cur_len == off) {
                cur_len += l;
            } else {
                if (!cur_spill) {
                    const piece = file[cur_off..][0..cur_len];
                    cur_off = spill.items.len;
                    try spill.appendSlice(gpa, piece);
                    cur_spill = true;
                }
                try spill.appendSlice(gpa, file[off..][0..l]);
                cur_len += l;
            }
            if (cur_len > max_packet) return error.Corrupt;
            if (l == 255) continue;
            open = false;
            const pkt: Packet = .{ .off = @intCast(cur_off), .len = @intCast(cur_len), .spill = cur_spill, .start = sample };
            const bytes = (if (cur_spill) spill.items else file)[pkt.off..][0..pkt.len];
            switch (n_seen) {
                0 => {
                    // OpusHead: versão 0.x, mapeamento 0 (mono ou estéreo).
                    if (bytes.len < 19 or !std.mem.eql(u8, bytes[0..8], "OpusHead")) return error.NotOpus;
                    if (bytes[8] & 0xf0 != 0 or bytes[18] != 0) return error.NotOpus;
                    channels = bytes[9];
                    if (channels < 1 or channels > 2) return error.NotOpus;
                    pre_skip = std.mem.readInt(u16, bytes[10..12], .little);
                },
                1 => if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], "OpusTags")) return error.NotOpus,
                else => if (packetSamples(bytes)) |n| {
                    if (packets.items.len >= max_packets) return error.TooBig;
                    try packets.append(gpa, pkt);
                    sample += n;
                },
            }
            n_seen += 1;
        }
        if (pg.granule != no_granule and n_seen > 2) end = pg.granule;
        if (pg.flags & flag_eos != 0) break;
    }
    if (n_seen == 0) return error.NotOpus;
    if (packets.items.len == 0) return error.Corrupt;
    // A última granule pode cortar o fim (end trimming); nunca passa do que há.
    if (end == 0 or end > sample) end = sample;
    const out_packets = try packets.toOwnedSlice(gpa);
    errdefer gpa.free(out_packets);
    return .{ .channels = channels, .pre_skip = pre_skip, .packets = out_packets, .spill = try spill.toOwnedSlice(gpa), .end = end };
}

// --- Escrita (a mensagem de voz da demonstração e os testes) -----------------

/// Monta páginas de Ogg (com o CRC certo).
pub const Writer = struct {
    out: std.ArrayList(u8) = .empty,
    gpa: std.mem.Allocator,
    seq: u32 = 0,

    pub fn pageOf(w: *Writer, flags: u8, granule: u64, lacing: []const u8, body: []const u8) !void {
        const start = w.out.items.len;
        try w.out.appendSlice(w.gpa, "OggS");
        try w.out.append(w.gpa, 0);
        try w.out.append(w.gpa, flags);
        var b8: [8]u8 = undefined;
        std.mem.writeInt(u64, &b8, granule, .little);
        try w.out.appendSlice(w.gpa, &b8);
        var b4: [4]u8 = undefined;
        std.mem.writeInt(u32, &b4, 0x1234, .little);
        try w.out.appendSlice(w.gpa, &b4);
        std.mem.writeInt(u32, &b4, w.seq, .little);
        try w.out.appendSlice(w.gpa, &b4);
        w.seq += 1;
        try w.out.appendSlice(w.gpa, &.{ 0, 0, 0, 0 });
        try w.out.append(w.gpa, @intCast(lacing.len));
        try w.out.appendSlice(w.gpa, lacing);
        try w.out.appendSlice(w.gpa, body);
        const crc = pageCrc(w.out.items[start..]);
        std.mem.writeInt(u32, w.out.items[start + 22 ..][0..4], crc, .little);
    }

    /// Uma página com pacotes inteiros.
    pub fn packets(w: *Writer, flags: u8, granule: u64, list: []const []const u8) !void {
        var lacing: std.ArrayList(u8) = .empty;
        defer lacing.deinit(w.gpa);
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(w.gpa);
        for (list) |p| {
            var n = p.len;
            while (n >= 255) : (n -= 255) try lacing.append(w.gpa, 255);
            try lacing.append(w.gpa, @intCast(n));
            try body.appendSlice(w.gpa, p);
        }
        try w.pageOf(flags, granule, lacing.items, body.items);
    }
};

pub fn opusHead(buf: *[19]u8, channels: u8, pre_skip: u16) []const u8 {
    @memcpy(buf[0..8], "OpusHead");
    buf[8] = 1;
    buf[9] = channels;
    std.mem.writeInt(u16, buf[10..12], pre_skip, .little);
    std.mem.writeInt(u32, buf[12..16], 48000, .little);
    buf[16] = 0;
    buf[17] = 0;
    buf[18] = 0;
    return buf;
}

test "TOC do Opus diz quantas amostras o pacote tem" {
    // SILK 20 ms, um quadro.
    try std.testing.expectEqual(@as(?u32, 960), packetSamples(&.{(1 << 3) | 0}));
    // CELT 20 ms (config 31), dois quadros.
    try std.testing.expectEqual(@as(?u32, 1920), packetSamples(&.{(31 << 3) | 1}));
    // Híbrido 10 ms (config 12), três quadros (código 3).
    try std.testing.expectEqual(@as(?u32, 1440), packetSamples(&.{ (12 << 3) | 3, 3 }));
    // Código 3 sem a contagem, zero quadros ou mais de 120 ms: inválido.
    try std.testing.expectEqual(@as(?u32, null), packetSamples(&.{(12 << 3) | 3}));
    try std.testing.expectEqual(@as(?u32, null), packetSamples(&.{ (12 << 3) | 3, 0 }));
    try std.testing.expectEqual(@as(?u32, null), packetSamples(&.{ (3 << 3) | 3, 3 }));
    try std.testing.expectEqual(@as(?u32, null), packetSamples(&.{}));
}

test "Ogg Opus: índice dos pacotes, pacote grande e pacote entre páginas" {
    const gpa = std.testing.allocator;
    var w: Writer = .{ .gpa = gpa };
    defer w.out.deinit(gpa);
    var hb: [19]u8 = undefined;
    try w.packets(flag_bos, 0, &.{opusHead(&hb, 1, 312)});
    try w.packets(0, 0, &.{"OpusTags\x00\x00\x00\x00\x00\x00\x00\x00"});
    // Três pacotes de 20 ms; o segundo tem 600 bytes (três segmentos).
    var big: [600]u8 = @splat(0xAB);
    big[0] = 1 << 3;
    try w.packets(0, 960 * 3, &.{ &.{1 << 3}, &big, &.{ 1 << 3, 7 } });
    // Um pacote de 300 bytes que começa numa página e termina na outra.
    var span: [300]u8 = @splat(0xCD);
    span[0] = 1 << 3;
    try w.pageOf(0, no_granule, &.{255}, span[0..255]);
    try w.pageOf(flag_continued | flag_eos, 960 * 4 - 100, &.{45}, span[255..]);


    var s = try index(gpa, w.out.items);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 1), s.channels);
    try std.testing.expectEqual(@as(u16, 312), s.pre_skip);
    try std.testing.expectEqual(@as(usize, 4), s.packets.len);
    try std.testing.expectEqual(@as(u64, 960), s.packets[1].start);
    try std.testing.expectEqual(@as(usize, 600), s.data(w.out.items, s.packets[1]).len);
    try std.testing.expect(!s.packets[1].spill);
    try std.testing.expect(s.packets[3].spill);
    try std.testing.expectEqualSlices(u8, &span, s.data(w.out.items, s.packets[3]));
    // O fim é a granule da última página (cortada em 100 amostras); a
    // duração desconta o pre-skip.
    try std.testing.expectEqual(@as(u64, 960 * 4 - 100), s.end);
    try std.testing.expectEqual(@as(u32, (960 * 4 - 100 - 312) / 48), s.durationMs());
    // Buscar: volta a folga do decodificador; no começo, o primeiro pacote.
    try std.testing.expectEqual(@as(usize, 0), s.seekIndex(0));
    try std.testing.expectEqual(@as(usize, 0), s.seekIndex(60));
    try std.testing.expectEqual(@as(usize, 3), s.seekIndex(10_000));
}

test "Ogg estragado vira erro, nunca leitura fora do lugar" {
    const gpa = std.testing.allocator;
    var w: Writer = .{ .gpa = gpa };
    defer w.out.deinit(gpa);
    var hb: [19]u8 = undefined;
    try w.packets(flag_bos, 0, &.{opusHead(&hb, 2, 0)});
    try w.packets(0, 0, &.{"OpusTags"});
    try w.packets(flag_eos, 960, &.{&.{1 << 3}});
    const good = w.out.items;
    {
        var s = try index(gpa, good);
        s.deinit(gpa);
    }
    // Truncado em qualquer ponto.
    var cut: usize = 1;
    while (cut < good.len) : (cut += 7) {
        if (index(gpa, good[0..cut])) |s_ok| {
            var s = s_ok;
            s.deinit(gpa);
            return error.TestUnexpectedResult;
        } else |_| {}
    }
    // Um byte trocado: o CRC pega.
    const bad = try gpa.dupe(u8, good);
    defer gpa.free(bad);
    bad[bad.len - 1] ^= 0xff;
    try std.testing.expectError(error.Corrupt, index(gpa, bad));
    try std.testing.expectError(error.NotOgg, index(gpa, "RIFF....WAVEfmt nada de ogg aqui, só lixo"));
    // Ogg de outra coisa (Vorbis): não é Opus.
    var v: Writer = .{ .gpa = gpa };
    defer v.out.deinit(gpa);
    try v.packets(flag_bos | flag_eos, 0, &.{"\x01vorbis\x00\x00\x00\x00\x02\x44\xac\x00\x00"});
    try std.testing.expectError(error.NotOpus, index(gpa, v.out.items));
    // Canais demais.
    var t: Writer = .{ .gpa = gpa };
    defer t.out.deinit(gpa);
    try t.packets(flag_bos | flag_eos, 0, &.{opusHead(&hb, 6, 0)});
    try std.testing.expectError(error.NotOpus, index(gpa, t.out.items));
}
