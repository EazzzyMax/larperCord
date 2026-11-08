//! QA do destaque de menção (entra na bateria por tema do qa_runner.zig): no
//! #setups do "Zig Brasil" da demonstração (net/fake_gateway.zig,
//! `demoMentionMessages`), menção direta, resposta que marca, @everyone, @here
//! e menção a um cargo nosso ficam destacadas; cargo dos outros, a nossa
//! mensagem e uma mensagem comum não. "Suprimir @everyone e @here" e
//! "Suprimir menções a cargos" do servidor tiram o destaque deles (a regra é
//! refeita quando as configurações mudam) e devolvem ao desligar. As cores do
//! destaque têm contraste com o fundo do tema, no escuro e no claro.
const std = @import("std");
const App = @import("app.zig").App;
const R = @import("qa_runner.zig");
const Op = R.Op;
const qa = @import("ui/qa.zig");
const gw = @import("net/fake_gateway.zig");
const types = @import("core/types.zig");
const conta = @import("core/conta.zig");
const destaque = @import("ui/destaque.zig");
const Rgba = @import("theme/color.zig").Rgba;
const StoredMessage = @import("core/store.zig").StoredMessage;
const Id = types.Id;
const Case = gw.MentionCase;

fn expect(name: []const u8, f: *const fn (*App) bool) Op {
    return .{ .expect = .{ .name = name, .check = f, .timeout_ms = 4000 } };
}
fn run(f: *const fn (*App) void) Op {
    return .{ .run = f };
}

const guild: Id = gw.guildId(gw.mod_guild);
const cases = std.enums.values(Case);

/// O canal em que a bateria estava, para voltar no fim.
var home: Id = 0;

fn toChannel(app: *App) void {
    home = app.st.activeChannel() orelse 0;
    app.handle(.{ .open_message = .{ .channel = gw.mention_channel, .id = 0 } });
    app.st.scrollOf(gw.mention_channel).stick_bottom = true;
}

/// A mensagem de cada caso: as últimas do canal, na ordem de `MentionCase`.
fn msgOf(app: *App, k: Case) ?*StoredMessage {
    const cs = app.store.channel(gw.mention_channel) orelse return null;
    const items = cs.messages.items;
    var end = items.len;
    while (end > 0 and items[end - 1].msg.id == 0) end -= 1;
    if (end < cases.len) return null;
    return &items[end - cases.len + @intFromEnum(k)];
}

/// O histórico chegou e a lista de membros já disse quais cargos temos.
fn channelReady(app: *App) bool {
    if (app.st.activeChannel() != gw.mention_channel) return false;
    const cs = app.store.channel(gw.mention_channel) orelse return false;
    return cs.history == .loaded and app.store.hasRole(guild, gw.mention_my_role) and msgOf(app, .normal) != null;
}

fn shouldLight(k: Case, sup: conta.GuildSettings) bool {
    return switch (k) {
        .direct, .reply_ping => true,
        .everyone, .here => !sup.suppress_everyone,
        .my_role => !sup.suppress_roles,
        .mine, .other_role, .normal => false,
    };
}

fn markOf(buf: []u8, comptime prefix: []const u8, id: Id) []const u8 {
    return std.fmt.bufPrint(buf, prefix ++ ":{d}", .{id}) catch "";
}

/// O resultado guardado em cada mensagem e o que está na tela batem com a
/// regra. As quatro de baixo estão sempre à vista; as de cima, se couberem.
fn matches(app: *App, sup: conta.GuildSettings) bool {
    var drawn: usize = 0;
    for (cases) |k| {
        const m = msgOf(app, k) orelse return false;
        const want = shouldLight(k, sup);
        if (app.store.mentionsMeCached(guild, m) != want) return false;
        var b: [48]u8 = undefined;
        if (qa.find(markOf(&b, "msgtext", m.msg.id)) == null) {
            if (@intFromEnum(k) >= @intFromEnum(Case.here)) return false;
            continue;
        }
        drawn += 1;
        if ((qa.find(markOf(&b, "row-mention", m.msg.id)) != null) != want) return false;
    }
    return drawn >= 4;
}

fn allOn(app: *App) bool {
    return matches(app, .{ .guild = guild });
}

/// As cores do destaque deste tema aparecem no fundo dele.
fn visible(app: *App) bool {
    const th = app.themes.theme_();
    const bg = th.c(.bg);
    const sf = th.c(.surface);
    // `idle` no estilo do Discord e nas bolhas; `mention` no estilo terminal.
    for ([_]Rgba{ th.c(.idle), th.c(.mention) }) |base| {
        const p = destaque.cores(base, &.{ bg, sf });
        for ([_]Rgba{ bg, sf }) |f| {
            const op: Rgba = .{ .r = f.r, .g = f.g, .b = f.b };
            if (p.faixa.contrast(op) < destaque.contraste_faixa) return false;
            if (destaque.maiorCanal(destaque.composto(p, f), op) < 0.05) return false;
        }
    }
    return true;
}

fn change(app: *App, ch: conta.Change) void {
    app.handle(.{ .conta = .{ .notif = .{ .target = guild, .change = ch } } });
}
fn suppressEveryone(app: *App) void {
    change(app, .{ .suppress_everyone = true });
}
fn suppressRoles(app: *App) void {
    change(app, .{ .suppress_roles = true });
}
/// Uma mudança por vez: cada uma parte das configurações que o Discord devolveu.
fn restoreEveryone(app: *App) void {
    change(app, .{ .suppress_everyone = false });
}
fn restoreRoles(app: *App) void {
    change(app, .{ .suppress_roles = false });
}

fn settingsIs(app: *App, everyone: bool, roles: bool) bool {
    const gs = app.st.conta.settings(guild) orelse return !everyone and !roles;
    return gs.suppress_everyone == everyone and gs.suppress_roles == roles;
}
fn everyoneOff(app: *App) bool {
    return settingsIs(app, true, false) and matches(app, .{ .guild = guild, .suppress_everyone = true });
}
fn rolesOff(app: *App) bool {
    return settingsIs(app, true, true) and matches(app, .{ .guild = guild, .suppress_everyone = true, .suppress_roles = true });
}
fn everyoneBack(app: *App) bool {
    return settingsIs(app, false, true) and matches(app, .{ .guild = guild, .suppress_roles = true });
}
fn backOn(app: *App) bool {
    return settingsIs(app, false, false) and allOn(app);
}

fn goHome(app: *App) void {
    if (home != 0) app.handle(.{ .open_message = .{ .channel = home, .id = 0 } });
}
fn atHome(app: *App) bool {
    return home == 0 or app.st.activeChannel() == home;
}

pub const ops_theme = [_]Op{
    .{ .section = "destaque de menção" },
    run(toChannel),
    expect("o canal das menções abre (e os nossos cargos chegam)", channelReady),
    .{ .wait = 300 },
    expect("menção direta, resposta que marca, @everyone, @here e cargo nosso destacam; o resto não", allOn),
    expect("o destaque tem contraste com o fundo do tema", visible),
    .{ .shot = "mencao" },
    run(suppressEveryone),
    expect("\"suprimir @everyone e @here\" tira o destaque deles", everyoneOff),
    run(suppressRoles),
    expect("\"suprimir menções a cargos\" tira o do cargo", rolesOff),
    run(restoreEveryone),
    expect("desligar a de @everyone devolve o destaque deles", everyoneBack),
    run(restoreRoles),
    expect("desligar a de cargos devolve o do cargo", backOn),
    run(goHome),
    expect("volta para o canal de antes", atHome),
};
