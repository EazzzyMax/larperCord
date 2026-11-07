//! Por que não dá para enviar agora: o motivo que a caixa de texto mostra no
//! lugar de deixar a pessoa escrever e levar um erro. Lógica pura, sem
//! interface nem rede. `pick` é o único lugar que decide o motivo; quem
//! desenha (ui/composer_limits.zig) só traduz.
//!
//! Regras (docs.discord.food):
//!  - modo lento: `rate_limit_per_user` (s, até 21600) no canal ou na thread;
//!    quem tem MANAGE_MESSAGES ou MANAGE_CHANNELS não é afetado;
//!  - castigo: `communication_disabled_until` no nosso membro; perde tudo menos
//!    VIEW_CHANNEL e READ_MESSAGE_HISTORY; dono e ADMINISTRATOR ficam de fora;
//!  - quarentena do AutoMod (flags de membro 1 << 7 e 1 << 10): "prevented from
//!    interacting with the guild in any way", como no castigo;
//!  - quarentena da conta (flag de usuário 1 << 44): não abre DMs nem aceita
//!    convites (não impede escrever num canal que já existe).
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;

const all: u64 = std.math.maxInt(u64);
/// Só esta parte usa (o resto das permissões está em types.perm).
const manage_channels: u64 = 1 << 4;

/// AUTOMOD_QUARANTINED_NAME e AUTOMOD_QUARANTINED_GUILD_TAG (a do bio saiu de uso).
pub const member_quarantine: u64 = (1 << 7) | (1 << 10);
/// QUARANTINED, nas flags da conta.
pub const user_quarantined: u64 = 1 << 44;
/// O maior modo lento que o Discord aceita (6 h).
pub const max_slowmode_s: u32 = 21600;

/// Na ordem em que `pick` confere: o primeiro que vale é o que aparece.
/// Motivo novo (a triagem de regras pendente, por exemplo): um valor aqui,
/// um campo em `Input` e um caso em `pick`.
pub const Reason = enum {
    none,
    timed_out,
    quarantined,
    thread_locked,
    thread_no_permission,
    no_permission,
    slowmode,
    /// O Discord recusou o envio (429) sem modo lento que valha para nós (o
    /// limite do canal para mensagens seguidas): espera do mesmo jeito.
    rate_limited,

    /// A caixa some e fica só o aviso. Na contagem dá para ir escrevendo a
    /// próxima (Enter só não manda).
    pub fn blocksInput(r: Reason) bool {
        return switch (r) {
            .none, .slowmode, .rate_limited => false,
            else => true,
        };
    }

    /// Uma contagem até poder enviar de novo (modo lento ou 429).
    pub fn cooling(r: Reason) bool {
        return r == .slowmode or r == .rate_limited;
    }
};

pub const Input = struct {
    /// 0 = DM (não tem castigo, quarentena de servidor nem modo lento por permissão).
    guild: Id = 0,
    /// Nossas permissões no canal (thread: as do pai) e no servidor.
    perms: u64 = all,
    guild_perms: u64 = all,
    thread: bool = false,
    locked: bool = false,
    /// Fórum: quem diz se dá para postar é a faixa "Novo post" (ui/forum.zig).
    forum: bool = false,
    timeout_until_ms: i64 = 0,
    member_flags: u64 = 0,
    slowmode_s: u32 = 0,
    cooldown_until_ms: i64 = 0,
    /// A contagem veio do Discord (429, POST de "digitando"), não da nossa conta.
    cooldown_from_server: bool = false,
    now_ms: i64,
};

pub const Block = struct {
    reason: Reason = .none,
    /// Até quando (castigo, modo lento); 0 = sem prazo.
    until_ms: i64 = 0,
    /// O modo lento do canal (s) e se ele não vale para nós.
    slowmode_s: u32 = 0,
    exempt: bool = false,
};

pub fn bypassesSlowmode(perms: u64) bool {
    return perms & (types.perm.manage_messages | manage_channels | types.perm.administrator) != 0;
}

pub fn pick(in: Input) Block {
    var b: Block = .{ .slowmode_s = in.slowmode_s, .exempt = bypassesSlowmode(in.perms) };
    if (in.guild != 0 and in.guild_perms & types.perm.administrator == 0) {
        if (in.timeout_until_ms > in.now_ms) {
            b.reason = .timed_out;
            b.until_ms = in.timeout_until_ms;
            return b;
        }
        if (in.member_flags & member_quarantine != 0) {
            b.reason = .quarantined;
            return b;
        }
    }
    if (!in.forum) {
        if (in.thread) {
            // Trancada vence a falta de permissão: é o motivo que a pessoa entende.
            if (in.locked and in.perms & types.perm.manage_threads == 0) {
                b.reason = .thread_locked;
                return b;
            }
            if (in.perms & types.perm.send_messages_in_threads == 0) {
                b.reason = .thread_no_permission;
                return b;
            }
        } else if (in.perms & types.perm.send_messages == 0) {
            b.reason = .no_permission;
            return b;
        }
    }
    if (in.cooldown_until_ms > in.now_ms) {
        if (in.slowmode_s > 0 and !b.exempt) {
            b.reason = .slowmode;
        } else if (in.cooldown_from_server) {
            b.reason = .rate_limited;
        } else return b; // a nossa conta, mas o modo lento saiu (ou não vale para nós)
        b.until_ms = in.cooldown_until_ms;
    }
    return b;
}

/// Passo do que `fmtLeft` mostra: segundos até 10 min, minutos até um dia, horas depois.
fn unitFor(left_ms: i64) i64 {
    if (left_ms <= 10 * 60_000) return 1000;
    if (left_ms <= 86_400_000) return 60_000;
    return 3_600_000;
}

/// Tempo que falta, arredondado para cima: "45s", "4m 05s", "12m", "2h 05m", "3d 4h".
pub fn fmtLeft(buf: []u8, left_ms: i64) []const u8 {
    const left = @max(left_ms, 0);
    const unit = unitFor(left);
    // Sem sinal: com sinal, "{d:0>2}" sai "+05".
    const n: u64 = @intCast(@divFloor(left + unit - 1, unit));
    return switch (unit) {
        1000 => if (n < 60)
            std.fmt.bufPrint(buf, "{d}s", .{n}) catch ""
        else
            std.fmt.bufPrint(buf, "{d}m {d:0>2}s", .{ n / 60, n % 60 }) catch "",
        60_000 => if (n < 60)
            std.fmt.bufPrint(buf, "{d}m", .{n}) catch ""
        else
            std.fmt.bufPrint(buf, "{d}h {d:0>2}m", .{ n / 60, n % 60 }) catch "",
        else => std.fmt.bufPrint(buf, "{d}d {d}h", .{ n / 24, n % 24 }) catch "",
    };
}

/// Quando o texto de `fmtLeft(until - now)` muda: é aí que a tela precisa de
/// um quadro (nada de redesenhar a cada segundo um castigo de dias).
pub fn nextChange(until_ms: i64, now_ms: i64) i64 {
    const left = until_ms - now_ms;
    if (left <= 0) return until_ms;
    const unit = unitFor(left);
    const n = @divFloor(left + unit - 1, unit);
    return until_ms - (n - 1) * unit;
}

/// O modo lento do canal, como as opções do Discord: "5s", "1m 30s", "2h".
pub fn fmtSlowmode(buf: []u8, s: u32) []const u8 {
    if (s < 60) return std.fmt.bufPrint(buf, "{d}s", .{s}) catch "";
    if (s < 3600) {
        if (s % 60 == 0) return std.fmt.bufPrint(buf, "{d}m", .{s / 60}) catch "";
        return std.fmt.bufPrint(buf, "{d}m {d}s", .{ s / 60, s % 60 }) catch "";
    }
    if (s % 3600 == 0) return std.fmt.bufPrint(buf, "{d}h", .{s / 3600}) catch "";
    return std.fmt.bufPrint(buf, "{d}h {d}m", .{ s / 3600, s % 3600 / 60 }) catch "";
}

/// O que sabemos dos nossos limites nesta conta. Fica só na memória: depois de
/// reabrir, o Discord conta de novo (o 429 ou o POST de "digitando" trazem o
/// que falta, ver net/limits_json.zig).
pub const State = struct {
    pub const Member = struct { timeout_until_ms: i64 = 0, flags: u64 = 0 };

    user_flags: u64 = 0,
    /// Só os servidores em que há algo (castigo ou flag de quarentena).
    members: std.AutoHashMapUnmanaged(Id, Member) = .empty,
    /// Canal -> até quando a contagem segura o envio.
    cooldowns: std.AutoHashMapUnmanaged(Id, Cooldown) = .empty,

    /// `server`: quem disse foi o Discord (vale mesmo sem modo lento no canal).
    pub const Cooldown = struct { until_ms: i64 = 0, server: bool = false };

    pub fn deinit(s: *State, gpa: std.mem.Allocator) void {
        s.members.deinit(gpa);
        s.cooldowns.deinit(gpa);
        s.* = .{};
    }

    /// Outra conta (ou saiu): nada do que valia continua valendo.
    pub fn reset(s: *State, gpa: std.mem.Allocator) void {
        s.deinit(gpa);
    }

    /// O nosso membro num servidor. null = o objeto não trouxe o campo (fica o
    /// que era); `timeout_until_ms` 0 ou no passado = sem castigo.
    pub fn applyMember(s: *State, gpa: std.mem.Allocator, guild: Id, timeout_until_ms: ?i64, flags: ?u64, now_ms: i64) void {
        if (guild == 0 or (timeout_until_ms == null and flags == null)) return;
        var m = s.members.get(guild) orelse Member{};
        if (timeout_until_ms) |until| m.timeout_until_ms = if (until > now_ms) until else 0;
        if (flags) |f| m.flags = f & member_quarantine;
        if (m.timeout_until_ms == 0 and m.flags == 0) {
            _ = s.members.remove(guild);
            return;
        }
        s.members.put(gpa, guild, m) catch {};
    }

    pub fn member(s: *const State, guild: Id) Member {
        if (guild == 0) return .{};
        return s.members.get(guild) orelse .{};
    }

    pub fn accountQuarantined(s: *const State) bool {
        return s.user_flags & user_quarantined != 0;
    }

    pub fn cooldown(s: *const State, channel: Id) Cooldown {
        return s.cooldowns.get(channel) orelse .{};
    }

    pub fn cooldownUntil(s: *const State, channel: Id) i64 {
        return s.cooldown(channel).until_ms;
    }

    /// Segura o envio no canal até `until_ms`. Quem diz por último manda: o envio
    /// que acabou de sair, ou o Discord dizendo quanto falta de verdade (o 429
    /// recusou a mensagem; a contagem que começou com ela não vale). Os vencidos
    /// saem antes: a lista não cresce numa sessão longa.
    pub fn holdUntil(s: *State, gpa: std.mem.Allocator, channel: Id, until_ms: i64, now_ms: i64, server: bool) void {
        var it = s.cooldowns.iterator();
        var stale: [16]Id = undefined;
        var n: usize = 0;
        while (it.next()) |kv| if (kv.value_ptr.until_ms <= now_ms and n < stale.len) {
            stale[n] = kv.key_ptr.*;
            n += 1;
        };
        for (stale[0..n]) |id| _ = s.cooldowns.remove(id);
        if (until_ms <= now_ms) {
            _ = s.cooldowns.remove(channel);
            return;
        }
        s.cooldowns.put(gpa, channel, .{ .until_ms = until_ms, .server = server }) catch {};
    }

    /// Mandamos uma mensagem: com modo lento que vale para nós, conta a partir de agora.
    pub fn noteSent(s: *State, gpa: std.mem.Allocator, channel: Id, b: Block, now_ms: i64) void {
        if (b.slowmode_s == 0 or b.exempt) return;
        s.holdUntil(gpa, channel, now_ms + @as(i64, @min(b.slowmode_s, max_slowmode_s)) * 1000, now_ms, false);
    }
};

// --- Testes -------------------------------------------------------------------

const t = std.testing;
const send = types.perm.send_messages;
const view = types.perm.view_channel;

test "sem nada no caminho: dá para enviar" {
    const b = pick(.{ .guild = 1, .perms = view | send, .guild_perms = view | send, .now_ms = 1000 });
    try t.expectEqual(Reason.none, b.reason);
    try t.expect(!b.reason.blocksInput());
}

test "castigo vence o resto e mostra até quando; dono e admin passam" {
    const in: Input = .{ .guild = 1, .perms = view, .guild_perms = view, .timeout_until_ms = 50_000, .slowmode_s = 10, .cooldown_until_ms = 9000, .now_ms = 1000 };
    const b = pick(in);
    try t.expectEqual(Reason.timed_out, b.reason);
    try t.expectEqual(@as(i64, 50_000), b.until_ms);
    try t.expect(b.reason.blocksInput());
    var admin = in;
    admin.guild_perms = all;
    admin.perms = all;
    try t.expectEqual(Reason.none, pick(admin).reason);
    // Venceu: volta ao normal sem ninguém mexer.
    var over = in;
    over.now_ms = 50_000;
    over.perms = view | send;
    try t.expectEqual(Reason.none, pick(over).reason);
}

test "quarentena do AutoMod segura o servidor" {
    const b = pick(.{ .guild = 1, .perms = view | send, .guild_perms = view | send, .member_flags = 1 << 7, .now_ms = 0 });
    try t.expectEqual(Reason.quarantined, b.reason);
    try t.expectEqual(Reason.quarantined, pick(.{ .guild = 1, .perms = all, .guild_perms = view, .member_flags = 1 << 10, .now_ms = 0 }).reason);
    // Outra flag de membro (ex.: já entrou, 1 << 1) não é quarentena.
    try t.expectEqual(Reason.none, pick(.{ .guild = 1, .perms = view | send, .guild_perms = view, .member_flags = 1 << 1, .now_ms = 0 }).reason);
}

test "permissões: canal, thread e thread trancada" {
    try t.expectEqual(Reason.no_permission, pick(.{ .guild = 1, .perms = view, .guild_perms = view, .now_ms = 0 }).reason);
    // Na thread vale SEND_MESSAGES_IN_THREADS, não SEND_MESSAGES.
    try t.expectEqual(Reason.thread_no_permission, pick(.{ .guild = 1, .perms = view | send, .guild_perms = view, .thread = true, .now_ms = 0 }).reason);
    try t.expectEqual(Reason.none, pick(.{ .guild = 1, .perms = view | types.perm.send_messages_in_threads, .guild_perms = view, .thread = true, .now_ms = 0 }).reason);
    try t.expectEqual(Reason.thread_locked, pick(.{ .guild = 1, .perms = view | types.perm.send_messages_in_threads, .guild_perms = view, .thread = true, .locked = true, .now_ms = 0 }).reason);
    try t.expectEqual(Reason.none, pick(.{ .guild = 1, .perms = view | types.perm.send_messages_in_threads | types.perm.manage_threads, .guild_perms = view, .thread = true, .locked = true, .now_ms = 0 }).reason);
    // Fórum: quem fala é a faixa "Novo post".
    try t.expectEqual(Reason.none, pick(.{ .guild = 1, .perms = view, .guild_perms = view, .forum = true, .now_ms = 0 }).reason);
    // DM: nada disso existe.
    try t.expectEqual(Reason.none, pick(.{ .guild = 0, .timeout_until_ms = 99, .member_flags = 1 << 7, .now_ms = 0 }).reason);
}

test "modo lento: conta, e quem gerencia mensagens ou canais passa" {
    const in: Input = .{ .guild = 1, .perms = view | send, .guild_perms = view | send, .slowmode_s = 10, .cooldown_until_ms = 8000, .now_ms = 1000 };
    const b = pick(in);
    try t.expectEqual(Reason.slowmode, b.reason);
    try t.expectEqual(@as(i64, 8000), b.until_ms);
    try t.expect(!b.reason.blocksInput());
    try t.expect(!b.exempt);
    for ([_]u64{ types.perm.manage_messages, manage_channels, types.perm.administrator }) |bit| {
        var mod = in;
        mod.perms |= bit;
        const m = pick(mod);
        try t.expectEqual(Reason.none, m.reason);
        try t.expect(m.exempt);
        try t.expectEqual(@as(u32, 10), m.slowmode_s);
    }
    var over = in;
    over.now_ms = 8000;
    try t.expectEqual(Reason.none, pick(over).reason);
}

test "429 sem modo lento que valha: conta do mesmo jeito; a nossa conta não" {
    const in: Input = .{ .guild = 1, .perms = view | send, .guild_perms = view | send, .cooldown_until_ms = 5000, .cooldown_from_server = true, .now_ms = 1000 };
    const b = pick(in);
    try t.expectEqual(Reason.rate_limited, b.reason);
    try t.expectEqual(@as(i64, 5000), b.until_ms);
    try t.expect(!b.reason.blocksInput());
    try t.expect(b.reason.cooling());
    // Quem gerencia o canal também leva o 429 do Discord.
    var mod = in;
    mod.perms |= types.perm.manage_messages;
    mod.slowmode_s = 10;
    try t.expectEqual(Reason.rate_limited, pick(mod).reason);
    // Com modo lento que vale: é ele.
    var slow = in;
    slow.slowmode_s = 10;
    try t.expectEqual(Reason.slowmode, pick(slow).reason);
    // Contagem só nossa, e o modo lento saiu do canal: libera.
    var ours = in;
    ours.cooldown_from_server = false;
    try t.expectEqual(Reason.none, pick(ours).reason);
    // DM também tem limite do Discord.
    try t.expectEqual(Reason.rate_limited, pick(.{ .cooldown_until_ms = 5000, .cooldown_from_server = true, .now_ms = 1000 }).reason);
}

test "tempo que falta e quando o texto muda" {
    var buf: [32]u8 = undefined;
    try t.expectEqualStrings("10s", fmtLeft(&buf, 9_001));
    try t.expectEqualStrings("1s", fmtLeft(&buf, 1));
    try t.expectEqualStrings("0s", fmtLeft(&buf, -5));
    try t.expectEqualStrings("1m 30s", fmtLeft(&buf, 90_000));
    try t.expectEqualStrings("10m 00s", fmtLeft(&buf, 600_000));
    try t.expectEqualStrings("11m", fmtLeft(&buf, 600_001));
    try t.expectEqualStrings("2h 15m", fmtLeft(&buf, (2 * 60 + 14) * 60_000 + 1));
    try t.expectEqualStrings("24h 00m", fmtLeft(&buf, 86_400_000));
    try t.expectEqualStrings("3d 4h", fmtLeft(&buf, (3 * 24 + 4) * 3_600_000));
    // Segundos: muda no próximo segundo cheio; minutos: no próximo minuto.
    try t.expectEqual(@as(i64, 1_000), nextChange(10_000, 400));
    try t.expectEqual(@as(i64, 10_000), nextChange(10_000, 9_500));
    try t.expectEqual(@as(i64, 3_600_000 - 59 * 60_000 + 0), nextChange(3_600_000, 1));
    try t.expectEqual(@as(i64, 5), nextChange(5, 9));
    // Logo depois da mudança, o texto é outro.
    const until: i64 = 7_200_000;
    var now: i64 = 123;
    var prev: [32]u8 = undefined;
    var i: usize = 0;
    while (now < until and i < 200) : (i += 1) {
        const a = fmtLeft(&prev, until - now);
        const nx = nextChange(until, now);
        try t.expect(nx > now);
        var b2: [32]u8 = undefined;
        try t.expectEqualStrings(a, fmtLeft(&b2, until - (nx - 1)));
        try t.expect(!std.mem.eql(u8, a, fmtLeft(&b2, until - nx)) or nx == until);
        now = nx;
    }
}

test "rótulo do modo lento" {
    var buf: [32]u8 = undefined;
    try t.expectEqualStrings("5s", fmtSlowmode(&buf, 5));
    try t.expectEqualStrings("2m", fmtSlowmode(&buf, 120));
    try t.expectEqualStrings("1m 30s", fmtSlowmode(&buf, 90));
    try t.expectEqualStrings("6h", fmtSlowmode(&buf, 21600));
    try t.expectEqualStrings("1h 30m", fmtSlowmode(&buf, 5400));
}

test "estado: membro, quarentena da conta e modo lento" {
    const gpa = t.allocator;
    var s: State = .{};
    defer s.deinit(gpa);
    s.applyMember(gpa, 7, 90_000, null, 1000);
    try t.expectEqual(@as(i64, 90_000), s.member(7).timeout_until_ms);
    // Objeto sem o campo: fica o que era.
    s.applyMember(gpa, 7, null, null, 2000);
    try t.expectEqual(@as(i64, 90_000), s.member(7).timeout_until_ms);
    // Castigo tirado (null no Discord vira 0 aqui) ou já vencido: some.
    s.applyMember(gpa, 7, 0, null, 3000);
    try t.expectEqual(@as(usize, 0), s.members.count());
    s.applyMember(gpa, 8, 500, 1 << 7 | 1 << 1, 1000);
    try t.expectEqual(@as(i64, 0), s.member(8).timeout_until_ms);
    try t.expectEqual(@as(u64, 1 << 7), s.member(8).flags);
    try t.expect(!s.accountQuarantined());
    s.user_flags = user_quarantined | 1;
    try t.expect(s.accountQuarantined());

    const b: Block = .{ .slowmode_s = 10 };
    s.noteSent(gpa, 55, b, 1000);
    try t.expectEqual(@as(i64, 11_000), s.cooldownUntil(55));
    // O Discord diz quanto falta de verdade: vale o que ele disse.
    try t.expect(!s.cooldown(55).server);
    s.holdUntil(gpa, 55, 20_000, 2000, true);
    try t.expectEqual(@as(i64, 20_000), s.cooldownUntil(55));
    try t.expect(s.cooldown(55).server);
    s.holdUntil(gpa, 55, 5_000, 2000, true);
    try t.expectEqual(@as(i64, 5_000), s.cooldownUntil(55));
    s.holdUntil(gpa, 55, 20_000, 2000, true);
    // Liberado ou canal sem modo lento: nada conta.
    s.noteSent(gpa, 56, .{ .slowmode_s = 10, .exempt = true }, 1000);
    s.noteSent(gpa, 57, .{}, 1000);
    try t.expectEqual(@as(i64, 0), s.cooldownUntil(56));
    try t.expectEqual(@as(i64, 0), s.cooldownUntil(57));
    // Os vencidos saem quando entra outro.
    s.holdUntil(gpa, 58, 40_000, 30_000, false);
    try t.expectEqual(@as(i64, 0), s.cooldownUntil(55));
    try t.expectEqual(@as(usize, 1), s.cooldowns.count());
    s.reset(gpa);
    try t.expectEqual(@as(u64, 0), s.user_flags);
}
