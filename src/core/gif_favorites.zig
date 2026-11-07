//! GIFs favoritos da conta. Ficam em FrecencyUserSettings, um protobuf que
//! GET /users/@me/settings-proto/2 devolve em base64. O formato não é público (campos
//! levantados pela comunidade em discord-protos). O mesmo arquivo guarda os emojis
//! recentes e outras preferências da conta: para escrever, `edit` só mexe nos favoritos
//! e copia todo o resto byte a byte. Se alguma parte não der para ler inteira, não
//! escreve nada.
const std = @import("std");
const types = @import("types.zig");

pub const Favorite = struct { url: []const u8, src: []const u8, order: u32 };

const favorite_gifs = 2; // FrecencyUserSettings.favorite_gifs
const gifs_map = 1; // FavoriteGIFs.gifs (map<string, FavoriteGIF>)
const hide_tooltip = 2; // FavoriteGIFs.hide_tooltip
const gif_format = 1; // FavoriteGIF.format (1 imagem, 2 vídeo)
const gif_src = 2; // FavoriteGIF.src
const gif_width = 3;
const gif_height = 4;
const gif_order = 5; // FavoriteGIF.order

/// Maior endereço que a gente grava (o Discord manda bem menos que isso).
const max_url = 4096;

const Field = struct {
    num: u64,
    wire: u3,
    int: u64 = 0,
    bytes: []const u8 = "",
    /// Onde o campo inteiro começa (a etiqueta), onde a etiqueta termina e onde o campo acaba.
    start: usize = 0,
    tag_end: usize = 0,
    end: usize = 0,
};

/// Dados malformados terminam a leitura: o resto do arquivo não dá para confiar.
const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    fn varint(r: *Reader) ?u64 {
        var out: u64 = 0;
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            if (r.pos >= r.data.len) return null;
            const b = r.data[r.pos];
            r.pos += 1;
            out |= @as(u64, b & 0x7f) << @intCast(i * 7);
            if (b & 0x80 == 0) return out;
        }
        return null;
    }

    fn skip(r: *Reader, n: u64) ?[]const u8 {
        if (n > r.data.len - r.pos) return null;
        const start = r.pos;
        r.pos += @intCast(n);
        return r.data[start..r.pos];
    }

    fn next(r: *Reader) error{Malformed}!?Field {
        if (r.pos >= r.data.len) return null;
        const start = r.pos;
        const tag = r.varint() orelse return error.Malformed;
        const num = tag >> 3;
        // Campo 0 não existe; tipos 3 e 4 (grupos) são obsoletos, 6 e 7 não existem.
        if (num == 0) return error.Malformed;
        var f: Field = .{ .num = num, .wire = @truncate(tag), .start = start, .tag_end = r.pos };
        switch (f.wire) {
            0 => f.int = r.varint() orelse return error.Malformed,
            1 => _ = r.skip(8) orelse return error.Malformed,
            2 => f.bytes = r.skip(r.varint() orelse return error.Malformed) orelse return error.Malformed,
            5 => _ = r.skip(4) orelse return error.Malformed,
            else => return error.Malformed,
        }
        f.end = r.pos;
        return f;
    }
};

fn newerFirst(_: void, a: Favorite, b: Favorite) bool {
    return a.order > b.order;
}

/// Os favoritos, do mais novo para o mais velho. As fatias apontam para `data`.
pub fn parse(gpa: std.mem.Allocator, data: []const u8) ![]Favorite {
    var out: std.ArrayList(Favorite) = .empty;
    errdefer out.deinit(gpa);
    var top: Reader = .{ .data = data };
    while (try top.next()) |f| {
        if (f.num != favorite_gifs) continue;
        var fav: Reader = .{ .data = f.bytes };
        while (try fav.next()) |entry_field| {
            if (entry_field.num != gifs_map) continue;
            var it: Favorite = .{ .url = "", .src = "", .order = 0 };
            var entry: Reader = .{ .data = entry_field.bytes };
            while (try entry.next()) |ef| {
                if (ef.num == 1) it.url = ef.bytes;
                if (ef.num != 2) continue;
                var gif: Reader = .{ .data = ef.bytes };
                while (try gif.next()) |gf| {
                    if (gf.num == gif_src) it.src = gf.bytes;
                    if (gf.num == gif_order) it.order = @truncate(gf.int);
                }
            }
            if (it.url.len > 0 and it.src.len > 0) try out.append(gpa, it);
        }
    }
    const items = try out.toOwnedSlice(gpa);
    std.mem.sort(Favorite, items, {}, newerFirst);
    return items;
}

pub const Format = enum(u8) { image = 1, video = 2 };

/// Um GIF para guardar: `url` é a chave (o link que vai na mensagem), `src` a mídia.
pub const NewGif = struct {
    url: []const u8,
    src: []const u8,
    width: u32 = 0,
    height: u32 = 0,
    format: Format = .image,
};

pub const Change = union(enum) { add: NewGif, remove: []const u8 };

pub const EditError = error{ Malformed, TooLong, OutOfMemory };

/// Confere um campo conhecido: tipo de fio errado é arquivo que não entendemos.
fn want(f: Field, wire: u3) error{Malformed}!void {
    if (f.wire != wire) return error.Malformed;
}

/// Lê um FavoriteGIF inteiro (para validar) e devolve a ordem dele.
fn gifOrder(data: []const u8) error{Malformed}!u64 {
    var order: u64 = 0;
    var r: Reader = .{ .data = data };
    while (try r.next()) |f| switch (f.num) {
        gif_format, gif_width, gif_height => try want(f, 0),
        gif_src => try want(f, 2),
        gif_order => {
            try want(f, 0);
            order = f.int;
        },
        else => {},
    };
    return order;
}

/// A chave de uma entrada do mapa (a última vence, como no protobuf), lendo a entrada inteira.
fn entryKey(data: []const u8, order: *u64) error{Malformed}![]const u8 {
    var key: []const u8 = "";
    var r: Reader = .{ .data = data };
    while (try r.next()) |f| switch (f.num) {
        1 => {
            try want(f, 2);
            key = f.bytes;
        },
        2 => {
            try want(f, 2);
            order.* = @max(order.*, try gifOrder(f.bytes));
        },
        else => {},
    };
    return key;
}

/// O que interessa da mensagem, lida e conferida inteira antes de qualquer escrita.
const Scan = struct { max_order: u64 = 0, found: bool = false, fav_fields: usize = 0 };

fn scan(data: []const u8, url: []const u8) error{Malformed}!Scan {
    var out: Scan = .{};
    var top: Reader = .{ .data = data };
    while (try top.next()) |f| {
        if (f.num != favorite_gifs) continue;
        try want(f, 2);
        out.fav_fields += 1;
        var fav: Reader = .{ .data = f.bytes };
        while (try fav.next()) |ef| switch (ef.num) {
            gifs_map => {
                try want(ef, 2);
                var order: u64 = 0;
                const key = try entryKey(ef.bytes, &order);
                out.max_order = @max(out.max_order, order);
                if (std.mem.eql(u8, key, url)) out.found = true;
            },
            hide_tooltip => try want(ef, 0),
            else => {},
        };
    }
    return out;
}

fn putVarint(out: *std.ArrayList(u8), gpa: std.mem.Allocator, value: u64) !void {
    var x = value;
    while (x >= 0x80) : (x >>= 7) try out.append(gpa, @as(u8, @truncate(x)) | 0x80);
    try out.append(gpa, @truncate(x));
}

fn putBytes(out: *std.ArrayList(u8), gpa: std.mem.Allocator, num: u64, data: []const u8) !void {
    try putVarint(out, gpa, num << 3 | 2);
    try putVarint(out, gpa, data.len);
    try out.appendSlice(gpa, data);
}

fn putInt(out: *std.ArrayList(u8), gpa: std.mem.Allocator, num: u64, value: u64) !void {
    try putVarint(out, gpa, num << 3);
    try putVarint(out, gpa, value);
}

/// Uma entrada nova do mapa: { 1: url, 2: FavoriteGIF }.
fn putEntry(out: *std.ArrayList(u8), gpa: std.mem.Allocator, g: NewGif, order: u64) !void {
    var gif: std.ArrayList(u8) = .empty;
    defer gif.deinit(gpa);
    try putInt(&gif, gpa, gif_format, @intFromEnum(g.format));
    try putBytes(&gif, gpa, gif_src, g.src);
    // Zero é o padrão do proto3: não vai.
    if (g.width > 0) try putInt(&gif, gpa, gif_width, g.width);
    if (g.height > 0) try putInt(&gif, gpa, gif_height, g.height);
    try putInt(&gif, gpa, gif_order, order);
    var entry: std.ArrayList(u8) = .empty;
    defer entry.deinit(gpa);
    try putBytes(&entry, gpa, 1, g.url);
    try putBytes(&entry, gpa, 2, gif.items);
    try putBytes(out, gpa, gifs_map, entry.items);
}

/// A mensagem com o favorito acrescentado (ordem = maior + 1, no fim da lista) ou
/// tirado. Tudo fora dos favoritos sai exatamente como entrou, no mesmo lugar; dentro
/// deles, só a entrada mexida muda. null = já estava assim (nada a gravar). Qualquer
/// parte que não dê para ler inteira dá erro antes de montar a saída.
pub fn edit(gpa: std.mem.Allocator, data: []const u8, change: Change) EditError!?[]u8 {
    const url = switch (change) {
        .add => |g| g.url,
        .remove => |u| u,
    };
    if (url.len == 0) return error.Malformed;
    if (url.len > max_url) return error.TooLong;
    if (change == .add and (change.add.src.len == 0 or change.add.src.len > max_url)) return error.TooLong;
    const info = try scan(data, url);
    switch (change) {
        .add => if (info.found) return null,
        .remove => if (!info.found) return null,
    }
    const order = @min(info.max_order + 1, std.math.maxInt(u32));

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, data.len + url.len * 2 + 64);
    var inner: std.ArrayList(u8) = .empty;
    defer inner.deinit(gpa);
    var seen: usize = 0;
    var top: Reader = .{ .data = data };
    while (try top.next()) |f| {
        if (f.num != favorite_gifs) {
            try out.appendSlice(gpa, data[f.start..f.end]);
            continue;
        }
        seen += 1;
        inner.clearRetainingCapacity();
        var fav: Reader = .{ .data = f.bytes };
        while (try fav.next()) |ef| {
            if (change == .remove and ef.num == gifs_map) {
                var ignored: u64 = 0;
                if (std.mem.eql(u8, try entryKey(ef.bytes, &ignored), url)) continue;
            }
            try inner.appendSlice(gpa, f.bytes[ef.start..ef.end]);
        }
        // O novo vai no último campo de favoritos (o protobuf junta todos).
        if (change == .add and seen == info.fav_fields) try putEntry(&inner, gpa, change.add, order);
        // A etiqueta como estava; só o tamanho muda.
        try out.appendSlice(gpa, data[f.start..f.tag_end]);
        try putVarint(&out, gpa, inner.items.len);
        try out.appendSlice(gpa, inner.items);
    }
    if (change == .add and info.fav_fields == 0) {
        try putEntry(&inner, gpa, change.add, order);
        try putBytes(&out, gpa, favorite_gifs, inner.items);
    }
    return try out.toOwnedSlice(gpa);
}

/// A chave de um GIF da conversa nos favoritos: a página do Tenor/Giphy (o link que
/// vai na mensagem) ou o próprio arquivo, num GIF anexado. Vazio = não é GIF.
pub fn attachmentKey(content: []const u8, a: *const types.Attachment) []const u8 {
    if (!a.animated or a.video or !a.isImage()) return "";
    if (a.link.len > 0) return a.link;
    // Mensagem guardada antes de o app anotar a página: o link do texto.
    if (a.embed) if (pageIn(content)) |p| return p;
    return a.url;
}

fn pageIn(text: []const u8) ?[]const u8 {
    for ([_][]const u8{ "https://tenor.com/", "https://giphy.com/", "https://media.giphy.com/" }) |prefix| {
        const i = std.mem.indexOf(u8, text, prefix) orelse continue;
        const end = std.mem.indexOfAnyPos(u8, text, i, " \t\r\n<>\"'") orelse text.len;
        return text[i..end];
    }
    return null;
}

test "chave do GIF da conversa" {
    var a: types.Attachment = .{ .url = "https://media.tenor.com/xAAAAx/a.webp", .filename = "a", .width = 10, .height = 10, .animated = true, .embed = true };
    // A página anotada vence; sem ela, o link do texto; sem link, o arquivo.
    a.link = "https://tenor.com/view/a-1";
    try std.testing.expectEqualStrings("https://tenor.com/view/a-1", attachmentKey("olha https://tenor.com/view/b-2", &a));
    a.link = "";
    try std.testing.expectEqualStrings("https://tenor.com/view/b-2", attachmentKey("olha https://tenor.com/view/b-2 kk", &a));
    try std.testing.expectEqualStrings(a.url, attachmentKey("sem link", &a));
    // GIF anexado: o próprio arquivo, mesmo com um link do Tenor no texto.
    a.embed = false;
    try std.testing.expectEqualStrings(a.url, attachmentKey("https://tenor.com/view/b-2", &a));
    // Imagem parada ou vídeo: sem estrela.
    a.animated = false;
    try std.testing.expectEqualStrings("", attachmentKey("", &a));
    a.animated = true;
    a.video = true;
    try std.testing.expectEqualStrings("", attachmentKey("", &a));
}

/// Está entre os favoritos? Erro se a mensagem não der para ler.
pub fn contains(data: []const u8, url: []const u8) error{Malformed}!bool {
    return (try scan(data, url)).found;
}

fn entryBytes(comptime url: []const u8, comptime src: []const u8, comptime order: u8) []const u8 {
    const gif = "\x08\x02" ++ "\x12" ++ [_]u8{src.len} ++ src ++ "\x18\x80\x03" ++ "\x28" ++ [_]u8{order};
    const body = "\x0a" ++ [_]u8{url.len} ++ url ++ "\x12" ++ [_]u8{gif.len} ++ gif;
    return "\x0a" ++ [_]u8{body.len} ++ body;
}

test "lê os favoritos, do mais novo para o mais velho, pulando o resto" {
    const a = comptime entryBytes("https://tenor.com/view/a", "https://media.tenor.com/aAAPo/a.mp4", 1);
    const b = comptime entryBytes("https://tenor.com/view/b", "https://media.tenor.com/bAAPo/b.mp4", 7);
    const favs = a ++ b ++ "\x10\x01"; // hide_tooltip
    // Antes dos favoritos: campos que não interessam, em cada tipo do formato.
    const data = "\x0a\x03abc" ++ "\x18\x96\x01" ++ "\x25\x01\x02\x03\x04" ++ "\x29\x01\x02\x03\x04\x05\x06\x07\x08" ++
        "\x12\x81\x01"[0..1] ++ [_]u8{ @intCast(favs.len & 0x7f | 0x80), @intCast(favs.len >> 7) } ++ favs;
    const got = try parse(std.testing.allocator, data);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqual(2, got.len);
    try std.testing.expectEqualStrings("https://tenor.com/view/b", got[0].url);
    try std.testing.expectEqualStrings("https://media.tenor.com/bAAPo/b.mp4", got[0].src);
    try std.testing.expectEqual(7, got[0].order);
    try std.testing.expectEqualStrings("https://tenor.com/view/a", got[1].url);
}

test "dados cortados ou malucos dão erro, sem ler fora do lugar" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.Malformed, parse(gpa, "\x12\x7f\x0a"));
    try std.testing.expectError(error.Malformed, parse(gpa, "\x12"));
    try std.testing.expectError(error.Malformed, parse(gpa, "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"));
    try std.testing.expectError(error.Malformed, parse(gpa, "\x12\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"));
    try std.testing.expectError(error.Malformed, parse(gpa, "\x0b"));
    const none = try parse(gpa, "");
    defer gpa.free(none);
    try std.testing.expectEqual(0, none.len);
}

/// Varint em tempo de compilação (para montar as mensagens dos testes).
fn varintOf(comptime n: usize) []const u8 {
    comptime var out: []const u8 = "";
    comptime var x = n;
    inline while (x >= 0x80) : (x >>= 7) out = out ++ [_]u8{@as(u8, x & 0x7f) | 0x80};
    return out ++ [_]u8{x};
}

const entry_a = entryBytes("https://tenor.com/view/a", "https://media.tenor.com/aAAPo/a.mp4", 3);
const entry_b = entryBytes("https://tenor.com/view/b", "https://media.tenor.com/bAAPo/b.mp4", 9);
// Dentro dos favoritos: hide_tooltip e um campo desconhecido entre as entradas.
const sample_favs = entry_a ++ "\x10\x01" ++ "\x3a\x02zz" ++ entry_b;
// Antes: mensagem aninhada, varint escrito de um jeito não canônico e fixed32.
const sample_head = "\x0a\x05\x08\x01\x10\x02\x00"[0..7] ++ "\x18\x96\x81\x80\x00" ++ "\x25\x01\x02\x03\x04";
// Depois: fixed64 e um campo de número alto.
const sample_tail = "\x29\x01\x02\x03\x04\x05\x06\x07\x08" ++ "\xa2\x06\x03xyz";

/// FrecencyUserSettings de exemplo: campos desconhecidos antes, no meio e depois dos favoritos.
fn sample() []const u8 {
    return sample_head ++ "\x12" ++ varintOf(sample_favs.len) ++ sample_favs ++ sample_tail;
}

test "acrescentar: ordem é a maior + 1 e o resto fica igual byte a byte" {
    const gpa = std.testing.allocator;
    const data = comptime sample();
    const out = (try edit(gpa, data, .{ .add = .{ .url = "https://tenor.com/view/c", .src = "https://media.tenor.com/cAAPo/c.mp4", .width = 498, .height = 280, .format = .video } })).?;
    defer gpa.free(out);
    // Tudo antes dos favoritos e tudo depois, idêntico; o miolo antigo também, no mesmo lugar.
    try std.testing.expectEqualSlices(u8, sample_head, out[0..sample_head.len]);
    try std.testing.expect(std.mem.endsWith(u8, out, sample_tail));
    const new_len = varintOf(sample_favs.len).len;
    try std.testing.expectEqualSlices(u8, sample_favs, out[sample_head.len + 1 + new_len ..][0..sample_favs.len]);

    const got = try parse(gpa, out);
    defer gpa.free(got);
    try std.testing.expectEqual(3, got.len);
    try std.testing.expectEqualStrings("https://tenor.com/view/c", got[0].url);
    try std.testing.expectEqualStrings("https://media.tenor.com/cAAPo/c.mp4", got[0].src);
    try std.testing.expectEqual(10, got[0].order);
    try std.testing.expect(try contains(out, "https://tenor.com/view/c"));
    // De novo: já está lá, nada a gravar.
    try std.testing.expectEqual(null, try edit(gpa, out, .{ .add = .{ .url = "https://tenor.com/view/c", .src = "x" } }));
}

test "tirar e pôr de volta devolve exatamente o arquivo do começo, menos a entrada" {
    const gpa = std.testing.allocator;
    const data = comptime sample();
    const out = (try edit(gpa, data, .{ .remove = "https://tenor.com/view/a" })).?;
    defer gpa.free(out);
    const got = try parse(gpa, out);
    defer gpa.free(got);
    try std.testing.expectEqual(1, got.len);
    try std.testing.expectEqualStrings("https://tenor.com/view/b", got[0].url);
    // O que não é a entrada tirada continua, na mesma ordem: hide_tooltip e o desconhecido.
    try std.testing.expect(std.mem.indexOf(u8, out, "\x10\x01\x3a\x02zz") != null);
    // Menos a entrada, e o tamanho dos favoritos passa a caber num byte só.
    try std.testing.expectEqual(data.len - entry_a.len - 1, out.len);
    // Tirar o que não está: nada a gravar.
    try std.testing.expectEqual(null, try edit(gpa, out, .{ .remove = "https://tenor.com/view/a" }));
    // Tirar o último deixa os favoritos vazios, mas o resto inteiro.
    const empty = (try edit(gpa, out, .{ .remove = "https://tenor.com/view/b" })).?;
    defer gpa.free(empty);
    const none = try parse(gpa, empty);
    defer gpa.free(none);
    try std.testing.expectEqual(0, none.len);
    try std.testing.expectEqualSlices(u8, sample_head, empty[0..sample_head.len]);
    try std.testing.expect(std.mem.endsWith(u8, empty, sample_tail));
}

test "sem favoritos ainda: o campo novo vai no fim e o resto fica igual" {
    const gpa = std.testing.allocator;
    const data = "\x0a\x02\x08\x01" ++ "\x18\x05";
    const out = (try edit(gpa, data, .{ .add = .{ .url = "u", .src = "s" } })).?;
    defer gpa.free(out);
    try std.testing.expectEqualSlices(u8, data, out[0..data.len]);
    const got = try parse(gpa, out);
    defer gpa.free(got);
    try std.testing.expectEqual(1, got.len);
    try std.testing.expectEqual(1, got[0].order);
    // Arquivo vazio (conta que nunca guardou nada).
    const fresh = (try edit(gpa, "", .{ .add = .{ .url = "u", .src = "s" } })).?;
    defer gpa.free(fresh);
    try std.testing.expect(try contains(fresh, "u"));
}

test "arquivo cortado ou com tipo errado nunca é escrito (e nunca lê fora)" {
    const gpa = std.testing.allocator;
    const data = comptime sample();
    const add: Change = .{ .add = .{ .url = "https://tenor.com/view/c", .src = "s" } };
    // Cortado em qualquer ponto que não seja o fim de um campo do topo: erro, nada escrito.
    var ok_cuts: usize = 0;
    for (0..data.len) |n| {
        if (edit(gpa, data[0..n], add)) |res| {
            if (res) |o| gpa.free(o);
            ok_cuts += 1;
        } else |err| try std.testing.expectEqual(error.Malformed, err);
    }
    // Só os cortes entre campos do topo passam: 0, depois de cada um dos 3 primeiros, dos favoritos e do fixed64.
    try std.testing.expectEqual(6, ok_cuts);
    // Favoritos com tipo de fio errado, entrada com chave numérica, ordem como texto, grupo.
    const bad = [_][]const u8{
        "\x10\x01",
        "\x12\x02\x08\x01",
        "\x12\x04\x0a\x02\x08\x01",
        "\x12\x08\x0a\x06\x12\x04\x2a\x02ab",
        "\x12\x01\x0b",
        "\x0b",
        "\x00\x01",
        "\x12\x03\x0a\x05",
    };
    for (bad) |b| try std.testing.expectError(error.Malformed, edit(gpa, b, add));
    try std.testing.expectError(error.Malformed, edit(gpa, data, .{ .remove = "" }));
    const long: [max_url + 1]u8 = @splat('a');
    try std.testing.expectError(error.TooLong, edit(gpa, data, .{ .add = .{ .url = &long, .src = "s" } }));
}

test "sem vazamento quando falta memória ao escrever" {
    const data = comptime sample();
    const run = struct {
        fn f(gpa: std.mem.Allocator, d: []const u8) !void {
            const out = (try edit(gpa, d, .{ .add = .{ .url = "https://tenor.com/view/c", .src = "s", .width = 10 } })).?;
            gpa.free(out);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, run.f, .{data});
}
