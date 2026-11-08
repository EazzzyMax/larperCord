//! Blocos do Unicode para as fontes reserva de qualquer escrita (ui/fonts.zig). Quando nenhuma
//! fonte carregada tem uma letra, o sistema diz qual fonte tem, e ela entra só com o bloco
//! dessa letra: o tailandês traz o bloco do tailandês, não a fonte inteira por cima das outras.
//! Aqui fica o que não depende do ImGui nem do sistema: a tabela de blocos, a lembrança dos
//! blocos já procurados (achando fonte ou não) e as fontes que o Windows tem para cada escrita.
const std = @import("std");

pub const Block = u16;

/// Os blocos do Unicode 17 (Blocks.txt), em ordem. As formas de apresentação alfabéticas param
/// em U+FB1C: as hebraicas, dali em diante, são do grupo do hebraico (ui/fonts.zig).
const table = [_][2]u32{
    .{ 0x0000, 0x007F },     .{ 0x0080, 0x00FF },   .{ 0x0100, 0x017F },   .{ 0x0180, 0x024F },   .{ 0x0250, 0x02AF },
    .{ 0x02B0, 0x02FF },     .{ 0x0300, 0x036F },   .{ 0x0370, 0x03FF },   .{ 0x0400, 0x04FF },   .{ 0x0500, 0x052F },
    .{ 0x0530, 0x058F },     .{ 0x0590, 0x05FF },   .{ 0x0600, 0x06FF },   .{ 0x0700, 0x074F },   .{ 0x0750, 0x077F },
    .{ 0x0780, 0x07BF },     .{ 0x07C0, 0x07FF },   .{ 0x0800, 0x083F },   .{ 0x0840, 0x085F },   .{ 0x0860, 0x086F },
    .{ 0x0870, 0x089F },     .{ 0x08A0, 0x08FF },   .{ 0x0900, 0x097F },   .{ 0x0980, 0x09FF },   .{ 0x0A00, 0x0A7F },
    .{ 0x0A80, 0x0AFF },     .{ 0x0B00, 0x0B7F },   .{ 0x0B80, 0x0BFF },   .{ 0x0C00, 0x0C7F },   .{ 0x0C80, 0x0CFF },
    .{ 0x0D00, 0x0D7F },     .{ 0x0D80, 0x0DFF },   .{ 0x0E00, 0x0E7F },   .{ 0x0E80, 0x0EFF },   .{ 0x0F00, 0x0FFF },
    .{ 0x1000, 0x109F },     .{ 0x10A0, 0x10FF },   .{ 0x1100, 0x11FF },   .{ 0x1200, 0x137F },   .{ 0x1380, 0x139F },
    .{ 0x13A0, 0x13FF },     .{ 0x1400, 0x167F },   .{ 0x1680, 0x169F },   .{ 0x16A0, 0x16FF },   .{ 0x1700, 0x171F },
    .{ 0x1720, 0x173F },     .{ 0x1740, 0x175F },   .{ 0x1760, 0x177F },   .{ 0x1780, 0x17FF },   .{ 0x1800, 0x18AF },
    .{ 0x18B0, 0x18FF },     .{ 0x1900, 0x194F },   .{ 0x1950, 0x197F },   .{ 0x1980, 0x19DF },   .{ 0x19E0, 0x19FF },
    .{ 0x1A00, 0x1A1F },     .{ 0x1A20, 0x1AAF },   .{ 0x1AB0, 0x1AFF },   .{ 0x1B00, 0x1B7F },   .{ 0x1B80, 0x1BBF },
    .{ 0x1BC0, 0x1BFF },     .{ 0x1C00, 0x1C4F },   .{ 0x1C50, 0x1C7F },   .{ 0x1C80, 0x1C8F },   .{ 0x1C90, 0x1CBF },
    .{ 0x1CC0, 0x1CCF },     .{ 0x1CD0, 0x1CFF },   .{ 0x1D00, 0x1D7F },   .{ 0x1D80, 0x1DBF },   .{ 0x1DC0, 0x1DFF },
    .{ 0x1E00, 0x1EFF },     .{ 0x1F00, 0x1FFF },   .{ 0x2000, 0x206F },   .{ 0x2070, 0x209F },   .{ 0x20A0, 0x20CF },
    .{ 0x20D0, 0x20FF },     .{ 0x2100, 0x214F },   .{ 0x2150, 0x218F },   .{ 0x2190, 0x21FF },   .{ 0x2200, 0x22FF },
    .{ 0x2300, 0x23FF },     .{ 0x2400, 0x243F },   .{ 0x2440, 0x245F },   .{ 0x2460, 0x24FF },   .{ 0x2500, 0x257F },
    .{ 0x2580, 0x259F },     .{ 0x25A0, 0x25FF },   .{ 0x2600, 0x26FF },   .{ 0x2700, 0x27BF },   .{ 0x27C0, 0x27EF },
    .{ 0x27F0, 0x27FF },     .{ 0x2800, 0x28FF },   .{ 0x2900, 0x297F },   .{ 0x2980, 0x29FF },   .{ 0x2A00, 0x2AFF },
    .{ 0x2B00, 0x2BFF },     .{ 0x2C00, 0x2C5F },   .{ 0x2C60, 0x2C7F },   .{ 0x2C80, 0x2CFF },   .{ 0x2D00, 0x2D2F },
    .{ 0x2D30, 0x2D7F },     .{ 0x2D80, 0x2DDF },   .{ 0x2DE0, 0x2DFF },   .{ 0x2E00, 0x2E7F },   .{ 0x2E80, 0x2EFF },
    .{ 0x2F00, 0x2FDF },     .{ 0x2FF0, 0x2FFF },   .{ 0x3000, 0x303F },   .{ 0x3040, 0x309F },   .{ 0x30A0, 0x30FF },
    .{ 0x3100, 0x312F },     .{ 0x3130, 0x318F },   .{ 0x3190, 0x319F },   .{ 0x31A0, 0x31BF },   .{ 0x31C0, 0x31EF },
    .{ 0x31F0, 0x31FF },     .{ 0x3200, 0x32FF },   .{ 0x3300, 0x33FF },   .{ 0x3400, 0x4DBF },   .{ 0x4DC0, 0x4DFF },
    .{ 0x4E00, 0x9FFF },     .{ 0xA000, 0xA48F },   .{ 0xA490, 0xA4CF },   .{ 0xA4D0, 0xA4FF },   .{ 0xA500, 0xA63F },
    .{ 0xA640, 0xA69F },     .{ 0xA6A0, 0xA6FF },   .{ 0xA700, 0xA71F },   .{ 0xA720, 0xA7FF },   .{ 0xA800, 0xA82F },
    .{ 0xA830, 0xA83F },     .{ 0xA840, 0xA87F },   .{ 0xA880, 0xA8DF },   .{ 0xA8E0, 0xA8FF },   .{ 0xA900, 0xA92F },
    .{ 0xA930, 0xA95F },     .{ 0xA960, 0xA97F },   .{ 0xA980, 0xA9DF },   .{ 0xA9E0, 0xA9FF },   .{ 0xAA00, 0xAA5F },
    .{ 0xAA60, 0xAA7F },     .{ 0xAA80, 0xAADF },   .{ 0xAAE0, 0xAAFF },   .{ 0xAB00, 0xAB2F },   .{ 0xAB30, 0xAB6F },
    .{ 0xAB70, 0xABBF },     .{ 0xABC0, 0xABFF },   .{ 0xAC00, 0xD7AF },   .{ 0xD7B0, 0xD7FF },   .{ 0xD800, 0xDB7F },
    .{ 0xDB80, 0xDBFF },     .{ 0xDC00, 0xDFFF },   .{ 0xE000, 0xF8FF },   .{ 0xF900, 0xFAFF },   .{ 0xFB00, 0xFB1C },
    .{ 0xFB50, 0xFDFF },     .{ 0xFE00, 0xFE0F },   .{ 0xFE10, 0xFE1F },   .{ 0xFE20, 0xFE2F },   .{ 0xFE30, 0xFE4F },
    .{ 0xFE50, 0xFE6F },     .{ 0xFE70, 0xFEFF },   .{ 0xFF00, 0xFFEF },   .{ 0xFFF0, 0xFFFF },   .{ 0x10000, 0x1007F },
    .{ 0x10080, 0x100FF },   .{ 0x10100, 0x1013F }, .{ 0x10140, 0x1018F }, .{ 0x10190, 0x101CF }, .{ 0x101D0, 0x101FF },
    .{ 0x10280, 0x1029F },   .{ 0x102A0, 0x102DF }, .{ 0x102E0, 0x102FF }, .{ 0x10300, 0x1032F }, .{ 0x10330, 0x1034F },
    .{ 0x10350, 0x1037F },   .{ 0x10380, 0x1039F }, .{ 0x103A0, 0x103DF }, .{ 0x10400, 0x1044F }, .{ 0x10450, 0x1047F },
    .{ 0x10480, 0x104AF },   .{ 0x104B0, 0x104FF }, .{ 0x10500, 0x1052F }, .{ 0x10530, 0x1056F }, .{ 0x10570, 0x105BF },
    .{ 0x105C0, 0x105FF },   .{ 0x10600, 0x1077F }, .{ 0x10780, 0x107BF }, .{ 0x10800, 0x1083F }, .{ 0x10840, 0x1085F },
    .{ 0x10860, 0x1087F },   .{ 0x10880, 0x108AF }, .{ 0x108E0, 0x108FF }, .{ 0x10900, 0x1091F }, .{ 0x10920, 0x1093F },
    .{ 0x10940, 0x1095F },   .{ 0x10980, 0x1099F }, .{ 0x109A0, 0x109FF }, .{ 0x10A00, 0x10A5F }, .{ 0x10A60, 0x10A7F },
    .{ 0x10A80, 0x10A9F },   .{ 0x10AC0, 0x10AFF }, .{ 0x10B00, 0x10B3F }, .{ 0x10B40, 0x10B5F }, .{ 0x10B60, 0x10B7F },
    .{ 0x10B80, 0x10BAF },   .{ 0x10C00, 0x10C4F }, .{ 0x10C80, 0x10CFF }, .{ 0x10D00, 0x10D3F }, .{ 0x10D40, 0x10D8F },
    .{ 0x10E60, 0x10E7F },   .{ 0x10E80, 0x10EBF }, .{ 0x10EC0, 0x10EFF }, .{ 0x10F00, 0x10F2F }, .{ 0x10F30, 0x10F6F },
    .{ 0x10F70, 0x10FAF },   .{ 0x10FB0, 0x10FDF }, .{ 0x10FE0, 0x10FFF }, .{ 0x11000, 0x1107F }, .{ 0x11080, 0x110CF },
    .{ 0x110D0, 0x110FF },   .{ 0x11100, 0x1114F }, .{ 0x11150, 0x1117F }, .{ 0x11180, 0x111DF }, .{ 0x111E0, 0x111FF },
    .{ 0x11200, 0x1124F },   .{ 0x11280, 0x112AF }, .{ 0x112B0, 0x112FF }, .{ 0x11300, 0x1137F }, .{ 0x11380, 0x113FF },
    .{ 0x11400, 0x1147F },   .{ 0x11480, 0x114DF }, .{ 0x11580, 0x115FF }, .{ 0x11600, 0x1165F }, .{ 0x11660, 0x1167F },
    .{ 0x11680, 0x116CF },   .{ 0x116D0, 0x116FF }, .{ 0x11700, 0x1174F }, .{ 0x11800, 0x1184F }, .{ 0x118A0, 0x118FF },
    .{ 0x11900, 0x1195F },   .{ 0x119A0, 0x119FF }, .{ 0x11A00, 0x11A4F }, .{ 0x11A50, 0x11AAF }, .{ 0x11AB0, 0x11ABF },
    .{ 0x11AC0, 0x11AFF },   .{ 0x11B00, 0x11B5F }, .{ 0x11B60, 0x11B7F }, .{ 0x11BC0, 0x11BFF }, .{ 0x11C00, 0x11C6F },
    .{ 0x11C70, 0x11CBF },   .{ 0x11D00, 0x11D5F }, .{ 0x11D60, 0x11DAF }, .{ 0x11DB0, 0x11DEF }, .{ 0x11EE0, 0x11EFF },
    .{ 0x11F00, 0x11F5F },   .{ 0x11FB0, 0x11FBF }, .{ 0x11FC0, 0x11FFF }, .{ 0x12000, 0x123FF }, .{ 0x12400, 0x1247F },
    .{ 0x12480, 0x1254F },   .{ 0x12F90, 0x12FFF }, .{ 0x13000, 0x1342F }, .{ 0x13430, 0x1345F }, .{ 0x13460, 0x143FF },
    .{ 0x14400, 0x1467F },   .{ 0x16100, 0x1613F }, .{ 0x16800, 0x16A3F }, .{ 0x16A40, 0x16A6F }, .{ 0x16A70, 0x16ACF },
    .{ 0x16AD0, 0x16AFF },   .{ 0x16B00, 0x16B8F }, .{ 0x16D40, 0x16D7F }, .{ 0x16E40, 0x16E9F }, .{ 0x16EA0, 0x16EDF },
    .{ 0x16F00, 0x16F9F },   .{ 0x16FE0, 0x16FFF }, .{ 0x17000, 0x187FF }, .{ 0x18800, 0x18AFF }, .{ 0x18B00, 0x18CFF },
    .{ 0x18D00, 0x18D7F },   .{ 0x18D80, 0x18DFF }, .{ 0x1AFF0, 0x1AFFF }, .{ 0x1B000, 0x1B0FF }, .{ 0x1B100, 0x1B12F },
    .{ 0x1B130, 0x1B16F },   .{ 0x1B170, 0x1B2FF }, .{ 0x1BC00, 0x1BC9F }, .{ 0x1BCA0, 0x1BCAF }, .{ 0x1CC00, 0x1CEBF },
    .{ 0x1CEC0, 0x1CEFF },   .{ 0x1CF00, 0x1CFCF }, .{ 0x1D000, 0x1D0FF }, .{ 0x1D100, 0x1D1FF }, .{ 0x1D200, 0x1D24F },
    .{ 0x1D2C0, 0x1D2DF },   .{ 0x1D2E0, 0x1D2FF }, .{ 0x1D300, 0x1D35F }, .{ 0x1D360, 0x1D37F }, .{ 0x1D400, 0x1D7FF },
    .{ 0x1D800, 0x1DAAF },   .{ 0x1DF00, 0x1DFFF }, .{ 0x1E000, 0x1E02F }, .{ 0x1E030, 0x1E08F }, .{ 0x1E100, 0x1E14F },
    .{ 0x1E290, 0x1E2BF },   .{ 0x1E2C0, 0x1E2FF }, .{ 0x1E4D0, 0x1E4FF }, .{ 0x1E5D0, 0x1E5FF }, .{ 0x1E6C0, 0x1E6FF },
    .{ 0x1E7E0, 0x1E7FF },   .{ 0x1E800, 0x1E8DF }, .{ 0x1E900, 0x1E95F }, .{ 0x1EC70, 0x1ECBF }, .{ 0x1ED00, 0x1ED4F },
    .{ 0x1EE00, 0x1EEFF },   .{ 0x1F000, 0x1F02F }, .{ 0x1F030, 0x1F09F }, .{ 0x1F0A0, 0x1F0FF }, .{ 0x1F100, 0x1F1FF },
    .{ 0x1F200, 0x1F2FF },   .{ 0x1F300, 0x1F5FF }, .{ 0x1F600, 0x1F64F }, .{ 0x1F650, 0x1F67F }, .{ 0x1F680, 0x1F6FF },
    .{ 0x1F700, 0x1F77F },   .{ 0x1F780, 0x1F7FF }, .{ 0x1F800, 0x1F8FF }, .{ 0x1F900, 0x1F9FF }, .{ 0x1FA00, 0x1FA6F },
    .{ 0x1FA70, 0x1FAFF },   .{ 0x1FB00, 0x1FBFF }, .{ 0x20000, 0x2A6DF }, .{ 0x2A700, 0x2B73F }, .{ 0x2B740, 0x2B81F },
    .{ 0x2B820, 0x2CEAF },   .{ 0x2CEB0, 0x2EBEF }, .{ 0x2EBF0, 0x2EE5F }, .{ 0x2F800, 0x2FA1F }, .{ 0x30000, 0x3134F },
    .{ 0x31350, 0x323AF },   .{ 0x323B0, 0x3347F }, .{ 0xE0000, 0xE007F }, .{ 0xE0100, 0xE01EF }, .{ 0xF0000, 0xFFFFF },
    .{ 0x100000, 0x10FFFF },
};

pub const count = table.len;

/// O bloco de `cp`, ou null se o Unicode ainda não usa esse trecho.
pub fn of(cp: u32) ?Block {
    var lo: usize = 0;
    var hi: usize = table.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (cp < table[mid][0]) {
            hi = mid;
        } else if (cp > table[mid][1]) {
            lo = mid + 1;
        } else return @intCast(mid);
    }
    return null;
}

pub fn first(b: Block) u32 {
    return table[b][0];
}

pub fn last(b: Block) u32 {
    return table[b][1];
}

/// Quais blocos pediram fonte e quais já foram procurados. Cada bloco é procurado uma vez só:
/// sem fonte no sistema, não adianta perguntar de novo a cada letra (nem a cada quadro). Tudo
/// de tamanho fixo: a memória não cresce com o que aparece na tela.
pub const Misses = struct {
    /// A letra que pediu cada bloco ainda não procurado (0: nenhuma; o U+0000 não pede fonte).
    want: [count]u32 = @splat(0),
    tried: std.StaticBitSet(count) = .empty,
    wanted_n: u16 = 0,

    pub const Wanted = struct { block: Block, cp: u32 };

    /// Uma letra sem fonte no bloco `b`. Falso se o bloco já foi procurado: a letra fica sem
    /// fonte. Outra letra do mesmo bloco antes da busca não muda nada (uma busca por bloco).
    pub fn note(m: *Misses, b: Block, cp: u32) bool {
        std.debug.assert(cp != 0);
        if (m.tried.isSet(b)) return false;
        if (m.want[b] == 0) {
            m.want[b] = cp;
            m.wanted_n += 1;
        }
        return true;
    }

    pub fn anyWanted(m: *const Misses) bool {
        return m.wanted_n > 0;
    }

    /// O próximo bloco a procurar. Ele passa a contar como procurado, ache fonte ou não.
    pub fn next(m: *Misses) ?Wanted {
        if (m.wanted_n == 0) return null;
        for (&m.want, 0..) |*w, i| if (w.* != 0) {
            const cp = w.*;
            w.* = 0;
            m.wanted_n -= 1;
            m.tried.set(i);
            return .{ .block = @intCast(i), .cp = cp };
        };
        unreachable;
    }

    pub fn triedBlock(m: *const Misses, b: Block) bool {
        return m.tried.isSet(b);
    }
};

/// Quantos lugares `exclude` pede para `n` blocos.
pub fn excludeLen(n: usize) usize {
    return 2 * (n + 1) + 1;
}

/// A fonte reserva vale só nos blocos `blocks` (em ordem crescente): o resto vira faixas a
/// excluir, no formato do ImGui (início e fim de cada faixa, e um 0 no fim). Blocos vizinhos
/// ficam numa faixa só. O ImGui aceita até 64 números antes do 0, ou seja, 31 blocos separados.
pub fn exclude(blocks: []const Block, out: []u32) []const u32 {
    std.debug.assert(out.len >= excludeLen(blocks.len));
    var n: usize = 0;
    // Começa no 1: o 0 é o fim da lista.
    var from: u32 = 1;
    for (blocks) |b| {
        if (table[b][0] > from) {
            out[n] = from;
            out[n + 1] = table[b][0] - 1;
            n += 2;
        }
        from = @max(from, table[b][1] + 1);
    }
    if (from <= max_cp) {
        out[n] = from;
        out[n + 1] = max_cp;
        n += 2;
    }
    out[n] = 0;
    return out[0 .. n + 1];
}

const max_cp: u32 = 0x10FFFF;

/// No Windows não há fontconfig: as fontes que vêm com o sistema para cada escrita, na ordem
/// de preferência. Nem toda versão do Windows tem todas, e o arquivo é conferido com o FreeType
/// antes de entrar (ui/fonts.zig). Fora da tabela, vale `windows_default`.
const WindowsRow = struct { first: u32, last: u32, files: []const []const u8 };
const nirmala = [_][]const u8{ "Nirmala.ttc", "Nirmala.ttf" };
const windows_rows = [_]WindowsRow{
    // Grego, cirílico e armênio.
    .{ .first = 0x0370, .last = 0x058F, .files = &.{ "segoeui.ttf", "sylfaen.ttf", "arial.ttf" } },
    .{ .first = 0x0700, .last = 0x074F, .files = &.{ "estre.ttf", "seguihis.ttf" } }, // siríaco
    .{ .first = 0x0780, .last = 0x07BF, .files = &.{"mvboli.ttf"} }, // thaana
    .{ .first = 0x07C0, .last = 0x07FF, .files = &.{"ebrima.ttf"} }, // n'ko
    .{ .first = 0x0800, .last = 0x085F, .files = &.{"seguihis.ttf"} }, // samaritano e mandeu
    // Devanágari, bengali, gurmukhi, guzerate, oriá, tâmil, télugo, canarês, malaiala e cingalês:
    // a Nirmala UI tem todas; as de antes dela, uma escrita cada.
    .{ .first = 0x0900, .last = 0x0DFF, .files = &(nirmala ++ [_][]const u8{ "mangal.ttf", "vrinda.ttf", "raavi.ttf", "shruti.ttf", "kalinga.ttf", "latha.ttf", "gautami.ttf", "tunga.ttf", "kartika.ttf", "iskpota.ttf" }) },
    .{ .first = 0x0E00, .last = 0x0EFF, .files = &.{ "LeelawUI.ttf", "leelawad.ttf", "tahoma.ttf", "LaoUI.ttf" } }, // tailandês e laosiano
    .{ .first = 0x0F00, .last = 0x0FFF, .files = &.{"himalaya.ttf"} }, // tibetano
    .{ .first = 0x1000, .last = 0x109F, .files = &.{"mmrtext.ttf"} }, // birmanês
    .{ .first = 0x10A0, .last = 0x10FF, .files = &.{ "segoeui.ttf", "sylfaen.ttf" } }, // georgiano
    .{ .first = 0x1200, .last = 0x139F, .files = &.{ "ebrima.ttf", "nyala.ttf" } }, // etíope
    .{ .first = 0x13A0, .last = 0x13FF, .files = &.{ "gadugi.ttf", "plantc.ttf" } }, // cherokee
    .{ .first = 0x1400, .last = 0x167F, .files = &.{ "gadugi.ttf", "euphemia.ttf" } }, // sílabas canadenses
    .{ .first = 0x1680, .last = 0x16FF, .files = &.{ "seguihis.ttf", "seguisym.ttf" } }, // ogham e rúnico
    .{ .first = 0x1700, .last = 0x177F, .files = &.{"seguihis.ttf"} }, // tagalo, hanunoo, buhid e tagbanwa
    .{ .first = 0x1780, .last = 0x17FF, .files = &.{ "LeelawUI.ttf", "KhmerUI.ttf", "daunpenh.ttf" } }, // khmer
    .{ .first = 0x1800, .last = 0x18AF, .files = &.{"monbaiti.ttf"} }, // mongol
    .{ .first = 0x18B0, .last = 0x18FF, .files = &.{ "gadugi.ttf", "euphemia.ttf" } }, // sílabas canadenses
    .{ .first = 0x1950, .last = 0x197F, .files = &.{"taile.ttf"} }, // tai le
    .{ .first = 0x1980, .last = 0x19DF, .files = &.{"ntailu.ttf"} }, // novo tai lue
    .{ .first = 0x19E0, .last = 0x1A1F, .files = &.{ "LeelawUI.ttf", "KhmerUI.ttf" } }, // símbolos khmer e buginês
    .{ .first = 0x1C50, .last = 0x1C7F, .files = &nirmala }, // ol chiki
    .{ .first = 0x1C90, .last = 0x1CBF, .files = &.{ "segoeui.ttf", "sylfaen.ttf" } }, // georgiano
    .{ .first = 0x1CD0, .last = 0x1CFF, .files = &nirmala }, // védico
    // Pontuação, símbolos, setas, matemática, desenho de caixas e braille.
    .{ .first = 0x2000, .last = 0x2BFF, .files = &.{ "seguisym.ttf", "segoeui.ttf", "arial.ttf" } },
    .{ .first = 0x2C00, .last = 0x2C5F, .files = &.{"seguihis.ttf"} }, // glagolítico
    .{ .first = 0x2C80, .last = 0x2CFF, .files = &.{ "seguihis.ttf", "segoeui.ttf" } }, // copta
    .{ .first = 0x2D00, .last = 0x2D2F, .files = &.{ "segoeui.ttf", "sylfaen.ttf" } }, // georgiano
    .{ .first = 0x2D30, .last = 0x2D7F, .files = &.{"ebrima.ttf"} }, // tifinagh
    .{ .first = 0x2D80, .last = 0x2DDF, .files = &.{ "ebrima.ttf", "nyala.ttf" } }, // etíope
    .{ .first = 0xA000, .last = 0xA4CF, .files = &.{"msyi.ttf"} }, // yi
    .{ .first = 0xA4D0, .last = 0xA4FF, .files = &.{"segoeui.ttf"} }, // lisu
    .{ .first = 0xA500, .last = 0xA63F, .files = &.{"ebrima.ttf"} }, // vai
    .{ .first = 0xA840, .last = 0xA87F, .files = &.{"phagspa.ttf"} }, // phags-pa
    .{ .first = 0xA8E0, .last = 0xA8FF, .files = &nirmala }, // devanágari
    .{ .first = 0xA980, .last = 0xA9DF, .files = &.{"javatext.ttf"} }, // javanês
    .{ .first = 0xA9E0, .last = 0xA9FF, .files = &.{"mmrtext.ttf"} }, // birmanês
    .{ .first = 0xAA60, .last = 0xAA7F, .files = &.{"mmrtext.ttf"} }, // birmanês
    .{ .first = 0xAB00, .last = 0xAB2F, .files = &.{ "ebrima.ttf", "nyala.ttf" } }, // etíope
    .{ .first = 0xAB70, .last = 0xABBF, .files = &.{ "gadugi.ttf", "plantc.ttf" } }, // cherokee
    .{ .first = 0x10480, .last = 0x104AF, .files = &.{"ebrima.ttf"} }, // osmanya
    .{ .first = 0x104B0, .last = 0x104FF, .files = &.{"gadugi.ttf"} }, // osage
    .{ .first = 0x110D0, .last = 0x1114F, .files = &nirmala }, // sora sompeng e chakma
    .{ .first = 0x1D000, .last = 0x1D24F, .files = &.{"seguisym.ttf"} }, // notação musical
    .{ .first = 0x1E900, .last = 0x1E95F, .files = &.{"ebrima.ttf"} }, // adlam
};
/// O resto: latim e fonéticos na Segoe UI, símbolos na Segoe UI Symbol e as escritas antigas
/// (linear B, gótico, cuneiforme, hieróglifos...) na Segoe UI Historic.
const windows_default: []const []const u8 = &.{ "segoeui.ttf", "seguisym.ttf", "seguihis.ttf", "arial.ttf" };

/// Os arquivos de C:\Windows\Fonts que podem ter `cp`, na ordem de preferência.
pub fn windowsFiles(cp: u32) []const []const u8 {
    for (windows_rows) |r| if (cp >= r.first and cp <= r.last) return r.files;
    return windows_default;
}

test "a tabela está em ordem, sem blocos sobrepostos" {
    var prev: u32 = 0;
    for (table, 0..) |b, i| {
        try std.testing.expect(b[0] <= b[1]);
        if (i > 0) try std.testing.expect(b[0] > prev);
        prev = b[1];
    }
    try std.testing.expectEqual(max_cp, table[table.len - 1][1]);
    var prev_w: u32 = 0;
    for (windows_rows) |r| {
        try std.testing.expect(r.first <= r.last and r.first > prev_w);
        prev_w = r.last;
    }
}

test "cada letra cai no bloco da escrita dela" {
    const thai = of(0x0E01).?;
    try std.testing.expectEqual(@as(u32, 0x0E00), first(thai));
    try std.testing.expectEqual(@as(u32, 0x0E7F), last(thai));
    try std.testing.expectEqual(@as(u32, 0x0900), first(of(0x0905).?)); // devanágari
    try std.testing.expectEqual(@as(u32, 0x10A0), first(of(0x10D0).?)); // georgiano
    try std.testing.expectEqual(@as(u32, 0x0530), first(of(0x0531).?)); // armênio
    try std.testing.expectEqual(@as(Block, 0), of('a').?);
    try std.testing.expectEqual(@as(Block, count - 1), of(0x10FFFF).?);
    // A primeira e a última letra do bloco são dele; a de antes, não.
    try std.testing.expectEqual(thai, of(0x0E00).?);
    try std.testing.expectEqual(thai, of(0x0E7F).?);
    try std.testing.expect(of(0x0DFF).? != thai);
    // Trecho que o Unicode ainda não usa, e as formas hebraicas (são do grupo do hebraico).
    try std.testing.expect(of(0x2FE0) == null);
    try std.testing.expect(of(0x10200) == null);
    try std.testing.expect(of(0xFB2A) == null);
    try std.testing.expect(of(0xFB01) != null);
    try std.testing.expect(of(0x110000) == null);
}

test "cada bloco é procurado uma vez só" {
    var m: Misses = .{};
    try std.testing.expect(!m.anyWanted());
    const thai = of(0x0E01).?;
    const deva = of(0x0905).?;
    try std.testing.expect(m.note(thai, 0x0E01));
    // Outra letra do mesmo bloco antes da busca: continua uma busca só, pela primeira letra.
    try std.testing.expect(m.note(thai, 0x0E02));
    try std.testing.expect(m.note(deva, 0x0905));
    try std.testing.expect(m.anyWanted());
    const a = m.next().?;
    const b = m.next().?;
    try std.testing.expect(m.next() == null);
    try std.testing.expect(!m.anyWanted());
    // Em ordem de bloco, cada um com a letra que pediu.
    try std.testing.expectEqual(deva, a.block);
    try std.testing.expectEqual(@as(u32, 0x0905), a.cp);
    try std.testing.expectEqual(thai, b.block);
    try std.testing.expectEqual(@as(u32, 0x0E01), b.cp);
    // Já procurado (achou fonte ou não): a letra fica sem fonte e nada volta para a fila.
    try std.testing.expect(m.triedBlock(thai));
    try std.testing.expect(!m.note(thai, 0x0E03));
    try std.testing.expect(!m.anyWanted());
    try std.testing.expect(!m.triedBlock(of(0x10D0).?));
}

test "a reserva vale só nos blocos dela" {
    var buf: [excludeLen(3)]u32 = undefined;
    const thai = of(0x0E01).?;
    const lao = of(0x0E81).?;
    const deva = of(0x0905).?;
    // Um bloco: tudo antes e tudo depois.
    try std.testing.expectEqualSlices(u32, &.{ 1, 0x0DFF, 0x0E80, max_cp, 0 }, exclude(&.{thai}, &buf));
    // Tailandês e laosiano são vizinhos: uma faixa só para os dois.
    try std.testing.expectEqualSlices(u32, &.{ 1, 0x0DFF, 0x0F00, max_cp, 0 }, exclude(&.{ thai, lao }, &buf));
    try std.testing.expectEqualSlices(u32, &.{ 1, 0x08FF, 0x0980, 0x0DFF, 0x0F00, max_cp, 0 }, exclude(&.{ deva, thai, lao }, &buf));
    // O último bloco vai até o fim do Unicode: nada a excluir depois dele.
    try std.testing.expectEqualSlices(u32, &.{ 1, 0xFFFFF, 0 }, exclude(&.{count - 1}, &buf));
}

test "fontes do Windows por escrita" {
    const has = struct {
        fn f(files: []const []const u8, name: []const u8) bool {
            for (files) |x| if (std.mem.eql(u8, x, name)) return true;
            return false;
        }
    }.f;
    try std.testing.expect(has(windowsFiles(0x0905), "Nirmala.ttf"));
    try std.testing.expect(has(windowsFiles(0x0B95), "Nirmala.ttc")); // tâmil
    try std.testing.expect(has(windowsFiles(0x0E01), "LeelawUI.ttf"));
    try std.testing.expect(has(windowsFiles(0x10D0), "segoeui.ttf"));
    try std.testing.expect(has(windowsFiles(0x1200), "ebrima.ttf"));
    try std.testing.expect(has(windowsFiles(0x13A0), "gadugi.ttf"));
    try std.testing.expect(has(windowsFiles(0x1820), "monbaiti.ttf"));
    try std.testing.expect(has(windowsFiles(0xA9C1), "javatext.ttf"));
    try std.testing.expect(has(windowsFiles(0x10330), "seguihis.ttf")); // gótico, fora da tabela
}
