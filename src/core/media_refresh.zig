//! Links de anexo do CDN do Discord expiram (a query `ex`/`is`/`hm`: ver
//! docs.discord.food → Reference → Signed Attachment URLs). Quando uma mídia
//! na tela falha e o link já venceu, pede links novos com
//! POST /attachments/refresh-urls (Cloud Uploads → Refresh Attachment URLs):
//! só os que a tela tentou mostrar ou abrir, juntos num pedido (até 50), cada
//! link uma vez por sessão, e a mídia tenta de novo uma vez com o link novo.
//! Nada aqui varre o histórico nem roda sozinho.
//!
//! Tudo na thread da interface (a tela anota, o Store entrega a resposta).
const std = @import("std");
const jsonx = @import("../net/jsonx.zig");

/// O Discord aceita de 1 a 50 links por pedido.
pub const max_batch = 50;
/// Falhou faltando menos que isso para vencer: conta como vencido.
const margin_s: u64 = 60;
const alloc = std.heap.c_allocator;

/// Um link renovado (textos com o c_allocator).
pub const Pair = struct { original: []const u8, refreshed: []const u8 };

/// Quando o link vence (o `ex`, segundos Unix em hexadecimal), se tiver.
pub fn expiry(url: []const u8) ?u64 {
    const q = std.mem.indexOfScalar(u8, url, '?') orelse return null;
    const end = std.mem.indexOfScalarPos(u8, url, q, '#') orelse url.len;
    var it = std.mem.splitScalar(u8, url[q + 1 .. end], '&');
    while (it.next()) |kv| if (std.mem.startsWith(u8, kv, "ex=")) {
        if (kv.len < 4 or kv.len > 3 + 16) return null;
        return std.fmt.parseInt(u64, kv[3..], 16) catch null;
    };
    return null;
}

/// Link assinado de anexo do Discord (o único que o pedido renova). Os da
/// demonstração ("demo:…?ex=…") entram para o QA.
pub fn refreshable(url: []const u8) bool {
    if (expiry(url) == null) return false;
    if (std.mem.startsWith(u8, url, "demo:")) return true;
    for ([_][]const u8{ "https://cdn.discordapp.com/", "https://media.discordapp.net/" }) |host| {
        if (!std.mem.startsWith(u8, url, host)) continue;
        const path = url[host.len..];
        return std.mem.startsWith(u8, path, "attachments/") or std.mem.startsWith(u8, path, "ephemeral-attachments/");
    }
    return false;
}

pub fn expired(url: []const u8, now_s: i64) bool {
    const ex = expiry(url) orelse return false;
    if (now_s < 0) return false;
    return @as(u64, @intCast(now_s)) + margin_s >= ex;
}

/// O link novo só vale se for do mesmo tipo do pedido (nada de trocar um
/// anexo do Discord por um endereço qualquer).
fn validTarget(original: []const u8, refreshed: []const u8) bool {
    if (std.mem.startsWith(u8, original, "demo:")) return std.mem.startsWith(u8, refreshed, "demo:");
    return refreshable(refreshed) and refreshed.len <= 2048;
}

fn hashOf(url: []const u8) u64 {
    return std.hash.Wyhash.hash(0x5EF2, url);
}

pub const State = struct {
    /// O próximo pedido (cópias).
    pending: std.ArrayList([]const u8) = .empty,
    /// Links já pedidos nesta sessão (cada um vai uma vez só).
    tried: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// Link vencido → o novo (os dois copiados).
    alias: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Clique em algo vencido (abrir arquivo, tocar): abre quando o novo chegar.
    open_hash: u64 = 0,
    open_ready: bool = false,

    /// A mídia `url` falhou na tela. Entra no próximo pedido se o link venceu
    /// e ainda não foi pedido nesta sessão. true = o lote estava vazio: quem
    /// chama avisa o app, que manda o pedido depois do quadro (juntando tudo
    /// o que falhou nele).
    pub fn note(s: *State, url: []const u8, now_s: i64) bool {
        if (!refreshable(url) or !expired(url, now_s)) return false;
        if (s.pending.items.len >= max_batch) return false;
        const h = hashOf(url);
        if (s.tried.contains(h)) return false;
        const copy = alloc.dupe(u8, url) catch return false;
        s.tried.put(alloc, h, {}) catch {
            alloc.free(copy);
            return false;
        };
        s.pending.append(alloc, copy) catch {
            _ = s.tried.remove(h);
            alloc.free(copy);
            return false;
        };
        return s.pending.items.len == 1;
    }

    /// Clique para abrir/tocar algo com o link vencido: pede o novo e lembra
    /// de abrir quando chegar. false = não tem o que renovar (abre como está).
    pub fn requestOpen(s: *State, url: []const u8, now_s: i64) struct { pending: bool, notify: bool } {
        if (!refreshable(url) or !expired(url, now_s) or s.tried.contains(hashOf(url))) return .{ .pending = false, .notify = false };
        const notify = s.note(url, now_s);
        if (!s.tried.contains(hashOf(url))) return .{ .pending = false, .notify = false };
        s.open_hash = hashOf(url);
        s.open_ready = false;
        return .{ .pending = true, .notify = notify };
    }

    /// O link novo de `url` chegou depois de um `requestOpen`? (Uma vez só.)
    pub fn takeOpen(s: *State, url: []const u8) bool {
        if (!s.open_ready or s.open_hash != hashOf(url)) return false;
        s.open_ready = false;
        s.open_hash = 0;
        return true;
    }

    /// O pedido a mandar (a lista e os textos passam para quem chama).
    pub fn takeBatch(s: *State) ?[]const []const u8 {
        if (s.pending.items.len == 0) return null;
        return s.pending.toOwnedSlice(alloc) catch null;
    }

    /// A resposta: assume a lista e os textos.
    pub fn deliver(s: *State, pairs: []const Pair) void {
        defer if (pairs.len > 0) alloc.free(pairs);
        for (pairs) |p| {
            const keep = validTarget(p.original, p.refreshed) and !s.alias.contains(p.original);
            if (keep) {
                if (s.alias.put(alloc, p.original, p.refreshed)) |_| {
                    if (s.open_hash == hashOf(p.original)) s.open_ready = true;
                    continue;
                } else |_| {}
            }
            alloc.free(p.original);
            alloc.free(p.refreshed);
        }
        // Não veio o link do que ia abrir: desiste (o clique vale de novo).
        if (!s.open_ready) s.open_hash = 0;
    }

    /// O link a usar no lugar de `url` (o renovado, se houver). Sem nenhum
    /// renovado na sessão, não custa nada.
    pub fn resolve(s: *const State, url: []const u8) []const u8 {
        if (s.alias.count() == 0) return url;
        return s.alias.get(url) orelse url;
    }

    pub fn deinit(s: *State) void {
        for (s.pending.items) |u| alloc.free(u);
        s.pending.deinit(alloc);
        s.tried.deinit(alloc);
        var it = s.alias.iterator();
        while (it.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        s.alias.deinit(alloc);
        s.* = .{};
    }
};

pub var global: State = .{};

/// {"attachment_urls":[...]}
pub fn body(gpa: std.mem.Allocator, urls: []const []const u8) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.appendSlice(gpa, "{\"attachment_urls\":[");
    for (urls[0..@min(urls.len, max_batch)], 0..) |u, i| {
        if (i > 0) try b.append(gpa, ',');
        try jsonx.writeString(&b, gpa, u);
    }
    try b.appendSlice(gpa, "]}");
    return b.toOwnedSlice(gpa);
}

/// {"refreshed_urls":[{"original":"…","refreshed":"…"}]} → pares (c_allocator).
pub fn parse(json: []const u8) ![]Pair {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), json, .{});
    const list = jsonx.array(jsonx.get(v, "refreshed_urls"));
    var out: std.ArrayList(Pair) = .empty;
    errdefer {
        for (out.items) |p| {
            alloc.free(p.original);
            alloc.free(p.refreshed);
        }
        out.deinit(alloc);
    }
    for (list[0..@min(list.len, max_batch)]) |it| {
        const o = jsonx.str(jsonx.get(it, "original")) orelse continue;
        const r = jsonx.str(jsonx.get(it, "refreshed")) orelse continue;
        const oc = try alloc.dupe(u8, o);
        const rc = alloc.dupe(u8, r) catch |e| {
            alloc.free(oc);
            return e;
        };
        out.append(alloc, .{ .original = oc, .refreshed = rc }) catch |e| {
            alloc.free(oc);
            alloc.free(rc);
            return e;
        };
    }
    return out.toOwnedSlice(alloc);
}

const old = "https://cdn.discordapp.com/attachments/1/2/a.png?ex=65d903de&is=65c68ede&hm=abc";

test "o ex do link diz quando vence; só anexo do Discord é renovável" {
    try std.testing.expectEqual(@as(?u64, 0x65d903de), expiry(old));
    try std.testing.expectEqual(@as(?u64, null), expiry("https://cdn.discordapp.com/attachments/1/2/a.png"));
    try std.testing.expectEqual(@as(?u64, null), expiry("https://x/a?ex=zz"));
    try std.testing.expectEqual(@as(?u64, 0x10), expiry("https://x/a?is=1&ex=10#frag"));
    try std.testing.expect(refreshable(old));
    try std.testing.expect(refreshable("https://media.discordapp.net/attachments/1/2/a.png?ex=1&is=0&hm=x&width=100"));
    try std.testing.expect(!refreshable("https://cdn.discordapp.com/avatars/1/a.png?ex=1"));
    try std.testing.expect(!refreshable("https://evil.example/attachments/1?ex=1"));
    try std.testing.expect(!refreshable("https://cdn.discordapp.com.evil/attachments/1?ex=1"));
    try std.testing.expect(refreshable("demo:expired:1?ex=1"));
    try std.testing.expect(expired(old, 0x65d903de));
    try std.testing.expect(expired(old, 0x65d903de - 30));
    try std.testing.expect(!expired(old, 0x65d903de - 3600));
}

test "lote: só o vencido, cada link uma vez, até 50, e o resto no próximo" {
    var s: State = .{};
    defer s.deinit();
    const now: i64 = 0x70000000;
    try std.testing.expect(s.note(old, now));
    try std.testing.expect(!s.note(old, now)); // já pedido
    try std.testing.expect(!s.note("https://cdn.discordapp.com/attachments/1/2/b.png?ex=7fffffff", now)); // não venceu
    try std.testing.expect(!s.note("https://cdn.discordapp.com/attachments/1/2/c.png", now)); // sem assinatura
    var buf: [128]u8 = undefined;
    for (0..60) |i| {
        const u = try std.fmt.bufPrint(&buf, "https://cdn.discordapp.com/attachments/1/{d}/x.png?ex=1", .{i});
        _ = s.note(u, now);
    }
    const batch = s.takeBatch().?;
    defer {
        for (batch) |u| alloc.free(u);
        alloc.free(batch);
    }
    try std.testing.expectEqual(@as(usize, max_batch), batch.len);
    try std.testing.expectEqualStrings(old, batch[0]);
    try std.testing.expect(s.takeBatch() == null);
    // Os que não couberam entram no próximo lote quando falharem de novo.
    const u = try std.fmt.bufPrint(&buf, "https://cdn.discordapp.com/attachments/1/{d}/x.png?ex=1", .{59});
    try std.testing.expect(s.note(u, now));

    const js = try body(std.testing.allocator, &.{ old, "https://cdn.discordapp.com/attachments/1/2/\"q.png?ex=1" });
    defer std.testing.allocator.free(js);
    try std.testing.expectEqualStrings("{\"attachment_urls\":[\"" ++ old ++ "\",\"https://cdn.discordapp.com/attachments/1/2/\\\"q.png?ex=1\"]}", js);
}

test "resposta: o link novo entra no lugar do velho e o clique pendente abre" {
    var s: State = .{};
    defer s.deinit();
    const now: i64 = 0x70000000;
    try std.testing.expectEqualStrings(old, s.resolve(old));
    const r = s.requestOpen(old, now);
    try std.testing.expect(r.pending and r.notify);
    const batch = s.takeBatch().?;
    for (batch) |u| alloc.free(u);
    alloc.free(batch);
    const fresh = "https://cdn.discordapp.com/attachments/1/2/a.png?ex=7fffffff&is=70000000&hm=def";
    const pairs = try parse("{\"refreshed_urls\":[{\"original\":\"" ++ old ++ "\",\"refreshed\":\"" ++ fresh ++ "\"}," ++
        "{\"original\":\"https://cdn.discordapp.com/attachments/9/9/z.png?ex=1\",\"refreshed\":\"https://evil.example/z.png\"}]}");
    s.deliver(pairs);
    try std.testing.expectEqualStrings(fresh, s.resolve(old));
    // O endereço de fora não entra.
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/attachments/9/9/z.png?ex=1", s.resolve("https://cdn.discordapp.com/attachments/9/9/z.png?ex=1"));
    try std.testing.expect(s.takeOpen(old));
    try std.testing.expect(!s.takeOpen(old));
    // O renovado não vence de novo; o velho não é pedido outra vez.
    try std.testing.expect(!s.note(fresh, now));
    try std.testing.expect(!s.note(old, now));
    try std.testing.expect(!s.requestOpen(old, now).pending);
}
