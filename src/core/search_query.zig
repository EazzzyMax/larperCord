//! Busca: interpreta a consulta, compara textos (busca local, Ctrl+F) e monta os parâmetros
//! da busca do Discord.
//!
//!   ziglang from:ana in:geral has:link before:2026-01-31 "frase com espaço"
//!
//! Sem diferença de maiúsculas nem de acentos ("nao" acha "não").
const std = @import("std");

pub const max_terms = 8;

/// A hora agora e os segundos a somar ao UTC para ter a hora local (quem usa atualiza):
/// "hoje" e as datas da consulta são dias locais.
pub var now_s: i64 = 0;
pub var tz_offset_s: i64 = 0;

pub const Filter = enum { none, from, mentions, in, has, before, after, during, pinned };

/// Em inglês, como no Discord, e em português.
pub fn filterOf(key: []const u8) Filter {
    const Name = struct { []const u8, Filter };
    const names = [_]Name{
        .{ "from", .from },         .{ "de", .from },
        .{ "mentions", .mentions }, .{ "menciona", .mentions },
        .{ "in", .in },             .{ "em", .in },
        .{ "has", .has },           .{ "tem", .has },
        .{ "before", .before },     .{ "antes", .before },
        .{ "after", .after },       .{ "depois", .after },
        .{ "during", .during },     .{ "durante", .during },
        .{ "pinned", .pinned },     .{ "fixada", .pinned },
    };
    for (names) |n| if (eqlFold(key, n[0])) return n[1];
    return .none;
}

/// Uma palavra (ou "frase entre aspas") da consulta, com o prefixo antes dos dois-pontos.
pub const Token = struct { key: []const u8, val: []const u8, start: usize, end: usize };

pub fn nextToken(src: []const u8, pos: *usize) ?Token {
    var i = pos.*;
    while (i < src.len and (src[i] == ' ' or src[i] == '\t')) i += 1;
    if (i >= src.len) {
        pos.* = i;
        return null;
    }
    var key: []const u8 = "";
    const start = i;
    while (i < src.len and src[i] != ' ' and src[i] != ':' and src[i] != '"') i += 1;
    if (i < src.len and src[i] == ':' and i > start) {
        key = src[start..i];
        i += 1;
    } else i = start;
    var val: []const u8 = undefined;
    if (i < src.len and src[i] == '"') {
        const v0 = i + 1;
        i = v0;
        while (i < src.len and src[i] != '"') i += 1;
        val = src[v0..i];
        if (i < src.len) i += 1;
    } else {
        const v0 = i;
        while (i < src.len and src[i] != ' ' and src[i] != '\t') i += 1;
        val = src[v0..i];
    }
    pos.* = i;
    return .{ .key = key, .val = val, .start = start, .end = i };
}

/// O que está sendo digitado no fim da consulta. Terminou em espaço: começa no fim, vazio.
pub fn lastToken(src: []const u8) Token {
    var i: usize = 0;
    var last: ?Token = null;
    while (nextToken(src, &i)) |t| last = t;
    if (last) |t| if (t.end == src.len) return t;
    return .{ .key = "", .val = "", .start = src.len, .end = src.len };
}

pub const Query = struct {
    terms_buf: [max_terms][64]u8 = undefined,
    terms_len: [max_terms]u8 = @splat(0),
    n_terms: usize = 0,
    from_buf: [64]u8 = undefined,
    from_len: u8 = 0,
    mentions_buf: [64]u8 = undefined,
    mentions_len: u8 = 0,
    in_buf: [64]u8 = undefined,
    in_len: u8 = 0,
    has_link: bool = false,
    has_image: bool = false,
    has_file: bool = false,
    has_video: bool = false,
    has_sound: bool = false,
    has_embed: bool = false,
    has_sticker: bool = false,
    pinned: ?bool = null,
    /// As datas viram uma faixa de IDs: o ID do Discord carrega a hora em que nasceu.
    min_id: u64 = 0,
    max_id: u64 = 0,
    /// O texto como foi digitado, sem os filtros (é o que vai para o Discord).
    content_buf: [256]u8 = undefined,
    content_len: u16 = 0,
    /// Um filtro com valor que não dá para entender ("before:ontemm").
    invalid_buf: [64]u8 = undefined,
    invalid_len: u8 = 0,

    pub fn term(q: *const Query, i: usize) []const u8 {
        return q.terms_buf[i][0..q.terms_len[i]];
    }
    pub fn from(q: *const Query) []const u8 {
        return q.from_buf[0..q.from_len];
    }
    pub fn mentions(q: *const Query) []const u8 {
        return q.mentions_buf[0..q.mentions_len];
    }
    pub fn in(q: *const Query) []const u8 {
        return q.in_buf[0..q.in_len];
    }
    pub fn content(q: *const Query) []const u8 {
        return q.content_buf[0..q.content_len];
    }
    pub fn invalid(q: *const Query) []const u8 {
        return q.invalid_buf[0..q.invalid_len];
    }

    /// Nada para procurar (nem texto nem filtro).
    pub fn empty(q: *const Query) bool {
        return q.n_terms == 0 and q.from_len == 0 and q.in_len == 0 and !q.has_link and !q.has_image and !q.has_file and
            q.min_id == 0 and q.max_id == 0 and !q.serverOnly();
    }

    /// Filtros que a busca local não tem como aplicar: só o Discord sabe.
    pub fn serverOnly(q: *const Query) bool {
        return q.mentions_len > 0 or q.pinned != null or q.has_video or q.has_sound or q.has_embed or q.has_sticker;
    }

    /// O ID está dentro das datas pedidas.
    pub fn idOk(q: *const Query, id: u64) bool {
        return (q.min_id == 0 or id > q.min_id) and (q.max_id == 0 or id < q.max_id);
    }

    fn setInvalid(q: *Query, t: Token, src: []const u8) void {
        if (q.invalid_len > 0) return;
        const s = src[t.start..t.end];
        const n = @min(s.len, q.invalid_buf.len);
        @memcpy(q.invalid_buf[0..n], s[0..n]);
        q.invalid_len = @intCast(n);
    }

    fn setHas(q: *Query, val: []const u8) bool {
        if (eqlFold(val, "link") or eqlFold(val, "url")) {
            q.has_link = true;
        } else if (eqlFold(val, "imagem") or eqlFold(val, "image") or eqlFold(val, "img") or eqlFold(val, "foto")) {
            q.has_image = true;
        } else if (eqlFold(val, "arquivo") or eqlFold(val, "file") or eqlFold(val, "anexo") or eqlFold(val, "attachment")) {
            q.has_file = true;
        } else if (eqlFold(val, "video") or eqlFold(val, "vídeo")) {
            q.has_video = true;
        } else if (eqlFold(val, "som") or eqlFold(val, "sound") or eqlFold(val, "audio") or eqlFold(val, "áudio")) {
            q.has_sound = true;
        } else if (eqlFold(val, "embed") or eqlFold(val, "previa") or eqlFold(val, "prévia")) {
            q.has_embed = true;
        } else if (eqlFold(val, "figurinha") or eqlFold(val, "sticker")) {
            q.has_sticker = true;
        } else return false;
        return true;
    }

    fn appendContent(q: *Query, s: []const u8) void {
        const sep: usize = if (q.content_len > 0) 1 else 0;
        if (q.content_len + sep + s.len > q.content_buf.len) return;
        if (sep == 1) q.content_buf[q.content_len] = ' ';
        @memcpy(q.content_buf[q.content_len + sep ..][0..s.len], s);
        q.content_len += @intCast(sep + s.len);
    }

    pub fn parse(src: []const u8) Query {
        return parseAt(src, now_s);
    }

    pub fn parseAt(src: []const u8, now: i64) Query {
        var q: Query = .{};
        var i: usize = 0;
        while (nextToken(src, &i)) |t| {
            const val = t.val;
            const f = filterOf(t.key);
            // Filtro ainda sem valor (está sendo digitado): não filtra nada.
            if (f != .none and val.len == 0) continue;
            switch (f) {
                .from => q.from_len = @intCast(foldInto(&q.from_buf, std.mem.trimStart(u8, val, "@")).len),
                .mentions => q.mentions_len = @intCast(foldInto(&q.mentions_buf, std.mem.trimStart(u8, val, "@")).len),
                // "in:#geral" também vale.
                .in => q.in_len = @intCast(foldInto(&q.in_buf, std.mem.trimStart(u8, val, "#@")).len),
                .has => if (!q.setHas(val)) q.setInvalid(t, src),
                .pinned => {
                    if (eqlFold(val, "true") or eqlFold(val, "sim") or eqlFold(val, "yes")) {
                        q.pinned = true;
                    } else if (eqlFold(val, "false") or eqlFold(val, "nao") or eqlFold(val, "não") or eqlFold(val, "no")) {
                        q.pinned = false;
                    } else q.setInvalid(t, src);
                },
                .before, .after, .during => {
                    const day = parseDay(val, now) orelse {
                        q.setInvalid(t, src);
                        continue;
                    };
                    if (f == .before or f == .during) {
                        const id = idOfDay(if (f == .during) day + 1 else day);
                        q.max_id = if (q.max_id == 0) id else @min(q.max_id, id);
                    }
                    if (f == .after or f == .during) {
                        const id = idOfDay(if (f == .after) day + 1 else day);
                        q.min_id = @max(q.min_id, id);
                    }
                },
                .none => {
                    // Prefixo desconhecido ("http:" de um link colado): é texto.
                    const whole = if (t.key.len > 0) src[t.start..t.end] else val;
                    if (whole.len == 0) continue;
                    q.appendContent(src[t.start..t.end]);
                    if (q.n_terms == max_terms) continue;
                    const folded = foldInto(&q.terms_buf[q.n_terms], std.mem.trim(u8, whole, "\""));
                    if (folded.len == 0) continue;
                    q.terms_len[q.n_terms] = @intCast(folded.len);
                    q.n_terms += 1;
                },
            }
        }
        return q;
    }
};

// --- Datas ------------------------------------------------------------------------------

fn daysFromCivil(y0: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y0 - 1 else y0;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = @mod(m + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// Dia local (dias desde 1970) de "hoje", "ontem", 2026-11-06 ou 06/11/2026.
pub fn parseDay(val: []const u8, now: i64) ?i64 {
    const today = @divFloor(now + tz_offset_s, 86400);
    if (eqlFold(val, "hoje") or eqlFold(val, "today")) return today;
    if (eqlFold(val, "ontem") or eqlFold(val, "yesterday")) return today - 1;
    const sep: u8 = if (std.mem.indexOfScalar(u8, val, '-') != null) '-' else '/';
    var it = std.mem.splitScalar(u8, val, sep);
    const a = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const b = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const e = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    if (it.next() != null) return null;
    const y, const m, const d = if (sep == '-') [3]i64{ a, b, e } else [3]i64{ e, b, a };
    if (y < 2015 or y > 9999 or m < 1 or m > 12 or d < 1 or d > 31) return null;
    return daysFromCivil(y, m, d);
}

/// O menor ID possível no começo desse dia local.
pub fn idOfDay(day: i64) u64 {
    const discord_epoch_ms: i64 = 1420070400000;
    const ms = (day * 86400 - tz_offset_s) * 1000 - discord_epoch_ms;
    return if (ms <= 0) 0 else @as(u64, @intCast(ms)) << 22;
}

// --- A busca do Discord -----------------------------------------------------------------

pub const Sort = enum { newest, oldest, relevance };
/// O que a interface resolveu a partir dos nomes (0 = sem o filtro).
pub const ApiIds = struct { author: u64 = 0, mentions: u64 = 0, channel: u64 = 0 };

const Out = struct {
    buf: []u8,
    n: usize = 0,
    overflow: bool = false,

    fn raw(o: *Out, s: []const u8) void {
        if (o.n + s.len > o.buf.len) {
            o.overflow = true;
            return;
        }
        @memcpy(o.buf[o.n..][0..s.len], s);
        o.n += s.len;
    }
    fn key(o: *Out, name: []const u8) void {
        if (o.n > 0) o.raw("&");
        o.raw(name);
        o.raw("=");
    }
    fn str(o: *Out, name: []const u8, val: []const u8) void {
        o.key(name);
        o.raw(val);
    }
    fn num(o: *Out, name: []const u8, val: u64) void {
        var b: [24]u8 = undefined;
        o.str(name, std.fmt.bufPrint(&b, "{d}", .{val}) catch "0");
    }
    fn encoded(o: *Out, name: []const u8, val: []const u8) void {
        o.key(name);
        const hex = "0123456789ABCDEF";
        for (val) |ch| {
            if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '~') {
                o.raw(&.{ch});
            } else {
                o.raw(&.{ '%', hex[ch >> 4], hex[ch & 15] });
            }
        }
    }
};

/// A consulta como a API pede: `GET .../messages/search?<isto>`. Null: não coube em `buf`.
pub fn apiParams(buf: []u8, q: *const Query, ids: ApiIds, sort: Sort, offset: u32) ?[]const u8 {
    var o: Out = .{ .buf = buf };
    if (q.content_len > 0) o.encoded("content", q.content());
    if (ids.author != 0) o.num("author_id", ids.author);
    if (ids.mentions != 0) o.num("mentions", ids.mentions);
    if (ids.channel != 0) o.num("channel_id", ids.channel);
    if (q.has_link) o.str("has", "link");
    if (q.has_image) o.str("has", "image");
    if (q.has_file) o.str("has", "file");
    if (q.has_video) o.str("has", "video");
    if (q.has_sound) o.str("has", "sound");
    if (q.has_embed) o.str("has", "embed");
    if (q.has_sticker) o.str("has", "sticker");
    if (q.pinned) |p| o.str("pinned", if (p) "true" else "false");
    if (q.min_id != 0) o.num("min_id", q.min_id);
    if (q.max_id != 0) o.num("max_id", q.max_id);
    o.str("sort_by", if (sort == .relevance) "relevance" else "timestamp");
    o.str("sort_order", if (sort == .oldest) "asc" else "desc");
    o.num("offset", offset);
    return if (o.overflow) null else buf[0..o.n];
}

/// Pontos de uma pessoa para o que foi digitado (`needle` já dobrado). 0 = não serve.
pub fn userScore(name: []const u8, needle: []const u8) u8 {
    var b: [64]u8 = undefined;
    const f = foldInto(&b, name);
    return if (std.mem.eql(u8, f, needle)) 6 else if (std.mem.startsWith(u8, f, needle)) 4 else if (std.mem.indexOf(u8, f, needle) != null) 2 else 0;
}

// --- Comparar textos --------------------------------------------------------------------

/// Próximo caractere já "dobrado": minúsculo e sem acento (latinos comuns).
/// Outros caracteres UTF-8 passam byte a byte.
fn nextFold(s: []const u8, i: *usize) u8 {
    const b = s[i.*];
    if (b == 0xC3 and i.* + 1 < s.len) {
        const x = s[i.* + 1];
        const folded: u8 = switch (x | 0x20) {
            0xA0...0xA5 => 'a',
            0xA7 => 'c',
            0xA8...0xAB => 'e',
            0xAC...0xAF => 'i',
            0xB1 => 'n',
            0xB2...0xB6 => 'o',
            0xB9...0xBC => 'u',
            0xBD, 0xBF => 'y',
            else => 0,
        };
        if (folded != 0 and x >= 0x80 and x <= 0xBF and x != 0x97 and x != 0xB7 and x != 0x9F) {
            i.* += 2;
            return folded;
        }
    }
    i.* += 1;
    return std.ascii.toLower(b);
}

/// Copia `s` dobrado para `buf` (corta no tamanho do buffer).
pub fn foldInto(buf: []u8, s: []const u8) []const u8 {
    var i: usize = 0;
    var n: usize = 0;
    while (i < s.len and n < buf.len) {
        buf[n] = nextFold(s, &i);
        n += 1;
    }
    return buf[0..n];
}

fn eqlFold(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Onde `needle` (já dobrado) aparece em `hay`: faixa de bytes em `hay`.
pub fn findFold(hay: []const u8, needle: []const u8) ?[2]usize {
    if (needle.len == 0) return .{ 0, 0 };
    var start: usize = 0;
    while (start < hay.len) {
        var i = start;
        var k: usize = 0;
        while (k < needle.len and i < hay.len) : (k += 1) {
            if (nextFold(hay, &i) != needle[k]) break;
        } else if (k == needle.len) return .{ start, i };
        // Avança um caractere inteiro (não para no meio de um UTF-8).
        start += 1;
        while (start < hay.len and (hay[start] & 0xC0) == 0x80) start += 1;
    }
    return null;
}

pub fn containsFold(hay: []const u8, needle: []const u8) bool {
    return findFold(hay, needle) != null;
}

pub fn hasLink(s: []const u8) bool {
    return std.mem.indexOf(u8, s, "https://") != null or std.mem.indexOf(u8, s, "http://") != null;
}

test "consulta com filtros, aspas e acentos" {
    const q = Query.parse("Não sei from:Ana.exe in:#geral has:link has:imagem \"meio termo\" http://x.y");
    try std.testing.expectEqual(@as(usize, 4), q.n_terms);
    try std.testing.expectEqualStrings("nao", q.term(0));
    try std.testing.expectEqualStrings("sei", q.term(1));
    try std.testing.expectEqualStrings("meio termo", q.term(2));
    try std.testing.expectEqualStrings("http://x.y", q.term(3));
    try std.testing.expectEqualStrings("ana.exe", q.from());
    try std.testing.expectEqualStrings("geral", q.in());
    try std.testing.expect(q.has_link and q.has_image and !q.has_file);
    try std.testing.expect(Query.parse("   ").empty());
    // O que vai para o Discord é o texto como foi digitado.
    try std.testing.expectEqualStrings("Não sei \"meio termo\" http://x.y", q.content());
}

test "comparação sem maiúsculas nem acentos" {
    try std.testing.expect(containsFold("Eu NÃO acredito", "nao acre"));
    try std.testing.expect(containsFold("Ação", "acao"));
    try std.testing.expect(!containsFold("abc", "abd"));
    const r = findFold("olá Mundo", "mundo").?;
    try std.testing.expectEqual(@as(usize, 5), r[0]);
    try std.testing.expectEqual(@as(usize, 10), r[1]);
    try std.testing.expect(hasLink("veja https://ziglang.org"));
}

test "datas viram faixa de IDs" {
    const saved = tz_offset_s;
    defer tz_offset_s = saved;
    tz_offset_s = 0;
    // 2015-01-01 00:00 UTC é o começo da contagem do Discord.
    try std.testing.expectEqual(@as(u64, 0), idOfDay(parseDay("2015-01-01", 0).?));
    try std.testing.expectEqual(@as(u64, 86400000) << 22, idOfDay(parseDay("02/01/2015", 0).?));
    try std.testing.expect(parseDay("2015-13-01", 0) == null);
    try std.testing.expect(parseDay("ontemm", 0) == null);

    const before = Query.parseAt("before:2026-01-02", 0);
    const during = Query.parseAt("during:2026-01-02", 0);
    const after = Query.parseAt("after:2026-01-02", 0);
    const day = idOfDay(parseDay("2026-01-02", 0).?);
    const next = idOfDay(parseDay("2026-01-03", 0).?);
    try std.testing.expectEqual(day, before.max_id);
    try std.testing.expectEqual(@as(u64, 0), before.min_id);
    try std.testing.expectEqual(day, during.min_id);
    try std.testing.expectEqual(next, during.max_id);
    try std.testing.expectEqual(next, after.min_id);
    try std.testing.expect(during.idOk(day + 1) and !during.idOk(next + 1) and !during.idOk(day - 1));
    try std.testing.expectEqualStrings("before:logo", Query.parseAt("before:logo", 0).invalid());
    // Um filtro ainda sendo digitado não conta nem atrapalha.
    try std.testing.expect(Query.parseAt("from:", 0).empty());
    try std.testing.expectEqual(@as(usize, 0), Query.parseAt("before:", 0).invalid().len);
}

test "parâmetros da busca do Discord" {
    var buf: [512]u8 = undefined;
    const q = Query.parseAt("olá mundo has:image has:video pinned:true", 0);
    try std.testing.expect(q.serverOnly());
    const p = apiParams(&buf, &q, .{ .author = 11, .mentions = 22, .channel = 33 }, .newest, 25).?;
    try std.testing.expectEqualStrings("content=ol%C3%A1%20mundo&author_id=11&mentions=22&channel_id=33&has=image&has=video&pinned=true&sort_by=timestamp&sort_order=desc&offset=25", p);
    const r = apiParams(&buf, &Query.parseAt("oi", 0), .{}, .relevance, 0).?;
    try std.testing.expectEqualStrings("content=oi&sort_by=relevance&sort_order=desc&offset=0", r);
    const o = apiParams(&buf, &Query.parseAt("oi", 0), .{}, .oldest, 0).?;
    try std.testing.expectEqualStrings("content=oi&sort_by=timestamp&sort_order=asc&offset=0", o);
    var small: [8]u8 = undefined;
    try std.testing.expect(apiParams(&small, &q, .{}, .newest, 0) == null);
}

test "o que está sendo digitado" {
    const a = lastToken("oi from:an");
    try std.testing.expectEqualStrings("from", a.key);
    try std.testing.expectEqualStrings("an", a.val);
    try std.testing.expectEqual(@as(usize, 3), a.start);
    const b = lastToken("oi ");
    try std.testing.expectEqual(@as(usize, 3), b.start);
    try std.testing.expectEqual(@as(usize, 0), b.val.len);
    try std.testing.expectEqual(@as(u8, 6), userScore("Ana", "ana"));
    try std.testing.expectEqual(@as(u8, 4), userScore("Ana Clara", "an"));
    try std.testing.expectEqual(@as(u8, 2), userScore("Mariana", "ana"));
    try std.testing.expectEqual(@as(u8, 0), userScore("Bia", "ana"));
}
