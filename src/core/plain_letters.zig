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

test "o resto continua igual" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("olá, мир 日本語 🚨", plain(&b, "olá, мир 日本語 🚨"));
    try std.testing.expect(of('a') == null);
    try std.testing.expect(of(0x1F600) == null);
}
