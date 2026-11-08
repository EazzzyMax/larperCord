//! Status personalizado dentro do protobuf das configurações (tipo 1,
//! `PreloadedUserSettings`, discord-protos):
//!
//!   PreloadedUserSettings { Versions versions = 1; ... StatusSettings status = 11; ... }
//!   Versions       { uint32 client_version = 1; uint32 server_version = 2; uint32 data_version = 3; }
//!   StatusSettings { StringValue status = 1; CustomStatus custom_status = 2;
//!                    BoolValue show_current_game = 3; fixed64 status_expires_at_ms = 4;
//!                    UInt64Value status_created_at_ms = 5; }
//!   CustomStatus   { string text = 1; fixed64 emoji_id = 2; string emoji_name = 3;
//!                    fixed64 expires_at_ms = 4; fixed64 created_at_ms = 5; StringValue label = 6; }
//!
//! A edição preserva os bytes: só o campo 2 de `status` é trocado; o resto
//! de `status` (inclusive campos que não conhecemos) e as outras partes das
//! configurações ficam idênticos. Qualquer coisa que não dê para ler até o
//! fim é recusada: melhor não gravar do que estragar as configurações.
//! O PATCH leva só o campo 11 (o Discord troca só os campos de cima que vierem).
//!
//! O status da conta (online, ausente, não perturbe, invisível) mora no mesmo
//! campo 11: o guardado ali vence o op 3, então mudar o status é gravar aqui
//! também (`editStatus`), do jeito que o cliente oficial grava.
const std = @import("std");
const conta = @import("../core/conta.zig");
const types = @import("../core/types.zig");
const jsonx = @import("jsonx.zig");

pub const Error = error{
    Truncated,
    Malformed,
    /// Campo repetido onde esperamos um só (o protobuf juntaria; nós não).
    Unsupported,
    InvalidBase64,
    OutOfMemory,
};

const status_field = 11;
const custom_field = 2;

const Key = struct { field: u64, wire: u3 };

const Reader = struct {
    buf: []const u8,
    pos: usize = 0,

    fn done(r: *const Reader) bool {
        return r.pos >= r.buf.len;
    }

    fn varint(r: *Reader) Error!u64 {
        var v: u64 = 0;
        var i: u7 = 0;
        while (i < 10) : (i += 1) {
            if (r.pos >= r.buf.len) return error.Truncated;
            const ch = r.buf[r.pos];
            r.pos += 1;
            if (i == 9 and ch > 1) return error.Malformed;
            v |= @as(u64, ch & 0x7f) << @intCast(7 * @as(u7, i));
            if (ch & 0x80 == 0) return v;
        }
        return error.Malformed;
    }

    fn take(r: *Reader, n: u64) Error![]const u8 {
        if (n > r.buf.len - r.pos) return error.Truncated;
        const s = r.buf[r.pos..][0..@intCast(n)];
        r.pos += @intCast(n);
        return s;
    }

    fn key(r: *Reader) Error!Key {
        const k = try r.varint();
        if (k >> 3 == 0) return error.Malformed;
        return .{ .field = k >> 3, .wire = @truncate(k) };
    }

    /// O valor do campo (para tipo 2, só o conteúdo). Grupos: erro.
    fn value(r: *Reader, wire: u3) Error![]const u8 {
        switch (wire) {
            0 => {
                const start = r.pos;
                _ = try r.varint();
                return r.buf[start..r.pos];
            },
            1 => return r.take(8),
            2 => return r.take(try r.varint()),
            5 => return r.take(4),
            else => return error.Malformed,
        }
    }
};

/// Um campo inteiro: onde começa (na chave), onde acaba e o conteúdo.
const Field = struct { key: Key, start: usize, end: usize, data: []const u8 };

fn nextField(r: *Reader) Error!Field {
    const start = r.pos;
    const k = try r.key();
    const data = try r.value(k.wire);
    return .{ .key = k, .start = start, .end = r.pos, .data = data };
}

/// Lê a mensagem inteira (só valida) e acha o campo pedido (um só).
fn findOnly(msg: []const u8, field: u64, wire: u3) Error!?Field {
    var r: Reader = .{ .buf = msg };
    var found: ?Field = null;
    while (!r.done()) {
        const f = try nextField(&r);
        if (f.key.field != field) continue;
        if (f.key.wire != wire) return error.Malformed;
        if (found != null) return error.Unsupported;
        found = f;
    }
    return found;
}

fn validate(msg: []const u8) Error!void {
    var r: Reader = .{ .buf = msg };
    while (!r.done()) _ = try nextField(&r);
}

fn fixed64(data: []const u8) Error!u64 {
    if (data.len != 8) return error.Malformed;
    return std.mem.readInt(u64, data[0..8], .little);
}

/// O status personalizado das configurações (as fatias apontam para `bytes`).
/// null: não tem. Erro: as configurações não dão para ler até o fim.
pub fn read(bytes: []const u8) Error!?conta.CustomStatus {
    const st = try findOnly(bytes, status_field, 2) orelse return null;
    const cf = try findOnly(st.data, custom_field, 2) orelse return null;
    var out: conta.CustomStatus = .{};
    var r: Reader = .{ .buf = cf.data };
    while (!r.done()) {
        const f = try nextField(&r);
        switch (f.key.field) {
            1 => if (f.key.wire == 2) {
                out.text = f.data;
            } else return error.Malformed,
            2 => out.emoji_id = if (f.key.wire == 1) try fixed64(f.data) else return error.Malformed,
            3 => if (f.key.wire == 2) {
                out.emoji_name = f.data;
            } else return error.Malformed,
            4 => out.expires_ms = if (f.key.wire == 1) @intCast(@min(try fixed64(f.data), std.math.maxInt(i64))) else return error.Malformed,
            else => {},
        }
    }
    if (!std.unicode.utf8ValidateSlice(out.text) or !std.unicode.utf8ValidateSlice(out.emoji_name)) return error.Malformed;
    return out;
}

/// `versions.data_version` (para o `required_data_version` do PATCH).
pub fn dataVersion(bytes: []const u8) Error!?u32 {
    const v = try findOnly(bytes, 1, 2) orelse return null;
    const dv = try findOnly(v.data, 3, 0) orelse return null;
    var r: Reader = .{ .buf = dv.data };
    return @truncate(try r.varint());
}

const Writer = struct {
    out: *std.ArrayList(u8),
    gpa: std.mem.Allocator,

    fn varint(w: Writer, v: u64) Error!void {
        var x = v;
        while (x >= 0x80) : (x >>= 7) try w.out.append(w.gpa, @as(u8, @truncate(x)) | 0x80);
        try w.out.append(w.gpa, @truncate(x));
    }
    fn key(w: Writer, field: u64, wire: u3) Error!void {
        try w.varint(field << 3 | wire);
    }
    fn bytes(w: Writer, field: u64, data: []const u8) Error!void {
        try w.key(field, 2);
        try w.varint(data.len);
        try w.out.appendSlice(w.gpa, data);
    }
    fn fixed(w: Writer, field: u64, v: u64) Error!void {
        try w.key(field, 1);
        var b: [8]u8 = undefined;
        std.mem.writeInt(u64, &b, v, .little);
        try w.out.appendSlice(w.gpa, &b);
    }
};

/// `CustomStatus` novo (proto3: campo vazio/zero não vai).
fn encodeCustom(gpa: std.mem.Allocator, s: conta.CustomStatus, now_ms: i64) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const w: Writer = .{ .out = &out, .gpa = gpa };
    if (s.text.len > 0) try w.bytes(1, s.text);
    if (s.emoji_id != 0) try w.fixed(2, s.emoji_id);
    if (s.emoji_name.len > 0) try w.bytes(3, s.emoji_name);
    if (s.expires_ms > 0) try w.fixed(4, @intCast(s.expires_ms));
    if (now_ms > 0) try w.fixed(5, @intCast(now_ms));
    return out.toOwnedSlice(gpa);
}

/// As configurações com o campo 11 trocado por `status` (o conteúdo novo).
/// Fora dele, os bytes são os mesmos e no mesmo lugar; sem campo 11, ele
/// entra no fim.
fn replaceStatus(gpa: std.mem.Allocator, bytes: []const u8, st: ?Field, status: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const w: Writer = .{ .out = &out, .gpa = gpa };
    if (st) |f| {
        try out.appendSlice(gpa, bytes[0..f.start]);
        try w.bytes(status_field, status);
        try out.appendSlice(gpa, bytes[f.end..]);
    } else {
        try out.appendSlice(gpa, bytes);
        try w.bytes(status_field, status);
    }
    return out.toOwnedSlice(gpa);
}

/// As configurações inteiras com o status personalizado trocado (`new`
/// vazio = tira). Fora o campo 11, os bytes são os mesmos e no mesmo lugar;
/// dentro dele, só o campo 2 muda. Sem campo 11, ele entra no fim.
pub fn edit(gpa: std.mem.Allocator, bytes: []const u8, new: conta.CustomStatus, now_ms: i64) Error![]u8 {
    if (!std.unicode.utf8ValidateSlice(new.text) or !std.unicode.utf8ValidateSlice(new.emoji_name)) return error.Malformed;
    try validate(bytes);
    const st = try findOnly(bytes, status_field, 2);
    const old_status: []const u8 = if (st) |f| f.data else "";
    const old_custom = try findOnly(old_status, custom_field, 2);
    if (old_custom) |cf| try validate(cf.data);

    // `status` novo: tudo igual, com o campo 2 trocado (ou tirado) no mesmo lugar.
    var status: std.ArrayList(u8) = .empty;
    defer status.deinit(gpa);
    const sw: Writer = .{ .out = &status, .gpa = gpa };
    const custom: ?[]u8 = if (new.empty()) null else try encodeCustom(gpa, new, now_ms);
    defer if (custom) |x| gpa.free(x);
    if (old_custom) |cf| {
        try status.appendSlice(gpa, old_status[0..cf.start]);
        if (custom) |x| try sw.bytes(custom_field, x);
        try status.appendSlice(gpa, old_status[cf.end..]);
    } else {
        try status.appendSlice(gpa, old_status);
        if (custom) |x| try sw.bytes(custom_field, x);
    }
    return replaceStatus(gpa, bytes, st, status.items);
}

// --- O status da conta -----------------------------------------------------------

/// O nome do status nas configurações e no op 3 (offline = invisível para os outros).
pub fn statusName(s: types.Status) []const u8 {
    return switch (s) {
        .online => "online",
        .idle => "idle",
        .dnd => "dnd",
        .offline => "invisible",
    };
}

/// O status de um nome das configurações (null = um que o app não conhece).
pub fn statusFromName(name: []const u8) ?types.Status {
    const eql = std.mem.eql;
    if (eql(u8, name, "online")) return .online;
    if (eql(u8, name, "idle")) return .idle;
    if (eql(u8, name, "dnd")) return .dnd;
    if (eql(u8, name, "invisible") or eql(u8, name, "offline")) return .offline;
    return null;
}

/// O status guardado na conta (campo 11 das configurações).
pub const Stored = struct {
    /// null: não veio, ou é um nome que o app não conhece.
    status: ?types.Status = null,
    /// Até quando vale (ms desde 1970); 0 = até a pessoa mudar.
    expires_ms: i64 = 0,
    /// `show_current_game` (mostrar a atividade); null = não veio.
    show_game: ?bool = null,

    /// O prazo passou: o status volta a online.
    pub fn expired(s: Stored, now_ms: i64) bool {
        return s.expires_ms > 0 and s.expires_ms <= now_ms;
    }
};

/// As partes do `StatusSettings` que o app entende (fatias do conteúdo).
const Parts = struct {
    /// Conteúdo do StringValue.
    status: ?[]const u8 = null,
    /// O campo 2 inteiro (chave, tamanho e conteúdo), como veio.
    custom: ?Field = null,
    /// Conteúdo do BoolValue.
    show_game: ?[]const u8 = null,
    expires: ?u64 = null,
    created: bool = false,
};

/// Lê o `StatusSettings` inteiro: tipo de fio errado ou campo conhecido
/// repetido é recusado, como no resto do arquivo.
fn parts(data: []const u8) Error!Parts {
    var out: Parts = .{};
    var r: Reader = .{ .buf = data };
    while (!r.done()) {
        const f = try nextField(&r);
        const want: u3 = switch (f.key.field) {
            1, 2, 3, 5 => 2,
            4 => 1,
            else => continue,
        };
        if (f.key.wire != want) return error.Malformed;
        const dup = switch (f.key.field) {
            1 => out.status != null,
            2 => out.custom != null,
            3 => out.show_game != null,
            4 => out.expires != null,
            else => out.created,
        };
        if (dup) return error.Unsupported;
        switch (f.key.field) {
            1 => out.status = f.data,
            2 => out.custom = f,
            3 => out.show_game = f.data,
            4 => out.expires = try fixed64(f.data),
            else => out.created = true,
        }
    }
    return out;
}

/// O texto de dentro de um StringValue (campo 1; sem ele, vazio).
fn wrappedString(content: []const u8) Error![]const u8 {
    const f = try findOnly(content, 1, 2) orelse return "";
    if (!std.unicode.utf8ValidateSlice(f.data)) return error.Malformed;
    return f.data;
}

/// O valor de dentro de um BoolValue (campo 1; sem ele, false).
fn wrappedBool(content: []const u8) Error!bool {
    const f = try findOnly(content, 1, 0) orelse return false;
    var r: Reader = .{ .buf = f.data };
    return (try r.varint()) != 0;
}

/// O status guardado nas configurações. null: não tem campo 11. Erro: as
/// configurações não dão para ler até o fim.
pub fn readStatus(bytes: []const u8) Error!?Stored {
    const st = try findOnly(bytes, status_field, 2) orelse return null;
    const p = try parts(st.data);
    return .{
        .status = if (p.status) |s| statusFromName(try wrappedString(s)) else null,
        .expires_ms = if (p.expires) |e| @intCast(@min(e, std.math.maxInt(i64))) else 0,
        .show_game = if (p.show_game) |b| try wrappedBool(b) else null,
    };
}

/// O `StatusSettings` que vai no PATCH, campo a campo na ordem do protobuf
/// (1 a 5 e depois o resto), como o cliente oficial manda.
pub const StatusFields = struct {
    status: types.Status,
    /// O status personalizado que já estava (o campo 2 inteiro, como veio).
    custom: []const u8 = "",
    /// `show_current_game` como estava guardado; null não vai (não mexe nele).
    show_game: ?bool = null,
    /// 0 = até a pessoa mudar (o campo 4 não vai).
    expires_ms: i64 = 0,
    /// `status_created_at_ms`: a hora da escolha.
    created_ms: i64 = 0,
    /// Campos que o app não conhece, inteiros e na ordem em que vieram.
    unknown: []const u8 = "",
};

fn varintInto(buf: []u8, v: u64) usize {
    var x = v;
    var n: usize = 0;
    while (x >= 0x80) : (x >>= 7) {
        buf[n] = @as(u8, @truncate(x)) | 0x80;
        n += 1;
    }
    buf[n] = @truncate(x);
    return n + 1;
}

fn writeStatusContent(w: Writer, f: StatusFields) Error!void {
    // StringValue { 1: nome } (os nomes cabem num byte de tamanho).
    const name = statusName(f.status);
    var sb: [16]u8 = undefined;
    sb[0] = 0x0a;
    sb[1] = @intCast(name.len);
    @memcpy(sb[2..][0..name.len], name);
    try w.bytes(1, sb[0 .. 2 + name.len]);
    try w.out.appendSlice(w.gpa, f.custom);
    // BoolValue: false é a mensagem vazia (o padrão do proto3 não vai).
    if (f.show_game) |on| try w.bytes(3, if (on) &.{ 0x08, 0x01 } else &.{});
    if (f.expires_ms > 0) try w.fixed(4, @intCast(f.expires_ms));
    if (f.created_ms > 0) {
        // UInt64Value { 1: ms }.
        var cb: [11]u8 = undefined;
        cb[0] = 0x08;
        const n = varintInto(cb[1..], @intCast(f.created_ms));
        try w.bytes(5, cb[0 .. 1 + n]);
    }
    try w.out.appendSlice(w.gpa, f.unknown);
}

/// Só o campo 11 com o status de `f`: as configurações parciais do PATCH.
pub fn encodeStatus(gpa: std.mem.Allocator, f: StatusFields) Error![]u8 {
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    try writeStatusContent(.{ .out = &content, .gpa = gpa }, f);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try (Writer{ .out = &out, .gpa = gpa }).bytes(status_field, content.items);
    return out.toOwnedSlice(gpa);
}

/// As configurações inteiras com o status da conta trocado: o campo 11 sai
/// de novo com o status, o prazo (`expires_ms` 0 = até mudar) e a hora da
/// escolha; o status personalizado, o `show_current_game` e os campos
/// desconhecidos continuam como estavam. Fora do campo 11, nada muda.
pub fn editStatus(gpa: std.mem.Allocator, bytes: []const u8, status: types.Status, expires_ms: i64, now_ms: i64) Error![]u8 {
    try validate(bytes);
    const st = try findOnly(bytes, status_field, 2);
    const old: []const u8 = if (st) |f| f.data else "";
    const p = try parts(old);
    if (p.custom) |cf| try validate(cf.data);
    var unknown: std.ArrayList(u8) = .empty;
    defer unknown.deinit(gpa);
    var r: Reader = .{ .buf = old };
    while (!r.done()) {
        const f = try nextField(&r);
        if (f.key.field > 5) try unknown.appendSlice(gpa, old[f.start..f.end]);
    }
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    try writeStatusContent(.{ .out = &content, .gpa = gpa }, .{
        .status = status,
        .custom = if (p.custom) |cf| old[cf.start..cf.end] else "",
        .show_game = if (p.show_game) |b| try wrappedBool(b) else null,
        .expires_ms = expires_ms,
        .created_ms = now_ms,
        .unknown = unknown.items,
    });
    return replaceStatus(gpa, bytes, st, content.items);
}

/// Só o campo 11, como mensagem própria: o corpo do PATCH.
pub fn statusOnly(gpa: std.mem.Allocator, bytes: []const u8) Error![]u8 {
    const st = try findOnly(bytes, status_field, 2) orelse return gpa.alloc(u8, 0);
    return gpa.dupe(u8, bytes[st.start..st.end]);
}

pub fn decodeBase64(gpa: std.mem.Allocator, b64: []const u8) Error![]u8 {
    const src = std.mem.trim(u8, b64, " \t\r\n");
    const dec = if (std.mem.endsWith(u8, src, "=")) std.base64.standard.Decoder else std.base64.standard_no_pad.Decoder;
    const n = dec.calcSizeForSlice(src) catch return error.InvalidBase64;
    const buf = try gpa.alloc(u8, n);
    errdefer gpa.free(buf);
    dec.decode(buf, src) catch return error.InvalidBase64;
    return buf;
}

pub fn encodeBase64(gpa: std.mem.Allocator, bytes: []const u8) Error![]u8 {
    const enc = std.base64.standard.Encoder;
    const buf = try gpa.alloc(u8, enc.calcSize(bytes.len));
    _ = enc.encode(buf, bytes);
    return buf;
}

/// `{"settings":"<só o campo 11 editado>","required_data_version":N}`.
pub fn patchBody(ar: std.mem.Allocator, b64: []const u8, cs: conta.CustomStatus, now_ms: i64) Error![]u8 {
    const bytes = try decodeBase64(ar, b64);
    return jsonBody(ar, bytes, try edit(ar, bytes, cs, now_ms));
}

/// O mesmo corpo, com o status da conta trocado (`editStatus`).
pub fn statusPatchBody(ar: std.mem.Allocator, b64: []const u8, status: types.Status, expires_ms: i64, now_ms: i64) Error![]u8 {
    const bytes = try decodeBase64(ar, b64);
    return jsonBody(ar, bytes, try editStatus(ar, bytes, status, expires_ms, now_ms));
}

/// O JSON do PATCH: só o campo 11 de `edited` e a versão das configurações lidas (`bytes`).
fn jsonBody(ar: std.mem.Allocator, bytes: []const u8, edited: []const u8) Error![]u8 {
    const only = try statusOnly(ar, edited);
    const enc = try encodeBase64(ar, only);
    var out: std.ArrayList(u8) = .empty;
    try out.print(ar, "{{\"settings\":\"{s}\"", .{enc});
    if (try dataVersion(bytes)) |dv| try out.print(ar, ",\"required_data_version\":{d}", .{dv});
    try out.append(ar, '}');
    return out.toOwnedSlice(ar);
}

test "corpo do PATCH do status: só o campo 11 e a versão" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    // versions { data_version: 9 } + pastas (14); sem status.
    const src = [_]u8{ 0x0a, 0x02, 0x18, 0x09, 0x72, 0x00 };
    const b64 = try encodeBase64(ar, &src);
    const body = try patchBody(ar, b64, .{ .text = "oi" }, 0);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, ar, body, .{});
    try std.testing.expectEqual(@as(?i64, 9), jsonx.int(jsonx.get(v, "required_data_version")));
    const sent = try decodeBase64(ar, jsonx.str(jsonx.get(v, "settings")).?);
    // 0x5a = campo 11, tipo 2: só ele vai.
    try std.testing.expectEqual(@as(u8, 0x5a), sent[0]);
    try std.testing.expectEqualStrings("oi", (try read(sent)).?.text);
    // Lixo no lugar das configurações: erro, nada sai.
    try std.testing.expectError(error.Truncated, patchBody(ar, try encodeBase64(ar, &.{ 0x5a, 0x09 }), .{}, 0));
}

// ---------------------------------------------------------------------------

/// Configurações de exemplo: versões, um campo desconhecido antes e um
/// depois do status, e dentro do status o texto do status, o custom, um
/// desconhecido (99) e o show_current_game.
fn sample(gpa: std.mem.Allocator, with_custom: bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const w: Writer = .{ .out = &out, .gpa = gpa };
    // versions { client_version: 7, data_version: 42 }
    try w.bytes(1, &.{ 0x08, 0x07, 0x18, 42 });
    // Um campo de outra parte (texto e imagens = 6), qualquer conteúdo.
    try w.bytes(6, &.{ 0x0a, 0x02, 0x08, 0x01, 0x10, 0x05 });
    var st: std.ArrayList(u8) = .empty;
    defer st.deinit(gpa);
    const sw: Writer = .{ .out = &st, .gpa = gpa };
    try sw.bytes(1, &.{ 0x0a, 0x03, 'd', 'n', 'd' });
    if (with_custom) {
        var cs: std.ArrayList(u8) = .empty;
        defer cs.deinit(gpa);
        const cw: Writer = .{ .out = &cs, .gpa = gpa };
        try cw.bytes(1, "almoçando");
        try cw.bytes(3, "🍝");
        try cw.fixed(4, 1_900_000_000_000);
        try cw.fixed(5, 1_800_000_000_000);
        try sw.bytes(2, cs.items);
    }
    // Campo novo que ainda não conhecemos, tipo varint e fixed32.
    try sw.key(99, 0);
    try sw.varint(300);
    try sw.key(98, 5);
    try st.appendSlice(gpa, &.{ 1, 2, 3, 4 });
    try sw.bytes(3, &.{ 0x08, 0x01 });
    try w.bytes(11, st.items);
    // Pastas (14) depois do status.
    try w.bytes(14, &.{ 0x12, 0x08, 1, 0, 0, 0, 0, 0, 0, 0 });
    return out.toOwnedSlice(gpa);
}

test "lê o status personalizado e a versão" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    const s = (try read(b)).?;
    try std.testing.expectEqualStrings("almoçando", s.text);
    try std.testing.expectEqualStrings("🍝", s.emoji_name);
    try std.testing.expectEqual(@as(i64, 1_900_000_000_000), s.expires_ms);
    try std.testing.expectEqual(@as(?u32, 42), try dataVersion(b));
    const none = try sample(gpa, false);
    defer gpa.free(none);
    try std.testing.expect((try read(none)) == null);
    try std.testing.expect((try read("")) == null);
}

test "editar troca só o status personalizado, byte a byte" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    const e = try edit(gpa, b, .{ .text = "no ar", .emoji_name = "🎧", .expires_ms = 1_950_000_000_000 }, 1_940_000_000_000);
    defer gpa.free(e);
    const s = (try read(e)).?;
    try std.testing.expectEqualStrings("no ar", s.text);
    try std.testing.expectEqualStrings("🎧", s.emoji_name);
    try std.testing.expectEqual(@as(i64, 1_950_000_000_000), s.expires_ms);
    // Antes e depois do campo 11, tudo igual.
    const old = (try findOnly(b, 11, 2)).?;
    const now = (try findOnly(e, 11, 2)).?;
    try std.testing.expectEqualSlices(u8, b[0..old.start], e[0..now.start]);
    try std.testing.expectEqualSlices(u8, b[old.end..], e[now.end..]);
    // Dentro dele, o que vem antes e depois do campo 2 (com os desconhecidos) também.
    const oc = (try findOnly(old.data, 2, 2)).?;
    const nc = (try findOnly(now.data, 2, 2)).?;
    try std.testing.expectEqualSlices(u8, old.data[0..oc.start], now.data[0..nc.start]);
    try std.testing.expectEqualSlices(u8, old.data[oc.end..], now.data[nc.end..]);
    // Voltar ao que era devolve exatamente os bytes de antes (com a mesma data de criação).
    const back = try edit(gpa, e, .{ .text = "almoçando", .emoji_name = "🍝", .expires_ms = 1_900_000_000_000 }, 1_800_000_000_000);
    defer gpa.free(back);
    try std.testing.expectEqualSlices(u8, b, back);
}

test "limpar tira só o campo 2; sem status, ele entra no fim" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    const cleared = try edit(gpa, b, .{}, 5);
    defer gpa.free(cleared);
    try std.testing.expect((try read(cleared)) == null);
    const plain = try sample(gpa, false);
    defer gpa.free(plain);
    try std.testing.expectEqualSlices(u8, plain, cleared);
    // Configurações sem o campo 11: o resto fica, o status novo vai no fim.
    const bare = [_]u8{ 0x0a, 0x02, 0x18, 0x05 };
    const added = try edit(gpa, &bare, .{ .text = "oi" }, 0);
    defer gpa.free(added);
    try std.testing.expectEqualSlices(u8, &bare, added[0..bare.len]);
    try std.testing.expectEqualStrings("oi", (try read(added)).?.text);
    // O PATCH leva só o campo 11.
    const only = try statusOnly(gpa, added);
    defer gpa.free(only);
    try std.testing.expectEqualSlices(u8, added[bare.len..], only);
}

test "entrada malformada ou incompleta é recusada" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    // Cortada em qualquer ponto: nunca grava.
    var cut: usize = 1;
    while (cut < b.len) : (cut += 1) {
        if (edit(gpa, b[0..cut], .{ .text = "x" }, 0)) |out| {
            gpa.free(out);
            // Só passa quando o corte cai entre dois campos inteiros de cima.
            try validate(b[0..cut]);
        } else |err| try std.testing.expect(err == error.Truncated or err == error.Malformed or err == error.Unsupported);
    }
    // Grupo (tipo 3), campo 0, varint longo demais.
    try std.testing.expectError(error.Malformed, edit(gpa, &.{0x0b}, .{}, 0));
    try std.testing.expectError(error.Malformed, edit(gpa, &.{ 0x00, 0x01 }, .{}, 0));
    try std.testing.expectError(error.Malformed, edit(gpa, &.{ 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f }, .{}, 0));
    // Status com tipo de fio errado, ou repetido.
    try std.testing.expectError(error.Malformed, edit(gpa, &.{ 0x58, 0x01 }, .{}, 0));
    try std.testing.expectError(error.Unsupported, edit(gpa, &.{ 0x5a, 0x00, 0x5a, 0x00 }, .{}, 0));
    // Custom status antigo quebrado por dentro.
    try std.testing.expectError(error.Truncated, edit(gpa, &.{ 0x5a, 0x03, 0x12, 0x01, 0x0a }, .{}, 0));
    // Texto que não é UTF-8.
    try std.testing.expectError(error.Malformed, edit(gpa, &.{}, .{ .text = "\xff" }, 0));
    try std.testing.expectError(error.InvalidBase64, decodeBase64(gpa, "@@@"));
}

/// Os corpos que o cliente oficial mandou (base64 do proto), com as horas de lá.
const official_idle = "WhMKBgoEaWRsZRoAKgcIrbXbw5s0";
const official_invisible_until = "WiEKCwoJaW52aXNpYmxlGgAhHCvqx6EBAAAqBwicrtzDmzQ=";
const official_invisible = "WhgKCwoJaW52aXNpYmxlGgAqBwicrtzDmzQ=";

test "o status sai com os mesmos bytes do cliente oficial" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    const cases = [_]struct { f: StatusFields, want: []const u8 }{
        .{ .f = .{ .status = .idle, .show_game = false, .created_ms = 1794096159405 }, .want = official_idle },
        .{ .f = .{ .status = .offline, .show_game = false, .expires_ms = 1794355374876, .created_ms = 1794096174876 }, .want = official_invisible_until },
        .{ .f = .{ .status = .offline, .show_game = false, .created_ms = 1794096174876 }, .want = official_invisible },
    };
    for (cases) |cs| {
        try std.testing.expectEqualSlices(u8, try decodeBase64(ar, cs.want), try encodeStatus(ar, cs.f));
        // Editando as configurações guardadas (o show_current_game vazio de lá), o PATCH é o mesmo.
        const stored = [_]u8{ 0x0a, 0x02, 0x18, 0x07, 0x5a, 0x0c, 0x0a, 0x08, 0x0a, 0x06, 'o', 'n', 'l', 'i', 'n', 'e', 0x1a, 0x00, 0x72, 0x00 };
        const edited = try editStatus(ar, &stored, cs.f.status, cs.f.expires_ms, cs.f.created_ms);
        try std.testing.expectEqualSlices(u8, try decodeBase64(ar, cs.want), try statusOnly(ar, edited));
        // Fora do campo 11, nada muda.
        try std.testing.expectEqualSlices(u8, stored[0..4], edited[0..4]);
        try std.testing.expectEqualSlices(u8, &.{ 0x72, 0x00 }, edited[edited.len - 2 ..]);
    }
    // Mostrar a atividade ligado: vai ligado (o cliente oficial manda vazio, que desligaria).
    const on = try encodeStatus(ar, .{ .status = .dnd, .show_game = true, .created_ms = 5 });
    try std.testing.expectEqual(@as(?bool, true), (try readStatus(on)).?.show_game);
    // Sem nada guardado, o campo 3 nem vai: o Discord não mexe nele.
    const bare = try statusOnly(ar, try editStatus(ar, "", .online, 0, 5));
    try std.testing.expectEqualSlices(u8, &.{ 0x5a, 0x0e, 0x0a, 0x08, 0x0a, 0x06, 'o', 'n', 'l', 'i', 'n', 'e', 0x2a, 0x02, 0x08, 0x05 }, bare);
}

test "trocar o status mantém o status personalizado e o resto do campo 11" {
    const gpa = std.testing.allocator;
    // sample(): status "dnd", custom, campos 99 e 98 desconhecidos, show_current_game ligado.
    const b = try sample(gpa, true);
    defer gpa.free(b);
    const was = (try readStatus(b)).?;
    try std.testing.expectEqual(@as(?types.Status, .dnd), was.status);
    try std.testing.expectEqual(@as(?bool, true), was.show_game);
    const e = try editStatus(gpa, b, .idle, 1_900_000_000_000, 1_800_000_000_000);
    defer gpa.free(e);
    const now = (try readStatus(e)).?;
    try std.testing.expectEqual(@as(?types.Status, .idle), now.status);
    try std.testing.expectEqual(@as(i64, 1_900_000_000_000), now.expires_ms);
    try std.testing.expectEqual(@as(?bool, true), now.show_game);
    // O status personalizado é o mesmo, byte a byte.
    const cs = (try read(e)).?;
    try std.testing.expectEqualStrings("almoçando", cs.text);
    const oc = (try findOnly((try findOnly(b, 11, 2)).?.data, 2, 2)).?;
    const nc = (try findOnly((try findOnly(e, 11, 2)).?.data, 2, 2)).?;
    try std.testing.expectEqualSlices(u8, oc.data, nc.data);
    // Os desconhecidos continuam, na ordem, depois dos conhecidos.
    const st = (try findOnly(e, 11, 2)).?.data;
    try std.testing.expect(std.mem.endsWith(u8, st, &.{ 0x98, 0x06, 0xac, 0x02, 0x95, 0x06, 1, 2, 3, 4 }));
    // Antes e depois do campo 11, tudo igual.
    const of = (try findOnly(b, 11, 2)).?;
    const nf = (try findOnly(e, 11, 2)).?;
    try std.testing.expectEqualSlices(u8, b[0..of.start], e[0..nf.start]);
    try std.testing.expectEqualSlices(u8, b[of.end..], e[nf.end..]);
    // Voltar para "até mudar" tira o prazo.
    const f = try editStatus(gpa, e, .online, 0, 1_800_000_000_001);
    defer gpa.free(f);
    try std.testing.expectEqual(@as(i64, 0), (try readStatus(f)).?.expires_ms);
}

test "ler o status guardado: nomes, prazo e o que vence" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    const s = (try readStatus(try decodeBase64(ar, official_invisible_until))).?;
    try std.testing.expectEqual(@as(?types.Status, .offline), s.status);
    try std.testing.expectEqual(@as(i64, 1794355374876), s.expires_ms);
    try std.testing.expectEqual(@as(?bool, false), s.show_game);
    try std.testing.expect(!s.expired(1794355374875) and s.expired(1794355374876));
    // Até mudar nunca vence.
    try std.testing.expect(!(try readStatus(try decodeBase64(ar, official_idle))).?.expired(std.math.maxInt(i64)));
    // Nome que o app não conhece, campo 11 sem status, configurações sem campo 11.
    try std.testing.expectEqual(@as(?types.Status, null), (try readStatus(&.{ 0x5a, 0x06, 0x0a, 0x04, 0x0a, 0x02, 'z', 'z' })).?.status);
    try std.testing.expectEqual(@as(?types.Status, null), (try readStatus(&.{ 0x5a, 0x02, 0x1a, 0x00 })).?.status);
    try std.testing.expect((try readStatus(&.{ 0x0a, 0x02, 0x18, 0x01 })) == null);
    for ([_]types.Status{ .online, .idle, .dnd, .offline }) |st| try std.testing.expectEqual(@as(?types.Status, st), statusFromName(statusName(st)));
    // Tipo de fio errado, campo repetido ou cortado: recusa (nada é gravado em cima).
    try std.testing.expectError(error.Malformed, readStatus(&.{ 0x5a, 0x02, 0x20, 0x01 }));
    try std.testing.expectError(error.Unsupported, editStatus(ar, &.{ 0x5a, 0x04, 0x1a, 0x00, 0x1a, 0x00 }, .idle, 0, 1));
    try std.testing.expectError(error.Truncated, editStatus(ar, &.{ 0x5a, 0x03, 0x0a, 0x05, 0x0a }, .idle, 0, 1));
    try std.testing.expectError(error.Malformed, readStatus(&.{ 0x5a, 0x05, 0x0a, 0x03, 0x0a, 0x01, 0xff }));
}

test "corpo do PATCH do status da conta: só o campo 11 e a versão" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const ar = a.allocator();
    const src = [_]u8{ 0x0a, 0x02, 0x18, 0x09, 0x72, 0x00 };
    const body = try statusPatchBody(ar, try encodeBase64(ar, &src), .dnd, 7_000, 6_000);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, ar, body, .{});
    try std.testing.expectEqual(@as(?i64, 9), jsonx.int(jsonx.get(v, "required_data_version")));
    const sent = try decodeBase64(ar, jsonx.str(jsonx.get(v, "settings")).?);
    try std.testing.expectEqual(@as(u8, 0x5a), sent[0]);
    const s = (try readStatus(sent)).?;
    try std.testing.expectEqual(@as(?types.Status, .dnd), s.status);
    try std.testing.expectEqual(@as(i64, 7_000), s.expires_ms);
}

test "status da conta sem vazamento quando falta memória" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn f(a: std.mem.Allocator, bytes: []const u8) !void {
            const e = try editStatus(a, bytes, .idle, 10, 1);
            a.free(e);
            const o = try encodeStatus(a, .{ .status = .dnd, .show_game = true, .created_ms = 1 });
            a.free(o);
        }
    }.f, .{b});
}

test "base64 vai e volta" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    const s = try encodeBase64(gpa, b);
    defer gpa.free(s);
    const back = try decodeBase64(gpa, s);
    defer gpa.free(back);
    try std.testing.expectEqualSlices(u8, b, back);
}

test "sem vazamento quando falta memória" {
    const gpa = std.testing.allocator;
    const b = try sample(gpa, true);
    defer gpa.free(b);
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn f(a: std.mem.Allocator, bytes: []const u8) !void {
            const e = try edit(a, bytes, .{ .text = "x", .emoji_name = "y" }, 1);
            a.free(e);
        }
    }.f, .{b});
}
