//! Texto da direita para a esquerda (árabe, hebraico). O ImGui desenha letra por letra, da
//! esquerda para a direita: o árabe sairia com as letras soltas e de trás para frente. Aqui
//! cada linha que tem uma letra RTL passa pelo GNU FriBidi (third_party/fribidi): o árabe vira
//! as formas de apresentação ligadas (inicial, medial, final, lam-alef) e a linha fica na ordem
//! visual do algoritmo bidirecional do Unicode. O texto continua guardado na ordem lógica: só o
//! que vai para a tela muda, e copiar ou selecionar seguem o original.
//!
//! Texto sem letra RTL (quase tudo) passa direto: uma varredura dos bytes, sem alocar nada.
//! Os buffers são fixos e só da thread da interface; nem as listas do FriBidi chamam o malloc
//! (ver `larper_fribidi_malloc`).
const std = @import("std");

// --- FriBidi (lib/fribidi-*.h) ----------------------------------------------------------

const Char = u32;
const Index = c_int;
const CharType = u32;
const ParType = u32;
const Level = i8;
const ArabicProp = u8;
const BracketType = u32;
const Flags = u32;

extern fn fribidi_get_bidi_type(ch: Char) CharType;
extern fn fribidi_get_bidi_types(str: [*]const Char, len: Index, btypes: [*]CharType) void;
extern fn fribidi_get_bracket_types(str: [*]const Char, len: Index, types: [*]const CharType, btypes: [*]BracketType) void;
extern fn fribidi_get_par_embedding_levels_ex(bidi_types: [*]const CharType, bracket_types: [*]const BracketType, len: Index, pbase_dir: *ParType, embedding_levels: [*]Level) Level;
extern fn fribidi_get_joining_types(str: [*]const Char, len: Index, jtypes: [*]ArabicProp) void;
extern fn fribidi_join_arabic(bidi_types: [*]const CharType, len: Index, embedding_levels: [*]const Level, ar_props: [*]ArabicProp) void;
extern fn fribidi_shape(flags: Flags, embedding_levels: [*]const Level, len: Index, ar_props: [*]ArabicProp, str: [*]Char) void;
extern fn fribidi_reorder_line(flags: Flags, bidi_types: [*]const CharType, len: Index, off: Index, base_dir: ParType, embedding_levels: [*]Level, visual_str: ?[*]Char, map: ?[*]Index) Level;

// fribidi-bidi-types.h e fribidi-flags.h
const mask_rtl: u32 = 0x1;
const mask_arabic: u32 = 0x2;
const mask_strong: u32 = 0x10;
const mask_letter: u32 = 0x100;
const mask_number: u32 = 0x200;
const mask_nsm: u32 = 0x80000;
const strong_rtl = mask_strong | mask_letter | mask_rtl;
const par_on: ParType = 0x40; // FRIBIDI_PAR_ON: a direção vem da primeira letra forte
const par_rtl: ParType = strong_rtl; // FRIBIDI_PAR_RTL
const flag_shape_mirroring: Flags = 0x1;
const flag_reorder_nsm: Flags = 0x2;
const flag_shape_arab_pres: Flags = 0x100;
const flag_shape_arab_liga: Flags = 0x200;
/// FRIBIDI_FLAGS_DEFAULT sem REMOVE_SPECIALS (aqui os invisíveis saem em `emit`) + FRIBIDI_FLAGS_ARABIC.
const flags = flag_shape_mirroring | flag_reorder_nsm | flag_shape_arab_pres | flag_shape_arab_liga;
/// O lugar que sobra quando lam + alef viram uma letra só (FRIBIDI_CHAR_FILL).
const fill: u32 = 0xFEFF;

// --- Arena das listas do FriBidi --------------------------------------------------------

/// O FriBidi monta listas ligadas dos trechos de cada linha, um malloc por nó. Saem daqui,
/// zerado no começo de cada linha; uma linha enorme que passe do tamanho cai no malloc.
/// Fica na seção de zeros do executável: nenhuma página é usada até aparecer texto RTL.
var arena: [96 * 1024]u8 align(16) = undefined;
var arena_used: usize = 0;
/// Quantas vezes a arena não bastou (os testes conferem que uma linha comum cabe).
var arena_misses: u32 = 0;

export fn larper_fribidi_malloc(size: usize) ?*anyopaque {
    const at = std.mem.alignForward(usize, arena_used, 16);
    if (at + size <= arena.len) {
        arena_used = at + size;
        return &arena[at];
    }
    arena_misses += 1;
    return std.c.malloc(size);
}

export fn larper_fribidi_free(ptr: ?*anyopaque) void {
    const p = @intFromPtr(ptr orelse return);
    const lo = @intFromPtr(&arena);
    if (p >= lo and p < lo + arena.len) return;
    std.c.free(ptr);
}

// --- Quem é RTL -------------------------------------------------------------------------

/// Letra de uma escrita da direita para a esquerda, ou marca que pede essa direção.
pub fn isRtl(cp: u32) bool {
    return switch (cp) {
        0x0590...0x08FF => true, // hebraico, árabe, siríaco, thaana, n'ko, samaritano, mandaico, árabe estendido
        0xFB1D...0xFDFF => true, // formas de apresentação do hebraico e do árabe (A)
        0xFE70...0xFEFE => true, // formas de apresentação do árabe (B)
        0x10800...0x10FFF => true, // escritas históricas RTL
        0x1E800...0x1EFFF => true, // mende kikakui, adlam, símbolos matemáticos árabes
        0x200F, 0x202B, 0x202E, 0x2067 => true, // RLM, RLE, RLO, RLI
        else => false,
    };
}

/// Tem alguma letra RTL? Bytes abaixo de 0xD6 nunca começam uma: em texto latino o laço só
/// compara, 16 bytes por vez.
pub fn hasRtl(s: []const u8) bool {
    var i: usize = 0;
    const V = @Vector(16, u8);
    while (i + 16 <= s.len) : (i += 16) {
        const chunk: V = s[i..][0..16].*;
        if (@reduce(.Or, chunk >= @as(V, @splat(0xD6)))) break;
    }
    while (i < s.len) {
        if (s[i] < 0xD6) {
            i += 1;
            continue;
        }
        if (isRtl(decode(s, &i))) return true;
    }
    return false;
}

/// Um caractere de `s[i.*..]`, andando `i`. Byte inválido vira U+FFFD (como no ImGui).
fn decode(s: []const u8, i: *usize) u32 {
    const b = s[i.*];
    if (b < 0x80) {
        i.* += 1;
        return b;
    }
    const n = std.unicode.utf8ByteSequenceLength(b) catch {
        i.* += 1;
        return 0xFFFD;
    };
    if (i.* + n > s.len) {
        i.* += 1;
        return 0xFFFD;
    }
    const cp = std.unicode.utf8Decode(s[i.* .. i.* + n]) catch {
        i.* += 1;
        return 0xFFFD;
    };
    i.* += n;
    return cp;
}

/// A primeira letra forte de `s` é RTL (a direção do parágrafo, regras P2 e P3).
pub fn baseRtl(s: []const u8) bool {
    if (!hasRtl(s)) return false;
    var i: usize = 0;
    while (i < s.len) {
        const t = fribidi_get_bidi_type(decode(s, &i));
        if (t & mask_strong != 0 and t & mask_letter != 0) return t & mask_rtl != 0;
    }
    return false;
}

// --- Uma linha na ordem de desenho ------------------------------------------------------

/// Letras por linha convertida (uma linha maior fica como veio).
const max_line = 2048;
var cps: [max_line]Char = undefined;
var types: [max_line]CharType = undefined;
var brackets: [max_line]BracketType = undefined;
var levels: [max_line]Level = undefined;
var props: [max_line]ArabicProp = undefined;
var out: [16 * 1024]u8 = undefined;

/// As últimas palavras convertidas: a mesma palavra é medida e desenhada várias vezes por
/// quadro (ui/rich.zig), e achar aqui custa um hash em vez do FriBidi de novo.
const Cached = struct {
    hash: u64 = 0,
    in_len: u8 = 0,
    out_len: u8 = 0,
    in: [cache_in]u8 = undefined,
    out: [cache_out]u8 = undefined,
};
const cache_in = 48;
const cache_out = 64;
var cache: [128]Cached = @splat(.{});

/// `s` como deve ir para a tela: cada linha com letra RTL moldada e na ordem visual, as
/// outras iguais. Null quando não há nada a mudar (desenhe `s` mesmo) ou não coube. O
/// resultado vale até a próxima chamada.
pub fn visual(s: []const u8) ?[]const u8 {
    if (!hasRtl(s)) return null;
    if (s.len > cache_in) return convert(s);
    const h = std.hash.Wyhash.hash(0, s);
    const e = &cache[@intCast(h % cache.len)];
    if (e.in_len == s.len and e.hash == h and std.mem.eql(u8, e.in[0..s.len], s)) return e.out[0..e.out_len];
    const v = convert(s) orelse return null;
    if (v.len <= cache_out) {
        e.* = .{ .hash = h, .in_len = @intCast(s.len), .out_len = @intCast(v.len) };
        @memcpy(e.in[0..s.len], s);
        @memcpy(e.out[0..v.len], v);
    }
    return v;
}

fn convert(s: []const u8) ?[]const u8 {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, '\n');
    var first = true;
    while (it.next()) |ln| {
        if (!first) {
            if (n == out.len) return null;
            out[n] = '\n';
            n += 1;
        }
        first = false;
        n = line(ln, n) orelse return null;
    }
    return out[0..n];
}

/// Escreve a linha `ln` em `out[at..]`; devolve onde parou, ou null se `out` encheu.
fn line(ln: []const u8, at: usize) ?usize {
    const len = load(ln) orelse return copy(ln, at);
    if (len == 0) return at;
    const l: Index = @intCast(len);
    fribidi_get_bidi_types(&cps, l, &types);
    var base: ParType = par_on;
    if (allRtl(types[0..len])) {
        // Palavra só de letras RTL (o caso comum, palavra por palavra numa mensagem): todas no
        // nível 1, sem precisar montar as listas do algoritmo.
        @memset(levels[0..len], 1);
        base = par_rtl;
    } else {
        fribidi_get_bracket_types(&cps, l, &types, &brackets);
        arena_used = 0;
        if (fribidi_get_par_embedding_levels_ex(&types, &brackets, l, &base, &levels) == 0) return copy(ln, at);
    }
    fribidi_get_joining_types(&cps, l, &props);
    fribidi_join_arabic(&types, l, &levels, &props);
    fribidi_shape(flags, &levels, l, &props, &cps);
    if (fribidi_reorder_line(flags, &types, l, 0, base, &levels, &cps, null) == 0) return copy(ln, at);
    return emit(cps[0..len], at);
}

/// Só letras fortes RTL e marcas que vão em cima delas, começando por uma letra.
fn allRtl(list: []const CharType) bool {
    if (list.len == 0 or list[0] & strong_rtl != strong_rtl) return false;
    for (list) |t| if (t & strong_rtl != strong_rtl and t & mask_nsm == 0) return false;
    return true;
}

/// Decodifica `ln` em `cps`. Null se não couber (a linha vai como veio).
fn load(ln: []const u8) ?usize {
    var i: usize = 0;
    var len: usize = 0;
    while (i < ln.len) : (len += 1) {
        if (len == max_line) return null;
        cps[len] = decode(ln, &i);
    }
    return len;
}

fn copy(ln: []const u8, at: usize) ?usize {
    if (at + ln.len > out.len) return null;
    @memcpy(out[at..][0..ln.len], ln);
    return at + ln.len;
}

/// Invisíveis que não vão para a tela: o ImGui não os conhece e desenharia o "?".
fn invisible(cp: u32) bool {
    return cp == fill or (cp >= 0x200B and cp <= 0x200F) or (cp >= 0x202A and cp <= 0x202E) or (cp >= 0x2060 and cp <= 0x206F);
}

fn emit(list: []const Char, at: usize) ?usize {
    var n = at;
    for (list) |cp| {
        if (invisible(cp)) continue;
        if (n + 4 > out.len) return null;
        const c21 = std.math.cast(u21, cp) orelse 0xFFFD;
        n += std.unicode.utf8Encode(c21, out[n..]) catch std.unicode.utf8Encode(0xFFFD, out[n..]) catch unreachable;
    }
    return n;
}

// --- Palavras de uma mensagem -----------------------------------------------------------

/// O que uma palavra é para a ordem da linha (ui/rich.zig desenha palavra por palavra: cada
/// uma se molda sozinha em `visual`, e a ordem entre elas sai daqui).
pub const Class = enum(u8) {
    /// Pontuação, emoji, menção: segue as vizinhas.
    neutral,
    ltr,
    /// Hebraico (e as outras RTL que não são árabe).
    rtl,
    arabic,
    number,
    arabic_number,

    /// Um caractere que o FriBidi classifica igual à palavra toda.
    fn stand(c: Class) Char {
        return switch (c) {
            .neutral => 0xFFFC,
            .ltr => 'a',
            .rtl => 0x05D0,
            .arabic => 0x0627,
            .number => '1',
            .arabic_number => 0x0661,
        };
    }
};

/// A classe da palavra: a da primeira letra forte; sem letra, número ou neutra.
pub fn classOf(s: []const u8) Class {
    var i: usize = 0;
    var num: Class = .neutral;
    while (i < s.len) {
        const cp = decode(s, &i);
        if (cp < 0x80) {
            if (std.ascii.isAlphabetic(@intCast(cp))) return .ltr;
            if (std.ascii.isDigit(@intCast(cp)) and num == .neutral) num = .number;
            continue;
        }
        const t = fribidi_get_bidi_type(cp);
        if (t & mask_strong != 0 and t & mask_letter != 0) {
            if (t & mask_rtl == 0) return .ltr;
            return if (t & mask_arabic != 0) .arabic else .rtl;
        }
        if (t & mask_number != 0 and num == .neutral) num = if (t & mask_arabic != 0) .arabic_number else .number;
    }
    return num;
}

/// Algum dos pedaços é RTL? (Só aí a linha precisa de outra ordem.)
pub fn anyRtl(cls: []const Class) bool {
    for (cls) |c| if (c == .rtl or c == .arabic) return true;
    return false;
}

var owner: [max_line]u16 = undefined;
var map: [max_line]Index = undefined;

/// Ordem visual das palavras de um parágrafo: `cls[i]` é a classe da palavra `i`, `gap[i]` diz
/// se há espaço entre ela e a anterior e `starts[i]`, se ela abre uma linha (a quebra já foi
/// feita com as larguras moldadas). Escreve em `order`, linha por linha, os índices da
/// esquerda para a direita, e devolve a direção do parágrafo (true: da direita para a
/// esquerda). Null se não deu: o parágrafo fica na ordem lógica.
pub fn orderWords(cls: []const Class, gap: []const bool, starts: []const bool, order: []u16) ?bool {
    const n = cls.len;
    if (n == 0 or n > order.len or n > std.math.maxInt(u16)) return null;
    // Um caractere por palavra e um espaço onde havia espaço (na quebra de linha, nenhum).
    var len: usize = 0;
    var line_off: [max_line]u16 = undefined;
    var lines: usize = 0;
    for (cls, 0..) |c, i| {
        if (len + 2 > max_line) return null;
        if (i == 0 or starts[i]) {
            line_off[lines] = @intCast(len);
            lines += 1;
        } else if (gap[i]) {
            cps[len] = ' ';
            owner[len] = std.math.maxInt(u16);
            len += 1;
        }
        cps[len] = c.stand();
        owner[len] = @intCast(i);
        len += 1;
    }
    const l: Index = @intCast(len);
    fribidi_get_bidi_types(&cps, l, &types);
    @memset(brackets[0..len], 0);
    var base: ParType = par_on;
    arena_used = 0;
    if (fribidi_get_par_embedding_levels_ex(&types, &brackets, l, &base, &levels) == 0) return null;
    for (map[0..len], 0..) |*m, i| m.* = @intCast(i);
    var k: usize = 0;
    for (0..lines) |li| {
        const from = line_off[li];
        const to = if (li + 1 < lines) line_off[li + 1] else len;
        if (fribidi_reorder_line(flags, &types, @intCast(to - from), from, base, &levels, null, &map) == 0) return null;
        for (map[from..to]) |m| {
            const w = owner[@intCast(m)];
            if (w == std.math.maxInt(u16)) continue;
            order[k] = w;
            k += 1;
        }
    }
    if (k != n) return null;
    return base & mask_rtl != 0;
}

// --- Testes -----------------------------------------------------------------------------

fn expectCodepoints(want: []const u32, got: []const u8) !void {
    var buf: [256]u32 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < got.len) : (n += 1) buf[n] = decode(got, &i);
    try std.testing.expectEqualSlices(u32, want, buf[0..n]);
}

test "texto sem RTL passa direto" {
    try std.testing.expect(!hasRtl(""));
    try std.testing.expect(!hasRtl("bom dia rapaziada, tudo certo por aí? 0123456789 kkkkkkkkkkkkkkkkk"));
    try std.testing.expect(!hasRtl("Polski: zażółć gęślą jaźń. Русский: привет. 日本語: こんにちは 😂"));
    try std.testing.expect(!hasRtl("Հայերեն")); // armênio: 0x0580 começa com o mesmo byte do hebraico
    try std.testing.expect(!hasRtl("\xEF\xBB\xBFbom")); // BOM
    try std.testing.expect(visual("nada para mudar aqui, nem em 32 bytes ou mais de texto") == null);
    try std.testing.expect(hasRtl("um pouco de texto latino antes, e só no fim: שלום"));
    try std.testing.expect(hasRtl("ﻻ"));
    try std.testing.expect(!hasRtl("\xff\xfe quebrado \xd7"));
}

test "lam + alef viram uma letra só" {
    try expectCodepoints(&.{0xFEFB}, visual("لا").?);
}

test "hebraico de trás para frente" {
    try std.testing.expectEqualStrings("םולש", visual("שלום").?);
}

test "parágrafo da esquerda para a direita com hebraico e número" {
    // O número logo depois do hebraico fica com ele (regras W e N do UAX #9).
    try std.testing.expectEqualStrings("abc 123 םולש", visual("abc שלום 123").?);
    try std.testing.expectEqualStrings("abc םולש def", visual("abc שלום def").?);
}

test "frase árabe com as letras ligadas, na ordem de desenho" {
    try expectCodepoints(&.{
        0xFEEA, 0xFEE0, 0xFEDF, 0xFE8D, ' ', // الله
        0xFE94, 0xFEE4, 0xFEA3, 0xFEAD, 0xFEED, ' ', // ورحمة
        0xFEE2, 0xFEDC, 0xFEF4, 0xFEE0, 0xFECB, ' ', // عليكم
        0xFEE1, 0xFEFC, 0xFEB4, 0xFEDF, 0xFE8D, // السلام (com lam-alef)
    }, visual("السلام عليكم ورحمة الله").?);
    try std.testing.expectEqual(@as(u32, 0), arena_misses);
}

test "cada linha por si, e o espelho dos parênteses" {
    try std.testing.expectEqualStrings("ok\nםולש\nfim", visual("ok\nשלום\nfim").?);
    // Dentro do RTL o parêntese é espelhado: continua abrindo do lado certo.
    try std.testing.expectEqualStrings("(םולש)", visual("(שלום)").?);
}

test "atalho da palavra toda RTL dá o mesmo que o algoritmo inteiro" {
    // Com um espaço no fim a linha não é mais só RTL e passa pelo caminho completo.
    for ([_][]const u8{ "مَرْحَبًا", "שָׁלוֹם", "السلام", "لا" }) |w| {
        var a: [64]u8 = undefined;
        const fast = visual(w).?;
        @memcpy(a[0..fast.len], fast);
        var with_space: [64]u8 = undefined;
        @memcpy(with_space[0..w.len], w);
        with_space[w.len] = ' ';
        const full = convert(with_space[0 .. w.len + 1]).?;
        try std.testing.expectEqualStrings(full[1..], a[0..fast.len]);
    }
}

test "invisíveis de direção não vão para a tela" {
    try std.testing.expectEqualStrings("םולש", visual("\u{200F}שלום\u{200E}").?);
}

test "linha longa cabe na arena" {
    // Perto do limite de letras por linha, com trechos trocando de direção o tempo todo.
    const w = "السلام عليكم abc 12 ";
    var buf: [90 * w.len]u8 = undefined;
    for (0..90) |i| @memcpy(buf[i * w.len ..][0..w.len], w);
    const got = visual(&buf).?;
    try std.testing.expect(std.mem.indexOf(u8, got, "\u{FEFC}") != null);
    try std.testing.expectEqual(@as(u32, 0), arena_misses);
}

test "classe das palavras" {
    try std.testing.expectEqual(Class.ltr, classOf("hello"));
    try std.testing.expectEqual(Class.rtl, classOf("שלום"));
    try std.testing.expectEqual(Class.arabic, classOf("مرحبا!"));
    try std.testing.expectEqual(Class.number, classOf("123"));
    try std.testing.expectEqual(Class.arabic_number, classOf("١٢٣"));
    try std.testing.expectEqual(Class.neutral, classOf("!?"));
    try std.testing.expectEqual(Class.ltr, classOf("abc-שלום"));
    try std.testing.expect(baseRtl("(שלום) abc"));
    try std.testing.expect(!baseRtl("abc שלום"));
}

test "ordem das palavras numa linha" {
    var order: [8]u16 = undefined;
    // "السلام عليكم ورحمة الله": tudo árabe, a linha inteira ao contrário.
    try std.testing.expectEqual(@as(?bool, true), orderWords(&.{ .arabic, .arabic, .arabic, .arabic }, &.{ false, true, true, true }, &.{ true, false, false, false }, &order));
    try std.testing.expectEqualSlices(u16, &.{ 3, 2, 1, 0 }, order[0..4]);
    // "abc שלום עולם def": só o trecho hebraico vira.
    try std.testing.expectEqual(@as(?bool, false), orderWords(&.{ .ltr, .rtl, .rtl, .ltr }, &.{ false, true, true, true }, &.{ true, false, false, false }, &order));
    try std.testing.expectEqualSlices(u16, &.{ 0, 2, 1, 3 }, order[0..4]);
    // "عمري 25 سنة": o número fica no meio, na ordem dele.
    try std.testing.expectEqual(@as(?bool, true), orderWords(&.{ .arabic, .number, .arabic }, &.{ false, true, true }, &.{ true, false, false }, &order));
    try std.testing.expectEqualSlices(u16, &.{ 2, 1, 0 }, order[0..3]);
    // Parágrafo RTL quebrado em duas linhas: a direção é a do parágrafo, não a de cada linha.
    try std.testing.expectEqual(@as(?bool, true), orderWords(&.{ .rtl, .rtl, .ltr, .ltr, .rtl }, &.{ false, true, true, true, true }, &.{ true, false, true, false, false }, &order));
    try std.testing.expectEqualSlices(u16, &.{ 1, 0, 4, 2, 3 }, order[0..5]);
    // "ouvindo agora: فيروز - كيفك إنت 🎶": o traço entre dois trechos árabes vai com eles, e o
    // emoji do fim fica no fim do parágrafo da esquerda para a direita.
    try std.testing.expectEqual(@as(?bool, false), orderWords(&.{ .ltr, .ltr, .arabic, .neutral, .arabic, .arabic, .neutral }, &.{ false, true, true, true, true, true, true }, &.{ true, false, false, false, false, false, false }, &order));
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 5, 4, 3, 2, 6 }, order[0..7]);
}
