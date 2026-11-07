//! Letras "estilizadas" de volta à letra comum. 𝐫𝐞𝐠𝐫𝐚𝐬, ʀᴇɢʀᴀs, ｒｅｇｒａｓ e ⓡⓔⓖⓡⓐⓢ não são
//! fontes: são caracteres Unicode próprios, que muita fonte não tem. Quando nenhuma fonte
//! carregada tem o desenho, o texto mostra a letra comum em vez de "??????". O texto em si
//! não muda: copiar e citar continuam com os caracteres originais.
const std = @import("std");

/// Capitais pequenas, letras sobrescritas e subscritas, e as letras de `ℝ` e companhia que
/// o Unicode deixou fora dos alfabetos matemáticos.
const singles = [_][2]u32{
    // Capitais pequenas.
    .{ 0x1D00, 'a' }, .{ 0x0299, 'b' }, .{ 0x1D04, 'c' }, .{ 0x1D05, 'd' }, .{ 0x1D07, 'e' },
    .{ 0xA730, 'f' }, .{ 0x0262, 'g' }, .{ 0x029C, 'h' }, .{ 0x026A, 'i' }, .{ 0x1D0A, 'j' },
    .{ 0x1D0B, 'k' }, .{ 0x029F, 'l' }, .{ 0x1D0D, 'm' }, .{ 0x0274, 'n' }, .{ 0x1D0F, 'o' },
    .{ 0x1D18, 'p' }, .{ 0x01EB, 'q' }, .{ 0x0280, 'r' }, .{ 0xA731, 's' }, .{ 0x1D1B, 't' },
    .{ 0x1D1C, 'u' }, .{ 0x1D20, 'v' }, .{ 0x1D21, 'w' }, .{ 0x028F, 'y' }, .{ 0x1D22, 'z' },
    // Sobrescritas.
    .{ 0x1D43, 'a' }, .{ 0x1D47, 'b' }, .{ 0x1D9C, 'c' }, .{ 0x1D48, 'd' }, .{ 0x1D49, 'e' },
    .{ 0x1DA0, 'f' }, .{ 0x1D4D, 'g' }, .{ 0x02B0, 'h' }, .{ 0x2071, 'i' }, .{ 0x02B2, 'j' },
    .{ 0x1D4F, 'k' }, .{ 0x02E1, 'l' }, .{ 0x1D50, 'm' }, .{ 0x207F, 'n' }, .{ 0x1D52, 'o' },
    .{ 0x1D56, 'p' }, .{ 0x02B3, 'r' }, .{ 0x02E2, 's' }, .{ 0x1D57, 't' }, .{ 0x1D58, 'u' },
    .{ 0x1D5B, 'v' }, .{ 0x02B7, 'w' }, .{ 0x02E3, 'x' }, .{ 0x02B8, 'y' }, .{ 0x1DBB, 'z' },
    // Subscritas.
    .{ 0x2090, 'a' }, .{ 0x2091, 'e' }, .{ 0x2092, 'o' }, .{ 0x2093, 'x' }, .{ 0x2095, 'h' },
    .{ 0x2096, 'k' }, .{ 0x2097, 'l' }, .{ 0x2098, 'm' }, .{ 0x2099, 'n' }, .{ 0x209A, 'p' },
    .{ 0x209B, 's' }, .{ 0x209C, 't' },
    // Buracos dos alfabetos matemáticos: estas ficam no bloco de símbolos com letras.
    .{ 0x212C, 'B' }, .{ 0x2130, 'E' }, .{ 0x2131, 'F' }, .{ 0x210B, 'H' }, .{ 0x2110, 'I' },
    .{ 0x2112, 'L' }, .{ 0x2133, 'M' }, .{ 0x211B, 'R' }, .{ 0x212F, 'e' }, .{ 0x210A, 'g' },
    .{ 0x2134, 'o' }, .{ 0x212D, 'C' }, .{ 0x210C, 'H' }, .{ 0x2111, 'I' }, .{ 0x211C, 'R' },
    .{ 0x2128, 'Z' }, .{ 0x2102, 'C' }, .{ 0x210D, 'H' }, .{ 0x2115, 'N' }, .{ 0x2119, 'P' },
    .{ 0x211A, 'Q' }, .{ 0x211D, 'R' }, .{ 0x2124, 'Z' }, .{ 0x210E, 'h' },
    .{ 0x1D6A4, 'i' }, .{ 0x1D6A5, 'j' },
    // Barras que os nomes de canal usam como separador.
    .{ 0x2502, '|' }, .{ 0x2503, '|' }, .{ 0x2551, '|' },
};

/// A letra comum por trás de `cp`, ou null se ele não for uma letra estilizada.
pub fn of(cp: u32) ?u32 {
    return switch (cp) {
        // Alfabetos matemáticos (negrito, itálico, cursivo, gótico...): 52 letras cada.
        0x1D400...0x1D6A3 => blk: {
            const i = (cp - 0x1D400) % 52;
            break :blk if (i < 26) 'A' + i else 'a' + i - 26;
        },
        0x1D7CE...0x1D7FF => '0' + (cp - 0x1D7CE) % 10,
        // Largura cheia.
        0xFF01...0xFF5E => cp - 0xFF01 + '!',
        // Em círculo, entre parênteses e em quadrado.
        0x24B6...0x24CF => 'A' + cp - 0x24B6,
        0x24D0...0x24E9 => 'a' + cp - 0x24D0,
        0x24EA => '0',
        0x2460...0x2468 => '1' + cp - 0x2460,
        0x249C...0x24B5 => 'a' + cp - 0x249C,
        0x1F110...0x1F129 => 'A' + cp - 0x1F110,
        0x1F130...0x1F149 => 'A' + cp - 0x1F130,
        0x1F150...0x1F169 => 'A' + cp - 0x1F150,
        0x1F170...0x1F189 => 'A' + cp - 0x1F170,
        // Números pequenos.
        0x2070 => '0',
        0x2074...0x2079 => '4' + cp - 0x2074,
        0x2080...0x2089 => '0' + cp - 0x2080,
        else => for (singles) |s| {
            if (s[0] == cp) break s[1];
        } else null,
    };
}

/// Não desenha nada de qualquer jeito: não conta como letra sem fonte.
pub fn invisible(cp: u32) bool {
    return cp < 0x20 or cp == 0x7F or cp == 0xAD or cp == 0xFFFD or cp == 0xFEFF or
        (cp >= 0x200B and cp <= 0x200F) or (cp >= 0x2028 and cp <= 0x202E) or (cp >= 0x2060 and cp <= 0x206F) or
        (cp >= 0xFE00 and cp <= 0xFE0F) or (cp >= 0xE0000 and cp <= 0xE01EF);
}

pub const Script = struct { first: u32, last: u32, pt: []const u8, en: []const u8 };

const scripts = [_]Script{
    .{ .first = 0x0370, .last = 0x03FF, .pt = "grego", .en = "Greek" },
    .{ .first = 0x0400, .last = 0x052F, .pt = "cirílico", .en = "Cyrillic" },
    .{ .first = 0x0530, .last = 0x058F, .pt = "armênio", .en = "Armenian" },
    .{ .first = 0x0590, .last = 0x05FF, .pt = "hebraico", .en = "Hebrew" },
    .{ .first = 0x0600, .last = 0x077F, .pt = "árabe", .en = "Arabic" },
    .{ .first = 0x0900, .last = 0x097F, .pt = "devanágari", .en = "Devanagari" },
    .{ .first = 0x0E00, .last = 0x0E7F, .pt = "tailandês", .en = "Thai" },
    .{ .first = 0x0E80, .last = 0x0EFF, .pt = "laosiano", .en = "Lao" },
    .{ .first = 0x0F00, .last = 0x0FFF, .pt = "tibetano", .en = "Tibetan" },
    .{ .first = 0x10A0, .last = 0x10FF, .pt = "georgiano", .en = "Georgian" },
    .{ .first = 0x1200, .last = 0x137F, .pt = "etíope", .en = "Ethiopic" },
    .{ .first = 0x13A0, .last = 0x13FF, .pt = "cherokee", .en = "Cherokee" },
    .{ .first = 0x16A0, .last = 0x16FF, .pt = "rúnico", .en = "Runic" },
    .{ .first = 0x1780, .last = 0x17FF, .pt = "khmer", .en = "Khmer" },
    .{ .first = 0x2200, .last = 0x22FF, .pt = "símbolos matemáticos", .en = "math symbols" },
    .{ .first = 0x2800, .last = 0x28FF, .pt = "braille", .en = "Braille" },
    .{ .first = 0xA980, .last = 0xA9DF, .pt = "javanês", .en = "Javanese" },
};

/// A escrita de uma letra, para dizer qual está sem fonte.
pub fn scriptOf(cp: u32) ?*const Script {
    for (&scripts) |*s| if (cp >= s.first and cp <= s.last) return s;
    return null;
}

fn plain(buf: []u8, text: []const u8) []const u8 {
    var n: usize = 0;
    var it = (std.unicode.Utf8View.init(text) catch unreachable).iterator();
    while (it.nextCodepoint()) |cp| {
        const out = of(cp) orelse cp;
        n += std.unicode.utf8Encode(@intCast(out), buf[n..]) catch unreachable;
    }
    return buf[0..n];
}

test "alfabetos estilizados voltam à letra comum" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("regras", plain(&b, "𝐫𝐞𝐠𝐫𝐚𝐬")); // negrito
    try std.testing.expectEqualStrings("regras", plain(&b, "𝓻𝓮𝓰𝓻𝓪𝓼")); // cursivo
    try std.testing.expectEqualStrings("regras", plain(&b, "𝖗𝖊𝖌𝖗𝖆𝖘")); // gótico
    try std.testing.expectEqualStrings("regras", plain(&b, "ʀᴇɢʀᴀꜱ")); // capitais pequenas
    try std.testing.expectEqualStrings("regras", plain(&b, "ｒｅｇｒａｓ")); // largura cheia
    try std.testing.expectEqualStrings("regras", plain(&b, "ⓡⓔⓖⓡⓐⓢ")); // em círculo
    try std.testing.expectEqualStrings("REGRAS", plain(&b, "🆁🅴🅶🆁🅰🆂")); // em quadrado
    try std.testing.expectEqualStrings("chat-123", plain(&b, "𝗰𝗵𝗮𝘁-𝟏𝟐𝟑")); // com números
    try std.testing.expectEqualStrings("RH", plain(&b, "ℝℍ")); // os do bloco de símbolos
    // Canais de verdade: sem serifa em negrito e itálico em negrito.
    try std.testing.expectEqualStrings("|Memes", plain(&b, "┃𝗠𝗲𝗺𝗲𝘀"));
    try std.testing.expectEqualStrings("|Ajuda", plain(&b, "┃𝑨𝒋𝒖𝒅𝒂"));
    try std.testing.expectEqualStrings("AFK", plain(&b, "𝑨𝑭𝑲"));
}

test "invisíveis não contam e a escrita tem nome" {
    try std.testing.expect(invisible(0x200D)); // junta emojis
    try std.testing.expect(invisible(0xFE0F)); // pede emoji colorido
    try std.testing.expect(!invisible(0xA9C1));
    try std.testing.expectEqualStrings("javanês", scriptOf(0xA9C1).?.pt);
    try std.testing.expect(scriptOf('a') == null);
}

test "o resto continua igual" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("olá, мир 日本語 🚨", plain(&b, "olá, мир 日本語 🚨"));
    try std.testing.expect(of('a') == null);
    try std.testing.expect(of(0x1F600) == null);
}
