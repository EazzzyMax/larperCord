//! Entrar num servidor com regras e boas-vindas: o formulário de regras (a verificação de
//! membro) e as perguntas de boas-vindas (onboarding).
//!
//! Aqui só se lê o que o Discord manda e se monta o corpo com o que quem usa respondeu à mão.
//! Nada aceita regra, escreve resposta ou escolhe opção sozinho: sem resposta, o campo vai
//! sem `response`, e o envio fica travado enquanto faltar algo obrigatório.
//!
//! Formulário: GET /guilds/{id}/member-verification e PUT /guilds/{id}/requests/@me, com
//! `form_fields` (todos os campos que vieram, cada um com a sua `response`) e `version`.
//! Boas-vindas: GET /guilds/{id}/onboarding e POST (primeira vez) ou PUT
//! /guilds/{id}/onboarding-responses. Conferido em docs.discord.food (recurso Guild).
const std = @import("std");
const j = @import("../net/jsonx.zig");
const Value = std.json.Value;
const Id = u64;

// --- Comandos e eventos (rede) ------------------------------------------------------------

pub const Status = enum { ok, forbidden, not_found, failed };

/// O que veio no `application_status` do pedido de entrada.
pub const Application = enum { approved, submitted, rejected, started, unknown };

/// Corpos alocados com o c_allocator; quem executa libera (`freeCmd`).
pub const Cmd = union(enum) {
    /// Busca o formulário de regras (só quando quem usa abre a janela).
    form: Id,
    send_form: struct { guild: Id, body: []const u8 },
    /// Busca as perguntas de boas-vindas (idem).
    onboarding: Id,
    /// `first`: ainda não havia respostas (POST); senão, troca as que existem (PUT).
    send_onboarding: struct { guild: Id, body: []const u8, first: bool },
};

/// Corpos alocados com o c_allocator; a interface libera depois de ler.
pub const Event = union(enum) {
    /// O `pending` do nosso membro num servidor (só quando o campo veio).
    pending: struct { guild: Id, pending: bool },
    form: struct { guild: Id, status: Status, body: []const u8 = "" },
    form_sent: struct { guild: Id, status: Status, application: Application = .unknown },
    onboarding: struct { guild: Id, status: Status, body: []const u8 = "" },
    onboarding_sent: struct { guild: Id, status: Status },
};

pub fn freeCmd(gpa: std.mem.Allocator, cmd: Cmd) void {
    switch (cmd) {
        .send_form => |s| gpa.free(s.body),
        .send_onboarding => |s| gpa.free(s.body),
        .form, .onboarding => {},
    }
}

pub fn freeEvent(gpa: std.mem.Allocator, e: Event) void {
    switch (e) {
        .form => |f| if (f.body.len > 0) gpa.free(f.body),
        .onboarding => |o| if (o.body.len > 0) gpa.free(o.body),
        .pending, .form_sent, .onboarding_sent => {},
    }
}

/// Comando que não vai mais ser executado: a janela que espera fica sabendo.
pub fn dropped(cmd: Cmd) Event {
    return switch (cmd) {
        .form => |g| .{ .form = .{ .guild = g, .status = .failed } },
        .send_form => |s| .{ .form_sent = .{ .guild = s.guild, .status = .failed } },
        .onboarding => |g| .{ .onboarding = .{ .guild = g, .status = .failed } },
        .send_onboarding => |s| .{ .onboarding_sent = .{ .guild = s.guild, .status = .failed } },
    };
}

pub fn statusOf(http: i64) Status {
    return if (http >= 200 and http < 300) .ok else if (http == 403 or http == 401) .forbidden else if (http == 404) .not_found else .failed;
}

pub fn applicationStatus(gpa: std.mem.Allocator, body: []const u8) Application {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = std.json.parseFromSliceLeaky(Value, arena.allocator(), body, .{}) catch return .unknown;
    const s = j.str(j.get(v, "application_status")) orelse return .unknown;
    const names = [_]struct { []const u8, Application }{ .{ "APPROVED", .approved }, .{ "SUBMITTED", .submitted }, .{ "REJECTED", .rejected }, .{ "STARTED", .started } };
    for (names) |n| if (std.mem.eql(u8, s, n[0])) return n[1];
    return .unknown;
}

// --- Formulário de regras -----------------------------------------------------------------

pub const FieldKind = enum { terms, text_input, paragraph, multiple_choice, unknown };

/// Limites da documentação: até 5 campos (folga para não recusar se mudar), resposta curta
/// de 150 letras e parágrafo de 1000.
pub const max_fields = 8;
pub const max_short = 150;
pub const max_paragraph = 1000;

pub const Field = struct {
    kind: FieldKind,
    label: []const u8,
    description: []const u8,
    placeholder: []const u8,
    required: bool,
    /// As regras (TERMS).
    values: []const []const u8,
    /// As opções (MULTIPLE_CHOICE).
    choices: []const []const u8,
    /// O objeto como veio: volta igual no envio, só com a resposta.
    raw: std.json.ObjectMap,
};

pub const Form = struct {
    arena: std.heap.ArenaAllocator,
    version: ?[]const u8,
    description: []const u8,
    fields: []Field,

    pub fn deinit(f: *Form) void {
        f.arena.deinit();
    }
};

fn kindOf(s: []const u8) FieldKind {
    if (std.mem.eql(u8, s, "TERMS")) return .terms;
    if (std.mem.eql(u8, s, "TEXT_INPUT")) return .text_input;
    if (std.mem.eql(u8, s, "PARAGRAPH")) return .paragraph;
    if (std.mem.eql(u8, s, "MULTIPLE_CHOICE")) return .multiple_choice;
    return .unknown;
}

fn strings(a: std.mem.Allocator, v: ?Value) ![]const []const u8 {
    const list = j.array(v);
    const out = try a.alloc([]const u8, list.len);
    var n: usize = 0;
    for (list) |x| if (j.str(x)) |s| {
        out[n] = s;
        n += 1;
    };
    return out[0..n];
}

/// Os textos são copiados para a arena: o corpo pode ser liberado logo depois.
const copy: std.json.ParseOptions = .{ .allocate = .alloc_always };

pub fn parseForm(gpa: std.mem.Allocator, body: []const u8) !Form {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const root = try std.json.parseFromSliceLeaky(Value, a, body, copy);
    if (root != .object) return error.BadForm;
    const list = j.array(j.get(root, "form_fields"));
    if (list.len > max_fields) return error.TooManyFields;
    const fields = try a.alloc(Field, list.len);
    for (list, fields) |fv, *f| {
        if (fv != .object) return error.BadForm;
        const choices = try strings(a, j.get(fv, "choices"));
        // A resposta da múltipla escolha é o índice, num byte.
        if (choices.len > 255) return error.BadForm;
        f.* = .{
            .kind = kindOf(j.str(j.get(fv, "field_type")) orelse ""),
            .label = j.str(j.get(fv, "label")) orelse "",
            .description = j.str(j.get(fv, "description")) orelse "",
            .placeholder = j.str(j.get(fv, "placeholder")) orelse "",
            .required = if (j.get(fv, "required")) |r| r == .bool and r.bool else false,
            .values = try strings(a, j.get(fv, "values")),
            .choices = choices,
            .raw = fv.object,
        };
    }
    return .{
        .arena = arena,
        .version = j.str(j.get(root, "version")),
        .description = j.str(j.get(root, "description")) orelse "",
        .fields = fields,
    };
}

/// O que quem usa respondeu em cada campo.
pub const Answer = union(enum) {
    none,
    /// Marcou que leu e concorda com as regras.
    agreed,
    text: []const u8,
    choice: u8,
};

pub fn letters(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

fn trimmed(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

/// O campo está respondido (do jeito que o Discord aceita)?
pub fn answered(f: *const Field, a: Answer) bool {
    return switch (f.kind) {
        .terms => a == .agreed,
        .text_input, .paragraph => a == .text and trimmed(a.text).len > 0 and letters(trimmed(a.text)) <= limit(f.kind),
        .multiple_choice => a == .choice and a.choice < f.choices.len,
        .unknown => false,
    };
}

pub fn limit(kind: FieldKind) usize {
    return if (kind == .paragraph) max_paragraph else max_short;
}

/// Um tipo de campo que o app não sabe responder e é obrigatório: só dá no app oficial.
pub fn blocked(form: *const Form) bool {
    for (form.fields) |*f| if (f.kind == .unknown and f.required) return true;
    return false;
}

/// Dá para enviar: todo obrigatório respondido, e nada passou do limite.
pub fn ready(form: *const Form, answers: []const Answer) bool {
    if (answers.len < form.fields.len) return false;
    for (form.fields, answers[0..form.fields.len]) |*f, a| {
        if (f.required and !answered(f, a)) return false;
        if (a == .text and letters(trimmed(a.text)) > limit(f.kind)) return false;
    }
    return true;
}

/// O corpo do PUT /guilds/{id}/requests/@me: todos os campos como vieram, cada um com a
/// resposta que quem usa deu (sem resposta, sem `response`).
pub fn buildJoinRequest(gpa: std.mem.Allocator, form: *const Form, answers: []const Answer) ![]u8 {
    if (answers.len < form.fields.len) return error.MissingAnswers;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"form_fields\":[");
    for (form.fields, answers[0..form.fields.len], 0..) |*f, a, i| {
        if (i > 0) try out.append(gpa, ',');
        try out.append(gpa, '{');
        var first = true;
        var it = f.raw.iterator();
        while (it.next()) |kv| {
            if (std.mem.eql(u8, kv.key_ptr.*, "response")) continue;
            if (!first) try out.append(gpa, ',');
            first = false;
            try out.print(gpa, "{f}:{f}", .{ std.json.fmt(kv.key_ptr.*, .{}), std.json.fmt(kv.value_ptr.*, .{}) });
        }
        if (answered(f, a)) {
            const r = a;
            if (!first) try out.append(gpa, ',');
            try out.appendSlice(gpa, "\"response\":");
            switch (r) {
                .agreed => try out.appendSlice(gpa, "true"),
                .text => |txt| try out.print(gpa, "{f}", .{std.json.fmt(trimmed(txt), .{})}),
                .choice => |k| try out.print(gpa, "{d}", .{k}),
                .none => unreachable,
            }
        }
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"version\":");
    if (form.version) |ver| try out.print(gpa, "{f}", .{std.json.fmt(ver, .{})}) else try out.appendSlice(gpa, "null");
    try out.append(gpa, '}');
    return out.toOwnedSlice(gpa);
}

// --- Boas-vindas (onboarding) -------------------------------------------------------------

pub const Option = struct {
    id: Id,
    title: []const u8,
    description: []const u8,
    /// Emoji padrão (o caractere); o personalizado não aparece.
    emoji: []const u8,
};

pub const Prompt = struct {
    id: Id,
    title: []const u8,
    single: bool,
    required: bool,
    in_onboarding: bool,
    options: []Option,
};

pub const Onboarding = struct {
    arena: std.heap.ArenaAllocator,
    enabled: bool,
    prompts: []Prompt,
    /// O que a conta já tinha escolhido antes (vem só no GET).
    chosen: []const Id,

    pub fn deinit(o: *Onboarding) void {
        o.arena.deinit();
    }

    pub fn promptOf(o: *const Onboarding, option: Id) ?*const Prompt {
        for (o.prompts) |*p| for (p.options) |op| if (op.id == option) return p;
        return null;
    }
};

pub fn parseOnboarding(gpa: std.mem.Allocator, body: []const u8) !Onboarding {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const root = try std.json.parseFromSliceLeaky(Value, a, body, copy);
    if (root != .object) return error.BadOnboarding;
    const pl = j.array(j.get(root, "prompts"));
    const prompts = try a.alloc(Prompt, pl.len);
    var np: usize = 0;
    for (pl) |pv| {
        const pid = j.id(j.get(pv, "id")) orelse continue;
        const ol = j.array(j.get(pv, "options"));
        const opts = try a.alloc(Option, ol.len);
        var no: usize = 0;
        for (ol) |ov| {
            const oid = j.id(j.get(ov, "id")) orelse continue;
            const em = j.get(ov, "emoji");
            // Emoji personalizado tem `id`: sem a imagem, fica de fora.
            const emoji = if (em != null and j.id(j.get(em.?, "id")) == null) j.str(j.get(em.?, "name")) orelse "" else "";
            opts[no] = .{ .id = oid, .title = j.str(j.get(ov, "title")) orelse "", .description = j.str(j.get(ov, "description")) orelse "", .emoji = emoji };
            no += 1;
        }
        prompts[np] = .{
            .id = pid,
            .title = j.str(j.get(pv, "title")) orelse "",
            .single = flag(pv, "single_select"),
            .required = flag(pv, "required"),
            .in_onboarding = if (j.get(pv, "in_onboarding")) |x| x != .bool or x.bool else true,
            .options = opts[0..no],
        };
        np += 1;
    }
    const rl = j.array(j.get(root, "responses"));
    const chosen = try a.alloc(Id, rl.len);
    var nc: usize = 0;
    for (rl) |rv| if (j.id(rv)) |id| {
        chosen[nc] = id;
        nc += 1;
    };
    return .{ .arena = arena, .enabled = flag(root, "enabled"), .prompts = prompts[0..np], .chosen = chosen[0..nc] };
}

fn flag(v: Value, key: []const u8) bool {
    const x = j.get(v, key) orelse return false;
    return x == .bool and x.bool;
}

/// Clique numa opção: marca ou desmarca. Pergunta de escolha única troca a anterior.
pub fn toggle(gpa: std.mem.Allocator, selected: *std.ArrayList(Id), ob: *const Onboarding, option: Id) !void {
    const p = ob.promptOf(option) orelse return;
    if (std.mem.indexOfScalar(Id, selected.items, option)) |i| {
        _ = selected.swapRemove(i);
        return;
    }
    if (p.single) {
        var i: usize = 0;
        while (i < selected.items.len) {
            if (ob.promptOf(selected.items[i]) == p) _ = selected.swapRemove(i) else i += 1;
        }
    }
    // A documentação limita a 750 respostas.
    if (selected.items.len >= 750) return;
    try selected.append(gpa, option);
}

pub fn promptAnswered(p: *const Prompt, selected: []const Id) bool {
    for (p.options) |op| if (std.mem.indexOfScalar(Id, selected, op.id) != null) return true;
    return false;
}

/// Toda pergunta obrigatória das boas-vindas tem ao menos uma escolha.
pub fn onboardingReady(ob: *const Onboarding, selected: []const Id) bool {
    for (ob.prompts) |*p| if (p.required and p.in_onboarding and !promptAnswered(p, selected)) return false;
    return true;
}

/// O corpo das respostas: as opções escolhidas (só as que existem) e quando cada pergunta e
/// cada opção foi vista na janela (`now_ms`).
pub fn buildOnboarding(gpa: std.mem.Allocator, ob: *const Onboarding, selected: []const Id, now_ms: i64) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"onboarding_responses\":[");
    var n: usize = 0;
    for (ob.prompts) |p| for (p.options) |op| {
        if (std.mem.indexOfScalar(Id, selected, op.id) == null) continue;
        if (n > 0) try out.append(gpa, ',');
        try out.print(gpa, "\"{d}\"", .{op.id});
        n += 1;
    };
    try out.appendSlice(gpa, "],\"onboarding_prompts_seen\":{");
    for (ob.prompts, 0..) |p, i| {
        if (i > 0) try out.append(gpa, ',');
        try out.print(gpa, "\"{d}\":{d}", .{ p.id, now_ms });
    }
    try out.appendSlice(gpa, "},\"onboarding_responses_seen\":{");
    n = 0;
    for (ob.prompts) |p| for (p.options) |op| {
        if (n > 0) try out.append(gpa, ',');
        try out.print(gpa, "\"{d}\":{d}", .{ op.id, now_ms });
        n += 1;
    };
    try out.appendSlice(gpa, "}}");
    return out.toOwnedSlice(gpa);
}

// --- Testes -------------------------------------------------------------------------------

const t = std.testing;

const demo_form =
    \\{"version":"2026-10-01T12:00:00.000000+00:00","description":"Servidor de Zig",
    \\ "form_fields":[
    \\  {"field_type":"TERMS","label":"Leia as regras","values":["Sem spam","Respeito"],"required":true,"description":null,"automations":null},
    \\  {"field_type":"TEXT_INPUT","label":"Seu nome","required":true,"placeholder":"nome","description":null,"automations":null},
    \\  {"field_type":"PARAGRAPH","label":"Por que entrar?","required":false,"description":"opcional","automations":null},
    \\  {"field_type":"MULTIPLE_CHOICE","label":"Nível","choices":["iniciante","médio","avançado"],"required":true,"description":null,"automations":null}
    \\ ]}
;

test "formulário: lê os tipos e os campos" {
    // O corpo some depois de lido (a janela libera): os textos não podem apontar para ele.
    const body = try t.allocator.dupe(u8, demo_form);
    var f = parseForm(t.allocator, body) catch |err| {
        t.allocator.free(body);
        return err;
    };
    defer f.deinit();
    @memset(body, 'x');
    t.allocator.free(body);
    try t.expectEqual(@as(usize, 4), f.fields.len);
    try t.expectEqual(FieldKind.terms, f.fields[0].kind);
    try t.expectEqual(@as(usize, 2), f.fields[0].values.len);
    try t.expectEqualStrings("Respeito", f.fields[0].values[1]);
    try t.expectEqual(FieldKind.text_input, f.fields[1].kind);
    try t.expectEqualStrings("nome", f.fields[1].placeholder);
    try t.expectEqual(FieldKind.paragraph, f.fields[2].kind);
    try t.expect(!f.fields[2].required);
    try t.expectEqual(FieldKind.multiple_choice, f.fields[3].kind);
    try t.expectEqual(@as(usize, 3), f.fields[3].choices.len);
    try t.expectEqualStrings("Servidor de Zig", f.description);
    try t.expect(!blocked(&f));
}

test "formulário: nada respondido não deixa enviar" {
    var f = try parseForm(t.allocator, demo_form);
    defer f.deinit();
    var ans: [4]Answer = @splat(.none);
    try t.expect(!ready(&f, &ans));
    ans[0] = .agreed;
    ans[1] = .{ .text = "   " };
    ans[3] = .{ .choice = 1 };
    // Só espaços não é resposta.
    try t.expect(!ready(&f, &ans));
    ans[1] = .{ .text = "Ana" };
    try t.expect(ready(&f, &ans));
    // Opção fora da lista não vale.
    ans[3] = .{ .choice = 9 };
    try t.expect(!ready(&f, &ans));
}

test "formulário: limite de letras, não de bytes" {
    var f = try parseForm(t.allocator, demo_form);
    defer f.deinit();
    var ans = [_]Answer{ .agreed, .none, .none, .{ .choice = 0 } };
    // 150 letras de 2 bytes cabem; uma a mais, não.
    var acentos: [max_short * 2 + 1]u8 = undefined;
    for (0..max_short) |k| @memcpy(acentos[k * 2 ..][0..2], "é");
    acentos[max_short * 2] = 'a';
    ans[1] = .{ .text = acentos[0 .. max_short * 2] };
    try t.expect(ready(&f, &ans));
    ans[1] = .{ .text = &acentos };
    try t.expect(!ready(&f, &ans));
    // Parágrafo opcional grande demais também trava.
    const longo: [max_paragraph + 1]u8 = @splat('x');
    ans[1] = .{ .text = "Ana" };
    ans[2] = .{ .text = &longo };
    try t.expect(!ready(&f, &ans));
}

test "formulário: o corpo leva todos os campos e só as respostas dadas" {
    var f = try parseForm(t.allocator, demo_form);
    defer f.deinit();
    const ans = [_]Answer{ .agreed, .{ .text = "  Ana \"A\"  " }, .none, .{ .choice = 2 } };
    const body = try buildJoinRequest(t.allocator, &f, &ans);
    defer t.allocator.free(body);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, body, .{});
    defer parsed.deinit();
    const fields = j.array(j.get(parsed.value, "form_fields"));
    try t.expectEqual(@as(usize, 4), fields.len);
    try t.expectEqualStrings("2026-10-01T12:00:00.000000+00:00", j.str(j.get(parsed.value, "version")).?);
    try t.expect(j.get(fields[0], "response").?.bool);
    try t.expectEqualStrings("Ana \"A\"", j.str(j.get(fields[1], "response")).?);
    // O opcional sem resposta vai sem `response`, mas vai.
    try t.expect(j.get(fields[2], "response") == null);
    try t.expectEqualStrings("Por que entrar?", j.str(j.get(fields[2], "label")).?);
    try t.expectEqual(@as(i64, 2), j.int(j.get(fields[3], "response")).?);
    // O resto do campo volta como veio.
    try t.expectEqual(@as(usize, 2), j.array(j.get(fields[0], "values")).len);
    try t.expectEqualStrings("TERMS", j.str(j.get(fields[0], "field_type")).?);
}

test "formulário: regras não marcadas não viram true" {
    var f = try parseForm(t.allocator, demo_form);
    defer f.deinit();
    const ans = [_]Answer{ .none, .{ .text = "Ana" }, .none, .{ .choice = 0 } };
    const body = try buildJoinRequest(t.allocator, &f, &ans);
    defer t.allocator.free(body);
    try t.expect(std.mem.indexOf(u8, body, "\"response\":true") == null);
}

test "formulário: tipo desconhecido obrigatório trava, e JSON ruim é erro" {
    var f = try parseForm(t.allocator,
        \\{"version":null,"form_fields":[{"field_type":"VERIFICATION","label":"x","required":true}]}
    );
    defer f.deinit();
    try t.expect(blocked(&f));
    try t.expect(!ready(&f, &[_]Answer{.none}));
    try t.expectError(error.BadForm, parseForm(t.allocator, "[1,2]"));
    try t.expect(std.meta.isError(parseForm(t.allocator, "{\"form_fields\":")));
}

test "pedido de entrada: o status da resposta" {
    try t.expectEqual(Application.approved, applicationStatus(t.allocator, "{\"application_status\":\"APPROVED\"}"));
    try t.expectEqual(Application.submitted, applicationStatus(t.allocator, "{\"application_status\":\"SUBMITTED\",\"id\":\"1\"}"));
    try t.expectEqual(Application.unknown, applicationStatus(t.allocator, "nada"));
    try t.expectEqual(Status.forbidden, statusOf(403));
    try t.expectEqual(Status.ok, statusOf(204));
}

const demo_onboarding =
    \\{"guild_id":"1","enabled":true,"mode":0,"default_channel_ids":[],"responses":["21"],
    \\ "prompts":[
    \\  {"id":"10","type":0,"title":"O que te trouxe?","single_select":true,"required":true,"in_onboarding":true,
    \\   "options":[{"id":"11","title":"Zig","description":null,"emoji":{"id":null,"name":"⚡"},"role_ids":[],"channel_ids":[]},
    \\              {"id":"12","title":"C","description":"a velha guarda","emoji":{"id":"99","name":"custom"},"role_ids":[],"channel_ids":[]}]},
    \\  {"id":"20","type":1,"title":"Interesses","single_select":false,"required":false,"in_onboarding":true,
    \\   "options":[{"id":"21","title":"Jogos","description":null,"emoji":null},{"id":"22","title":"Música","description":null}]}
    \\ ]}
;

test "boas-vindas: lê perguntas, opções e o que já foi escolhido" {
    var ob = try parseOnboarding(t.allocator, demo_onboarding);
    defer ob.deinit();
    try t.expect(ob.enabled);
    try t.expectEqual(@as(usize, 2), ob.prompts.len);
    try t.expect(ob.prompts[0].single and ob.prompts[0].required);
    try t.expectEqualStrings("⚡", ob.prompts[0].options[0].emoji);
    try t.expectEqualStrings("", ob.prompts[0].options[1].emoji);
    try t.expectEqualStrings("a velha guarda", ob.prompts[0].options[1].description);
    try t.expectEqualSlices(Id, &.{21}, ob.chosen);
}

test "boas-vindas: escolha única troca, múltipla acumula" {
    var ob = try parseOnboarding(t.allocator, demo_onboarding);
    defer ob.deinit();
    var sel: std.ArrayList(Id) = .empty;
    defer sel.deinit(t.allocator);
    try t.expect(!onboardingReady(&ob, sel.items));
    try toggle(t.allocator, &sel, &ob, 11);
    try toggle(t.allocator, &sel, &ob, 12);
    try t.expectEqualSlices(Id, &.{12}, sel.items);
    try toggle(t.allocator, &sel, &ob, 21);
    try toggle(t.allocator, &sel, &ob, 22);
    try t.expectEqual(@as(usize, 3), sel.items.len);
    try t.expect(onboardingReady(&ob, sel.items));
    // Desmarcar a obrigatória trava de novo; opção que não existe é ignorada.
    try toggle(t.allocator, &sel, &ob, 12);
    try toggle(t.allocator, &sel, &ob, 999);
    try t.expect(!onboardingReady(&ob, sel.items));
}

test "boas-vindas: o corpo leva só as opções que existem e o que foi visto" {
    var ob = try parseOnboarding(t.allocator, demo_onboarding);
    defer ob.deinit();
    const body = try buildOnboarding(t.allocator, &ob, &.{ 11, 22, 999 }, 1700000000000);
    defer t.allocator.free(body);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, body, .{});
    defer parsed.deinit();
    const resp = j.array(j.get(parsed.value, "onboarding_responses"));
    try t.expectEqual(@as(usize, 2), resp.len);
    try t.expectEqualStrings("11", j.str(resp[0]).?);
    try t.expectEqualStrings("22", j.str(resp[1]).?);
    const seen = j.get(parsed.value, "onboarding_prompts_seen").?.object;
    try t.expectEqual(@as(usize, 2), seen.count());
    try t.expectEqual(@as(i64, 1700000000000), j.int(seen.get("10")).?);
    try t.expectEqual(@as(usize, 4), j.get(parsed.value, "onboarding_responses_seen").?.object.count());
}
