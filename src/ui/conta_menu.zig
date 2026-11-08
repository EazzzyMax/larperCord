//! Entradas dos menus de contexto que mexem na conta no Discord (core/conta.zig):
//! bloquear, ignorar, pedir amizade, silenciar e notificações, status
//! personalizado. ui/popup.zig desenha; aqui fica o que entra e o que cada
//! uma faz. Toda entrada é um clique, um pedido.
const std = @import("std");
const d = @import("draw.zig");
const i18n = @import("i18n.zig");
const state = @import("state.zig");
const types = @import("../core/types.zig");
const conta = @import("../core/conta.zig");
const Item = @import("popup.zig").Item;
const Id = types.Id;

/// Ids das entradas (os outros do popup.zig não usam estes).
const add_friend = 30;
const dm_mute = 31;
const block = 32;
const unblock = 33;
const block_yes = 34;
const ignore = 26;
const guild_mute = 70;
const guild_notif = 71;
const channel_notif = 72;
const lv_all = 73;
const lv_mentions = 74;
const lv_nothing = 75;
const sup_everyone = 76;
const sup_roles = 77;
const lv_inherit = 78;
const channel_mute = 42;
const status_set = 91;
const status_clear = 92;

/// Texto do botão de confirmar o bloqueio (leva o nome).
var block_buf: [128]u8 = undefined;
/// De onde veio o "Bloquear…" que abriu a confirmação (o perfil ou o menu).
var block_from: conta.Origin = .context_menu;

/// Abre a confirmação do bloqueio em (x, y); `from`: de onde foi o clique.
pub fn askBlock(ctx: *d.Ctx, uid: Id, x: f32, y: f32, from: conta.Origin) void {
    block_from = from;
    ctx.popup(.{ .menu = .{ .kind = .block_confirm, .id = uid, .x = x, .y = y } });
}

const List = struct {
    items: []Item,
    n: usize = 0,
    fn add(l: *List, it: Item) void {
        if (l.n < l.items.len) {
            l.items[l.n] = it;
            l.n += 1;
        }
    }
};

/// O canal de DM com alguém (0 = não tem).
fn dmWith(ctx: *d.Ctx, uid: Id) Id {
    for (ctx.store.channelsOf(0)) |ch| if (ctx.store.channel(ch)) |cs| {
        if (!cs.info.group and cs.info.recipient == uid) return ch;
    };
    return 0;
}

/// Pessoa: ignorar (da conta), pedir amizade, silenciar a DM, bloquear.
pub fn userItems(ctx: *d.Ctx, id: Id, out: []Item) usize {
    var l: List = .{ .items = out };
    const u = ctx.store.user(id) orelse return 0;
    if (id == ctx.store.me or u.webhook) return 0;
    const rel = ctx.store.relationship(id);
    if (!u.bot and rel == .none) {
        const fs = ctx.st.conta.friends.get(id);
        if (fs == null or (fs.? != .sending and fs.? != .sent))
            l.add(.{ .label = "Adicionar amigo", .en = "Add Friend", .id = add_friend });
    }
    const dm = dmWith(ctx, id);
    if (dm != 0) l.add(if (ctx.st.conta.channelMuted(0, dm, ctx.now_ms))
        .{ .label = "Reativar conversa", .en = "Unmute Conversation", .id = dm_mute }
    else
        .{ .label = "Silenciar conversa", .en = "Mute Conversation", .id = dm_mute });
    l.add(if (ctx.st.filtros.isIgnored(id))
        .{ .label = "Deixar de ignorar", .en = "Unignore", .id = ignore }
    else
        .{ .label = "Ignorar", .en = "Ignore", .id = ignore });
    l.add(if (rel == .blocked)
        .{ .label = "Desbloquear", .en = "Unblock", .id = unblock }
    else
        .{ .label = "Bloquear…", .en = "Block…", .id = block, .danger = true });
    return l.n;
}

/// Servidor: silenciar inteiro e o nível de notificação.
pub fn guildItems(ctx: *d.Ctx, id: Id, out: []Item) usize {
    var l: List = .{ .items = out };
    l.add(if (ctx.st.conta.guildMuted(id, ctx.now_ms))
        .{ .label = "Reativar servidor", .en = "Unmute Server", .id = guild_mute, .sep = true }
    else
        .{ .label = "Silenciar servidor", .en = "Mute Server", .id = guild_mute, .sep = true });
    l.add(.{ .label = "Notificações…", .en = "Notifications…", .id = guild_notif });
    return l.n;
}

/// Canal, categoria ou grupo: silenciar (pela conta) e o nível.
pub fn channelItems(ctx: *d.Ctx, id: Id, out: []Item) usize {
    var l: List = .{ .items = out };
    const cs = ctx.store.channel(id) orelse return 0;
    if (cs.info.thread != null) return 0;
    l.add(if (ctx.st.conta.channelMuted(cs.info.guild, id, ctx.now_ms))
        .{ .label = "Reativar notificações", .en = "Unmute Channel", .id = channel_mute }
    else
        .{ .label = "Silenciar canal", .en = "Mute Channel", .id = channel_mute });
    l.add(.{ .label = "Notificações do canal…", .en = "Channel Notifications…", .id = channel_notif });
    return l.n;
}

/// Menu do status: o status personalizado.
pub fn statusItems(ctx: *d.Ctx, out: []Item) usize {
    var l: List = .{ .items = out };
    if (ctx.st.conta.custom.active(ctx.now_ms)) {
        l.add(.{ .label = "Editar status personalizado…", .en = "Edit Custom Status…", .id = status_set, .sep = true });
        l.add(.{ .label = "Limpar status personalizado", .en = "Clear Custom Status", .id = status_clear });
    } else l.add(.{ .label = "Definir status personalizado…", .en = "Set Custom Status…", .id = status_set, .sep = true });
    return l.n;
}

/// A escolha do nível (servidor ou canal), com a marca no que vale.
pub fn notifItems(ctx: *d.Ctx, id: Id, out: []Item) usize {
    var l: List = .{ .items = out };
    if (ctx.store.guild(id) != null) {
        const gs = ctx.st.conta.settings(id);
        const lv: ?conta.Level = if (gs) |s| s.level else null;
        l.add(.{ .label = "Todas as mensagens", .en = "All Messages", .id = lv_all, .on = lv == .all });
        l.add(.{ .label = "Só @menções", .en = "Only @mentions", .id = lv_mentions, .on = lv == .mentions });
        l.add(.{ .label = "Nada", .en = "Nothing", .id = lv_nothing, .on = lv == .nothing });
        l.add(.{ .label = "Suprimir @everyone e @here", .en = "Suppress @everyone and @here", .id = sup_everyone, .on = if (gs) |s| s.suppress_everyone else false, .sep = true });
        l.add(.{ .label = "Suprimir menções a cargos", .en = "Suppress All Role @mentions", .id = sup_roles, .on = if (gs) |s| s.suppress_roles else false });
        return l.n;
    }
    const cs = ctx.store.channel(id) orelse return 0;
    const gs = ctx.st.conta.settings(cs.info.guild);
    const lv: conta.Level = if (gs) |s| (if (s.override(id)) |o| o.level else .inherit) else .inherit;
    l.add(.{ .label = if (cs.info.guild == 0) "Padrão das DMs" else "Padrão do servidor", .en = if (cs.info.guild == 0) "Use DM Default" else "Use Server Default", .id = lv_inherit, .on = lv == .inherit });
    l.add(.{ .label = "Todas as mensagens", .en = "All Messages", .id = lv_all, .on = lv == .all });
    l.add(.{ .label = "Só @menções", .en = "Only @mentions", .id = lv_mentions, .on = lv == .mentions });
    l.add(.{ .label = "Nada", .en = "Nothing", .id = lv_nothing, .on = lv == .nothing });
    return l.n;
}

/// Bloquear pede confirmação: some das DMs e a pessoa não te manda mais nada.
pub fn blockItems(ctx: *d.Ctx, id: Id, out: []Item) usize {
    var l: List = .{ .items = out };
    const name = if (ctx.store.user(id)) |u| u.name else "?";
    const label = i18n.fmt(&block_buf, "Bloquear {s}", "Block {s}", .{d.utf8Prefix(name, 40)});
    l.add(.{ .label = label, .en = label, .id = block_yes, .danger = true });
    l.add(.{ .label = "Cancelar", .en = "Cancel", .id = 52 });
    return l.n;
}

fn level(item: u8) conta.Level {
    return switch (item) {
        lv_all => .all,
        lv_mentions => .mentions,
        lv_nothing => .nothing,
        else => .inherit,
    };
}

/// Faz o que a entrada pede. false: a entrada não é daqui.
pub fn choose(ctx: *d.Ctx, kind: state.MenuKind, id: Id, item: u8, r: d.Rect) bool {
    const st = ctx.st;
    switch (item) {
        add_friend => ctx.act(.{ .conta = .{ .friend_request = .{ .user = id, .from = .context_menu } } }),
        dm_mute => {
            const dm = dmWith(ctx, id);
            if (dm == 0) return true;
            ctx.act(.{ .conta = .{ .notif = .{ .target = dm, .change = .{ .channel_mute = .{ .channel = dm, .on = !st.conta.channelMuted(0, dm, ctx.now_ms) } } } } });
        },
        ignore => ctx.act(.{ .conta = .{ .ignore = .{ .user = id, .on = !st.filtros.isIgnored(id) } } }),
        block => askBlock(ctx, id, r.x, r.y, .context_menu),
        block_yes => ctx.act(.{ .conta = .{ .block = .{ .user = id, .from = block_from } } }),
        unblock => ctx.act(.{ .remove_relationship = .{ .user = id, .from = .context_menu } }),
        guild_mute => ctx.act(.{ .conta = .{ .notif = .{ .target = id, .change = .{ .mute = !st.conta.guildMuted(id, ctx.now_ms) } } } }),
        guild_notif, channel_notif => st.popup = .{ .menu = .{ .kind = .notif, .id = id, .x = r.x, .y = r.y } },
        channel_mute => {
            const cs = ctx.store.channel(id) orelse return true;
            ctx.act(.{ .conta = .{ .notif = .{ .target = id, .change = .{ .channel_mute = .{ .channel = id, .on = !st.conta.channelMuted(cs.info.guild, id, ctx.now_ms) } } } } });
        },
        lv_all, lv_mentions, lv_nothing, lv_inherit => {
            if (kind != .notif) return false;
            const change: conta.Change = if (ctx.store.guild(id) != null)
                .{ .level = level(item) }
            else
                .{ .channel_level = .{ .channel = id, .level = level(item) } };
            ctx.act(.{ .conta = .{ .notif = .{ .target = id, .change = change } } });
        },
        sup_everyone, sup_roles => {
            if (kind != .notif) return false;
            const gs = st.conta.settings(id);
            ctx.act(.{ .conta = .{ .notif = .{ .target = id, .change = if (item == sup_everyone)
                .{ .suppress_everyone = !(if (gs) |s| s.suppress_everyone else false) }
            else
                .{ .suppress_roles = !(if (gs) |s| s.suppress_roles else false) } } } });
        },
        status_set => st.popup = .{ .custom_status = .{ .x = r.x, .y = r.y } },
        status_clear => ctx.act(.{ .conta = .clear_custom_status }),
        else => return false,
    }
    return true;
}
