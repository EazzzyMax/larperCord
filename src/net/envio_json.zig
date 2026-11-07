//! O que vai e volta do Discord no envio e nas listas sob demanda: o corpo de
//! uma mensagem (flags, allowed_mentions, anexos com spoiler e texto
//! alternativo), o voto numa enquete, os caminhos das fixadas, de quem reagiu e
//! de quem votou, e a leitura da enquete. Sem rede, para dar para testar.
const std = @import("std");
const types = @import("../core/types.zig");
const envio = @import("../core/envio.zig");
const polls = @import("../core/polls.zig");
const i18n = @import("../ui/i18n.zig");
const j = @import("jsonx.zig");
const Id = types.Id;
const Value = std.json.Value;

const alloc = std.heap.c_allocator;

/// Pessoas por página (quem reagiu, quem votou): o padrão do Discord.
pub const people_page = 25;
/// Fixadas por página: o máximo que o Discord aceita.
pub const pins_page = 50;

pub const MessageParams = struct {
    content: []const u8,
    nonce: u64,
    reply_to: Id = 0,
    opts: envio.SendOpts = .{},
    /// Nome de cada arquivo (sem a pasta), na ordem de `files[n]`.
    names: []const []const u8 = &.{},
    /// Spoiler e texto alternativo de cada arquivo (pode ter menos que `names`).
    files: []const envio.FileOpt = &.{},
};

/// Nome com que o arquivo vai: spoiler é `SPOILER_` na frente, como o cliente oficial.
pub fn uploadName(buf: []u8, name: []const u8, spoiler: bool) []const u8 {
    if (!spoiler or std.mem.startsWith(u8, name, "SPOILER_")) return name;
    return std.fmt.bufPrint(buf, "SPOILER_{s}", .{name}) catch name;
}

/// Corpo de POST /channels/{id}/messages (ou o `payload_json`, com arquivos).
/// Respondendo, `allowed_mentions` mantém as menções normais e decide só se
/// quem escreveu a mensagem respondida é avisado; "não mencionar ninguém" é
/// `parse` vazio.
pub fn messageBody(b: *std.ArrayList(u8), a: std.mem.Allocator, p: MessageParams) !void {
    try b.appendSlice(a, "{\"content\":");
    try j.writeString(b, a, p.content);
    try b.print(a, ",\"nonce\":\"{d}\",\"tts\":false", .{p.nonce});
    const fl = envio.flags(p.opts);
    if (fl != 0) try b.print(a, ",\"flags\":{d}", .{fl});
    if (p.reply_to != 0) try b.print(a, ",\"message_reference\":{{\"message_id\":\"{d}\"}}", .{p.reply_to});
    if (p.opts.no_pings) {
        try b.appendSlice(a, ",\"allowed_mentions\":{\"parse\":[],\"replied_user\":false}");
    } else if (p.reply_to != 0) {
        try b.print(a, ",\"allowed_mentions\":{{\"parse\":[\"users\",\"roles\",\"everyone\"],\"replied_user\":{s}}}", .{if (p.opts.ping_reply) "true" else "false"});
    }
    if (p.names.len > 0) {
        // Como o cliente oficial: payload_json + files[n], `id` = n.
        try b.appendSlice(a, ",\"attachments\":[");
        for (p.names, 0..) |name, i| {
            const f: envio.FileOpt = if (i < p.files.len) p.files[i] else .{};
            if (i > 0) try b.append(a, ',');
            var nb: [300]u8 = undefined;
            try b.print(a, "{{\"id\":{d},\"filename\":", .{i});
            try j.writeString(b, a, uploadName(&nb, name, f.spoiler));
            if (f.spoiler) try b.appendSlice(a, ",\"is_spoiler\":true");
            if (f.alt.len > 0) {
                try b.appendSlice(a, ",\"description\":");
                try j.writeString(b, a, envio.clampAlt(f.alt));
            }
            try b.append(a, '}');
        }
        try b.append(a, ']');
    }
    try b.append(a, '}');
}

/// Corpo de PUT /channels/{c}/polls/{m}/answers/@me (lista vazia tira o voto).
pub fn pollVoteBody(buf: []u8, answers: []const u32) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    w.writeAll("{\"answer_ids\":[") catch return "";
    for (answers, 0..) |id, i| w.print("{s}{d}", .{ if (i > 0) "," else "", id }) catch return "";
    w.writeAll("]}") catch return "";
    return w.buffered();
}

/// GET /channels/{id}/messages/pins (o caminho atual; o /pins antigo está
/// marcado como obsoleto). `before`: o `pinned_at` da última que veio.
pub fn pinsPath(buf: []u8, ch: Id, before: []const u8) []const u8 {
    if (before.len == 0) return std.fmt.bufPrint(buf, "/channels/{d}/messages/pins?limit={d}", .{ ch, pins_page }) catch "";
    var enc: [160]u8 = undefined;
    return std.fmt.bufPrint(buf, "/channels/{d}/messages/pins?limit={d}&before={s}", .{ ch, pins_page, j.urlEncode(&enc, before) }) catch "";
}

/// GET /channels/{c}/messages/{m}/reactions/{emoji}: quem reagiu (type 0) ou
/// deu super reação (type 1), uma página depois de `after`.
pub fn reactorsPath(buf: []u8, ch: Id, msg: Id, emoji: *const types.Reaction, burst: bool, after: Id) []const u8 {
    var enc: [128]u8 = undefined;
    const key = j.reactionKey(&enc, emoji.text(), emoji.custom);
    const t: u8 = if (burst) 1 else 0;
    if (after == 0) return std.fmt.bufPrint(buf, "/channels/{d}/messages/{d}/reactions/{s}?limit={d}&type={d}", .{ ch, msg, key, people_page, t }) catch "";
    return std.fmt.bufPrint(buf, "/channels/{d}/messages/{d}/reactions/{s}?limit={d}&type={d}&after={d}", .{ ch, msg, key, people_page, t, after }) catch "";
}

/// GET /channels/{c}/polls/{m}/answers/{answer}: quem votou nessa opção.
pub fn votersPath(buf: []u8, ch: Id, msg: Id, answer: u32, after: Id) []const u8 {
    if (after == 0) return std.fmt.bufPrint(buf, "/channels/{d}/polls/{d}/answers/{d}?limit={d}", .{ ch, msg, answer, people_page }) catch "";
    return std.fmt.bufPrint(buf, "/channels/{d}/polls/{d}/answers/{d}?limit={d}&after={d}", .{ ch, msg, answer, people_page, after }) catch "";
}

/// As pessoas de uma página: quem votou vem em `{"users": […]}`, quem reagiu
/// numa lista solta.
pub fn peopleItems(root: Value, voters: bool) []const Value {
    return if (voters) j.array(j.get(root, "users")) else j.array(root);
}

pub const PinsPage = struct { items: []const Value, more: bool, cursor: envio.PinCursor };

/// A resposta das fixadas: `{"items": [{"pinned_at", "message"}], "has_more"}`.
/// (A forma antiga, uma lista de mensagens, ainda é lida: sem mais páginas.)
pub fn pinsPageOf(root: Value) PinsPage {
    if (root == .array) return .{ .items = j.array(root), .more = false, .cursor = .{} };
    const items = j.array(j.get(root, "items"));
    const more = if (j.get(root, "has_more")) |m| m == .bool and m.bool else false;
    const last = if (items.len > 0) j.str(j.get(items[items.len - 1], "pinned_at")) orelse "" else "";
    // Sem onde continuar, não dá para pedir a próxima.
    return .{ .items = items, .more = more and last.len > 0, .cursor = envio.PinCursor.init(last) };
}

/// Super reações de uma reação do histórico (`count_details.burst`).
pub fn burstCount(rv: Value) u16 {
    const cd = j.get(rv, "count_details") orelse return 0;
    return @intCast(std.math.clamp(j.int(j.get(cd, "burst")) orelse 0, 0, 65535));
}

fn emojiOf(e: Value) types.Reaction {
    const name = j.str(j.get(e, "name")) orelse return .{};
    if (j.isNull(j.get(e, "id"))) return types.Reaction.init(name);
    const animated = if (j.get(e, "animated")) |a| a == .bool and a.bool else false;
    return types.Reaction.initCustom(name, j.id(j.get(e, "id")) orelse 0, animated);
}

/// A enquete de uma mensagem (`poll`), com os textos e os votos. Quem recebe
/// fica com ela (polls.destroy).
pub fn parsePoll(pv: Value) !*polls.Poll {
    const p = try polls.create();
    errdefer polls.destroy(p);
    var texts: [polls.max_answers][]const u8 = undefined;
    for (j.array(j.get(pv, "answers"))) |av| {
        if (p.n == polls.max_answers) break;
        const a = &p.answers[p.n];
        a.id = @intCast(std.math.clamp(j.int(j.get(av, "answer_id")) orelse 0, 0, std.math.maxInt(u32)));
        const media = j.get(av, "poll_media");
        texts[p.n] = if (media) |m| j.str(j.get(m, "text")) orelse "" else "";
        if (media) |m| if (j.get(m, "emoji")) |e| {
            a.emoji = emojiOf(e);
        };
        p.n += 1;
    }
    p.expiry = if (j.str(j.get(pv, "expiry"))) |s| j.isoTime(s) else 0;
    p.multi = if (j.get(pv, "allow_multiselect")) |m| m == .bool and m.bool else false;
    if (j.get(pv, "results")) |r| if (r == .object) {
        p.known = true;
        p.finalized = if (j.get(r, "is_finalized")) |f| f == .bool and f.bool else false;
        for (j.array(j.get(r, "answer_counts"))) |cv| {
            const id: u32 = @intCast(std.math.clamp(j.int(j.get(cv, "id")) orelse 0, 0, std.math.maxInt(u32)));
            const a = p.find(id) orelse continue;
            a.count = @intCast(std.math.clamp(j.int(j.get(cv, "count")) orelse 0, 0, std.math.maxInt(u32)));
            a.me = if (j.get(cv, "me_voted")) |m| m == .bool and m.bool else false;
        }
    };
    const q = if (j.get(pv, "question")) |qv| j.str(j.get(qv, "text")) orelse "" else "";
    try p.setTexts(q, texts[0..p.n]);
    return p;
}

/// O cartão parado da enquete (o que aparece sem os dados dela: nas fixadas
/// do cache, numa encaminhada). Marcado com `poll` para a conversa trocar
/// pelo cartão de votar quando a enquete estiver no Store.
pub fn pollEmbed(p: *const polls.Poll) !types.Embed {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(alloc);
    for (p.slice()) |a| try text.print(alloc, "- {s} (**{d}**)\n", .{ a.text, a.count });
    var fb: [64]u8 = undefined;
    const title = try alloc.dupe(u8, p.question);
    errdefer alloc.free(title);
    const desc = try alloc.dupe(u8, std.mem.trimEnd(u8, text.items, "\n"));
    errdefer alloc.free(desc);
    const provider = try alloc.dupe(u8, i18n.tr("Enquete", "Poll"));
    errdefer alloc.free(provider);
    return .{
        .provider = provider,
        .title = title,
        .description = desc,
        .footer = try alloc.dupe(u8, i18n.fmt(&fb, "{d} votos", "{d} votes", .{p.total()})),
        .poll = true,
    };
}

// --- Testes ---------------------------------------------------------------------

fn body(p: MessageParams) ![]u8 {
    const a = std.testing.allocator;
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(a);
    try messageBody(&b, a, p);
    return b.toOwnedSlice(a);
}

fn expectBody(want: []const u8, p: MessageParams) !void {
    const got = try body(p);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings(want, got);
    // Sempre JSON válido.
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, got, .{});
    parsed.deinit();
}

test "corpo: mensagem simples continua igual" {
    try expectBody("{\"content\":\"oi\",\"nonce\":\"5\",\"tts\":false}", .{ .content = "oi", .nonce = 5 });
}

test "corpo: resposta com e sem mencionar o autor" {
    try expectBody("{\"content\":\"oi\",\"nonce\":\"5\",\"tts\":false,\"message_reference\":{\"message_id\":\"9\"},\"allowed_mentions\":{\"parse\":[\"users\",\"roles\",\"everyone\"],\"replied_user\":true}}", .{ .content = "oi", .nonce = 5, .reply_to = 9 });
    try expectBody("{\"content\":\"oi\",\"nonce\":\"5\",\"tts\":false,\"message_reference\":{\"message_id\":\"9\"},\"allowed_mentions\":{\"parse\":[\"users\",\"roles\",\"everyone\"],\"replied_user\":false}}", .{ .content = "oi", .nonce = 5, .reply_to = 9, .opts = .{ .ping_reply = false } });
}

test "corpo: silenciosa, sem prévias e sem menções" {
    try expectBody("{\"content\":\"a\",\"nonce\":\"1\",\"tts\":false,\"flags\":4096}", .{ .content = "a", .nonce = 1, .opts = .{ .silent = true } });
    try expectBody("{\"content\":\"a\",\"nonce\":\"1\",\"tts\":false,\"flags\":4}", .{ .content = "a", .nonce = 1, .opts = .{ .no_embeds = true } });
    try expectBody("{\"content\":\"a\",\"nonce\":\"1\",\"tts\":false,\"flags\":4100,\"message_reference\":{\"message_id\":\"9\"},\"allowed_mentions\":{\"parse\":[],\"replied_user\":false}}", .{ .content = "a", .nonce = 1, .reply_to = 9, .opts = .{ .silent = true, .no_embeds = true, .no_pings = true } });
    // Sem responder, "não mencionar ninguém" também vale.
    try expectBody("{\"content\":\"@ana\",\"nonce\":\"1\",\"tts\":false,\"allowed_mentions\":{\"parse\":[],\"replied_user\":false}}", .{ .content = "@ana", .nonce = 1, .opts = .{ .no_pings = true } });
}

test "corpo: anexos com spoiler e texto alternativo" {
    const alt = "um gato \"laranja\"\nno sofá";
    try expectBody("{\"content\":\"\",\"nonce\":\"2\",\"tts\":false,\"attachments\":[{\"id\":0,\"filename\":\"SPOILER_gato.png\",\"is_spoiler\":true,\"description\":\"um gato \\\"laranja\\\"\\nno sofá\"},{\"id\":1,\"filename\":\"notas.txt\"}]}", .{
        .content = "",
        .nonce = 2,
        .names = &.{ "gato.png", "notas.txt" },
        .files = &.{.{ .spoiler = true, .alt = alt }},
    });
    // Já com o prefixo: não repete.
    var nb: [64]u8 = undefined;
    try std.testing.expectEqualStrings("SPOILER_x.png", uploadName(&nb, "SPOILER_x.png", true));
    try std.testing.expectEqualStrings("x.png", uploadName(&nb, "x.png", false));
}

test "corpo: texto alternativo longo é cortado em 1024 caracteres" {
    const long: [1500]u8 = @splat('a');
    const got = try body(.{ .content = "", .nonce = 1, .names = &.{"a.png"}, .files = &.{.{ .alt = &long }} });
    defer std.testing.allocator.free(got);
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, got, .{});
    defer parsed.deinit();
    const d = j.str(j.get(j.array(j.get(parsed.value, "attachments"))[0], "description")).?;
    try std.testing.expectEqual(@as(usize, 1024), d.len);
}

test "voto na enquete" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("{\"answer_ids\":[1,3]}", pollVoteBody(&buf, &.{ 1, 3 }));
    try std.testing.expectEqualStrings("{\"answer_ids\":[]}", pollVoteBody(&buf, &.{}));
}

test "caminhos das listas sob demanda" {
    var buf: [320]u8 = undefined;
    try std.testing.expectEqualStrings("/channels/7/messages/pins?limit=50", pinsPath(&buf, 7, ""));
    try std.testing.expectEqualStrings("/channels/7/messages/pins?limit=50&before=2026-11-02T23%3A41%3A12.345000%2B00%3A00", pinsPath(&buf, 7, "2026-11-02T23:41:12.345000+00:00"));
    const thumbs = types.Reaction.init("👍");
    try std.testing.expectEqualStrings("/channels/1/messages/2/reactions/%F0%9F%91%8D?limit=25&type=0", reactorsPath(&buf, 1, 2, &thumbs, false, 0));
    const custom = types.Reaction.initCustom("larper", 900101, false);
    try std.testing.expectEqualStrings("/channels/1/messages/2/reactions/larper:900101?limit=25&type=1&after=55", reactorsPath(&buf, 1, 2, &custom, true, 55));
    try std.testing.expectEqualStrings("/channels/1/polls/2/answers/3?limit=25", votersPath(&buf, 1, 2, 3, 0));
    try std.testing.expectEqualStrings("/channels/1/polls/2/answers/3?limit=25&after=99", votersPath(&buf, 1, 2, 3, 99));
}

test "leitura da enquete e do cartão parado" {
    const json =
        \\{"question":{"text":"qual editor?"},"allow_multiselect":true,"expiry":"2026-11-08T12:00:00.000000+00:00",
        \\ "answers":[{"answer_id":1,"poll_media":{"text":"vim","emoji":{"id":null,"name":"📝"}}},
        \\            {"answer_id":2,"poll_media":{"text":"emacs","emoji":{"id":"77","name":"gnu","animated":true}}},
        \\            {"answer_id":3,"poll_media":{"text":"helix"}}],
        \\ "results":{"is_finalized":false,"answer_counts":[{"id":1,"count":4,"me_voted":true},{"id":3,"count":1,"me_voted":false}]}}
    ;
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const p = try parsePoll(parsed.value);
    defer polls.destroy(p);
    try std.testing.expectEqualStrings("qual editor?", p.question);
    try std.testing.expectEqual(@as(u8, 3), p.n);
    try std.testing.expect(p.multi and p.known and !p.finalized);
    try std.testing.expectEqual(j.isoTime("2026-11-08T12:00:00.000000+00:00"), p.expiry);
    try std.testing.expectEqualStrings("📝", p.answers[0].emoji.text());
    try std.testing.expectEqual(@as(Id, 77), p.answers[1].emoji.custom);
    try std.testing.expect(p.answers[1].emoji.animated);
    try std.testing.expectEqual(@as(u32, 4), p.answers[0].count);
    try std.testing.expect(p.answers[0].me and !p.answers[2].me);
    try std.testing.expectEqual(@as(u32, 0), p.answers[1].count);
    const e = try pollEmbed(p);
    defer types.freeEmbed(alloc, e);
    try std.testing.expect(e.poll);
    try std.testing.expectEqualStrings("- vim (**4**)\n- emacs (**0**)\n- helix (**1**)", e.description);
}

test "enquete sem resultados: votos desconhecidos" {
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, "{\"question\":{\"text\":\"?\"},\"answers\":[{\"answer_id\":1,\"poll_media\":{\"text\":\"a\"}}]}", .{});
    defer parsed.deinit();
    const p = try parsePoll(parsed.value);
    defer polls.destroy(p);
    try std.testing.expect(!p.known and p.expiry == 0 and !p.multi);
}

test "página de fixadas" {
    const json =
        \\{"items":[{"pinned_at":"2026-11-01T10:00:00+00:00","message":{"id":"1"}},
        \\          {"pinned_at":"2026-10-01T10:00:00.5+00:00","message":{"id":"2"}}],"has_more":true}
    ;
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const pg = pinsPageOf(parsed.value);
    try std.testing.expectEqual(@as(usize, 2), pg.items.len);
    try std.testing.expect(pg.more);
    try std.testing.expectEqualStrings("2026-10-01T10:00:00.5+00:00", pg.cursor.slice());
    const old = try std.json.parseFromSlice(Value, std.testing.allocator, "[{\"id\":\"1\"}]", .{});
    defer old.deinit();
    try std.testing.expect(!pinsPageOf(old.value).more);
}

test "super reações e listas de pessoas" {
    const parsed = try std.json.parseFromSlice(Value, std.testing.allocator, "{\"count\":5,\"count_details\":{\"burst\":2,\"normal\":3}}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u16, 2), burstCount(parsed.value));
    const v = try std.json.parseFromSlice(Value, std.testing.allocator, "{\"users\":[{\"id\":\"1\"},{\"id\":\"2\"}]}", .{});
    defer v.deinit();
    try std.testing.expectEqual(@as(usize, 2), peopleItems(v.value, true).len);
    try std.testing.expectEqual(@as(usize, 0), peopleItems(v.value, false).len);
}
