//! Opções de envio de uma mensagem (silenciosa, sem prévias, sem menções,
//! mencionar quem recebe a resposta) e dos anexos (spoiler, texto alternativo).
//! A rede monta o corpo com elas (net/envio_json.zig); aqui fica o que a
//! interface e o Store precisam saber.
const std = @import("std");

pub const SendOpts = struct {
    /// SUPPRESS_NOTIFICATIONS: ninguém recebe notificação (o "@silent").
    silent: bool = false,
    /// SUPPRESS_EMBEDS: os links vão sem o cartão de prévia.
    no_embeds: bool = false,
    /// `allowed_mentions` com `parse` vazio: as menções ficam no texto, sem notificar.
    no_pings: bool = false,
    /// Respondendo: o autor da mensagem respondida é mencionado (`replied_user`).
    ping_reply: bool = true,

    pub fn isDefault(o: SendOpts) bool {
        return !o.silent and !o.no_embeds and !o.no_pings and o.ping_reply;
    }

    /// Quantas das opções do menu da caixa estão ligadas.
    pub fn count(o: SendOpts) u8 {
        return @as(u8, @intFromBool(o.silent)) + @intFromBool(o.no_embeds) + @intFromBool(o.no_pings);
    }
};

/// O que vai junto com um arquivo. `alt` é alocado com o c_allocator.
pub const FileOpt = struct {
    spoiler: bool = false,
    alt: []const u8 = "",

    pub fn isDefault(f: FileOpt) bool {
        return !f.spoiler and f.alt.len == 0;
    }
};

/// Texto alternativo: o Discord aceita até 1024 caracteres.
pub const max_alt = 1024;

/// Onde a próxima página de fixadas começa: o `pinned_at` da última que veio
/// (ISO 8601, exatamente como o Discord mandou). Vazio = a primeira página.
pub const PinCursor = struct {
    buf: [48]u8 = undefined,
    len: u8 = 0,

    pub fn init(s: []const u8) PinCursor {
        var c: PinCursor = .{};
        if (s.len > c.buf.len) return c;
        @memcpy(c.buf[0..s.len], s);
        c.len = @intCast(s.len);
        return c;
    }

    pub fn slice(c: *const PinCursor) []const u8 {
        return c.buf[0..c.len];
    }
};

pub const flag_suppress_embeds: u32 = 1 << 2;
pub const flag_suppress_notifications: u32 = 1 << 12;

pub fn flags(o: SendOpts) u32 {
    var f: u32 = 0;
    if (o.no_embeds) f |= flag_suppress_embeds;
    if (o.silent) f |= flag_suppress_notifications;
    return f;
}

/// "@silent " no começo, como no Discord: devolve o resto da mensagem (que vai
/// sem o prefixo e sem notificar ninguém). null = não começa assim.
pub fn stripSilent(text: []const u8) ?[]const u8 {
    const p = "@silent";
    if (!std.mem.startsWith(u8, text, p)) return null;
    if (text.len > p.len and !std.ascii.isWhitespace(text[p.len])) return null;
    return std.mem.trimStart(u8, text[p.len..], " \t\r\n");
}

/// Até 1024 caracteres (contando cada caractere UTF-8 como um).
pub fn clampAlt(s: []const u8) []const u8 {
    var chars: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (chars == max_alt) return s[0..i];
        const n = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        i = @min(s.len, i + n);
        chars += 1;
    }
    return s;
}

pub fn freeFileOpts(a: std.mem.Allocator, list: []const FileOpt) void {
    for (list) |f| if (f.alt.len > 0) a.free(f.alt);
    if (list.len > 0) a.free(list);
}

pub fn dupeFileOpts(a: std.mem.Allocator, list: []const FileOpt) ![]FileOpt {
    if (list.len == 0) return &.{};
    const out = try a.alloc(FileOpt, list.len);
    for (out) |*o| o.* = .{};
    errdefer freeFileOpts(a, out);
    for (list, out) |f, *o| o.* = .{ .spoiler = f.spoiler, .alt = if (f.alt.len > 0) try a.dupe(u8, f.alt) else "" };
    return out;
}

/// As opções das mensagens nossas ainda sem confirmação, por nonce: o
/// "tentar de novo" de uma que falhou manda igual (silenciosa continua
/// silenciosa, o spoiler continua spoiler). Só entra o que não é o padrão.
pub const Outbox = struct {
    pub const Entry = struct { opts: SendOpts, files: []FileOpt };
    items: std.AutoHashMapUnmanaged(u64, Entry) = .empty,

    /// Copia `files` (com os textos).
    pub fn put(o: *Outbox, gpa: std.mem.Allocator, nonce: u64, opts: SendOpts, files: []const FileOpt) !void {
        var any_file = false;
        for (files) |f| any_file = any_file or !f.isDefault();
        if (opts.isDefault() and !any_file) return;
        const copy = try dupeFileOpts(gpa, if (any_file) files else &.{});
        errdefer freeFileOpts(gpa, copy);
        o.remove(gpa, nonce);
        try o.items.put(gpa, nonce, .{ .opts = opts, .files = copy });
    }

    pub fn get(o: *const Outbox, nonce: u64) ?Entry {
        return o.items.get(nonce);
    }

    pub fn remove(o: *Outbox, gpa: std.mem.Allocator, nonce: u64) void {
        if (o.items.count() == 0) return;
        if (o.items.fetchRemove(nonce)) |kv| freeFileOpts(gpa, kv.value.files);
    }

    pub fn deinit(o: *Outbox, gpa: std.mem.Allocator) void {
        var it = o.items.valueIterator();
        while (it.next()) |e| freeFileOpts(gpa, e.files);
        o.items.deinit(gpa);
    }
};

test "@silent no começo" {
    try std.testing.expectEqualStrings("oi gente", stripSilent("@silent oi gente").?);
    try std.testing.expectEqualStrings("linha", stripSilent("@silent\nlinha").?);
    try std.testing.expectEqualStrings("", stripSilent("@silent").?);
    try std.testing.expect(stripSilent("@silentbob oi") == null);
    try std.testing.expect(stripSilent("oi @silent") == null);
    try std.testing.expect(stripSilent("@Silent oi") == null);
}

test "flags de envio" {
    try std.testing.expectEqual(@as(u32, 0), flags(.{}));
    try std.testing.expectEqual(@as(u32, 4), flags(.{ .no_embeds = true }));
    try std.testing.expectEqual(@as(u32, 4096), flags(.{ .silent = true }));
    try std.testing.expectEqual(@as(u32, 4100), flags(.{ .silent = true, .no_embeds = true, .no_pings = true }));
    try std.testing.expect((SendOpts{}).isDefault());
    try std.testing.expect(!(SendOpts{ .ping_reply = false }).isDefault());
    try std.testing.expectEqual(@as(u8, 2), (SendOpts{ .silent = true, .no_pings = true }).count());
}

test "texto alternativo até 1024 caracteres" {
    var many: [1030 * 2]u8 = undefined;
    for (0..1030) |i| @memcpy(many[i * 2 ..][0..2], "é");
    try std.testing.expectEqual(@as(usize, 2048), clampAlt(&many).len);
    try std.testing.expectEqualStrings("gato", clampAlt("gato"));
}

test "outbox guarda só o que não é padrão e copia os textos" {
    const gpa = std.testing.allocator;
    var o: Outbox = .{};
    defer o.deinit(gpa);
    try o.put(gpa, 1, .{}, &.{.{}});
    try std.testing.expect(o.get(1) == null);
    var alt = "um gato".*;
    try o.put(gpa, 2, .{}, &.{ .{}, .{ .spoiler = true, .alt = &alt } });
    alt[0] = 'X';
    const e = o.get(2).?;
    try std.testing.expectEqual(@as(usize, 2), e.files.len);
    try std.testing.expectEqualStrings("um gato", e.files[1].alt);
    try o.put(gpa, 3, .{ .silent = true }, &.{});
    try std.testing.expect(o.get(3).?.opts.silent and o.get(3).?.files.len == 0);
    o.remove(gpa, 2);
    o.remove(gpa, 99);
    try std.testing.expect(o.get(2) == null);
}
