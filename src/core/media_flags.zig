//! Marcas de mídia de uma mensagem: anexo com spoiler (nome SPOILER_ ou a
//! marca IS_SPOILER), conteúdo sensível (marcado pelo Discord como explícito,
//! violento ou de autolesão), link dentro de ||spoiler|| e a forma de onda das
//! mensagens de voz. Tudo puro, para os testes.
//!
//! Os números são os de docs.discord.food (Message resource: Attachment Flags,
//! Embed Flags e Message Flags).
const std = @import("std");
const types = @import("types.zig");

pub const att_spoiler: u64 = 1 << 3;
pub const att_explicit: u64 = 1 << 4;
pub const att_gore: u64 = 1 << 6;
pub const att_self_harm: u64 = 1 << 7;
/// Os embeds usam os mesmos bits para conteúdo sensível.
pub const embed_explicit: u64 = 1 << 4;
pub const embed_gore: u64 = 1 << 6;
pub const embed_self_harm: u64 = 1 << 7;
/// IS_VOICE_MESSAGE: o anexo de áudio é uma mensagem de voz.
pub const msg_voice: u64 = 1 << 13;

const sensitive_bits = att_explicit | att_gore | att_self_harm;

/// O `flags` de um objeto do Discord (negativo ou ausente = nenhum).
pub fn flagsValue(v: ?i64) u64 {
    const x = v orelse return 0;
    return if (x < 0) 0 else @intCast(x);
}

/// Anexo que o autor marcou como spoiler (o cliente oficial põe SPOILER_ no
/// nome; o Discord também manda a marca).
pub fn spoilerAttachment(filename: []const u8, flags: u64) bool {
    return flags & att_spoiler != 0 or std.ascii.startsWithIgnoreCase(filename, "SPOILER_");
}

/// Anexo ou embed marcado pelo Discord como conteúdo sensível.
pub fn sensitive(flags: u64) bool {
    return flags & sensitive_bits != 0;
}

/// O link `url` aparece dentro de um ||spoiler|| do texto? (É assim que a
/// prévia de um link escondido fica coberta também.)
pub fn urlInSpoiler(content: []const u8, url_in: []const u8) bool {
    const url = std.mem.trimEnd(u8, url_in, "/");
    if (url.len < 8) return false;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, content, i, "||")) |open| {
        const close = std.mem.indexOfPos(u8, content, open + 2, "||") orelse return false;
        if (std.mem.indexOf(u8, content[open + 2 .. close], url) != null) return true;
        i = close + 2;
    }
    return false;
}

/// `duration_secs` (segundos, com fração) em ms; fora do razoável = 0.
pub fn secondsToMs(secs: f64) u32 {
    if (!(secs > 0) or secs > 86_400) return 0;
    return @intFromFloat(secs * 1000);
}

/// A forma de onda do Discord (base64 de bytes de 0 a 255, uma amostra cada,
/// até 256) reduzida a `types.wave_bars` barras: o pico de cada pedaço.
/// false = não veio ou veio estragada (fica a barra lisa).
pub fn waveBars(b64_in: []const u8, out: *[types.wave_bars]u8) bool {
    const b64 = std.mem.trim(u8, b64_in, " \r\n");
    if (b64.len == 0 or b64.len > 4096) return false;
    var raw: [3072]u8 = undefined;
    const n = decodeB64(b64, &raw) orelse return false;
    if (n == 0) return false;
    for (out, 0..) |*bar, k| {
        const from = k * n / out.len;
        const to = @max(from + 1, (k + 1) * n / out.len);
        bar.* = std.mem.max(u8, raw[from..@min(to, n)]);
    }
    return true;
}

fn decodeB64(s: []const u8, buf: []u8) ?usize {
    // Com ou sem o "=" no fim (o Discord manda com).
    inline for (.{ std.base64.standard.Decoder, std.base64.standard_no_pad.Decoder }) |dec| {
        if (dec.calcSizeForSlice(s)) |n| {
            if (n <= buf.len) {
                if (dec.decode(buf[0..n], s)) |_| return n else |_| {}
            }
        } else |_| {}
    }
    return null;
}

test "spoiler pelo nome ou pela marca; sensível pelos bits do Discord" {
    try std.testing.expect(spoilerAttachment("SPOILER_gato.png", 0));
    try std.testing.expect(spoilerAttachment("spoiler_gato.png", 0));
    try std.testing.expect(spoilerAttachment("gato.png", att_spoiler));
    try std.testing.expect(!spoilerAttachment("gato_SPOILER_.png", 0));
    try std.testing.expect(!spoilerAttachment("gato.png", att_explicit));
    try std.testing.expect(sensitive(att_explicit));
    try std.testing.expect(sensitive(att_gore | att_spoiler));
    try std.testing.expect(sensitive(att_self_harm));
    try std.testing.expect(!sensitive(att_spoiler | (1 << 5)));
    try std.testing.expectEqual(@as(u64, 0), flagsValue(-3));
    try std.testing.expectEqual(@as(u64, 8192), flagsValue(8192));
}

test "link dentro de ||spoiler||" {
    try std.testing.expect(urlInSpoiler("olha ||https://exemplo.com/a.png|| kkk", "https://exemplo.com/a.png"));
    try std.testing.expect(urlInSpoiler("||veja https://exemplo.com/a||", "https://exemplo.com/a/"));
    try std.testing.expect(!urlInSpoiler("https://exemplo.com/a.png ||outra coisa||", "https://exemplo.com/a.png"));
    try std.testing.expect(!urlInSpoiler("||https://exemplo.com/a.png", "https://exemplo.com/a.png"));
    try std.testing.expect(urlInSpoiler("||x|| e ||https://e.com/z||", "https://e.com/z"));
    try std.testing.expect(!urlInSpoiler("||||", ""));
}

test "forma de onda: base64 vira barras com o pico de cada pedaço" {
    var bars: [types.wave_bars]u8 = undefined;
    // 96 amostras: 0, 10, 20... a cada duas barras sobe.
    var raw: [96]u8 = undefined;
    for (&raw, 0..) |*b, i| b.* = @intCast(i * 2);
    var enc: [200]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&enc, &raw);
    try std.testing.expect(waveBars(b64, &bars));
    try std.testing.expectEqual(@as(u8, 2), bars[0]);
    try std.testing.expectEqual(@as(u8, 190), bars[types.wave_bars - 1]);
    // Poucas amostras: esticadas.
    try std.testing.expect(waveBars("AP8=", &bars));
    try std.testing.expectEqual(@as(u8, 0), bars[0]);
    try std.testing.expectEqual(@as(u8, 255), bars[types.wave_bars - 1]);
    // Sem "=" também vale; lixo não.
    try std.testing.expect(waveBars("AP8", &bars));
    try std.testing.expect(!waveBars("@@@@", &bars));
    try std.testing.expect(!waveBars("", &bars));
    try std.testing.expectEqual(@as(u32, 3500), secondsToMs(3.5));
    try std.testing.expectEqual(@as(u32, 0), secondsToMs(-1));
    try std.testing.expectEqual(@as(u32, 0), secondsToMs(std.math.nan(f64)));
}
