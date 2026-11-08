//! Quando uma mensagem chama a gente, pela regra do Discord:
//!
//! - menção direta: estamos no `mentions` da mensagem (inclui a resposta que
//!   marca quem foi respondido, sem `<@nós>` no texto);
//! - @everyone e @here: `mention_everyone`, que o servidor só liga quando
//!   quem escreveu podia usar (e fora de bloco de código);
//! - um cargo nosso no `mention_roles`.
//!
//! "Suprimir @everyone e @here" e "Suprimir menções a cargos" do servidor
//! (configurações da conta, core/conta.zig) desligam as duas últimas. Vale
//! igual nas threads: o servidor delas é o do canal pai.
//!
//! É a mesma regra para o destaque na conversa, os contadores de menção, a
//! caixa de entrada e as notificações. O Store guarda o resultado na mensagem
//! (`StoredMessage.mm`) e só refaz quando os nossos cargos ou essas
//! configurações mudam (`Store.me_rev`): nada disto roda a cada quadro.
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;

/// O que as notificações do servidor tiram ("Suprimir…").
pub const Supressao = struct { everyone: bool = false, roles: bool = false };

/// O que a mensagem chama, antes das supressões.
pub const Chamado = struct { me: bool = false, everyone: bool = false, role: bool = false };

/// Lê os campos que o servidor preencheu. `cargos.tem(id)`: temos o cargo
/// (no servidor da conversa). `demo`: a demonstração não tem servidor para
/// preencher os campos, então o texto também vale (`<@nós>`, `@everyone`,
/// `@here`, `<@&cargo>`).
pub fn chamado(m: *const types.Message, me: Id, demo: bool, cargos: anytype) Chamado {
    var out: Chamado = .{ .me = m.mentions_me, .everyone = m.mention_everyone };
    for (m.mention_roles) |r| if (cargos.tem(r)) {
        out.role = true;
        break;
    };
    if (demo) doTexto(m.content, me, cargos, &out);
    return out;
}

/// Destaca, conta e notifica (as notificações ainda passam pelo nível do
/// servidor e pelo silêncio, em core/conta.zig).
pub fn destaca(ch: Chamado, sup: Supressao) bool {
    return ch.me or (ch.everyone and !sup.everyone) or (ch.role and !sup.roles);
}

fn doTexto(t: []const u8, me: Id, cargos: anytype, out: *Chamado) void {
    var b: [32]u8 = undefined;
    inline for (.{ "<@{d}>", "<@!{d}>" }) |f| {
        if (!out.me) {
            const a = std.fmt.bufPrint(&b, f, .{me}) catch "";
            out.me = a.len > 0 and std.mem.indexOf(u8, t, a) != null;
        }
    }
    if (!out.everyone) out.everyone = std.mem.indexOf(u8, t, "@everyone") != null or std.mem.indexOf(u8, t, "@here") != null;
    if (out.role) return;
    var rest = t;
    while (std.mem.indexOf(u8, rest, "<@&")) |i| {
        rest = rest[i + 3 ..];
        const end = std.mem.indexOfScalar(u8, rest, '>') orelse return;
        const role = std.fmt.parseInt(Id, rest[0..end], 10) catch continue;
        if (cargos.tem(role)) {
            out.role = true;
            return;
        }
    }
}

// --- Testes -----------------------------------------------------------------

const Cargos = struct {
    meus: []const Id,
    pub fn tem(c: Cargos, r: Id) bool {
        return std.mem.indexOfScalar(Id, c.meus, r) != null;
    }
};

const eu: Id = 1000;
const meus: Cargos = .{ .meus = &.{ 77, 78 } };

fn msg(content: []const u8) types.Message {
    return .{ .id = 1, .channel = 10, .author = 2, .timestamp = 0, .content = content };
}

fn pinga(m: types.Message, sup: Supressao) bool {
    return destaca(chamado(&m, eu, false, meus), sup);
}

test "menção direta e resposta que marca" {
    var m = msg("<@1000> olha isso");
    m.mentions_me = true;
    try std.testing.expect(pinga(m, .{}));
    // Responder com a marcação ligada: estamos no `mentions`, sem nada no texto.
    var r = msg("concordo");
    r.reply_to = 5;
    r.mentions_me = true;
    try std.testing.expect(pinga(r, .{}));
    // As supressões não tiram a menção direta.
    try std.testing.expect(pinga(r, .{ .everyone = true, .roles = true }));
}

test "@everyone e @here, liberados e suprimidos" {
    var m = msg("@everyone reunião às 20h");
    m.mention_everyone = true;
    try std.testing.expect(pinga(m, .{}));
    try std.testing.expect(!pinga(m, .{ .everyone = true }));
    var h = msg("@here alguém online?");
    h.mention_everyone = true;
    try std.testing.expect(pinga(h, .{ .roles = true }));
    try std.testing.expect(!pinga(h, .{ .everyone = true }));
    // Escrito por quem não pode usar: o servidor não liga o campo.
    try std.testing.expect(!pinga(msg("@everyone sem permissão"), .{}));
}

test "menção a cargo: só os nossos, e respeita a supressão" {
    const roles = [_]Id{ 99, 78 };
    var m = msg("<@&99> <@&78> olhem o #bugs");
    m.mention_roles = &roles;
    try std.testing.expect(pinga(m, .{}));
    try std.testing.expect(pinga(m, .{ .everyone = true }));
    try std.testing.expect(!pinga(m, .{ .roles = true }));
    // Cargo dos outros.
    const outros = [_]Id{99};
    var o = msg("<@&99> fundadores");
    o.mention_roles = &outros;
    try std.testing.expect(!pinga(o, .{}));
    // `<@&78>` no texto sem estar no `mention_roles` (o bot pediu para não
    // marcar ninguém, ou o cargo não pode ser mencionado): não chama.
    try std.testing.expect(!pinga(msg("<@&78> recebeu o cargo"), .{}));
}

test "mensagem sem menção a nós não destaca" {
    var m = msg("<@1001> e <@&99>, bom dia");
    const outros = [_]Id{99};
    m.mention_roles = &outros;
    try std.testing.expect(!pinga(m, .{}));
    try std.testing.expect(!pinga(msg("bom dia, pessoal"), .{}));
    // `everyone` no meio de outra palavra não é menção (o campo é do servidor).
    try std.testing.expect(!pinga(msg("e-mail para everyone@exemplo"), .{}));
}

test "na demonstração o texto preenche o que o servidor preencheria" {
    const d = struct {
        fn f(t: []const u8) Chamado {
            const m = msg(t);
            return chamado(&m, eu, true, meus);
        }
    }.f;
    try std.testing.expect(d("<@1000> oi").me and d("<@!1000> oi").me);
    try std.testing.expect(!d("<@10001> oi").me);
    try std.testing.expect(d("@here bora").everyone);
    try std.testing.expect(d("<@&78> moderação").role and !d("<@&99> fundação").role);
    try std.testing.expect(!destaca(d("@everyone"), .{ .everyone = true }));
}
