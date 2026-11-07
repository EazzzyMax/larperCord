//! Figurinhas que dá para enviar: as dos servidores (vêm com o servidor, no
//! READY/GUILD_CREATE, e no GUILD_STICKERS_UPDATE) e os pacotes padrão do
//! Discord (GET /sticker-packs, só quando a aba de figurinhas abre). Também
//! a regra de quem pode mandar o quê e o corpo do envio (`sticker_ids`).
//!
//! Regras (docs.discord.food: Sticker resource e Permissions): as dos pacotes
//! padrão valem para todos; a de um servidor vale nele mesmo; fora dele (outro
//! servidor ou DM) só com Nitro e, num servidor, com USE_EXTERNAL_STICKERS.
const std = @import("std");
const types = @import("types.zig");
const Id = types.Id;

/// USE_EXTERNAL_STICKERS (Permissions).
pub const use_external_stickers: u64 = 1 << 37;
/// Formatos (Sticker Format Types). Lottie é animação vetorial: não desenhamos.
pub const format_png: u8 = 1;
pub const format_apng: u8 = 2;
pub const format_lottie: u8 = 3;
pub const format_gif: u8 = 4;
/// O Discord aceita até 3 figurinhas por mensagem; aqui vai uma por clique.
pub const max_per_message = 3;

/// Nome alocado com o c_allocator.
pub const Sticker = struct {
    id: Id,
    name: []const u8,
    format: u8 = format_png,
    /// Do servidor (0 = de um pacote padrão).
    guild: Id = 0,
    /// O servidor perdeu o nível de impulso que liberava esta.
    available: bool = true,
};

pub const Pack = struct {
    id: Id,
    name: []const u8,
    stickers: []Sticker,
};

pub const Use = enum { ok, needs_nitro, no_permission, unavailable };

/// Dá para mandar `st` numa conversa do servidor `here` (0 = DM), com a nossa
/// assinatura (`premium_type`) e as permissões do canal?
pub fn canSend(st: *const Sticker, here: Id, premium: u8, perms: u64) Use {
    if (!st.available) return .unavailable;
    if (st.guild == 0 or st.guild == here) return .ok;
    // Nitro (2) e Nitro Basic (3) levam figurinhas para qualquer lugar; o
    // Nitro Classic (1) não incluía figurinhas.
    if (premium != 2 and premium != 3) return .needs_nitro;
    if (here != 0 and perms & use_external_stickers == 0) return .no_permission;
    return .ok;
}

/// POST /channels/{id}/messages com uma figurinha.
pub fn sendBody(buf: []u8, sticker: Id, nonce: u64) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{{\"sticker_ids\":[\"{d}\"],\"nonce\":\"{d}\",\"tts\":false}}", .{ sticker, nonce }) catch null;
}

const alloc = std.heap.c_allocator;

fn freeList(list: []Sticker) void {
    for (list) |s| alloc.free(s.name);
    if (list.len > 0) alloc.free(list);
}

pub fn freePacks(packs: []Pack) void {
    for (packs) |p| {
        alloc.free(p.name);
        freeList(p.stickers);
    }
    if (packs.len > 0) alloc.free(packs);
}

pub const PacksState = enum { none, loading, ready, failed };

pub const Book = struct {
    guilds: std.AutoHashMapUnmanaged(Id, []Sticker) = .empty,
    packs: []Pack = &.{},
    packs_state: PacksState = .none,

    /// Troca as figurinhas de um servidor (assume a lista e os nomes).
    pub fn setGuild(b: *Book, guild: Id, list: []Sticker) void {
        if (b.guilds.fetchRemove(guild)) |kv| freeList(kv.value);
        if (list.len == 0) return;
        for (list) |*s| s.guild = guild;
        b.guilds.put(alloc, guild, list) catch freeList(list);
    }

    pub fn setPacks(b: *Book, packs: []Pack, ok: bool) void {
        if (!ok) {
            freePacks(packs);
            if (b.packs_state != .ready) b.packs_state = .failed;
            return;
        }
        freePacks(b.packs);
        b.packs = packs;
        b.packs_state = .ready;
    }

    pub fn deinit(b: *Book) void {
        var it = b.guilds.valueIterator();
        while (it.next()) |l| freeList(l.*);
        b.guilds.deinit(alloc);
        freePacks(b.packs);
        b.* = .{};
    }
};

fn dupName(s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch @panic("sem memória");
}

test "quem pode mandar qual figurinha" {
    const mine: Sticker = .{ .id = 1, .name = "a", .guild = 10 };
    const std_pack: Sticker = .{ .id = 2, .name = "b" };
    const gone: Sticker = .{ .id = 3, .name = "c", .guild = 10, .available = false };
    // Sem Nitro: a do próprio servidor e as padrão.
    try std.testing.expectEqual(Use.ok, canSend(&mine, 10, 0, 0));
    try std.testing.expectEqual(Use.ok, canSend(&std_pack, 10, 0, 0));
    try std.testing.expectEqual(Use.ok, canSend(&std_pack, 0, 0, 0));
    try std.testing.expectEqual(Use.needs_nitro, canSend(&mine, 20, 0, use_external_stickers));
    try std.testing.expectEqual(Use.needs_nitro, canSend(&mine, 0, 0, 0));
    try std.testing.expectEqual(Use.needs_nitro, canSend(&mine, 20, 1, use_external_stickers));
    // Com Nitro: em outro servidor só com a permissão; na DM, sempre.
    try std.testing.expectEqual(Use.no_permission, canSend(&mine, 20, 2, 0));
    try std.testing.expectEqual(Use.ok, canSend(&mine, 20, 2, use_external_stickers));
    try std.testing.expectEqual(Use.ok, canSend(&mine, 0, 3, 0));
    try std.testing.expectEqual(Use.unavailable, canSend(&gone, 10, 2, std.math.maxInt(u64)));
}

test "corpo do envio e a lista de um servidor" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("{\"sticker_ids\":[\"749054660769218631\"],\"nonce\":\"42\",\"tts\":false}", sendBody(&buf, 749054660769218631, 42).?);
    var b: Book = .{};
    defer b.deinit();
    const list = try alloc.alloc(Sticker, 2);
    list[0] = .{ .id = 1, .name = dupName("um") };
    list[1] = .{ .id = 2, .name = dupName("dois") };
    b.setGuild(7, list);
    try std.testing.expectEqual(@as(Id, 7), b.guilds.get(7).?[1].guild);
    // Lista nova troca a velha; vazia apaga.
    const l2 = try alloc.alloc(Sticker, 1);
    l2[0] = .{ .id = 3, .name = dupName("tres") };
    b.setGuild(7, l2);
    try std.testing.expectEqual(@as(usize, 1), b.guilds.get(7).?.len);
    var none: [0]Sticker = .{};
    b.setGuild(7, &none);
    try std.testing.expect(b.guilds.get(7) == null);
    var no_packs: [0]Pack = .{};
    b.setPacks(&no_packs, false);
    try std.testing.expectEqual(PacksState.failed, b.packs_state);
}
