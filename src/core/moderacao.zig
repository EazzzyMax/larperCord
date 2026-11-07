//! Moderação: quem pode expulsar, banir, castigar e silenciar quem, e os
//! pedidos que vão para o Discord. A regra e os pedidos são puros (testados
//! aqui); a interface fica em ui/moderacao.zig e a rede em net/discord.zig.
const std = @import("std");
const types = @import("types.zig");
const Store = @import("store.zig").Store;
const Id = types.Id;
const perm = types.perm;

pub const Acao = enum(u8) { kick, ban, unban, timeout, untimeout, mute, unmute, deafen, undeafen };

/// O que dá para fazer com alguém agora.
pub const Pode = packed struct(u8) {
    kick: bool = false,
    ban: bool = false,
    timeout: bool = false,
    mute: bool = false,
    deafen: bool = false,
    _pad: u3 = 0,

    pub fn algo(p: Pode) bool {
        return @as(u8, @bitCast(p)) != 0;
    }
};

/// Tudo o que a regra precisa saber, já tirado do Store.
pub const Quem = struct {
    me: Id,
    alvo: Id,
    dono: Id,
    /// Nossas permissões no servidor.
    perms: u64,
    /// As do canal de voz em que o alvo está (silenciar e ensurdecer valem por
    /// canal); null = o alvo não está em call neste servidor.
    perms_voz: ?u64 = null,
    /// Posição do cargo mais alto de cada um (0 = só @everyone).
    meu_topo: i32,
    topo_alvo: i32,
    /// O alvo é administrador: castigo não pega nele.
    alvo_admin: bool = false,
};

fn tem(p: u64, bit: u64) bool {
    return p & (bit | perm.administrator) != 0;
}

/// Como o Discord decide: o dono age sobre todos menos ele mesmo; os outros
/// precisam da permissão e de um cargo estritamente acima do cargo mais alto do
/// alvo. Ninguém age sobre o dono nem sobre si, e administrador não leva castigo.
pub fn pode(q: Quem) Pode {
    if (q.alvo == 0 or q.alvo == q.me or q.alvo == q.dono) return .{};
    const dono = q.dono != 0 and q.me == q.dono;
    if (!dono and q.meu_topo <= q.topo_alvo) return .{};
    return .{
        .kick = dono or tem(q.perms, perm.kick_members),
        .ban = dono or tem(q.perms, perm.ban_members),
        .timeout = !q.alvo_admin and (dono or tem(q.perms, perm.moderate_members)),
        .mute = if (q.perms_voz) |pv| dono or tem(pv, perm.mute_members) else false,
        .deafen = if (q.perms_voz) |pv| dono or tem(pv, perm.deafen_members) else false,
    };
}

/// Ver e revogar banimentos: só quem pode banir.
pub fn podeBanir(perms: u64) bool {
    return tem(perms, perm.ban_members);
}

// --- Pedidos -------------------------------------------------------------------

pub fn metodo(a: Acao) [:0]const u8 {
    return switch (a) {
        .kick, .unban => "DELETE",
        .ban => "PUT",
        .timeout, .untimeout, .mute, .unmute, .deafen, .undeafen => "PATCH",
    };
}

pub fn caminho(buf: []u8, a: Acao, guild: Id, user: Id) ![]const u8 {
    return switch (a) {
        .ban, .unban => std.fmt.bufPrint(buf, "/guilds/{d}/bans/{d}", .{ guild, user }),
        else => std.fmt.bufPrint(buf, "/guilds/{d}/members/{d}", .{ guild, user }),
    };
}

/// Mensagens apagadas junto com o banimento: o Discord aceita até 7 dias.
pub const max_apagar_s: u32 = 604_800;

/// Corpo JSON (null = sem corpo). `apagar_s`: banir; `ate_s`: fim do castigo (s Unix).
pub fn corpo(buf: []u8, a: Acao, apagar_s: u32, ate_s: i64) !?[]const u8 {
    return switch (a) {
        .kick, .unban => null,
        .ban => try std.fmt.bufPrint(buf, "{{\"delete_message_seconds\":{d}}}", .{@min(apagar_s, max_apagar_s)}),
        .timeout => blk: {
            var ib: [32]u8 = undefined;
            break :blk try std.fmt.bufPrint(buf, "{{\"communication_disabled_until\":\"{s}\"}}", .{isoUtc(&ib, ate_s)});
        },
        .untimeout => "{\"communication_disabled_until\":null}",
        .mute => "{\"mute\":true}",
        .unmute => "{\"mute\":false}",
        .deafen => "{\"deaf\":true}",
        .undeafen => "{\"deaf\":false}",
    };
}

/// "2026-11-07T12:00:00.000Z" (como o `toISOString` do navegador).
pub fn isoUtc(buf: []u8, secs: i64) []const u8 {
    const es: std.time.epoch.EpochSeconds = .{ .secs = @intCast(std.math.clamp(secs, 0, 253402300799)) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{ yd.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute() }) catch "";
}

/// O registro de auditoria guarda até 512 caracteres de motivo.
pub const max_motivo = 512;
const prefixo_motivo = "X-Audit-Log-Reason: ";
/// Cabe o pior caso: 512 bytes, cada um virando %XX.
pub const motivo_buf_len = prefixo_motivo.len + max_motivo * 3 + 1;

fn livre(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_' or ch == '~';
}

/// Linha `X-Audit-Log-Reason` com o motivo em URL (como o `encodeURIComponent`):
/// tudo fora de [A-Za-z0-9-._~] vira %XX, então quebra de linha ou dois-pontos
/// nunca viram outro cabeçalho. null = sem motivo. Corta em 512 bytes sem partir
/// um caractere UTF-8 no meio.
pub fn cabecalhoMotivo(buf: *[motivo_buf_len]u8, motivo: []const u8) ?[:0]const u8 {
    var m = std.mem.trim(u8, motivo, " \t\r\n");
    if (m.len > max_motivo) {
        var k: usize = max_motivo;
        while (k > 0 and m[k] & 0xC0 == 0x80) k -= 1;
        m = m[0..k];
    }
    if (m.len == 0) return null;
    @memcpy(buf[0..prefixo_motivo.len], prefixo_motivo);
    var n: usize = prefixo_motivo.len;
    const hex = "0123456789ABCDEF";
    for (m) |ch| {
        if (livre(ch)) {
            buf[n] = ch;
            n += 1;
        } else {
            buf[n] = '%';
            buf[n + 1] = hex[ch >> 4];
            buf[n + 2] = hex[ch & 15];
            n += 3;
        }
    }
    buf[n] = 0;
    return buf[0..n :0];
}

// --- Escolhas dos diálogos ---------------------------------------------------------

pub const Preset = struct { s: u32, pt: []const u8, en: []const u8 };

pub const castigos = [_]Preset{
    .{ .s = 60, .pt = "60 s", .en = "60 sec" },
    .{ .s = 300, .pt = "5 min", .en = "5 min" },
    .{ .s = 600, .pt = "10 min", .en = "10 min" },
    .{ .s = 3600, .pt = "1 h", .en = "1 hour" },
    .{ .s = 86_400, .pt = "1 dia", .en = "1 day" },
    .{ .s = 604_800, .pt = "1 semana", .en = "1 week" },
};

pub const apagar = [_]Preset{
    .{ .s = 0, .pt = "Nada", .en = "Nothing" },
    .{ .s = 3600, .pt = "Última hora", .en = "Last hour" },
    .{ .s = 86_400, .pt = "Últimas 24 h", .en = "Last 24 hours" },
    .{ .s = 604_800, .pt = "Últimos 7 dias", .en = "Last 7 days" },
};

/// Por que o Discord recusou, em palavras (status HTTP e o `code` do JSON).
/// Status 0 = nem chegou lá.
pub fn erro(status: u16, code: u32) struct { pt: []const u8, en: []const u8 } {
    return switch (code) {
        50013 => .{ .pt = "Falta permissão para isso: o cargo dessa pessoa pode estar acima do seu.", .en = "Missing permissions: their role may be above yours." },
        50001 => .{ .pt = "Sem acesso a este servidor.", .en = "Missing access to this server." },
        10007 => .{ .pt = "Essa pessoa não está mais no servidor.", .en = "That member is no longer in the server." },
        10013 => .{ .pt = "Essa conta não existe mais.", .en = "That user no longer exists." },
        10026 => .{ .pt = "Esse banimento não existe mais.", .en = "That ban no longer exists." },
        else => switch (status) {
            0 => .{ .pt = "Sem conexão com o Discord.", .en = "No connection to Discord." },
            401 => .{ .pt = "O Discord não aceitou a sessão.", .en = "Discord rejected the session." },
            403 => .{ .pt = "O Discord recusou: sem permissão.", .en = "Discord refused: forbidden." },
            404 => .{ .pt = "Não encontrado no Discord.", .en = "Not found on Discord." },
            429 => .{ .pt = "Muitas ações seguidas: tente daqui a pouco.", .en = "Too many actions in a row: try again shortly." },
            else => .{ .pt = "O Discord recusou o pedido.", .en = "Discord refused the request." },
        },
    };
}

// --- A partir do Store ------------------------------------------------------------

/// Cargo mais alto de alguém no servidor (os nossos, todos; dos outros, os
/// que a lista de membros mandou).
fn topo(s: *const Store, guild: Id, user: Id) i32 {
    var top: i32 = 0;
    if (user == s.me) if (s.my_roles.get(guild)) |list| {
        for (list) |rid| if (s.roles.get(rid)) |r| {
            top = @max(top, r.position);
        };
        return top;
    };
    if (s.memberInfo(guild, user)) |mi| for (mi.roleSlice()) |rid| {
        if (s.roles.get(rid)) |r| top = @max(top, r.position);
    };
    return top;
}

fn admin(s: *const Store, guild: Id, user: Id) bool {
    var p: u64 = if (s.roles.get(guild)) |r| r.permissions else 0;
    if (s.memberInfo(guild, user)) |mi| for (mi.roleSlice()) |rid| {
        if (s.roles.get(rid)) |r| p |= r.permissions;
    };
    return p & perm.administrator != 0;
}

/// A regra aplicada a alguém num servidor. Só roda com o menu aberto (procura a
/// call do alvo em todos os canais).
pub fn podeNoStore(s: *const Store, guild: Id, alvo: Id) Pode {
    const g = s.guild(guild) orelse return .{};
    var pv: ?u64 = null;
    const vc = s.voiceChannelOf(alvo, guild);
    if (vc != 0) if (s.channel(vc)) |cs| if (cs.info.guild == guild) {
        pv = s.channelPermissions(&cs.info);
    };
    return pode(.{
        .me = s.me,
        .alvo = alvo,
        .dono = g.owner,
        .perms = s.permissions(guild),
        .perms_voz = pv,
        .meu_topo = topo(s, guild, s.me),
        .topo_alvo = topo(s, guild, alvo),
        .alvo_admin = admin(s, guild, alvo),
    });
}

// --- Testes -------------------------------------------------------------------------

const t = std.testing;

test "moderação: dono age sobre todos menos ele mesmo" {
    const base: Quem = .{ .me = 1, .alvo = 2, .dono = 1, .perms = 0, .meu_topo = 0, .topo_alvo = 50, .perms_voz = 0 };
    const p = pode(base);
    try t.expect(p.kick and p.ban and p.timeout and p.mute and p.deafen);
    var eu = base;
    eu.alvo = 1;
    try t.expect(!pode(eu).algo());
    // Fora de call: nada de silenciar/ensurdecer.
    var fora = base;
    fora.perms_voz = null;
    const pf = pode(fora);
    try t.expect(pf.kick and !pf.mute and !pf.deafen);
}

test "moderação: precisa da permissão e de um cargo acima" {
    const mod = perm.kick_members | perm.ban_members | perm.moderate_members;
    const base: Quem = .{ .me = 1, .alvo = 2, .dono = 9, .perms = mod, .perms_voz = perm.mute_members, .meu_topo = 5, .topo_alvo = 3 };
    const p = pode(base);
    try t.expect(p.kick and p.ban and p.timeout and p.mute and !p.deafen);
    // Mesmo nível não basta: precisa estar estritamente acima.
    var igual = base;
    igual.topo_alvo = 5;
    try t.expect(!pode(igual).algo());
    var acima = base;
    acima.topo_alvo = 8;
    try t.expect(!pode(acima).algo());
    // Sem a permissão, nada daquela ação.
    var so_kick = base;
    so_kick.perms = perm.kick_members;
    const pk = pode(so_kick);
    try t.expect(pk.kick and !pk.ban and !pk.timeout);
    // Administrador tem tudo (ainda respeitando a hierarquia).
    var adm = base;
    adm.perms = perm.administrator;
    adm.perms_voz = perm.administrator;
    const pa = pode(adm);
    try t.expect(pa.kick and pa.ban and pa.timeout and pa.mute and pa.deafen);
}

test "moderação: ninguém age sobre o dono; administrador não leva castigo" {
    const all = std.math.maxInt(u64);
    const dono: Quem = .{ .me = 1, .alvo = 9, .dono = 9, .perms = all, .meu_topo = 100, .topo_alvo = 0 };
    try t.expect(!pode(dono).algo());
    const adm: Quem = .{ .me = 1, .alvo = 2, .dono = 1, .perms = all, .meu_topo = 0, .topo_alvo = 0, .alvo_admin = true };
    const p = pode(adm);
    try t.expect(p.kick and p.ban and !p.timeout);
    try t.expect(podeBanir(perm.ban_members) and podeBanir(perm.administrator) and !podeBanir(perm.kick_members));
}

test "moderação: método, caminho e corpo" {
    var pb: [96]u8 = undefined;
    var bb: [96]u8 = undefined;
    try t.expectEqualStrings("DELETE", metodo(.kick));
    try t.expectEqualStrings("/guilds/10/members/20", try caminho(&pb, .kick, 10, 20));
    try t.expect(try corpo(&bb, .kick, 0, 0) == null);
    try t.expectEqualStrings("PUT", metodo(.ban));
    try t.expectEqualStrings("/guilds/10/bans/20", try caminho(&pb, .ban, 10, 20));
    try t.expectEqualStrings("{\"delete_message_seconds\":86400}", (try corpo(&bb, .ban, 86_400, 0)).?);
    try t.expectEqualStrings("{\"delete_message_seconds\":604800}", (try corpo(&bb, .ban, 9_999_999, 0)).?);
    try t.expectEqualStrings("DELETE", metodo(.unban));
    try t.expectEqualStrings("/guilds/10/bans/20", try caminho(&pb, .unban, 10, 20));
    try t.expectEqualStrings("PATCH", metodo(.timeout));
    try t.expectEqualStrings("{\"communication_disabled_until\":\"2026-11-07T12:34:56.000Z\"}", (try corpo(&bb, .timeout, 0, 1794054896)).?);
    try t.expectEqualStrings("{\"communication_disabled_until\":null}", (try corpo(&bb, .untimeout, 0, 0)).?);
    try t.expectEqualStrings("{\"mute\":true}", (try corpo(&bb, .mute, 0, 0)).?);
    try t.expectEqualStrings("{\"deaf\":false}", (try corpo(&bb, .undeafen, 0, 0)).?);
}

test "moderação: hora ISO" {
    var b: [32]u8 = undefined;
    try t.expectEqualStrings("1970-01-01T00:00:00.000Z", isoUtc(&b, 0));
    try t.expectEqualStrings("2024-02-29T23:59:59.000Z", isoUtc(&b, 1709251199));
    try t.expectEqualStrings("1970-01-01T00:00:00.000Z", isoUtc(&b, -5));
}

test "moderação: motivo em URL, sem injeção de cabeçalho" {
    var b: [motivo_buf_len]u8 = undefined;
    try t.expect(cabecalhoMotivo(&b, "") == null);
    try t.expect(cabecalhoMotivo(&b, "  \n ") == null);
    try t.expectEqualStrings("X-Audit-Log-Reason: spam", cabecalhoMotivo(&b, " spam ").?);
    try t.expectEqualStrings("X-Audit-Log-Reason: flood%20no%20%23geral%3A%20100%25", cabecalhoMotivo(&b, "flood no #geral: 100%").?);
    // Quebra de linha vira %0D%0A: não nasce outro cabeçalho.
    const inj = cabecalhoMotivo(&b, "a\r\nX-Evil: 1").?;
    try t.expectEqualStrings("X-Audit-Log-Reason: a%0D%0AX-Evil%3A%201", inj);
    try t.expect(std.mem.indexOfAny(u8, inj, "\r\n") == null);
    try t.expectEqualStrings("X-Audit-Log-Reason: a%C3%A7%C3%A3o", cabecalhoMotivo(&b, "ação").?);
    // Longo demais: corta em 512 bytes sem partir o "ç" (2 bytes) no meio.
    var long: [600]u8 = undefined;
    @memset(long[0..511], 'x');
    @memcpy(long[511..513], "ç");
    @memset(long[513..], 'y');
    const cut = cabecalhoMotivo(&b, &long).?;
    try t.expectEqual(prefixo_motivo.len + 511, cut.len);
    // Pior caso: tudo vira %XX e ainda cabe no buffer.
    var all: [max_motivo + 50]u8 = undefined;
    @memset(&all, '#');
    try t.expectEqual(motivo_buf_len - 1, cabecalhoMotivo(&b, &all).?.len);
}

test "moderação: a regra com o que o Store sabe, e o castigo na lista" {
    try t.expectEqual(@as(usize, 64), @sizeOf(types.MemberInfo));
    const ca = std.heap.c_allocator;
    var s = Store.init(t.allocator);
    defer s.deinit();
    const users = try ca.alloc(types.User, 1);
    users[0] = .{ .id = 1, .name = try ca.dupe(u8, "eu") };
    const guilds = try ca.alloc(types.Guild, 1);
    guilds[0] = .{ .id = 5, .name = try ca.dupe(u8, "srv"), .acronym = try ca.dupe(u8, "S"), .owner = 9 };
    try s.apply(.{ .ready = .{ .me = 1, .users = users, .guilds = guilds, .channels = try ca.alloc(types.Channel, 0), .voice = try ca.alloc([2]Id, 0) } }, 0);
    // Moderação (posição 2) pode expulsar e castigar; administração (3) tem tudo.
    const rs = try ca.alloc(types.Role, 3);
    rs[0] = .{ .id = 51, .guild = 5, .name = try ca.dupe(u8, "adm"), .position = 3, .permissions = perm.administrator };
    rs[1] = .{ .id = 52, .guild = 5, .name = try ca.dupe(u8, "mod"), .position = 2, .permissions = perm.kick_members | perm.moderate_members };
    rs[2] = .{ .id = 53, .guild = 5, .name = try ca.dupe(u8, "membro"), .position = 1 };
    try s.apply(.{ .roles = .{ .guild = 5, .roles = rs } }, 0);
    const info = struct {
        fn f(role: Id) types.MemberInfo {
            var mi: types.MemberInfo = .{};
            mi.roles[0] = role;
            mi.n_roles = 1;
            return mi;
        }
    }.f;
    try s.apply(.{ .member_info = .{ .guild = 5, .user = 1, .info = info(52) } }, 0);
    try s.apply(.{ .member_info = .{ .guild = 5, .user = 2, .info = info(53) } }, 0);
    try s.apply(.{ .member_info = .{ .guild = 5, .user = 3, .info = info(51) } }, 0);
    try s.apply(.{ .member_info = .{ .guild = 5, .user = 4, .info = info(52) } }, 0);
    const abaixo = podeNoStore(&s, 5, 2);
    try t.expect(abaixo.kick and abaixo.timeout and !abaixo.ban and !abaixo.mute);
    try t.expect(!podeNoStore(&s, 5, 3).algo()); // acima
    try t.expect(!podeNoStore(&s, 5, 4).algo()); // mesmo cargo
    try t.expect(!podeNoStore(&s, 5, 9).algo()); // o dono
    try t.expect(!podeNoStore(&s, 5, 1).algo()); // a gente
    // Deu certo: o castigo aparece já, e some ao tirar.
    try s.apply(.{ .moderated = .{ .req = 1, .guild = 5, .user = 2, .acao = .timeout, .ok = true, .ate_s = 2_000_000_000 } }, 0);
    try t.expectEqual(@as(u32, 2_000_000_000), s.memberInfo(5, 2).?.timeout_s);
    try s.apply(.{ .moderated = .{ .req = 2, .guild = 5, .user = 2, .acao = .untimeout, .ok = true } }, 0);
    try t.expectEqual(@as(u32, 0), s.memberInfo(5, 2).?.timeout_s);
    // Recusado: nada muda.
    try s.apply(.{ .moderated = .{ .req = 3, .guild = 5, .user = 2, .acao = .timeout, .ok = false, .ate_s = 2_000_000_000 } }, 0);
    try t.expectEqual(@as(u32, 0), s.memberInfo(5, 2).?.timeout_s);
}

test "moderação: erros em palavras" {
    try t.expect(std.mem.indexOf(u8, erro(403, 50013).en, "Missing permissions") != null);
    try t.expect(std.mem.indexOf(u8, erro(403, 0).en, "forbidden") != null);
    try t.expect(std.mem.indexOf(u8, erro(0, 0).en, "No connection") != null);
    try t.expect(std.mem.indexOf(u8, erro(404, 10026).en, "ban") != null);
}
