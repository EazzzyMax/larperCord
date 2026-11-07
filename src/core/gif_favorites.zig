//! GIFs favoritos da conta. Ficam em FrecencyUserSettings, um protobuf que
//! GET /users/@me/settings-proto/2 devolve em base64. O formato não é público (campos
//! levantados pela comunidade em discord-protos): só lemos, nunca escrevemos de volta,
//! porque o mesmo arquivo guarda os emojis recentes e outras preferências da conta.
const std = @import("std");

pub const Favorite = struct { url: []const u8, src: []const u8, order: u32 };

const favorite_gifs = 2; // FrecencyUserSettings.favorite_gifs
const gifs_map = 1; // FavoriteGIFs.gifs (map<string, FavoriteGIF>)
const gif_src = 2; // FavoriteGIF.src
const gif_order = 5; // FavoriteGIF.order

const Field = struct { num: u64, int: u64 = 0, bytes: []const u8 = "" };

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
        const tag = r.varint() orelse return error.Malformed;
        const num = tag >> 3;
        return switch (tag & 7) {
            0 => .{ .num = num, .int = r.varint() orelse return error.Malformed },
            1 => blk: {
                _ = r.skip(8) orelse return error.Malformed;
                break :blk .{ .num = num };
            },
            2 => .{ .num = num, .bytes = r.skip(r.varint() orelse return error.Malformed) orelse return error.Malformed },
            5 => blk: {
                _ = r.skip(4) orelse return error.Malformed;
                break :blk .{ .num = num };
            },
            else => error.Malformed,
        };
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
