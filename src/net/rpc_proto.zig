//! Rich Presence: o protocolo que jogos e apps usam para falar com o Discord do
//! computador (o "discord-ipc"). Quadros de [op u32 LE][tamanho u32 LE][JSON].
//! Aqui fica só a parte pura (quadros, comandos, a atividade, o ritmo dos envios
//! e o op 3 do gateway), testada sem sockets. O servidor está em rpc_ipc.zig.
const std = @import("std");
const j = @import("jsonx.zig");
const types = @import("../core/types.zig");
const ev = @import("../core/event.zig");
const i18n = @import("../ui/i18n.zig");
const Value = std.json.Value;
const Allocator = std.mem.Allocator;
const Out = std.ArrayList(u8);

/// Maior quadro aceito: uma atividade cabe com folga em poucos KB.
pub const max_frame: u32 = 64 * 1024;
/// Textos da atividade (details, state…): o limite do Discord, em caracteres.
pub const max_text: usize = 128;

pub const op_handshake: u32 = 0;
pub const op_frame: u32 = 1;
pub const op_close: u32 = 2;
pub const op_ping: u32 = 3;
pub const op_pong: u32 = 4;

pub const Header = struct { op: u32, len: u32 };

/// Cabeçalho de 8 bytes. null = ainda faltam bytes.
pub fn parseHeader(buf: []const u8) error{ Oversized, BadOp }!?Header {
    if (buf.len < 8) return null;
    const op = std.mem.readInt(u32, buf[0..4], .little);
    const len = std.mem.readInt(u32, buf[4..8], .little);
    if (op > op_pong) return error.BadOp;
    if (len > max_frame) return error.Oversized;
    return .{ .op = op, .len = len };
}

pub fn writeFrame(out: *Out, gpa: Allocator, op: u32, payload: []const u8) !void {
    var h: [8]u8 = undefined;
    std.mem.writeInt(u32, h[0..4], op, .little);
    std.mem.writeInt(u32, h[4..8], @intCast(payload.len), .little);
    try out.appendSlice(gpa, &h);
    try out.appendSlice(gpa, payload);
}

/// Texto de tamanho fixo: a atividade inteira passa entre as threads numa
/// alocação só. 512 bytes = 128 caracteres de até 4 bytes.
pub const Text = struct {
    len: u16 = 0,
    buf: [512]u8 = undefined,

    pub fn slice(t: *const Text) []const u8 {
        return t.buf[0..t.len];
    }

    /// Até `max_chars` caracteres, sem cortar um no meio (e parando num
    /// UTF-8 inválido, que o gateway recusaria).
    pub fn set(t: *Text, s: []const u8, max_chars: usize) void {
        var end: usize = 0;
        var chars: usize = 0;
        while (end < s.len and chars < max_chars) {
            const n = std.unicode.utf8ByteSequenceLength(s[end]) catch break;
            if (end + n > s.len or end + n > t.buf.len) break;
            _ = std.unicode.utf8Decode(s[end .. end + n]) catch break;
            end += n;
            chars += 1;
        }
        @memcpy(t.buf[0..end], s[0..end]);
        t.len = @intCast(end);
    }
};

/// O que o jogo pediu, já limpo e cortado nos limites do Discord.
pub const Activity = struct {
    /// 0 jogando, 2 ouvindo, 3 assistindo, 5 competindo (o que o RPC aceita).
    kind: u8 = 0,
    details: Text = .{},
    state: Text = .{},
    /// ms Unix (0 = não diz).
    start_ms: i64 = 0,
    end_ms: i64 = 0,
    large_image: Text = .{},
    large_text: Text = .{},
    small_image: Text = .{},
    small_text: Text = .{},
    party_id: Text = .{},
    /// (atual, máximo); 0 = sem tamanho.
    party_size: [2]u32 = .{ 0, 0 },
    instance: bool = false,

    pub fn eql(a: *const Activity, b: *const Activity) bool {
        if (a.kind != b.kind or a.start_ms != b.start_ms or a.end_ms != b.end_ms or a.instance != b.instance) return false;
        if (a.party_size[0] != b.party_size[0] or a.party_size[1] != b.party_size[1]) return false;
        inline for (.{ "details", "state", "large_image", "large_text", "small_image", "small_text", "party_id" }) |f| {
            if (!std.mem.eql(u8, @field(a, f).slice(), @field(b, f).slice())) return false;
        }
        return true;
    }
};

/// Texto da atividade: 2 a 128 caracteres (menos que 2 o Discord recusa).
fn setText(t: *Text, v: ?Value) void {
    const s = j.str(v) orelse return;
    t.set(s, max_text);
    if ((std.unicode.utf8CountCodepoints(t.slice()) catch 0) < 2) t.len = 0;
}

/// Chave de imagem: inteira ou nada (cortada, apontaria para outra).
fn setKey(t: *Text, v: ?Value) void {
    const s = j.str(v) orelse return;
    if (s.len > t.buf.len) return;
    t.set(s, t.buf.len);
    if (t.len != s.len) t.len = 0;
}

/// Tempo em ms. As bibliotecas costumam mandar em segundos.
fn toMs(v: ?Value) i64 {
    const t = j.int(v) orelse return 0;
    if (t <= 0) return 0;
    if (t < 100_000_000_000) return t * 1000;
    if (t > 100_000_000_000_000) return 0;
    return t;
}

/// null = não é um objeto (resposta de erro para o jogo).
pub fn parseActivity(v: Value) ?Activity {
    if (v != .object) return null;
    var a: Activity = .{};
    const kind = j.int(j.get(v, "type")) orelse 0;
    a.kind = switch (kind) {
        2, 3, 5 => @intCast(kind),
        else => 0,
    };
    setText(&a.details, j.get(v, "details"));
    setText(&a.state, j.get(v, "state"));
    if (j.get(v, "timestamps")) |ts| {
        a.start_ms = toMs(j.get(ts, "start"));
        a.end_ms = toMs(j.get(ts, "end"));
    }
    if (j.get(v, "assets")) |as| {
        setKey(&a.large_image, j.get(as, "large_image"));
        setText(&a.large_text, j.get(as, "large_text"));
        setKey(&a.small_image, j.get(as, "small_image"));
        setText(&a.small_text, j.get(as, "small_text"));
    }
    if (j.get(v, "party")) |p| {
        setText(&a.party_id, j.get(p, "id"));
        const size = j.array(j.get(p, "size"));
        if (size.len == 2) {
            const cur = j.int(size[0]) orelse 0;
            const max = j.int(size[1]) orelse 0;
            if (cur > 0 and max >= cur and max <= 1_000_000) a.party_size = .{ @intCast(cur), @intCast(max) };
        }
    }
    if (j.get(v, "instance")) |x| a.instance = x == .bool and x.bool;
    return a;
}

/// Uma imagem da aplicação (GET /oauth2/applications/{id}/assets).
pub const Asset = struct {
    id: u64,
    name: Text = .{},
};

/// A chave da imagem como o gateway aceita: "mp:…" e IDs passam, nomes viram
/// o ID da imagem da aplicação. `assets` null = como veio (resposta ao jogo).
fn imageKey(buf: []u8, key: []const u8, assets: ?[]const Asset) ?[]const u8 {
    if (key.len == 0) return null;
    const list = assets orelse return key;
    if (std.mem.startsWith(u8, key, "mp:")) return key;
    for (key) |ch| {
        if (!std.ascii.isDigit(ch)) break;
    } else return key;
    for (list) |*as| if (std.ascii.eqlIgnoreCase(as.name.slice(), key)) return std.fmt.bufPrint(buf, "{d}", .{as.id}) catch null;
    // URL de fora ou nome que a aplicação não tem: fica sem a imagem.
    return null;
}

fn field(out: *Out, gpa: Allocator, first: *bool, name: []const u8, s: []const u8) !void {
    if (s.len == 0) return;
    if (!first.*) try out.append(gpa, ',');
    first.* = false;
    try j.writeString(out, gpa, name);
    try out.append(gpa, ':');
    try j.writeString(out, gpa, s);
}

/// A atividade como o gateway (op 3) e a resposta do SET_ACTIVITY esperam.
pub fn writeActivity(out: *Out, gpa: Allocator, a: *const Activity, app: u64, name: []const u8, assets: ?[]const Asset) !void {
    try out.print(gpa, "{{\"type\":{d},\"name\":", .{a.kind});
    try j.writeString(out, gpa, name);
    try out.print(gpa, ",\"application_id\":\"{d}\"", .{app});
    var first = false;
    try field(out, gpa, &first, "details", a.details.slice());
    try field(out, gpa, &first, "state", a.state.slice());
    if (a.start_ms != 0 or a.end_ms != 0) {
        try out.appendSlice(gpa, ",\"timestamps\":{");
        if (a.start_ms != 0) try out.print(gpa, "\"start\":{d}", .{a.start_ms});
        if (a.end_ms != 0) try out.print(gpa, "{s}\"end\":{d}", .{ if (a.start_ms != 0) "," else "", a.end_ms });
        try out.append(gpa, '}');
    }
    var lb: [24]u8 = undefined;
    var sb: [24]u8 = undefined;
    const large = imageKey(&lb, a.large_image.slice(), assets) orelse "";
    const small = imageKey(&sb, a.small_image.slice(), assets) orelse "";
    if (large.len + small.len + a.large_text.len + a.small_text.len > 0) {
        try out.appendSlice(gpa, ",\"assets\":{");
        var f = true;
        try field(out, gpa, &f, "large_image", large);
        try field(out, gpa, &f, "large_text", a.large_text.slice());
        try field(out, gpa, &f, "small_image", small);
        try field(out, gpa, &f, "small_text", a.small_text.slice());
        try out.append(gpa, '}');
    }
    if (a.party_id.len > 0 or a.party_size[1] > 0) {
        try out.appendSlice(gpa, ",\"party\":{");
        var f = true;
        try field(out, gpa, &f, "id", a.party_id.slice());
        if (a.party_size[1] > 0) try out.print(gpa, "{s}\"size\":[{d},{d}]", .{ if (f) "" else ",", a.party_size[0], a.party_size[1] });
        try out.append(gpa, '}');
    }
    // "instance" também vira a flag INSTANCE, como o cliente oficial manda.
    if (a.instance) try out.appendSlice(gpa, ",\"instance\":true,\"flags\":1");
    try out.append(gpa, '}');
}

/// Quem somos, para o READY do handshake.
pub const Me = struct {
    id: u64 = 0,
    username: Text = .{},
    global_name: Text = .{},
    /// Hash do avatar no CDN ("" = sem foto).
    avatar: Text = .{},
};

fn writeNullable(out: *Out, gpa: Allocator, s: []const u8) !void {
    if (s.len == 0) return out.appendSlice(gpa, "null");
    try j.writeString(out, gpa, s);
}

/// O nonce volta como veio (texto ou número); o resto vira null.
fn writeNonce(out: *Out, gpa: Allocator, v: ?Value) !void {
    const x = v orelse return out.appendSlice(gpa, "null");
    switch (x) {
        .string => |s| {
            var t: Text = .{};
            t.set(s, 256);
            try j.writeString(out, gpa, t.slice());
        },
        .integer => |i| try out.print(gpa, "{d}", .{i}),
        else => try out.appendSlice(gpa, "null"),
    }
}

fn readyPayload(out: *Out, gpa: Allocator, me: *const Me) !void {
    try out.appendSlice(gpa, "{\"cmd\":\"DISPATCH\",\"evt\":\"READY\",\"data\":{\"v\":1,\"config\":{\"cdn_host\":\"cdn.discordapp.com\",\"api_endpoint\":\"//discord.com/api\",\"environment\":\"production\"},\"user\":{");
    try out.print(gpa, "\"id\":\"{d}\",\"username\":", .{me.id});
    try j.writeString(out, gpa, me.username.slice());
    try out.appendSlice(gpa, ",\"discriminator\":\"0\",\"global_name\":");
    try writeNullable(out, gpa, me.global_name.slice());
    try out.appendSlice(gpa, ",\"avatar\":");
    try writeNullable(out, gpa, me.avatar.slice());
    try out.appendSlice(gpa, ",\"bot\":false,\"flags\":0,\"premium_type\":0}},\"nonce\":null}");
}

/// O estado de uma conexão: handshake, depois comandos.
pub const Conn = struct {
    handshaken: bool = false,
    client_id: u64 = 0,
    /// Processo que pediu a atividade (0 = não disse).
    pid: i64 = 0,
    /// O último pedido desta conexão (null = nenhuma atividade).
    activity: ?Activity = null,
    /// Ordem do pedido entre as conexões: a mais recente é a que vale.
    seq: u64 = 0,
    /// Bytes que ainda não formam um quadro inteiro.
    pending: Out = .empty,

    pub const Result = enum { keep, changed, close };

    pub fn deinit(conn: *Conn, gpa: Allocator) void {
        conn.pending.deinit(gpa);
    }

    /// Junta o que chegou e trata cada quadro inteiro; as respostas vão para
    /// `out`. `changed`: a atividade desta conexão mudou. `close`: manda o
    /// que estiver em `out` e fecha (quadro inválido, grande demais, CLOSE).
    pub fn feed(conn: *Conn, gpa: Allocator, bytes: []const u8, me: *const Me, out: *Out) Result {
        conn.pending.appendSlice(gpa, bytes) catch return .close;
        var result: Result = .keep;
        var off: usize = 0;
        defer if (off > 0) {
            const rest = conn.pending.items.len - off;
            std.mem.copyForwards(u8, conn.pending.items[0..rest], conn.pending.items[off..]);
            conn.pending.shrinkRetainingCapacity(rest);
        };
        while (true) {
            const h = (parseHeader(conn.pending.items[off..]) catch {
                writeClose(out, gpa, 4000, "invalid frame") catch {};
                return .close;
            }) orelse break;
            if (conn.pending.items.len - off < 8 + h.len) break;
            const payload = conn.pending.items[off + 8 .. off + 8 + h.len];
            off += 8 + h.len;
            switch (conn.handle(gpa, h.op, payload, me, out)) {
                .keep => {},
                .changed => result = .changed,
                .close => return .close,
            }
        }
        // Sem quadros pendentes, a memória da conexão volta ao tamanho de um cabeçalho.
        if (conn.pending.items.len == off and conn.pending.capacity > 4096) {
            conn.pending.clearAndFree(gpa);
            off = 0;
        }
        return result;
    }

    /// Um quadro inteiro.
    pub fn handle(conn: *Conn, gpa: Allocator, op: u32, payload: []const u8, me: *const Me, out: *Out) Result {
        switch (op) {
            op_ping => {
                writeFrame(out, gpa, op_pong, payload) catch return .close;
                return .keep;
            },
            op_pong => return .keep,
            op_close => return .close,
            else => {},
        }
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), payload, .{}) catch {
            writeClose(out, gpa, 4000, "invalid payload") catch {};
            return .close;
        };
        if (op == op_handshake) {
            if (conn.handshaken) {
                writeClose(out, gpa, 4000, "already connected") catch {};
                return .close;
            }
            const version = j.int(j.get(v, "v")) orelse 0;
            const id = j.id(j.get(v, "client_id")) orelse 0;
            if (version != 1 or id == 0) {
                writeClose(out, gpa, 4000, "invalid handshake") catch {};
                return .close;
            }
            conn.handshaken = true;
            conn.client_id = id;
            var p: Out = .empty;
            defer p.deinit(gpa);
            readyPayload(&p, gpa, me) catch return .close;
            writeFrame(out, gpa, op_frame, p.items) catch return .close;
            return .keep;
        }
        // op_frame
        if (!conn.handshaken or v != .object) {
            writeClose(out, gpa, 4000, if (conn.handshaken) "invalid payload" else "handshake first") catch {};
            return .close;
        }
        const cmd = j.str(j.get(v, "cmd")) orelse "";
        const nonce = j.get(v, "nonce");
        if (!std.mem.eql(u8, cmd, "SET_ACTIVITY")) {
            writeError(out, gpa, cmd, nonce, "not supported") catch return .close;
            return .keep;
        }
        const args = j.get(v, "args") orelse Value{ .null = {} };
        const av = j.get(args, "activity");
        var next: ?Activity = null;
        if (!j.isNull(av)) {
            next = parseActivity(av.?) orelse {
                writeError(out, gpa, cmd, nonce, "invalid activity") catch return .close;
                return .keep;
            };
        }
        var p: Out = .empty;
        defer p.deinit(gpa);
        reply(&p, gpa, if (next) |*a| a else null, conn.client_id, nonce) catch return .close;
        writeFrame(out, gpa, op_frame, p.items) catch return .close;
        conn.activity = next;
        conn.pid = j.int(j.get(args, "pid")) orelse 0;
        return .changed;
    }
};

/// Resposta do SET_ACTIVITY: a atividade como ficou (ou null).
fn reply(p: *Out, gpa: Allocator, act: ?*const Activity, app: u64, nonce: ?Value) !void {
    try p.appendSlice(gpa, "{\"cmd\":\"SET_ACTIVITY\",\"data\":");
    if (act) |a| try writeActivity(p, gpa, a, app, "", null) else try p.appendSlice(gpa, "null");
    try p.appendSlice(gpa, ",\"evt\":null,\"nonce\":");
    try writeNonce(p, gpa, nonce);
    try p.append(gpa, '}');
}

fn writeClose(out: *Out, gpa: Allocator, code: u32, message: []const u8) !void {
    var b: [128]u8 = undefined;
    const p = try std.fmt.bufPrint(&b, "{{\"code\":{d},\"message\":\"{s}\"}}", .{ code, message });
    try writeFrame(out, gpa, op_close, p);
}

fn writeError(out: *Out, gpa: Allocator, cmd: []const u8, nonce: ?Value, message: []const u8) !void {
    var p: Out = .empty;
    defer p.deinit(gpa);
    var t: Text = .{};
    t.set(cmd, 64);
    try p.appendSlice(gpa, "{\"cmd\":");
    try j.writeString(&p, gpa, t.slice());
    try p.print(gpa, ",\"evt\":\"ERROR\",\"data\":{{\"code\":4000,\"message\":\"{s}\"}},\"nonce\":", .{message});
    try writeNonce(&p, gpa, nonce);
    try p.append(gpa, '}');
    try writeFrame(out, gpa, op_frame, p.items);
}

/// No máximo um envio a cada `interval_ms`; o que chega no meio espera e só o
/// mais novo vai.
pub const Throttle = struct {
    interval_ms: i64,
    last_ms: ?i64 = null,
    dirty: bool = false,

    /// Tem mudança esperando e já pode ir? (marca o envio)
    pub fn take(t: *Throttle, now: i64) bool {
        if (!t.dirty) return false;
        if (t.last_ms) |l| if (now - l < t.interval_ms) return false;
        t.dirty = false;
        t.last_ms = now;
        return true;
    }

    /// Quanto falta para poder mandar (null = nada esperando).
    pub fn waitMs(t: *const Throttle, now: i64) ?i64 {
        if (!t.dirty) return null;
        const l = t.last_ms orelse return 0;
        return @max(0, l + t.interval_ms - now);
    }
};

/// Qual atividade vale entre as conexões (a do pedido mais recente que ainda
/// está de pé) e quando ela pode ir para o gateway.
pub const Hub = struct {
    throttle: Throttle,
    seq: u64 = 0,
    /// O que foi entregue por último: não repete, e a limpeza final sempre vai.
    sent_app: u64 = 0,
    sent: ?Activity = null,
    want_app: u64 = 0,
    want: ?Activity = null,

    pub fn nextSeq(h: *Hub) u64 {
        h.seq += 1;
        return h.seq;
    }

    /// Recalcula depois de qualquer mudança nas conexões.
    pub fn update(h: *Hub, conns: []const *const Conn) void {
        var best: ?*const Conn = null;
        for (conns) |cn| if (cn.activity != null and (best == null or cn.seq > best.?.seq)) {
            best = cn;
        };
        h.want = if (best) |b| b.activity else null;
        h.want_app = if (best) |b| b.client_id else 0;
        const same = if (h.want) |*w| (h.sent != null and h.sent_app == h.want_app and w.eql(&h.sent.?)) else h.sent == null;
        h.throttle.dirty = !same;
    }

    pub const Update = struct { app: u64, activity: ?Activity };

    /// O que mandar agora, se o ritmo deixa.
    pub fn take(h: *Hub, now: i64) ?Update {
        if (!h.throttle.take(now)) return null;
        h.sent = h.want;
        h.sent_app = h.want_app;
        return .{ .app = h.want_app, .activity = h.want };
    }
};

/// Do lado do gateway: nome e imagens de cada aplicação (buscados uma vez) e a
/// atividade de agora já como JSON, que vai no op 3 e no IDENTIFY.
pub const Presence = struct {
    apps: std.AutoHashMapUnmanaged(u64, App) = .empty,
    /// null = nenhuma atividade.
    current: ?[]u8 = null,
    current_app: u64 = 0,

    pub const App = struct {
        /// "" = a aplicação não existe (não manda atividade sem nome).
        name: []u8,
        assets: []Asset,
    };

    pub fn deinit(p: *Presence, gpa: Allocator) void {
        var it = p.apps.valueIterator();
        while (it.next()) |a| {
            gpa.free(a.name);
            gpa.free(a.assets);
        }
        p.apps.deinit(gpa);
        if (p.current) |cur| gpa.free(cur);
        p.* = .{};
    }

    pub fn known(p: *const Presence, app: u64) bool {
        return p.apps.contains(app);
    }

    /// Respostas de GET /applications/{id}/rpc e /oauth2/applications/{id}/assets.
    /// `rpc` null = não deu para perguntar (tenta de novo no próximo pedido);
    /// `missing`: a aplicação não existe (não pergunta mais).
    pub fn learn(p: *Presence, gpa: Allocator, app: u64, rpc: ?[]const u8, missing: bool, assets: ?[]const u8) void {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var name: []const u8 = "";
        if (rpc) |body| {
            const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return;
            name = j.str(j.get(v, "name")) orelse "";
        } else if (!missing) return;
        var t: Text = .{};
        t.set(name, max_text);
        var list: std.ArrayList(Asset) = .empty;
        defer list.deinit(gpa);
        if (assets) |body| if (std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{})) |v| {
            for (j.array(v)) |as| {
                if (list.items.len == 256) break;
                const id = j.id(j.get(as, "id")) orelse continue;
                var a: Asset = .{ .id = id };
                a.name.set(j.str(j.get(as, "name")) orelse continue, 64);
                list.append(gpa, a) catch break;
            }
        } else |_| {};
        const owned_name = gpa.dupe(u8, t.slice()) catch return;
        const owned_assets = list.toOwnedSlice(gpa) catch {
            gpa.free(owned_name);
            return;
        };
        const gop = p.apps.getOrPut(gpa, app) catch {
            gpa.free(owned_name);
            gpa.free(owned_assets);
            return;
        };
        if (gop.found_existing) {
            gpa.free(gop.value_ptr.name);
            gpa.free(gop.value_ptr.assets);
        }
        gop.value_ptr.* = .{ .name = owned_name, .assets = owned_assets };
    }

    /// Troca a atividade de agora (null limpa). Sem nome conhecido, fica sem
    /// atividade: o Discord não aceita uma sem nome.
    pub fn set(p: *Presence, gpa: Allocator, app: u64, act: ?*const Activity) void {
        if (p.current) |cur| gpa.free(cur);
        p.current = null;
        p.current_app = 0;
        const a = act orelse return;
        const info = p.apps.get(app) orelse return;
        if (info.name.len == 0) return;
        var out: Out = .empty;
        writeActivity(&out, gpa, a, app, info.name, info.assets) catch {
            out.deinit(gpa);
            return;
        };
        p.current = out.toOwnedSlice(gpa) catch {
            out.deinit(gpa);
            return;
        };
        p.current_app = app;
    }

    /// `"activities":[…]` com a atividade de agora (ou vazio).
    pub fn writeActivities(p: *const Presence, out: *Out, gpa: Allocator) !void {
        try out.appendSlice(gpa, "\"activities\":[");
        if (p.current) |cur| try out.appendSlice(gpa, cur);
        try out.append(gpa, ']');
    }

    /// O op 3 inteiro: o status de agora com a atividade.
    pub fn writeOp3(p: *const Presence, out: *Out, gpa: Allocator, status: []const u8) !void {
        try out.print(gpa, "{{\"op\":3,\"d\":{{\"status\":\"{s}\",\"since\":0,", .{status});
        try p.writeActivities(out, gpa);
        try out.appendSlice(gpa, ",\"afk\":false}}");
    }

    /// A nossa linha na interface (painel e perfil) com a atividade de agora.
    /// Textos alocados com `ea` (o Store assume).
    pub fn meEvent(p: *const Presence, ea: Allocator, me: types.Id, status: types.Status) ev.Event {
        const empty: ev.Event = .{ .presence_update = .{ .user = me, .status = status, .activity = "", .activities = ea.alloc(types.Activity, 0) catch null } };
        const cur = p.current orelse return empty;
        var arena = std.heap.ArenaAllocator.init(ea);
        defer arena.deinit();
        const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), cur, .{}) catch return empty;
        const name = j.str(j.get(v, "name")) orelse return empty;
        const kind = j.int(j.get(v, "type")) orelse 0;
        const prefix: []const u8 = switch (kind) {
            2 => i18n.tr("Ouvindo ", "Listening to "),
            3 => i18n.tr("Assistindo ", "Watching "),
            5 => i18n.tr("Competindo em ", "Competing in "),
            else => i18n.tr("Jogando ", "Playing "),
        };
        const text = std.fmt.allocPrint(ea, "{s}{s}", .{ prefix, name }) catch return empty;
        const list = ea.alloc(types.Activity, 1) catch {
            ea.free(text);
            return empty;
        };
        const ts = j.get(v, "timestamps");
        var ib: [160]u8 = undefined;
        const img = imageUrl(&ib, p.current_app, if (j.get(v, "assets")) |as| j.str(j.get(as, "large_image")) orelse "" else "");
        list[0] = .{
            .kind = @intCast(std.math.clamp(kind, 0, 255)),
            .name = dupe(ea, name),
            .details = dupe(ea, j.str(j.get(v, "details")) orelse ""),
            .state = dupe(ea, j.str(j.get(v, "state")) orelse ""),
            .start_ms = if (ts) |t| j.int(j.get(t, "start")) orelse 0 else 0,
            .end_ms = if (ts) |t| j.int(j.get(t, "end")) orelse 0 else 0,
            .image = dupe(ea, img),
            .app = p.current_app,
        };
        return .{ .presence_update = .{ .user = me, .status = status, .activity = text, .activities = list } };
    }
};

fn dupe(ea: Allocator, s: []const u8) []const u8 {
    return if (s.len == 0) "" else ea.dupe(u8, s) catch "";
}

/// A imagem grande como URL que o cache de imagens aceita (igual às atividades
/// dos outros, em discord.zig).
fn imageUrl(buf: []u8, app: u64, key: []const u8) []const u8 {
    if (std.mem.startsWith(u8, key, "mp:")) return std.fmt.bufPrint(buf, "https://media.discordapp.net/{s}", .{key[3..]}) catch "";
    if (key.len == 0 or app == 0) return "";
    for (key) |ch| if (!std.ascii.isDigit(ch)) return "";
    return std.fmt.bufPrint(buf, "https://cdn.discordapp.com/app-assets/{d}/{s}.png", .{ app, key }) catch "";
}

// --- Testes -----------------------------------------------------------------------

const testing = std.testing;
const ta = testing.allocator;

fn frame(out: *Out, op: u32, payload: []const u8) void {
    writeFrame(out, ta, op, payload) catch unreachable;
}

/// Os quadros de `bytes`, um por um: (op, JSON).
fn frames(bytes: []const u8, i: usize) ?struct { op: u32, body: []const u8 } {
    var off: usize = 0;
    var k: usize = 0;
    while (off + 8 <= bytes.len) {
        const h = (parseHeader(bytes[off..]) catch return null).?;
        if (k == i) return .{ .op = h.op, .body = bytes[off + 8 .. off + 8 + h.len] };
        off += 8 + h.len;
        k += 1;
    }
    return null;
}

fn testMe() Me {
    var me: Me = .{ .id = 42 };
    me.username.set("fulano", 64);
    me.global_name.set("Fulano", 64);
    return me;
}

test "cabeçalho: curto, grande demais, op desconhecido" {
    try testing.expectEqual(@as(?Header, null), try parseHeader("\x00\x00\x00"));
    var b: [8]u8 = undefined;
    std.mem.writeInt(u32, b[0..4], 1, .little);
    std.mem.writeInt(u32, b[4..8], max_frame + 1, .little);
    try testing.expectError(error.Oversized, parseHeader(&b));
    std.mem.writeInt(u32, b[0..4], 9, .little);
    std.mem.writeInt(u32, b[4..8], 2, .little);
    try testing.expectError(error.BadOp, parseHeader(&b));
    std.mem.writeInt(u32, b[0..4], 3, .little);
    try testing.expectEqual(@as(u32, 2), (try parseHeader(&b)).?.len);
}

test "handshake responde READY com o nosso usuário, em pedaços" {
    const me = testMe();
    var conn: Conn = .{};
    defer conn.deinit(ta);
    var in: Out = .empty;
    defer in.deinit(ta);
    frame(&in, op_handshake, "{\"v\":1,\"client_id\":\"123456789\"}");
    var out: Out = .empty;
    defer out.deinit(ta);
    // Chega aos poucos: nada até o quadro estar inteiro.
    try testing.expectEqual(Conn.Result.keep, conn.feed(ta, in.items[0..5], &me, &out));
    try testing.expectEqual(@as(usize, 0), out.items.len);
    try testing.expectEqual(Conn.Result.keep, conn.feed(ta, in.items[5..], &me, &out));
    const f = frames(out.items, 0).?;
    try testing.expectEqual(op_frame, f.op);
    try testing.expect(std.mem.indexOf(u8, f.body, "\"evt\":\"READY\"") != null);
    try testing.expect(std.mem.indexOf(u8, f.body, "\"id\":\"42\",\"username\":\"fulano\",\"discriminator\":\"0\",\"global_name\":\"Fulano\",\"avatar\":null") != null);
    try testing.expect(std.mem.indexOf(u8, f.body, "\"cdn_host\":\"cdn.discordapp.com\"") != null);
    try testing.expect(conn.handshaken);
    try testing.expectEqual(@as(u64, 123456789), conn.client_id);
}

test "comando antes do handshake, handshake ruim ou repetido fecham" {
    const me = testMe();
    var out: Out = .empty;
    defer out.deinit(ta);
    {
        var conn: Conn = .{};
        defer conn.deinit(ta);
        try testing.expectEqual(Conn.Result.close, conn.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{}}", &me, &out));
        try testing.expectEqual(op_close, frames(out.items, 0).?.op);
    }
    for ([_][]const u8{ "{\"v\":2,\"client_id\":\"1\"}", "{\"v\":1}", "{\"v\":1,\"client_id\":\"abc\"}", "[1,2]", "{nada" }) |bad| {
        var conn: Conn = .{};
        defer conn.deinit(ta);
        try testing.expectEqual(Conn.Result.close, conn.handle(ta, op_handshake, bad, &me, &out));
        try testing.expect(!conn.handshaken);
    }
    var conn: Conn = .{};
    defer conn.deinit(ta);
    try testing.expectEqual(Conn.Result.keep, conn.handle(ta, op_handshake, "{\"v\":1,\"client_id\":\"7\"}", &me, &out));
    try testing.expectEqual(Conn.Result.close, conn.handle(ta, op_handshake, "{\"v\":1,\"client_id\":\"7\"}", &me, &out));
}

test "quadro grande demais, op inválido e lixo fecham sem estourar" {
    const me = testMe();
    var out: Out = .empty;
    defer out.deinit(ta);
    var big: [8]u8 = undefined;
    std.mem.writeInt(u32, big[0..4], op_frame, .little);
    std.mem.writeInt(u32, big[4..8], 0xFFFF_FFFF, .little);
    var conn: Conn = .{};
    defer conn.deinit(ta);
    try testing.expectEqual(Conn.Result.close, conn.feed(ta, &big, &me, &out));
    var c2: Conn = .{};
    defer c2.deinit(ta);
    try testing.expectEqual(Conn.Result.close, c2.feed(ta, "GET / HTTP/1.1\r\n\r\n", &me, &out));
    // JSON quebrado depois do handshake também fecha.
    var c3: Conn = .{};
    defer c3.deinit(ta);
    _ = c3.handle(ta, op_handshake, "{\"v\":1,\"client_id\":\"7\"}", &me, &out);
    try testing.expectEqual(Conn.Result.close, c3.handle(ta, op_frame, "{\"cmd\":", &me, &out));
}

test "SET_ACTIVITY: responde com o mesmo nonce, corta textos e limpa com null" {
    const me = testMe();
    var conn: Conn = .{};
    defer conn.deinit(ta);
    var out: Out = .empty;
    defer out.deinit(ta);
    _ = conn.handle(ta, op_handshake, "{\"v\":1,\"client_id\":\"99\"}", &me, &out);
    out.clearRetainingCapacity();
    // 200 "á" (2 bytes cada): passa dos 128 caracteres.
    var long: [400]u8 = undefined;
    for (0..200) |i| long[i * 2 ..][0..2].* = "\u{e1}".*;
    var rb: [1024]u8 = undefined;
    const req = try std.fmt.bufPrint(&rb, "{{\"cmd\":\"SET_ACTIVITY\",\"nonce\":\"n-1\",\"args\":{{\"pid\":1234,\"activity\":{{\"details\":\"{s}\",\"state\":\"No menu\",\"type\":3,\"timestamps\":{{\"start\":1700000000}},\"assets\":{{\"large_image\":\"logo\",\"large_text\":\"x\"}},\"party\":{{\"id\":\"p1\",\"size\":[2,4]}},\"instance\":true}}}}}}", .{&long});
    try testing.expectEqual(Conn.Result.changed, conn.handle(ta, op_frame, req, &me, &out));
    const a = conn.activity.?;
    try testing.expectEqual(@as(usize, 128), try std.unicode.utf8CountCodepoints(a.details.slice()));
    try testing.expectEqualStrings("No menu", a.state.slice());
    try testing.expectEqual(@as(u8, 3), a.kind);
    try testing.expectEqual(@as(i64, 1700000000000), a.start_ms);
    // Texto de 1 caractere o Discord recusa: fica de fora.
    try testing.expectEqual(@as(u16, 0), a.large_text.len);
    try testing.expectEqual([2]u32{ 2, 4 }, a.party_size);
    try testing.expectEqual(@as(i64, 1234), conn.pid);
    const f = frames(out.items, 0).?;
    try testing.expect(std.mem.indexOf(u8, f.body, "\"nonce\":\"n-1\"") != null);
    try testing.expect(std.mem.indexOf(u8, f.body, "\"application_id\":\"99\"") != null);
    try testing.expect(std.mem.indexOf(u8, f.body, "\"large_image\":\"logo\"") != null);
    // A resposta é JSON válido.
    const parsed = try std.json.parseFromSlice(Value, ta, f.body, .{});
    parsed.deinit();
    out.clearRetainingCapacity();
    try testing.expectEqual(Conn.Result.changed, conn.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"nonce\":7,\"args\":{\"pid\":1234,\"activity\":null}}", &me, &out));
    try testing.expect(conn.activity == null);
    try testing.expect(std.mem.indexOf(u8, frames(out.items, 0).?.body, "\"data\":null,\"evt\":null,\"nonce\":7") != null);
}

test "comandos sem suporte respondem ERROR 4000; PING vira PONG" {
    const me = testMe();
    var conn: Conn = .{};
    defer conn.deinit(ta);
    var out: Out = .empty;
    defer out.deinit(ta);
    _ = conn.handle(ta, op_handshake, "{\"v\":1,\"client_id\":\"99\"}", &me, &out);
    out.clearRetainingCapacity();
    try testing.expectEqual(Conn.Result.keep, conn.handle(ta, op_frame, "{\"cmd\":\"AUTHORIZE\",\"nonce\":\"a\",\"args\":{}}", &me, &out));
    try testing.expectEqualStrings("{\"cmd\":\"AUTHORIZE\",\"evt\":\"ERROR\",\"data\":{\"code\":4000,\"message\":\"not supported\"},\"nonce\":\"a\"}", frames(out.items, 0).?.body);
    out.clearRetainingCapacity();
    // Atividade que não é objeto: erro, a conexão continua.
    try testing.expectEqual(Conn.Result.keep, conn.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"activity\":5}}", &me, &out));
    try testing.expect(std.mem.indexOf(u8, frames(out.items, 0).?.body, "\"evt\":\"ERROR\"") != null);
    out.clearRetainingCapacity();
    try testing.expectEqual(Conn.Result.keep, conn.handle(ta, op_ping, "{\"x\":1}", &me, &out));
    const f = frames(out.items, 0).?;
    try testing.expectEqual(op_pong, f.op);
    try testing.expectEqualStrings("{\"x\":1}", f.body);
    try testing.expectEqual(Conn.Result.close, conn.handle(ta, op_close, "{}", &me, &out));
}

test "vários quadros num pedaço só" {
    const me = testMe();
    var conn: Conn = .{};
    defer conn.deinit(ta);
    var in: Out = .empty;
    defer in.deinit(ta);
    frame(&in, op_handshake, "{\"v\":1,\"client_id\":\"5\"}");
    frame(&in, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"nonce\":\"1\",\"args\":{\"activity\":{\"state\":\"Jogando sozinho\"}}}");
    frame(&in, op_ping, "{}");
    var out: Out = .empty;
    defer out.deinit(ta);
    try testing.expectEqual(Conn.Result.changed, conn.feed(ta, in.items, &me, &out));
    try testing.expectEqual(op_pong, frames(out.items, 2).?.op);
    try testing.expectEqual(@as(usize, 0), conn.pending.items.len);
}

test "ritmo: um envio por intervalo, o mais novo vence e a limpeza final vai" {
    const me = testMe();
    var hub: Hub = .{ .throttle = .{ .interval_ms = 15_000 } };
    var a: Conn = .{ .handshaken = true, .client_id = 1 };
    defer a.deinit(ta);
    var out: Out = .empty;
    defer out.deinit(ta);
    const set = struct {
        fn f(cn: *Conn, h: *Hub, o: *Out, m: *const Me, state: []const u8) void {
            var b: [256]u8 = undefined;
            const req = std.fmt.bufPrint(&b, "{{\"cmd\":\"SET_ACTIVITY\",\"args\":{{\"activity\":{{\"state\":\"{s}\"}}}}}}", .{state}) catch unreachable;
            _ = cn.handle(ta, op_frame, req, m, o);
            cn.seq = h.nextSeq();
            h.update(&.{cn});
        }
    }.f;
    set(&a, &hub, &out, &me, "um um");
    const first = hub.take(1000).?;
    try testing.expectEqualStrings("um um", first.activity.?.state.slice());
    set(&a, &hub, &out, &me, "dois");
    set(&a, &hub, &out, &me, "três");
    try testing.expect(hub.take(5000) == null);
    try testing.expectEqual(@as(?i64, 11_000), hub.throttle.waitMs(5000));
    const third = hub.take(16_000).?;
    try testing.expectEqualStrings("três", third.activity.?.state.slice());
    // Repetir a mesma atividade não gasta envio.
    set(&a, &hub, &out, &me, "três");
    try testing.expect(hub.throttle.waitMs(40_000) == null);
    // Limpou: a limpeza espera a vez, mas vai.
    _ = a.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"activity\":null}}", &me, &out);
    hub.update(&.{&a});
    try testing.expect(hub.take(20_000) == null);
    const clear = hub.take(31_000).?;
    try testing.expect(clear.activity == null);
    try testing.expect(hub.take(60_000) == null);
}

test "várias conexões: vale a mais recente; quando ela sai, volta a anterior" {
    const me = testMe();
    var hub: Hub = .{ .throttle = .{ .interval_ms = 0 } };
    var out: Out = .empty;
    defer out.deinit(ta);
    var a: Conn = .{ .handshaken = true, .client_id = 1 };
    defer a.deinit(ta);
    var b: Conn = .{ .handshaken = true, .client_id = 2 };
    defer b.deinit(ta);
    _ = a.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"activity\":{\"state\":\"jogo A\"}}}", &me, &out);
    a.seq = hub.nextSeq();
    _ = b.handle(ta, op_frame, "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"activity\":{\"state\":\"jogo B\"}}}", &me, &out);
    b.seq = hub.nextSeq();
    hub.update(&.{ &a, &b });
    try testing.expectEqual(@as(u64, 2), hub.take(0).?.app);
    // B desconectou: só A sobra.
    hub.update(&.{&a});
    try testing.expectEqual(@as(u64, 1), hub.take(1).?.app);
    hub.update(&.{});
    try testing.expect(hub.take(2).?.activity == null);
}

test "gateway: nome da aplicação, imagens por nome e op 3" {
    var p: Presence = .{};
    defer p.deinit(ta);
    var a: Activity = .{};
    a.details.set("Fase 3", max_text);
    a.large_image.set("logo", 512);
    a.small_image.set("https://example.com/x.png", 512);
    a.start_ms = 1_700_000_000_000;
    // Sem nome conhecido, nada de atividade.
    p.set(ta, 77, &a);
    try testing.expect(p.current == null);
    p.learn(ta, 77, null, false, null);
    try testing.expect(!p.known(77));
    p.learn(ta, 77, "{\"id\":\"77\",\"name\":\"Jogo \\\"X\\\"\"}", false, "[{\"id\":\"555\",\"type\":1,\"name\":\"logo\"}]");
    try testing.expect(p.known(77));
    p.set(ta, 77, &a);
    var out: Out = .empty;
    defer out.deinit(ta);
    try p.writeOp3(&out, ta, "dnd");
    try testing.expectEqualStrings("{\"op\":3,\"d\":{\"status\":\"dnd\",\"since\":0,\"activities\":[{\"type\":0,\"name\":\"Jogo \\\"X\\\"\",\"application_id\":\"77\",\"details\":\"Fase 3\",\"timestamps\":{\"start\":1700000000000},\"assets\":{\"large_image\":\"555\"}}],\"afk\":false}}", out.items);
    const e = p.meEvent(ta, 42, .dnd);
    try testing.expectEqualStrings("Jogando Jogo \"X\"", e.presence_update.activity.?);
    const list = e.presence_update.activities.?;
    try testing.expectEqualStrings("Fase 3", list[0].details);
    try testing.expectEqualStrings("https://cdn.discordapp.com/app-assets/77/555.png", list[0].image);
    for (list) |x| for ([_][]const u8{ x.name, x.details, x.state, x.image }) |t| if (t.len > 0) ta.free(t);
    ta.free(list);
    ta.free(e.presence_update.activity.?);
    // Limpa: o op 3 volta sem atividades e a nossa linha também.
    p.set(ta, 77, null);
    out.clearRetainingCapacity();
    try p.writeOp3(&out, ta, "online");
    try testing.expectEqualStrings("{\"op\":3,\"d\":{\"status\":\"online\",\"since\":0,\"activities\":[],\"afk\":false}}", out.items);
    const cleared = p.meEvent(ta, 42, .online);
    try testing.expectEqual(@as(usize, 0), cleared.presence_update.activities.?.len);
    // Aplicação que não existe: não pergunta de novo e não manda atividade.
    p.learn(ta, 88, null, true, null);
    try testing.expect(p.known(88));
    p.set(ta, 88, &a);
    try testing.expect(p.current == null);
}
