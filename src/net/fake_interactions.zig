//! O bot da demonstração ("radinho"): botões, menus, um modal e comandos de
//! barra (com autocompletar) no #bugs do primeiro servidor. Responde como um
//! bot de verdade, pelos mesmos eventos do gateway, e guarda o último pedido
//! para o QA conferir o que iria para o Discord.
const std = @import("std");
const types = @import("../core/types.zig");
const ev = @import("../core/event.zig");
const ix = @import("../core/interaction.zig");
const i18n = @import("../ui/i18n.zig");
const fg = @import("fake_gateway.zig");
const j = @import("jsonx.zig");
const Id = types.Id;
const Value = std.json.Value;

const alloc = std.heap.c_allocator;

pub fn channel() Id {
    return fg.channelId(0, 11);
}

/// O que "foi para o Discord" (lido pelo QA, da thread da interface).
pub const sent = struct {
    const A = std.atomic.Value(u32);
    pub var interactions: A = .init(0);
    pub var fetches: A = .init(0);
    pub var autocompletes: A = .init(0);
    pub var last: [4096]u8 = undefined;
    pub var last_len: std.atomic.Value(usize) = .init(0);

    pub fn lastPayload() []const u8 {
        return last[0..last_len.load(.acquire)];
    }
};

pub const Out = struct {
    events: [4]ev.Event = undefined,
    n: usize = 0,
    /// A resposta do bot, um instante depois (como a de verdade).
    reply: ?types.Message = null,

    fn add(o: *Out, e: ev.Event) void {
        if (o.n < o.events.len) {
            o.events[o.n] = e;
            o.n += 1;
        } else ix.freeEvent(e.interaction);
    }
};

const index_json =
    \\{"version":"1","applications":[{"id":"1013","name":"radinho","icon":null}],
    \\ "application_commands":[
    \\  {"id":"771","application_id":"1013","version":"1","type":1,"name":"ping","description":"Responde pong","name_localized":"ping"},
    \\  {"id":"772","application_id":"1013","version":"1","type":1,"name":"eco","description":"Repete o que você escrever",
    \\   "options":[{"type":3,"name":"texto","description":"O que repetir","required":true,"max_length":80},
    \\              {"type":4,"name":"vezes","description":"Quantas vezes (1 a 5)","min_value":1,"max_value":5}]},
    \\  {"id":"773","application_id":"1013","version":"1","type":1,"name":"fruta","description":"Escolhe uma fruta",
    \\   "options":[{"type":3,"name":"nome","description":"Comece a digitar","required":true,"autocomplete":true}]},
    \\  {"id":"774","application_id":"1013","version":"1","type":1,"name":"ticket","description":"Abre ou fecha um ticket",
    \\   "options":[{"type":1,"name":"abrir","description":"Abre um ticket",
    \\                "options":[{"type":3,"name":"motivo","description":"Por quê","required":true},
    \\                           {"type":3,"name":"prioridade","description":"Urgência","choices":[{"name":"Baixa","value":"baixa"},{"name":"Alta","value":"alta"}]}]},
    \\              {"type":1,"name":"fechar","description":"Fecha o ticket aberto"}]},
    \\  {"id":"775","application_id":"1013","version":"1","type":1,"name":"avisar","description":"Avisa alguém",
    \\   "options":[{"type":6,"name":"quem","description":"Quem","required":true},
    \\              {"type":7,"name":"canal","description":"Onde"},
    \\              {"type":8,"name":"cargo","description":"Cargo junto"},
    \\              {"type":5,"name":"urgente","description":"É urgente?"},
    \\              {"type":10,"name":"nota","description":"Nota de 0 a 10","min_value":0,"max_value":10},
    \\              {"type":11,"name":"print","description":"Um print"}]},
    \\  {"id":"776","application_id":"1013","version":"1","type":1,"name":"banir","description":"Só para quem pode banir","default_member_permissions":"4"},
    \\  {"id":"777","application_id":"1013","version":"1","type":2,"name":"Perfil do radinho","description":""}
    \\ ]}
;

const fruits = [_][]const u8{ "abacaxi", "acerola", "banana", "caju", "goiaba", "jabuticaba", "laranja", "maçã", "manga", "maracujá", "morango", "pitanga", "uva" };

fn parse(a: std.mem.Allocator, s: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, a, s, .{});
}

/// Um pedido da interface. A memória do comando fica com esta função.
pub fn handle(cmd: ix.Cmd, now_ms: i64, seq: u64) !Out {
    defer ix.freeCmd(alloc, cmd);
    var out: Out = .{};
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    switch (cmd) {
        .fetch_commands => |sc| {
            _ = sent.fetches.fetchAdd(1, .monotonic);
            // Só o servidor da demonstração tem o bot.
            const body = if (!sc.user and sc.guild == fg.guildId(0)) index_json else "{\"applications\":[],\"application_commands\":[]}";
            out.add(.{ .interaction = .{ .commands = .{ .key = sc.key(), .index = try ix.parseIndex(alloc, try parse(a, body)) } } });
        },
        .send => |s| {
            _ = sent.interactions.fetchAdd(1, .monotonic);
            const body = try ix.payload(alloc, s, "demo-session");
            defer alloc.free(body);
            const n = @min(body.len, sent.last.len);
            @memcpy(sent.last[0..n], body[0..n]);
            sent.last_len.store(n, .release);
            try reply(a, s, now_ms, seq, &out);
        },
    }
    return out;
}

fn message(s: ix.Send, now_ms: i64, seq: u64, text: []const u8, ephemeral: bool) !types.Message {
    return .{
        .id = types.makeSnowflake(now_ms, seq +% 1),
        .channel = s.channel,
        .author = fg.plain_bot_user,
        .timestamp = @divTrunc(now_ms, 1000),
        .content = try alloc.dupe(u8, text),
        .flags = if (ephemeral) ix.ephemeral_flag else 0,
        .app = s.app,
    };
}

/// Valor de uma opção (procura também dentro de subcomandos).
fn optionValue(list: []const Value, name: []const u8) ?Value {
    for (list) |o| {
        if (std.mem.eql(u8, j.str(j.get(o, "name")) orelse "", name)) if (j.get(o, "value")) |v| return v;
        if (optionValue(j.array(j.get(o, "options")), name)) |v| return v;
    }
    return null;
}

fn valueText(buf: []u8, v: ?Value) []const u8 {
    const x = v orelse return "";
    return switch (x) {
        .string => |t| t,
        .integer => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "",
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "",
        .bool => |b| if (b) "true" else "false",
        else => "",
    };
}

fn subName(list: []const Value) []const u8 {
    for (list) |o| if ((j.int(j.get(o, "type")) orelse 0) == 1) return j.str(j.get(o, "name")) orelse "";
    return "";
}

fn ok(out: *Out, nonce: u64, id: Id) void {
    out.add(.{ .interaction = .{ .created = .{ .nonce = nonce, .id = id } } });
    out.add(.{ .interaction = .{ .succeeded = .{ .nonce = nonce, .id = id } } });
}

const modal_json =
    \\{{"id":"{d}","channel_id":"{d}","custom_id":"demo:feedback","nonce":"{d}","title":"{s}",
    \\ "application":{{"id":"1013","name":"radinho"}},
    \\ "components":[
    \\  {{"type":10,"id":1,"content":"{s}"}},
    \\  {{"type":18,"id":2,"label":"{s}","component":{{"type":4,"id":3,"custom_id":"nome","style":1,"min_length":2,"max_length":30,"placeholder":"{s}"}}}},
    \\  {{"type":18,"id":4,"label":"{s}","description":"{s}","component":{{"type":4,"id":5,"custom_id":"texto","style":2,"required":false,"max_length":400}}}},
    \\  {{"type":18,"id":6,"label":"{s}","component":{{"type":3,"id":7,"custom_id":"nota","placeholder":"1–5","options":[{{"label":"1","value":"1"}},{{"label":"2","value":"2"}},{{"label":"3","value":"3"}},{{"label":"4","value":"4"}},{{"label":"5","value":"5","default":true}}]}}}},
    \\  {{"type":18,"id":8,"label":"{s}","component":{{"type":23,"id":9,"custom_id":"contato"}}}}
    \\ ]}}
;

fn reply(a: std.mem.Allocator, s: ix.Send, now_ms: i64, seq: u64, out: *Out) !void {
    const id = types.makeSnowflake(now_ms, seq);
    const data = try parse(a, s.data);
    var tb: [64]u8 = undefined;
    switch (s.kind) {
        .component => {
            const cid = j.str(j.get(data, "custom_id")) orelse "";
            const values = j.array(j.get(data, "values"));
            if (std.mem.eql(u8, cid, "demo:ping")) {
                ok(out, s.nonce, id);
                out.reply = try message(s, now_ms, seq, i18n.tr("Pong! 🏓 Só você vê esta resposta.", "Pong! 🏓 Only you can see this reply."), true);
            } else if (std.mem.eql(u8, cid, "demo:form")) {
                out.add(.{ .interaction = .{ .created = .{ .nonce = s.nonce, .id = id } } });
                const body = try std.fmt.allocPrint(a, modal_json, .{
                    id,                                                s.channel,                                                                            s.nonce,
                    i18n.tr("Feedback", "Feedback"),                   i18n.tr("Conte o que achou do larperCord.", "Tell us what you think of larperCord."), i18n.tr("Seu nome", "Your name"),
                    i18n.tr("Como te chamam", "What people call you"),
                    i18n.tr("Comentário", "Comment"),
                    i18n.tr("Opcional", "Optional"),                   i18n.tr("Nota", "Rating"),                                                            i18n.tr("Posso responder por DM", "You can reply by DM"),
                });
                if (try ix.parseModal(alloc, try parse(a, body))) |m| out.add(.{ .interaction = .{ .modal = m } });
                out.add(.{ .interaction = .{ .succeeded = .{ .nonce = s.nonce, .id = id } } });
            } else if (std.mem.eql(u8, cid, "demo:cor") and values.len > 0) {
                ok(out, s.nonce, id);
                var b: std.ArrayList(u8) = .empty;
                try b.appendSlice(a, i18n.tr("🎨 Cores escolhidas: ", "🎨 Colors picked: "));
                for (values, 0..) |v, i| {
                    if (i > 0) try b.appendSlice(a, ", ");
                    try b.appendSlice(a, j.str(v) orelse "?");
                }
                out.reply = try message(s, now_ms, seq, b.items, false);
            } else if (std.mem.eql(u8, cid, "demo:quem") and values.len > 0) {
                ok(out, s.nonce, id);
                const text = try i18n.allocPrint(a, "📣 <@{s}>, chamaram você aqui.", "📣 <@{s}>, someone called you here.", .{j.str(values[0]) orelse "0"});
                out.reply = try message(s, now_ms, seq, text, false);
            } else {
                // "Falhar" e qualquer outro: o bot não responde a tempo.
                out.add(.{ .interaction = .{ .created = .{ .nonce = s.nonce, .id = id } } });
                out.add(.{ .interaction = .{ .failed = .{ .nonce = s.nonce, .reason = 1 } } });
            }
        },
        .modal_submit => {
            var nome: []const u8 = "?";
            var nota: []const u8 = "?";
            for (j.array(j.get(data, "components"))) |cv| {
                const inner = j.get(cv, "component") orelse continue;
                const cid = j.str(j.get(inner, "custom_id")) orelse "";
                if (std.mem.eql(u8, cid, "nome")) nome = j.str(j.get(inner, "value")) orelse "?";
                if (std.mem.eql(u8, cid, "nota")) {
                    const vs = j.array(j.get(inner, "values"));
                    if (vs.len > 0) nota = j.str(vs[0]) orelse "?";
                }
            }
            ok(out, s.nonce, id);
            out.reply = try message(s, now_ms, seq, try i18n.allocPrint(a, "📝 Valeu, **{s}**! Nota: {s}/5", "📝 Thanks, **{s}**! Rating: {s}/5", .{ nome, nota }), false);
        },
        .autocomplete => {
            _ = sent.autocompletes.fetchAdd(1, .monotonic);
            const typed = valueText(&tb, optionValue(j.array(j.get(data, "options")), "nome"));
            var b: std.ArrayList(u8) = .empty;
            try b.print(a, "{{\"nonce\":\"{d}\",\"choices\":[", .{s.nonce});
            var n: usize = 0;
            for (fruits) |f| {
                if (typed.len > 0 and std.ascii.findIgnoreCase(f, typed) == null) continue;
                if (n > 0) try b.append(a, ',');
                try b.appendSlice(a, "{\"name\":");
                try j.writeString(&b, a, f);
                try b.appendSlice(a, ",\"value\":");
                try j.writeString(&b, a, f);
                try b.append(a, '}');
                n += 1;
            }
            try b.appendSlice(a, "]}");
            out.add(.{ .interaction = .{ .autocomplete = try ix.parseChoices(alloc, try parse(a, b.items)) } });
        },
        .command => {
            const name = j.str(j.get(data, "name")) orelse "";
            const opts = j.array(j.get(data, "options"));
            ok(out, s.nonce, id);
            var vb: [64]u8 = undefined;
            const text: []const u8 = if (std.mem.eql(u8, name, "ping"))
                "Pong! 🏓"
            else if (std.mem.eql(u8, name, "eco")) blk: {
                const t = valueText(&tb, optionValue(opts, "texto"));
                const times: usize = @intCast(std.math.clamp(j.int(optionValue(opts, "vezes")) orelse 1, 1, 5));
                var b: std.ArrayList(u8) = .empty;
                for (0..times) |i| {
                    if (i > 0) try b.append(a, '\n');
                    try b.appendSlice(a, t);
                }
                break :blk b.items;
            } else if (std.mem.eql(u8, name, "fruta"))
                try i18n.allocPrint(a, "🍓 Você escolheu: **{s}**", "🍓 You picked: **{s}**", .{valueText(&tb, optionValue(opts, "nome"))})
            else if (std.mem.eql(u8, name, "ticket")) blk: {
                if (std.mem.eql(u8, subName(opts), "fechar")) break :blk i18n.tr("🔒 Ticket fechado.", "🔒 Ticket closed.");
                break :blk try i18n.allocPrint(a, "🎫 Ticket aberto: {s} (prioridade: {s})", "🎫 Ticket opened: {s} (priority: {s})", .{ valueText(&tb, optionValue(opts, "motivo")), valueText(&vb, optionValue(opts, "prioridade")) });
            } else if (std.mem.eql(u8, name, "avisar"))
                try i18n.allocPrint(a, "📣 <@{s}> foi avisado(a).", "📣 <@{s}> was notified.", .{valueText(&tb, optionValue(opts, "quem"))})
            else
                "🤖";
            out.reply = try message(s, now_ms, seq, text, std.mem.eql(u8, name, "ticket"));
        },
    }
}

/// O cartão do bot no #bugs: botões de todos os estilos (um desligado, um
/// de link) e dois menus (cores e pessoas).
pub fn demoMessage(m: *types.Message) !void {
    alloc.free(m.content);
    m.content = try alloc.dupe(u8, i18n.tr("🎫 **Central do radinho**: teste os botões, os menus e os comandos de barra (`/ping`, `/eco`, `/fruta`, `/ticket`, `/avisar`).", "🎫 **radinho's desk**: try the buttons, the menus and the slash commands (`/ping`, `/eco`, `/fruta`, `/ticket`, `/avisar`)."));
    m.author = fg.plain_bot_user;
    m.reply_to = 0;
    const btns = try alloc.alloc(types.EmbedMedia, 5);
    const specs = [_]struct { cid: []const u8, pt: []const u8, en: []const u8, style: u8, off: bool = false }{
        .{ .cid = "demo:ping", .pt = "🏓 Ping", .en = "🏓 Ping", .style = 1 },
        .{ .cid = "demo:form", .pt = "Formulário", .en = "Form", .style = 3 },
        .{ .cid = "demo:falha", .pt = "Falhar", .en = "Fail", .style = 4 },
        .{ .cid = "demo:off", .pt = "Desligado", .en = "Disabled", .style = 2, .off = true },
    };
    for (specs, 0..) |sp, i| btns[i] = .{ .custom_id = try alloc.dupe(u8, sp.cid), .label = try alloc.dupe(u8, i18n.tr(sp.pt, sp.en)), .style = sp.style, .disabled = sp.off };
    btns[4] = .{ .link = try alloc.dupe(u8, "https://docs.discord.food"), .label = try alloc.dupe(u8, "docs.discord.food") };
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const cores = try std.fmt.allocPrint(arena.allocator(),
        \\{{"type":3,"custom_id":"demo:cor","placeholder":"{s}","min_values":1,"max_values":2,
        \\ "options":[{{"label":"{s}","value":"azul","description":"{s}"}},{{"label":"{s}","value":"verde"}},{{"label":"{s}","value":"roxo"}}]}}
    , .{ i18n.tr("Escolha até 2 cores", "Pick up to 2 colors"), i18n.tr("Azul", "Blue"), i18n.tr("a preferida da casa", "the house favorite"), i18n.tr("Verde", "Green"), i18n.tr("Roxo", "Purple") });
    const quem = try std.fmt.allocPrint(arena.allocator(), "{{\"type\":5,\"custom_id\":\"demo:quem\",\"placeholder\":\"{s}\"}}", .{i18n.tr("Chamar alguém", "Call someone")});
    const blocks = try alloc.alloc(types.EmbedBlock, 3);
    blocks[0] = .{ .kind = .buttons, .media = btns };
    blocks[1] = .{ .kind = .select, .select = try ix.parseOwnedSelect(alloc, try parse(arena.allocator(), cores)) };
    blocks[2] = .{ .kind = .select, .select = try ix.parseOwnedSelect(alloc, try parse(arena.allocator(), quem)) };
    const e = try alloc.alloc(types.Embed, 1);
    e[0] = .{ .bare = true, .blocks = blocks };
    types.freeEmbeds(alloc, m.embeds);
    m.embeds = e;
}
