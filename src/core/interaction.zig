//! Interações com bots: botões, menus de seleção, modais e comandos de barra.
//! Aqui fica o modelo do que o bot mandou (lido do JSON do Discord), os corpos
//! do POST /interactions e a validação do que a pessoa preencheu. Sem rede e
//! sem interface: tudo testável.
//!
//! Referência: docs.discord.food (interactions/receiving-and-responding,
//! interactions/application-commands, resources/components, topics/gateway-events).
const std = @import("std");
const types = @import("types.zig");
const j = @import("../net/jsonx.zig");
const Id = types.Id;
const Value = std.json.Value;
const Allocator = std.mem.Allocator;

/// Campo `type` do POST /interactions.
pub const Kind = enum(u8) { command = 2, component = 3, autocomplete = 4, modal_submit = 5 };

/// Flags de mensagem: só quem usou vê (EPHEMERAL) e "o bot está pensando" (LOADING).
pub const ephemeral_flag: u32 = 1 << 6;
pub const loading_flag: u32 = 1 << 7;

/// Tipos de componente que este módulo entende.
pub const comp = struct {
    pub const action_row = 1;
    pub const button = 2;
    pub const string_select = 3;
    pub const text_input = 4;
    pub const user_select = 5;
    pub const role_select = 6;
    pub const mentionable_select = 7;
    pub const channel_select = 8;
    pub const text_display = 10;
    pub const label = 18;
    pub const file_upload = 19;
    pub const radio_group = 21;
    pub const checkbox_group = 22;
    pub const checkbox = 23;
};

/// Tipos de opção de um comando.
pub const opt = struct {
    pub const sub_command = 1;
    pub const sub_command_group = 2;
    pub const string = 3;
    pub const integer = 4;
    pub const boolean = 5;
    pub const user = 6;
    pub const channel = 7;
    pub const role = 8;
    pub const mentionable = 9;
    pub const number = 10;
    pub const attachment = 11;
};

pub fn isSelect(kind: u8) bool {
    return kind == comp.string_select or (kind >= comp.user_select and kind <= comp.channel_select);
}

// --- Componentes -------------------------------------------------------------------

pub const Option = struct {
    label: []const u8 = "",
    value: []const u8 = "",
    description: []const u8 = "",
    default: bool = false,
};

/// Menu de seleção (mensagem ou modal). Grupos de rádio e de caixas, nos
/// modais, usam a mesma forma (`kind` 21/22).
pub const Select = struct {
    kind: u8 = comp.string_select,
    id: i64 = 0,
    custom_id: []const u8 = "",
    placeholder: []const u8 = "",
    min: u8 = 1,
    max: u8 = 1,
    disabled: bool = false,
    required: bool = true,
    options: []const Option = &.{},
    /// Canal: tipos aceitos (vazio = todos).
    channel_types: []const u8 = &.{},
    /// Pessoas, cargos ou canais que o bot já deixou marcados.
    defaults: []const Id = &.{},
};

/// Menu de uma mensagem: dono da própria memória (vai junto com o cartão).
pub const OwnedSelect = struct {
    arena: std.heap.ArenaAllocator,
    sel: Select,
};

pub fn freeOwnedSelect(o: *OwnedSelect) void {
    var a = o.arena;
    a.deinit();
}

fn dupe(a: Allocator, s: ?[]const u8) ![]const u8 {
    const t = s orelse return "";
    return if (t.len == 0) "" else a.dupe(u8, t);
}

/// Os primeiros `max` bytes sem cortar um caractere UTF-8 no meio.
fn cut(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and s[n] & 0xC0 == 0x80) n -= 1;
    return s[0..n];
}

/// Texto limitado (o Discord limita; aqui é só para não confiar no que vem).
fn dupeMax(a: Allocator, s: ?[]const u8, max: usize) ![]const u8 {
    const t = s orelse return "";
    return dupe(a, cut(t, max));
}

fn isTrue(v: ?Value) bool {
    return if (v) |x| x == .bool and x.bool else false;
}

fn boolOr(v: ?Value, default: bool) bool {
    return if (v) |x| (if (x == .bool) x.bool else default) else default;
}

fn clampU8(v: ?i64, default: u8, lo: u8, hi: u8) u8 {
    return @intCast(std.math.clamp(v orelse default, lo, hi));
}

/// Menu de seleção, grupo de rádio ou de caixas. null = não é um desses, ou
/// veio sem `custom_id`.
pub fn parseSelect(a: Allocator, v: Value) !?Select {
    const kind_i = j.int(j.get(v, "type")) orelse return null;
    if (kind_i < 0 or kind_i > 255) return null;
    const kind: u8 = @intCast(kind_i);
    if (!isSelect(kind) and kind != comp.radio_group and kind != comp.checkbox_group) return null;
    const cid = j.str(j.get(v, "custom_id")) orelse return null;
    if (cid.len == 0 or cid.len > 100) return null;
    var out: Select = .{ .kind = kind, .id = j.int(j.get(v, "id")) orelse 0 };
    out.custom_id = try a.dupe(u8, cid);
    out.placeholder = try dupeMax(a, j.str(j.get(v, "placeholder")), 150);
    out.disabled = isTrue(j.get(v, "disabled"));
    out.required = boolOr(j.get(v, "required"), true);
    const limit: u8 = if (kind == comp.radio_group or kind == comp.checkbox_group) 10 else 25;
    var opts: std.ArrayList(Option) = .empty;
    for (j.array(j.get(v, "options"))) |ov| {
        if (opts.items.len >= limit) break;
        const value = j.str(j.get(ov, "value")) orelse continue;
        if (value.len == 0 or value.len > 100) continue;
        try opts.append(a, .{
            .label = try dupeMax(a, j.str(j.get(ov, "label")) orelse value, 100),
            .value = try a.dupe(u8, value),
            .description = try dupeMax(a, j.str(j.get(ov, "description")), 100),
            .default = isTrue(j.get(ov, "default")),
        });
    }
    out.options = try opts.toOwnedSlice(a);
    switch (kind) {
        comp.radio_group => {
            out.min = if (out.required) 1 else 0;
            out.max = 1;
        },
        comp.checkbox_group => {
            out.min = clampU8(j.int(j.get(v, "min_values")), 1, 0, 10);
            out.max = clampU8(j.int(j.get(v, "max_values")), @intCast(@max(out.options.len, 1)), 1, 10);
        },
        else => {
            out.min = clampU8(j.int(j.get(v, "min_values")), 1, 0, 25);
            out.max = clampU8(j.int(j.get(v, "max_values")), 1, 1, 25);
        },
    }
    // Menu de texto: não dá para pedir mais do que existe.
    if (kind == comp.string_select or kind == comp.checkbox_group) out.max = @min(out.max, @as(u8, @intCast(@max(out.options.len, 1))));
    if (out.min > out.max) out.min = out.max;
    var cts: std.ArrayList(u8) = .empty;
    for (j.array(j.get(v, "channel_types"))) |cv| {
        if (cts.items.len >= 16) break;
        const t = j.int(cv) orelse continue;
        if (t >= 0 and t <= 255) try cts.append(a, @intCast(t));
    }
    out.channel_types = try cts.toOwnedSlice(a);
    var defs: std.ArrayList(Id) = .empty;
    for (j.array(j.get(v, "default_values"))) |dv| {
        if (defs.items.len >= 25) break;
        if (j.id(j.get(dv, "id"))) |id| try defs.append(a, id);
    }
    out.defaults = try defs.toOwnedSlice(a);
    return out;
}

/// O menu de uma mensagem, com a própria memória (`freeOwnedSelect`).
pub fn parseOwnedSelect(gpa: Allocator, v: Value) !?*OwnedSelect {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const sel = (try parseSelect(a, v)) orelse {
        arena.deinit();
        return null;
    };
    const o = try a.create(OwnedSelect);
    o.* = .{ .arena = undefined, .sel = sel };
    // Por último: depois disso nada mais é alocado com `arena`.
    o.arena = arena;
    return o;
}

/// Texto de um botão: o rótulo, com o emoji Unicode na frente; emoji
/// personalizado sem rótulo vira `:nome:`.
pub fn buttonLabel(buf: []u8, btn: Value) []const u8 {
    const label = j.str(j.get(btn, "label")) orelse "";
    const ev = j.get(btn, "emoji");
    const ename = if (ev) |e| j.str(j.get(e, "name")) orelse "" else "";
    const custom = if (ev) |e| j.id(j.get(e, "id")) != null else false;
    if (ename.len == 0) return cut(label, 80);
    if (custom) {
        if (label.len > 0) return cut(label, 80);
        return std.fmt.bufPrint(buf, ":{s}:", .{cut(ename, 32)}) catch cut(label, 80);
    }
    if (label.len == 0) return cut(ename, 32);
    return std.fmt.bufPrint(buf, "{s} {s}", .{ cut(ename, 32), cut(label, 80) }) catch cut(label, 80);
}

// --- Modais ------------------------------------------------------------------------

/// Um campo do modal. `wrap` diz como veio, para a resposta ter a mesma forma:
/// dentro de um rótulo (18), de uma fileira (1, o jeito antigo) ou um texto solto (10).
pub const Field = struct {
    wrap: u8,
    wrap_id: i64 = 0,
    label: []const u8 = "",
    description: []const u8 = "",
    /// O componente de dentro (4 caixa de texto, 3/5..8 seleção, 19 arquivo,
    /// 21 rádio, 22 caixas, 23 caixa); 10 quando `wrap` é texto.
    kind: u8,
    id: i64 = 0,
    custom_id: []const u8 = "",
    /// Caixa de texto: 1 uma linha, 2 parágrafo.
    style: u8 = 1,
    min_len: u16 = 0,
    max_len: u16 = 4000,
    required: bool = true,
    placeholder: []const u8 = "",
    /// Valor inicial (caixa de texto) ou o texto (texto solto).
    value: []const u8 = "",
    /// Caixa (23): marcada de início.
    checked: bool = false,
    select: Select = .{},
};

pub const Modal = struct {
    arena: std.heap.ArenaAllocator,
    /// Interação que abriu o modal (vai de volta no envio).
    id: Id = 0,
    app: Id = 0,
    app_name: []const u8 = "",
    channel: Id = 0,
    nonce: u64 = 0,
    custom_id: []const u8 = "",
    title: []const u8 = "",
    fields: []const Field = &.{},
};

pub fn freeModal(m: *Modal) void {
    var a = m.arena;
    a.deinit();
}

fn textInput(a: Allocator, v: Value, f: *Field) !void {
    f.custom_id = try dupeMax(a, j.str(j.get(v, "custom_id")), 100);
    f.style = if ((j.int(j.get(v, "style")) orelse 1) == 2) 2 else 1;
    f.max_len = @intCast(std.math.clamp(j.int(j.get(v, "max_length")) orelse 4000, 1, 4000));
    f.min_len = @intCast(std.math.clamp(j.int(j.get(v, "min_length")) orelse 0, 0, f.max_len));
    f.required = boolOr(j.get(v, "required"), true);
    f.placeholder = try dupeMax(a, j.str(j.get(v, "placeholder")), 100);
    f.value = try dupeMax(a, j.str(j.get(v, "value")), 4000);
}

/// O componente de dentro de um rótulo (ou de uma fileira antiga).
fn innerField(a: Allocator, v: Value, f: *Field) !bool {
    const k = j.int(j.get(v, "type")) orelse return false;
    if (k < 0 or k > 255) return false;
    f.kind = @intCast(k);
    f.id = j.int(j.get(v, "id")) orelse 0;
    switch (f.kind) {
        comp.text_input => try textInput(a, v, f),
        comp.checkbox => {
            f.custom_id = try dupeMax(a, j.str(j.get(v, "custom_id")), 100);
            f.checked = isTrue(j.get(v, "default"));
            f.required = false;
        },
        comp.file_upload => {
            f.custom_id = try dupeMax(a, j.str(j.get(v, "custom_id")), 100);
            f.required = boolOr(j.get(v, "required"), false);
        },
        else => {
            const sel = (try parseSelect(a, v)) orelse return false;
            f.select = sel;
            f.custom_id = sel.custom_id;
            f.required = sel.required;
        },
    }
    return f.custom_id.len > 0;
}

/// INTERACTION_MODAL_CREATE: id, channel_id, custom_id, application, title,
/// components, nonce.
pub fn parseModal(gpa: Allocator, d: Value) !?*Modal {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const id = j.id(j.get(d, "id")) orelse {
        arena.deinit();
        return null;
    };
    var fields: std.ArrayList(Field) = .empty;
    for (j.array(j.get(d, "components"))) |cv| {
        if (fields.items.len >= 10) break;
        const wrap_i = j.int(j.get(cv, "type")) orelse continue;
        var f: Field = .{ .wrap = 0, .kind = 0, .wrap_id = j.int(j.get(cv, "id")) orelse 0 };
        switch (wrap_i) {
            comp.label => {
                f.wrap = comp.label;
                f.label = try dupeMax(a, j.str(j.get(cv, "label")), 45);
                f.description = try dupeMax(a, j.str(j.get(cv, "description")), 100);
                const inner = j.get(cv, "component") orelse continue;
                if (!try innerField(a, inner, &f)) continue;
            },
            comp.action_row => {
                // Antigo: a caixa de texto dentro de uma fileira, com o próprio rótulo.
                const list = j.array(j.get(cv, "components"));
                if (list.len == 0) continue;
                f.wrap = comp.action_row;
                f.label = try dupeMax(a, j.str(j.get(list[0], "label")), 45);
                if (!try innerField(a, list[0], &f)) continue;
            },
            comp.text_display => {
                f.wrap = comp.text_display;
                f.kind = comp.text_display;
                f.id = f.wrap_id;
                f.required = false;
                f.value = try dupeMax(a, j.str(j.get(cv, "content")), 4000);
            },
            else => continue,
        }
        try fields.append(a, f);
    }
    const app = j.get(d, "application");
    const m = try a.create(Modal);
    m.* = .{
        .arena = undefined,
        .id = id,
        .app = if (app) |x| j.id(j.get(x, "id")) orelse 0 else 0,
        .app_name = try dupeMax(a, if (app) |x| j.str(j.get(x, "name")) else null, 100),
        .channel = j.id(j.get(d, "channel_id")) orelse 0,
        .nonce = j.id(j.get(d, "nonce")) orelse 0,
        .custom_id = try dupeMax(a, j.str(j.get(d, "custom_id")), 100),
        .title = try dupeMax(a, j.str(j.get(d, "title")), 45),
        .fields = try fields.toOwnedSlice(a),
    };
    m.arena = arena;
    return m;
}

/// O que a pessoa preencheu num campo do modal.
pub const FieldValue = union(enum) {
    none,
    text: []const u8,
    values: []const []const u8,
    checked: bool,
};

pub const Problem = enum { none, missing, too_short, too_long, not_integer, not_number, too_small, too_large, too_few, too_many };

fn chars(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

/// O que falta (ou sobra) num campo do modal antes de enviar.
pub fn checkField(f: *const Field, v: FieldValue) Problem {
    switch (f.kind) {
        comp.text_display => return .none,
        comp.text_input => {
            const t = if (v == .text) v.text else "";
            const n = chars(std.mem.trim(u8, t, " \t\r\n"));
            if (n == 0) return if (f.required) .missing else .none;
            if (n < f.min_len) return .too_short;
            if (chars(t) > f.max_len) return .too_long;
            return .none;
        },
        comp.checkbox => return .none,
        comp.file_upload => return if (f.required) .missing else .none,
        comp.radio_group => return if (f.required and !(v == .text and v.text.len > 0)) .missing else .none,
        else => {
            const n = if (v == .values) v.values.len else 0;
            if (n == 0) return if (f.required and f.select.min > 0) .missing else .none;
            if (n < f.select.min) return .too_few;
            if (n > f.select.max) return .too_many;
            return .none;
        },
    }
}

// --- Comandos ----------------------------------------------------------------------

pub const Choice = struct {
    /// Nome mostrado (o traduzido, se veio) e o valor, como texto.
    name: []const u8 = "",
    value: []const u8 = "",
    /// O valor era número no JSON.
    numeric: bool = false,
};

pub const CmdOption = struct {
    kind: u8,
    name: []const u8 = "",
    /// Nome e descrição na língua da conta, quando o Discord manda.
    label: []const u8 = "",
    description: []const u8 = "",
    required: bool = false,
    autocomplete: bool = false,
    choices: []const Choice = &.{},
    options: []const CmdOption = &.{},
    channel_types: []const u8 = &.{},
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    min_len: u16 = 0,
    max_len: u16 = 6000,

    pub fn isGroup(o: *const CmdOption) bool {
        return o.kind == opt.sub_command or o.kind == opt.sub_command_group;
    }
};

pub const Command = struct {
    id: Id,
    app: Id,
    guild: Id = 0,
    /// 1 barra, 2 pessoa, 3 mensagem.
    kind: u8 = 1,
    name: []const u8 = "",
    label: []const u8 = "",
    description: []const u8 = "",
    /// Snowflake como veio (volta igual no envio).
    version: []const u8 = "",
    options: []const CmdOption = &.{},
    /// default_member_permissions: null = todos podem.
    perms: ?u64 = null,
    /// contexts: bit 0 servidor, 1 DM com o bot, 2 outras DMs/grupos.
    contexts: u8 = 0b111,
    nsfw: bool = false,

    /// Tem subcomandos (a primeira coisa a escolher).
    pub fn hasSubs(c: *const Command) bool {
        return c.options.len > 0 and c.options[0].isGroup();
    }
};

pub const App = struct { id: Id, name: []const u8 = "", icon: []const u8 = "" };

pub const Index = struct {
    arena: std.heap.ArenaAllocator,
    apps: []const App = &.{},
    commands: []const Command = &.{},

    pub fn appName(ix: *const Index, app: Id) []const u8 {
        for (ix.apps) |ap| if (ap.id == app) return ap.name;
        return "";
    }
};

pub fn freeIndex(ix: *Index) void {
    var a = ix.arena;
    a.deinit();
}

fn choiceOf(a: Allocator, cv: Value) !?Choice {
    const name = j.str(j.get(cv, "name_localized")) orelse j.str(j.get(cv, "name")) orelse return null;
    const vv = j.get(cv, "value") orelse return null;
    var nb: [64]u8 = undefined;
    const val: []const u8, const numeric = switch (vv) {
        .string => |s| .{ s, false },
        .number_string => |s| .{ s, true },
        .integer => |i| .{ std.fmt.bufPrint(&nb, "{d}", .{i}) catch return null, true },
        .float => |f| .{ std.fmt.bufPrint(&nb, "{d}", .{f}) catch return null, true },
        else => return null,
    };
    if (val.len > 100) return null;
    return .{ .name = try dupeMax(a, name, 100), .value = try a.dupe(u8, val), .numeric = numeric };
}

fn number(v: ?Value) ?f64 {
    const x = v orelse return null;
    return switch (x) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .number_string, .string => |s| std.fmt.parseFloat(f64, s) catch null,
        else => null,
    };
}

fn parseOptions(a: Allocator, list: []const Value, depth: u8) ![]const CmdOption {
    var out: std.ArrayList(CmdOption) = .empty;
    for (list) |ov| {
        if (out.items.len >= 25) break;
        const k = j.int(j.get(ov, "type")) orelse continue;
        if (k < 1 or k > 11) continue;
        const name = j.str(j.get(ov, "name")) orelse continue;
        if (name.len == 0 or name.len > 100) continue;
        var o: CmdOption = .{ .kind = @intCast(k) };
        // Grupo só no primeiro nível; subcomando até o segundo.
        if (o.kind == opt.sub_command_group and depth > 0) continue;
        if (o.kind == opt.sub_command and depth > 1) continue;
        o.name = try a.dupe(u8, name);
        o.label = try dupeMax(a, j.str(j.get(ov, "name_localized")) orelse name, 100);
        o.description = try dupeMax(a, j.str(j.get(ov, "description_localized")) orelse j.str(j.get(ov, "description")), 100);
        o.required = isTrue(j.get(ov, "required"));
        o.autocomplete = isTrue(j.get(ov, "autocomplete"));
        var chs: std.ArrayList(Choice) = .empty;
        for (j.array(j.get(ov, "choices"))) |cv| {
            if (chs.items.len >= 25) break;
            if (try choiceOf(a, cv)) |ch| try chs.append(a, ch);
        }
        o.choices = try chs.toOwnedSlice(a);
        if (o.isGroup()) o.options = try parseOptions(a, j.array(j.get(ov, "options")), depth + 1);
        var cts: std.ArrayList(u8) = .empty;
        for (j.array(j.get(ov, "channel_types"))) |cv| {
            if (cts.items.len >= 16) break;
            const t = j.int(cv) orelse continue;
            if (t >= 0 and t <= 255) try cts.append(a, @intCast(t));
        }
        o.channel_types = try cts.toOwnedSlice(a);
        o.min_value = number(j.get(ov, "min_value"));
        o.max_value = number(j.get(ov, "max_value"));
        o.max_len = @intCast(std.math.clamp(j.int(j.get(ov, "max_length")) orelse 6000, 1, 6000));
        o.min_len = @intCast(std.math.clamp(j.int(j.get(ov, "min_length")) orelse 0, 0, o.max_len));
        try out.append(a, o);
    }
    // Obrigatórias primeiro, como o Discord exige (e mostra).
    const items = out.items;
    std.sort.insertion(CmdOption, items, {}, struct {
        fn lt(_: void, x: CmdOption, y: CmdOption) bool {
            return x.required and !y.required;
        }
    }.lt);
    return out.toOwnedSlice(a);
}

/// Resposta de GET …/application-command-index: applications,
/// application_commands, version.
pub fn parseIndex(gpa: Allocator, root: Value) !*Index {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var apps: std.ArrayList(App) = .empty;
    for (j.array(j.get(root, "applications"))) |av| {
        if (apps.items.len >= 200) break;
        const id = j.id(j.get(av, "id")) orelse continue;
        try apps.append(a, .{ .id = id, .name = try dupeMax(a, j.str(j.get(av, "name")), 100), .icon = try dupeMax(a, j.str(j.get(av, "icon")), 64) });
    }
    var cmds: std.ArrayList(Command) = .empty;
    for (j.array(j.get(root, "application_commands"))) |cv| {
        if (cmds.items.len >= 1000) break;
        const id = j.id(j.get(cv, "id")) orelse continue;
        const app = j.id(j.get(cv, "application_id")) orelse continue;
        const name = j.str(j.get(cv, "name")) orelse continue;
        if (name.len == 0 or name.len > 32) continue;
        const kind = j.int(j.get(cv, "type")) orelse 1;
        if (kind < 1 or kind > 3) continue;
        var c: Command = .{ .id = id, .app = app, .kind = @intCast(kind) };
        c.guild = j.id(j.get(cv, "guild_id")) orelse 0;
        c.name = try a.dupe(u8, name);
        c.label = try dupeMax(a, j.str(j.get(cv, "name_localized")) orelse name, 32);
        c.description = try dupeMax(a, j.str(j.get(cv, "description_localized")) orelse j.str(j.get(cv, "description")), 100);
        // Snowflake: só dígitos (vai sem escape para o corpo do pedido).
        const ver = j.str(j.get(cv, "version")) orelse "";
        const digits = ver.len <= 24 and for (ver) |ch| {
            if (!std.ascii.isDigit(ch)) break false;
        } else true;
        c.version = if (digits) try dupe(a, ver) else "";
        if (c.kind == 1) c.options = try parseOptions(a, j.array(j.get(cv, "options")), 0);
        if (j.str(j.get(cv, "default_member_permissions"))) |p| c.perms = std.fmt.parseInt(u64, p, 10) catch null;
        c.nsfw = isTrue(j.get(cv, "nsfw"));
        if (j.get(cv, "contexts")) |ctxs| if (ctxs == .array) {
            c.contexts = 0;
            for (ctxs.array.items) |x| {
                const t = j.int(x) orelse continue;
                if (t >= 0 and t <= 2) c.contexts |= @as(u8, 1) << @intCast(t);
            }
        };
        try cmds.append(a, c);
    }
    const ix = try a.create(Index);
    ix.* = .{ .arena = undefined, .apps = try apps.toOwnedSlice(a), .commands = try cmds.toOwnedSlice(a) };
    ix.arena = arena;
    return ix;
}

/// Onde o comando é usado: servidor, DM com o próprio bot ou outra DM/grupo.
pub const Place = enum(u2) { guild = 0, bot_dm = 1, private = 2 };

/// O comando aparece aqui? `perms` = permissões da pessoa no canal (servidor).
pub fn usable(c: *const Command, place: Place, perms: u64, nsfw_ok: bool) bool {
    if (c.contexts & (@as(u8, 1) << @backingInt(place)) == 0) return false;
    if (c.nsfw and !nsfw_ok) return false;
    if (place == .guild) if (c.perms) |need| {
        const admin: u64 = 1 << 3;
        if (perms & admin == 0 and perms & need != need) return false;
    };
    return true;
}

/// Lista de sugestões que o bot devolveu (APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE).
pub const ChoiceList = struct {
    arena: std.heap.ArenaAllocator,
    nonce: u64 = 0,
    choices: []const Choice = &.{},
};

pub fn freeChoices(cl: *ChoiceList) void {
    var a = cl.arena;
    a.deinit();
}

pub fn parseChoices(gpa: Allocator, d: Value) !*ChoiceList {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var chs: std.ArrayList(Choice) = .empty;
    for (j.array(j.get(d, "choices"))) |cv| {
        if (chs.items.len >= 25) break;
        if (try choiceOf(a, cv)) |ch| try chs.append(a, ch);
    }
    const cl = try a.create(ChoiceList);
    cl.* = .{ .arena = undefined, .nonce = j.id(j.get(d, "nonce")) orelse 0, .choices = try chs.toOwnedSlice(a) };
    cl.arena = arena;
    return cl;
}

/// O texto digitado vale para esta opção? (Pessoa, canal e cargo chegam aqui
/// já como o ID escolhido; escolha fixa, como o valor da escolha.)
pub fn checkOption(o: *const CmdOption, text: []const u8) Problem {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return if (o.required) .missing else .none;
    switch (o.kind) {
        opt.string => {
            const n = chars(t);
            if (n < o.min_len) return .too_short;
            if (n > o.max_len) return .too_long;
        },
        opt.integer => {
            const v = std.fmt.parseInt(i64, t, 10) catch return .not_integer;
            // O Discord só aceita inteiros seguros para JavaScript.
            if (v > (1 << 53) or v < -(1 << 53)) return .too_large;
            const f: f64 = @floatFromInt(v);
            if (o.min_value) |m| if (f < m) return .too_small;
            if (o.max_value) |m| if (f > m) return .too_large;
        },
        opt.number => {
            const f = std.fmt.parseFloat(f64, t) catch return .not_number;
            if (!std.math.isFinite(f)) return .not_number;
            if (o.min_value) |m| if (f < m) return .too_small;
            if (o.max_value) |m| if (f > m) return .too_large;
        },
        opt.boolean => if (!std.mem.eql(u8, t, "true") and !std.mem.eql(u8, t, "false")) return .missing,
        opt.user, opt.channel, opt.role, opt.mentionable => _ = std.fmt.parseInt(u64, t, 10) catch return .missing,
        else => {},
    }
    return .none;
}

// --- Corpos do POST /interactions ----------------------------------------------------

/// Pedido pronto para ir ao Discord. `data` é o objeto `data` em JSON.
pub const Send = struct {
    kind: Kind,
    app: Id,
    guild: Id = 0,
    channel: Id,
    /// Só em componente: a mensagem e as flags dela.
    message: Id = 0,
    message_flags: u32 = 0,
    nonce: u64,
    data: []const u8,
    /// Opções de anexo: caminhos dos arquivos (files[n]).
    files: []const [:0]const u8 = &.{},
};

/// De onde vem o índice de comandos: do servidor, do canal (DM) ou da conta.
pub const Scope = struct {
    guild: Id = 0,
    channel: Id = 0,
    user: bool = false,

    /// Chave do cache (servidor, canal ou 0 = conta).
    pub fn key(s: Scope) Id {
        if (s.user) return 0;
        return if (s.guild != 0) s.guild else s.channel;
    }
};

/// Comando para a thread de rede. Textos alocados com o c_allocator.
pub const Cmd = union(enum) {
    send: Send,
    fetch_commands: Scope,
};

pub fn freeCmd(gpa: Allocator, c: Cmd) void {
    switch (c) {
        .send => |s| {
            gpa.free(s.data);
            for (s.files) |f| gpa.free(f);
            if (s.files.len > 0) gpa.free(s.files);
        },
        .fetch_commands => {},
    }
}

/// O que volta da rede (eventos do gateway e respostas do REST).
pub const Event = union(enum) {
    /// INTERACTION_CREATE: o Discord aceitou e deu um ID.
    created: struct { nonce: u64, id: Id },
    /// INTERACTION_SUCCESS: o bot respondeu.
    succeeded: struct { nonce: u64, id: Id },
    /// INTERACTION_FAILURE, ou o POST falhou (`reason` 0).
    failed: struct { nonce: u64, reason: u8 = 0 },
    /// INTERACTION_MODAL_CREATE.
    modal: *Modal,
    /// APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE.
    autocomplete: *ChoiceList,
    /// Índice de comandos (null = não veio).
    commands: struct { key: Id, index: ?*Index },
};

pub fn freeEvent(e: Event) void {
    switch (e) {
        .modal => |m| freeModal(m),
        .autocomplete => |cl| freeChoices(cl),
        .commands => |cm| if (cm.index) |ix| freeIndex(ix),
        else => {},
    }
}

/// Corpo do POST /interactions. `session_id` é a sessão do gateway (READY),
/// para os eventos da interação chegarem nela.
pub fn payload(gpa: Allocator, s: Send, session_id: []const u8) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.print(gpa, "{{\"type\":{d},\"application_id\":\"{d}\"", .{ @backingInt(s.kind), s.app });
    if (s.guild != 0) try b.print(gpa, ",\"guild_id\":\"{d}\"", .{s.guild});
    try b.print(gpa, ",\"channel_id\":\"{d}\"", .{s.channel});
    if (s.kind == .component) try b.print(gpa, ",\"message_id\":\"{d}\",\"message_flags\":{d}", .{ s.message, s.message_flags });
    if (session_id.len > 0) {
        try b.appendSlice(gpa, ",\"session_id\":");
        try j.writeString(&b, gpa, session_id);
    }
    try b.print(gpa, ",\"nonce\":\"{d}\",\"data\":", .{s.nonce});
    try b.appendSlice(gpa, s.data);
    try b.append(gpa, '}');
    return b.toOwnedSlice(gpa);
}

/// `data` de um clique de botão (values = null) ou de uma escolha num menu.
pub fn componentData(gpa: Allocator, component_type: u8, custom_id: []const u8, values: ?[]const []const u8) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.print(gpa, "{{\"component_type\":{d},\"custom_id\":", .{component_type});
    try j.writeString(&b, gpa, custom_id);
    if (values) |vs| {
        try b.appendSlice(gpa, ",\"values\":[");
        for (vs, 0..) |v, i| {
            if (i > 0) try b.append(gpa, ',');
            try j.writeString(&b, gpa, v);
        }
        try b.append(gpa, ']');
    }
    try b.append(gpa, '}');
    return b.toOwnedSlice(gpa);
}

fn writeValues(b: *std.ArrayList(u8), gpa: Allocator, vs: []const []const u8) !void {
    try b.append(gpa, '[');
    for (vs, 0..) |v, i| {
        if (i > 0) try b.append(gpa, ',');
        try j.writeString(b, gpa, v);
    }
    try b.append(gpa, ']');
}

/// `data` do envio de um modal: id da interação que o abriu, custom_id e os
/// componentes na mesma forma em que vieram (rótulo, fileira ou texto).
pub fn modalData(gpa: Allocator, m: *const Modal, values: []const FieldValue) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.print(gpa, "{{\"id\":\"{d}\",\"custom_id\":", .{m.id});
    try j.writeString(&b, gpa, m.custom_id);
    try b.appendSlice(gpa, ",\"components\":[");
    for (m.fields, 0..) |*f, i| {
        if (i > 0) try b.append(gpa, ',');
        const v: FieldValue = if (i < values.len) values[i] else .none;
        if (f.wrap == comp.text_display) {
            try b.print(gpa, "{{\"type\":10,\"id\":{d}}}", .{f.id});
            continue;
        }
        if (f.wrap == comp.label) {
            try b.print(gpa, "{{\"type\":18,\"id\":{d},\"component\":", .{f.wrap_id});
        } else {
            try b.print(gpa, "{{\"type\":1,\"id\":{d},\"components\":[", .{f.wrap_id});
        }
        try b.print(gpa, "{{\"type\":{d},\"id\":{d},\"custom_id\":", .{ f.kind, f.id });
        try j.writeString(&b, gpa, f.custom_id);
        switch (f.kind) {
            comp.text_input => {
                try b.appendSlice(gpa, ",\"value\":");
                try j.writeString(&b, gpa, if (v == .text) v.text else "");
            },
            comp.checkbox => try b.print(gpa, ",\"value\":{s}", .{if (v == .checked and v.checked) "true" else "false"}),
            comp.radio_group => {
                try b.appendSlice(gpa, ",\"value\":");
                if (v == .text and v.text.len > 0) try j.writeString(&b, gpa, v.text) else try b.appendSlice(gpa, "null");
            },
            else => {
                try b.appendSlice(gpa, ",\"values\":");
                try writeValues(&b, gpa, if (v == .values) v.values else &.{});
            },
        }
        try b.append(gpa, '}');
        try b.appendSlice(gpa, if (f.wrap == comp.label) "}" else "]}");
    }
    try b.appendSlice(gpa, "]}");
    return b.toOwnedSlice(gpa);
}

/// Uma opção preenchida (texto como a pessoa digitou ou o ID escolhido).
pub const OptValue = struct {
    opt: *const CmdOption,
    text: []const u8,
    /// Autocompletar: a opção que está sendo digitada.
    focused: bool = false,
};

fn writeOptValue(b: *std.ArrayList(u8), gpa: Allocator, v: OptValue, attachment_index: *u32) !void {
    const o = v.opt;
    try b.print(gpa, "{{\"type\":{d},\"name\":", .{o.kind});
    try j.writeString(b, gpa, o.name);
    try b.appendSlice(gpa, ",\"value\":");
    const t = std.mem.trim(u8, v.text, " \t\r\n");
    if (v.focused) {
        // O que está sendo digitado vai sempre como texto.
        try j.writeString(b, gpa, v.text);
        try b.appendSlice(gpa, ",\"focused\":true}");
        return;
    }
    switch (o.kind) {
        opt.integer => try b.print(gpa, "{d}", .{std.fmt.parseInt(i64, t, 10) catch 0}),
        opt.number => {
            const f = std.fmt.parseFloat(f64, t) catch 0;
            try b.print(gpa, "{d}", .{if (std.math.isFinite(f)) f else 0});
        },
        opt.boolean => try b.appendSlice(gpa, if (std.mem.eql(u8, t, "true")) "true" else "false"),
        opt.attachment => {
            try b.print(gpa, "{d}", .{attachment_index.*});
            attachment_index.* += 1;
        },
        opt.user, opt.channel, opt.role, opt.mentionable => try b.print(gpa, "\"{d}\"", .{std.fmt.parseInt(u64, t, 10) catch 0}),
        else => try j.writeString(b, gpa, v.text),
    }
    try b.append(gpa, '}');
}

/// `data` de um comando de barra (ou de um pedido de autocompletar).
/// `path`: o grupo e/ou subcomando escolhidos (0 a 2), do mais externo ao de dentro.
/// `files`: nomes dos arquivos das opções de anexo, na ordem em que aparecem.
pub fn commandData(gpa: Allocator, c: *const Command, path: []const *const CmdOption, values: []const OptValue, files: []const []const u8) ![]u8 {
    var b: std.ArrayList(u8) = .empty;
    errdefer b.deinit(gpa);
    try b.print(gpa, "{{\"version\":\"{s}\",\"id\":\"{d}\",\"name\":", .{ c.version, c.id });
    try j.writeString(&b, gpa, c.name);
    try b.print(gpa, ",\"type\":{d},\"options\":[", .{c.kind});
    for (path) |p| {
        try b.print(gpa, "{{\"type\":{d},\"name\":", .{p.kind});
        try j.writeString(&b, gpa, p.name);
        try b.appendSlice(gpa, ",\"options\":[");
    }
    var att: u32 = 0;
    var first = true;
    for (values) |v| {
        if (!v.focused and std.mem.trim(u8, v.text, " \t\r\n").len == 0) continue;
        if (!first) try b.append(gpa, ',');
        first = false;
        try writeOptValue(&b, gpa, v, &att);
    }
    for (path) |_| try b.appendSlice(gpa, "]}");
    try b.appendSlice(gpa, "],\"attachments\":[");
    for (files, 0..) |name, i| {
        if (i > 0) try b.append(gpa, ',');
        try b.print(gpa, "{{\"id\":\"{d}\",\"filename\":", .{i});
        try j.writeString(&b, gpa, name);
        try b.append(gpa, '}');
    }
    try b.appendSlice(gpa, "]}");
    return b.toOwnedSlice(gpa);
}

/// Nonce de uma interação: um snowflake do momento (como o cliente oficial).
pub fn makeNonce(now_ms: i64, seq: u64) u64 {
    return types.makeSnowflake(now_ms, seq);
}

// --- Testes ----------------------------------------------------------------------------

const testing = std.testing;

fn parseJson(a: Allocator, s: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, a, s, .{});
}

test "payload de componente tem os campos do Discord" {
    const gpa = testing.allocator;
    const data = try componentData(gpa, 3, "cor:\"x\"", &.{ "azul", "verde" });
    defer gpa.free(data);
    try testing.expectEqualStrings("{\"component_type\":3,\"custom_id\":\"cor:\\\"x\\\"\",\"values\":[\"azul\",\"verde\"]}", data);
    const body = try payload(gpa, .{ .kind = .component, .app = 11, .guild = 22, .channel = 33, .message = 44, .message_flags = 64, .nonce = 55, .data = data }, "sess");
    defer gpa.free(body);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = try parseJson(arena.allocator(), body);
    try testing.expectEqual(@as(i64, 3), j.int(j.get(v, "type")).?);
    try testing.expectEqualStrings("11", j.str(j.get(v, "application_id")).?);
    try testing.expectEqualStrings("22", j.str(j.get(v, "guild_id")).?);
    try testing.expectEqualStrings("33", j.str(j.get(v, "channel_id")).?);
    try testing.expectEqualStrings("44", j.str(j.get(v, "message_id")).?);
    try testing.expectEqual(@as(i64, 64), j.int(j.get(v, "message_flags")).?);
    try testing.expectEqualStrings("sess", j.str(j.get(v, "session_id")).?);
    try testing.expectEqualStrings("55", j.str(j.get(v, "nonce")).?);
    try testing.expectEqualStrings("azul", j.str(j.array(j.get(j.get(v, "data").?, "values"))[0]).?);
}

test "botão: sem values; comando em DM: sem guild_id nem message_id" {
    const gpa = testing.allocator;
    const data = try componentData(gpa, 2, "ping", null);
    defer gpa.free(data);
    try testing.expectEqualStrings("{\"component_type\":2,\"custom_id\":\"ping\"}", data);
    const body = try payload(gpa, .{ .kind = .command, .app = 1, .channel = 2, .nonce = 3, .data = "{}" }, "");
    defer gpa.free(body);
    try testing.expectEqualStrings("{\"type\":2,\"application_id\":\"1\",\"channel_id\":\"2\",\"nonce\":\"3\",\"data\":{}}", body);
}

test "menu de seleção: limites, opções e padrões" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = try parseJson(arena.allocator(),
        \\{"type":3,"custom_id":"cor","placeholder":"Escolha","min_values":0,"max_values":9,
        \\ "options":[{"label":"Azul","value":"a","default":true},{"label":"Verde","value":"v","description":"mato"},{"value":""}]}
    );
    const o = (try parseOwnedSelect(gpa, v)).?;
    defer freeOwnedSelect(o);
    try testing.expectEqual(@as(u8, 3), o.sel.kind);
    try testing.expectEqualStrings("cor", o.sel.custom_id);
    try testing.expectEqual(@as(usize, 2), o.sel.options.len);
    try testing.expectEqual(@as(u8, 0), o.sel.min);
    // Não pede mais do que existe.
    try testing.expectEqual(@as(u8, 2), o.sel.max);
    try testing.expect(o.sel.options[0].default);
    try testing.expectEqualStrings("mato", o.sel.options[1].description);
    const u = try parseJson(arena.allocator(),
        \\{"type":8,"custom_id":"canal","channel_types":[0,5],"default_values":[{"id":"77","type":"channel"}]}
    );
    const o2 = (try parseOwnedSelect(gpa, u)).?;
    defer freeOwnedSelect(o2);
    try testing.expectEqual(@as(u8, 1), o2.sel.max);
    try testing.expectEqualSlices(u8, &.{ 0, 5 }, o2.sel.channel_types);
    try testing.expectEqualSlices(Id, &.{77}, o2.sel.defaults);
    // Sem custom_id não é um menu que dá para usar.
    try testing.expect(try parseOwnedSelect(gpa, try parseJson(arena.allocator(), "{\"type\":3}")) == null);
}

test "corte de texto não parte caractere" {
    try testing.expectEqualStrings("a", cut("aé", 2));
    try testing.expectEqualStrings("aé", cut("aé", 3));
}

test "rótulo de botão com emoji" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var buf: [128]u8 = undefined;
    const a = try parseJson(arena.allocator(), "{\"label\":\"Abrir\",\"emoji\":{\"name\":\"🎫\"}}");
    try testing.expectEqualStrings("🎫 Abrir", buttonLabel(&buf, a));
    const b = try parseJson(arena.allocator(), "{\"emoji\":{\"name\":\"ok\",\"id\":\"123\"}}");
    try testing.expectEqualStrings(":ok:", buttonLabel(&buf, b));
}

const demo_modal =
    \\{"id":"900","channel_id":"5","custom_id":"fb","title":"Feedback","nonce":"42",
    \\ "application":{"id":"1013","name":"radinho"},
    \\ "components":[
    \\  {"type":10,"id":1,"content":"Conte o que achou"},
    \\  {"type":18,"id":2,"label":"Nome","component":{"type":4,"id":3,"custom_id":"nome","style":1,"min_length":2,"max_length":20}},
    \\  {"type":1,"id":4,"components":[{"type":4,"id":5,"custom_id":"texto","style":2,"label":"Texto","required":false}]},
    \\  {"type":18,"id":6,"label":"Nota","component":{"type":3,"id":7,"custom_id":"nota","options":[{"label":"1","value":"1"},{"label":"5","value":"5"}]}},
    \\  {"type":18,"id":8,"label":"Avisar","component":{"type":23,"id":9,"custom_id":"avisar","default":true}}
    \\ ]}
;

test "modal: lê rótulos, fileira antiga, menu e caixa" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const m = (try parseModal(gpa, try parseJson(arena.allocator(), demo_modal))).?;
    defer freeModal(m);
    try testing.expectEqual(@as(Id, 900), m.id);
    try testing.expectEqual(@as(Id, 1013), m.app);
    try testing.expectEqual(@as(u64, 42), m.nonce);
    try testing.expectEqualStrings("Feedback", m.title);
    try testing.expectEqual(@as(usize, 5), m.fields.len);
    try testing.expectEqual(@as(u8, comp.text_display), m.fields[0].kind);
    try testing.expectEqualStrings("Nome", m.fields[1].label);
    try testing.expectEqual(@as(u16, 2), m.fields[1].min_len);
    try testing.expectEqualStrings("Texto", m.fields[2].label);
    try testing.expectEqual(@as(u8, 2), m.fields[2].style);
    try testing.expect(!m.fields[2].required);
    try testing.expectEqual(@as(usize, 2), m.fields[3].select.options.len);
    try testing.expect(m.fields[4].checked);

    try testing.expectEqual(Problem.missing, checkField(&m.fields[1], .{ .text = "  " }));
    try testing.expectEqual(Problem.too_short, checkField(&m.fields[1], .{ .text = "a" }));
    try testing.expectEqual(Problem.too_long, checkField(&m.fields[1], .{ .text = "aaaaaaaaaaaaaaaaaaaaa" }));
    try testing.expectEqual(Problem.none, checkField(&m.fields[1], .{ .text = "Ana" }));
    try testing.expectEqual(Problem.none, checkField(&m.fields[2], .none));
    try testing.expectEqual(Problem.missing, checkField(&m.fields[3], .none));

    const vals = [_]FieldValue{ .none, .{ .text = "Ana" }, .{ .text = "oi\n" }, .{ .values = &.{"5"} }, .{ .checked = false } };
    const data = try modalData(gpa, m, &vals);
    defer gpa.free(data);
    try testing.expectEqualStrings(
        "{\"id\":\"900\",\"custom_id\":\"fb\",\"components\":[{\"type\":10,\"id\":1}," ++
            "{\"type\":18,\"id\":2,\"component\":{\"type\":4,\"id\":3,\"custom_id\":\"nome\",\"value\":\"Ana\"}}," ++
            "{\"type\":1,\"id\":4,\"components\":[{\"type\":4,\"id\":5,\"custom_id\":\"texto\",\"value\":\"oi\\n\"}]}," ++
            "{\"type\":18,\"id\":6,\"component\":{\"type\":3,\"id\":7,\"custom_id\":\"nota\",\"values\":[\"5\"]}}," ++
            "{\"type\":18,\"id\":8,\"component\":{\"type\":23,\"id\":9,\"custom_id\":\"avisar\",\"value\":false}}]}",
        data,
    );
}

const demo_index =
    \\{"applications":[{"id":"1013","name":"radinho","icon":null}],"version":"1",
    \\ "application_commands":[
    \\  {"id":"1","application_id":"1013","version":"7","type":1,"name":"echo","description":"Repete",
    \\   "options":[{"type":4,"name":"vezes","description":"quantas","min_value":1,"max_value":5},
    \\              {"type":3,"name":"texto","description":"o que","required":true,"max_length":10}]},
    \\  {"id":"2","application_id":"1013","version":"8","type":1,"name":"ticket","description":"Tickets",
    \\   "options":[{"type":1,"name":"abrir","description":"Abre","options":[{"type":3,"name":"motivo","description":"por quê","required":true,"autocomplete":true}]},
    \\              {"type":1,"name":"fechar","description":"Fecha"}]},
    \\  {"id":"3","application_id":"1013","version":"9","type":1,"name":"admin","description":"só adm","default_member_permissions":"8","contexts":[0]},
    \\  {"id":"4","application_id":"1013","version":"9","type":2,"name":"Perfil","description":""},
    \\  {"id":"5","application_id":"1013","type":1,"name":"","description":"sem nome"}
    \\ ]}
;

test "índice de comandos: opções, subcomandos, permissões" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const ix = try parseIndex(gpa, try parseJson(arena.allocator(), demo_index));
    defer freeIndex(ix);
    try testing.expectEqual(@as(usize, 4), ix.commands.len);
    try testing.expectEqualStrings("radinho", ix.appName(1013));
    const echo = &ix.commands[0];
    // Obrigatória vem primeiro.
    try testing.expectEqualStrings("texto", echo.options[0].name);
    try testing.expectEqual(@as(?f64, 5), echo.options[1].max_value);
    const ticket = &ix.commands[1];
    try testing.expect(ticket.hasSubs());
    try testing.expect(ticket.options[0].options[0].autocomplete);
    const admin = &ix.commands[2];
    try testing.expect(!usable(admin, .guild, 0x400, false));
    try testing.expect(usable(admin, .guild, 0x8, false));
    try testing.expect(!usable(admin, .private, 0x8, false));
    try testing.expect(usable(echo, .private, 0, false));
    try testing.expectEqual(@as(u8, 2), ix.commands[3].kind);

    try testing.expectEqual(Problem.missing, checkOption(&echo.options[0], ""));
    try testing.expectEqual(Problem.too_long, checkOption(&echo.options[0], "aaaaaaaaaaa"));
    try testing.expectEqual(Problem.none, checkOption(&echo.options[1], ""));
    try testing.expectEqual(Problem.not_integer, checkOption(&echo.options[1], "2.5"));
    try testing.expectEqual(Problem.too_large, checkOption(&echo.options[1], "6"));
    try testing.expectEqual(Problem.none, checkOption(&echo.options[1], "3"));

    const data = try commandData(gpa, echo, &.{}, &.{ .{ .opt = &echo.options[0], .text = "oi" }, .{ .opt = &echo.options[1], .text = " 3 " } }, &.{});
    defer gpa.free(data);
    try testing.expectEqualStrings("{\"version\":\"7\",\"id\":\"1\",\"name\":\"echo\",\"type\":1,\"options\":[{\"type\":3,\"name\":\"texto\",\"value\":\"oi\"},{\"type\":4,\"name\":\"vezes\",\"value\":3}],\"attachments\":[]}", data);

    // Subcomando, com a opção em foco do autocompletar sempre como texto.
    const sub = &ticket.options[0];
    const ac = try commandData(gpa, ticket, &.{sub}, &.{.{ .opt = &sub.options[0], .text = "ba", .focused = true }}, &.{});
    defer gpa.free(ac);
    try testing.expectEqualStrings("{\"version\":\"8\",\"id\":\"2\",\"name\":\"ticket\",\"type\":1,\"options\":[{\"type\":1,\"name\":\"abrir\",\"options\":[{\"type\":3,\"name\":\"motivo\",\"value\":\"ba\",\"focused\":true}]}],\"attachments\":[]}", ac);
}

test "anexo vira índice em attachments" {
    const gpa = testing.allocator;
    const o: CmdOption = .{ .kind = opt.attachment, .name = "foto", .required = true };
    const b: CmdOption = .{ .kind = opt.boolean, .name = "ok" };
    const u: CmdOption = .{ .kind = opt.user, .name = "quem" };
    const c: Command = .{ .id = 9, .app = 1, .name = "up", .version = "1" };
    const data = try commandData(gpa, &c, &.{}, &.{ .{ .opt = &o, .text = "x.png" }, .{ .opt = &b, .text = "true" }, .{ .opt = &u, .text = "123" } }, &.{"x.png"});
    defer gpa.free(data);
    try testing.expectEqualStrings("{\"version\":\"1\",\"id\":\"9\",\"name\":\"up\",\"type\":1,\"options\":[{\"type\":11,\"name\":\"foto\",\"value\":0},{\"type\":5,\"name\":\"ok\",\"value\":true},{\"type\":6,\"name\":\"quem\",\"value\":\"123\"}],\"attachments\":[{\"id\":\"0\",\"filename\":\"x.png\"}]}", data);
}

test "sugestões do autocompletar" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const cl = try parseChoices(gpa, try parseJson(arena.allocator(), "{\"nonce\":\"8\",\"choices\":[{\"name\":\"Banana\",\"value\":\"banana\"},{\"name\":\"Três\",\"value\":3},{\"name\":\"x\"}]}"));
    defer freeChoices(cl);
    try testing.expectEqual(@as(u64, 8), cl.nonce);
    try testing.expectEqual(@as(usize, 2), cl.choices.len);
    try testing.expectEqualStrings("3", cl.choices[1].value);
    try testing.expect(cl.choices[1].numeric);
}
