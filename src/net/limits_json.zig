//! Os limites de envio no JSON do Discord (sem rede, para dar para testar):
//! modo lento do canal, castigo e flags do nosso membro, flags da conta, o
//! tempo que falta no modo lento (POST de "digitando") e o 429 do envio.
const std = @import("std");
const j = @import("jsonx.zig");
const limites = @import("../core/limites.zig");
const Value = std.json.Value;

/// `rate_limit_per_user` (s) de um canal ou thread; fora da faixa vira 0 ou o teto.
pub fn slowmodeOf(cv: Value) u32 {
    const s = j.int(j.get(cv, "rate_limit_per_user")) orelse return 0;
    return @intCast(std.math.clamp(s, 0, limites.max_slowmode_s));
}

/// Do nosso membro num servidor. null = o campo não veio (objeto parcial: fica
/// o que era); `timeout_until_ms` 0 = sem castigo (null no Discord).
pub const MemberLimits = struct { timeout_until_ms: ?i64 = null, flags: ?u64 = null };

pub fn memberLimitsOf(m: Value) MemberLimits {
    var out: MemberLimits = .{};
    if (j.get(m, "communication_disabled_until")) |v| {
        out.timeout_until_ms = if (j.str(v)) |iso| j.isoTime(iso) * 1000 else 0;
    }
    if (j.int(j.get(m, "flags"))) |f| out.flags = @as(u64, @bitCast(f));
    return out;
}

/// As `flags` da conta (null = não vieram; READY e USER_UPDATE trazem).
pub fn userFlagsOf(u: Value) ?u64 {
    const f = j.int(j.get(u, "flags")) orelse return null;
    return @as(u64, @bitCast(f));
}

/// Segundos do servidor em ms: nada de negativo, NaN ou mais que o maior modo lento (com folga).
fn secondsMs(f: f64) ?u32 {
    if (!(f > 0) or f > 2 * @as(f64, limites.max_slowmode_s)) return null;
    return @intFromFloat(@ceil(f * 1000));
}

/// POST /channels/{id}/typing responde 200 (e não 204) quando o modo lento
/// ainda corre: `message_send_cooldown_ms` é quanto falta.
pub fn typingCooldownMs(body: []const u8) ?u32 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return null;
    const ms = j.int(j.get(v, "message_send_cooldown_ms")) orelse return null;
    if (ms <= 0) return null;
    return @intCast(@min(ms, 2 * @as(i64, limites.max_slowmode_s) * 1000));
}

/// 429: quanto esperar (`retry_after`, segundos com fração; senão o cabeçalho
/// Retry-After, senão 1 s) e se é o limite global da conta.
pub const Limited = struct { ms: u32, global: bool };

pub fn rateLimited(body: []const u8, header_ms: ?u32, header_global: bool) Limited {
    var out: Limited = .{ .ms = header_ms orelse 1000, .global = header_global };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return out;
    if (j.get(v, "retry_after")) |ra| {
        const f: ?f64 = switch (ra) {
            .float => |x| x,
            .integer => |x| @floatFromInt(x),
            else => null,
        };
        if (f) |x| if (secondsMs(x)) |ms| {
            out.ms = ms;
        };
    }
    if (j.get(v, "global")) |gv| if (gv == .bool and gv.bool) {
        out.global = true;
    };
    return out;
}

// --- Testes -------------------------------------------------------------------

const t = std.testing;

fn parse(arena: *std.heap.ArenaAllocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, arena.allocator(), text, .{});
}

test "modo lento do canal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqual(@as(u32, 10), slowmodeOf(try parse(&arena, "{\"id\":\"1\",\"rate_limit_per_user\":10}")));
    try t.expectEqual(@as(u32, 0), slowmodeOf(try parse(&arena, "{\"id\":\"1\"}")));
    try t.expectEqual(@as(u32, 0), slowmodeOf(try parse(&arena, "{\"rate_limit_per_user\":-3}")));
    try t.expectEqual(@as(u32, 21600), slowmodeOf(try parse(&arena, "{\"rate_limit_per_user\":999999}")));
}

test "castigo e flags do nosso membro" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const on = memberLimitsOf(try parse(&arena, "{\"roles\":[],\"communication_disabled_until\":\"2026-11-07T20:30:00.000000+00:00\",\"flags\":128}"));
    try t.expectEqual(@as(?i64, j.isoTime("2026-11-07T20:30:00") * 1000), on.timeout_until_ms);
    try t.expectEqual(@as(?u64, 128), on.flags);
    // null = castigo tirado; campo ausente = não diz nada.
    const off = memberLimitsOf(try parse(&arena, "{\"communication_disabled_until\":null}"));
    try t.expectEqual(@as(?i64, 0), off.timeout_until_ms);
    try t.expectEqual(@as(?u64, null), off.flags);
    const partial = memberLimitsOf(try parse(&arena, "{\"roles\":[\"5\"]}"));
    try t.expectEqual(@as(?i64, null), partial.timeout_until_ms);
    try t.expectEqual(@as(?u64, null), partial.flags);
}

test "flags da conta: quarentena" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const f = userFlagsOf(try parse(&arena, "{\"id\":\"1\",\"flags\":17592186044416}")).?;
    try t.expect(f & limites.user_quarantined != 0);
    try t.expectEqual(@as(?u64, null), userFlagsOf(try parse(&arena, "{\"id\":\"1\"}")));
}

test "digitando com o modo lento correndo" {
    try t.expectEqual(@as(?u32, 7250), typingCooldownMs("{\"message_send_cooldown_ms\":7250,\"thread_create_cooldown_ms\":0}"));
    try t.expectEqual(@as(?u32, null), typingCooldownMs("{\"thread_create_cooldown_ms\":500}"));
    try t.expectEqual(@as(?u32, null), typingCooldownMs("{\"message_send_cooldown_ms\":0}"));
    try t.expectEqual(@as(?u32, null), typingCooldownMs(""));
    try t.expectEqual(@as(?u32, 43_200_000), typingCooldownMs("{\"message_send_cooldown_ms\":99999999999}"));
}

test "429 do envio" {
    const a = rateLimited("{\"message\":\"You are being rate limited.\",\"retry_after\":4.2,\"global\":false}", 5000, false);
    try t.expectEqual(@as(u32, 4200), a.ms);
    try t.expect(!a.global);
    const b = rateLimited("{\"retry_after\":1,\"global\":true}", null, false);
    try t.expectEqual(@as(u32, 1000), b.ms);
    try t.expect(b.global);
    // Corpo estranho: fica o cabeçalho (ou 1 s).
    try t.expectEqual(@as(u32, 3000), rateLimited("<html>", 3000, false).ms);
    try t.expectEqual(@as(u32, 1000), rateLimited("{\"retry_after\":-1}", null, false).ms);
    try t.expect(rateLimited("{}", null, true).global);
}
