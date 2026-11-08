//! Idioma da interface: português, inglês ou japonês.
//!
//! O português e o inglês ficam no lugar em que o texto é usado:
//!
//!     tr("Entrar", "Sign in")
//!     fmt(&buf, "Respondendo a {s}", "Replying to {s}", .{nome})
//!
//! Os outros idiomas vêm de um arquivo por idioma (i18n/ja.kdl, embutido no
//! executável), com o texto em inglês como chave. O que não está no arquivo
//! aparece em inglês (nunca em português): adicionar ou corrigir uma tradução
//! não mexe no código. tools/i18n_strings.py lista os textos e confere o arquivo.
//!
//! O idioma é global e a thread de rede também lê (avisos, dados da
//! demonstração): por isso fica num valor atômico, e a tabela de traduções é
//! montada uma vez, antes de o idioma mudar, e depois só lida (sem trava).
const std = @import("std");
const c = @import("c");
const kdl = @import("../theme/kdl.zig");

pub const Lang = enum(u8) { pt, en, ja };

var lang: std.atomic.Value(Lang) = .init(.pt);

/// O arquivo de tradução do japonês (i18n/ja.kdl).
pub const ja_source = @embedFile("i18n_ja");

/// Lê um arquivo de tradução a mais (larpercord/i18n/<idioma>.kdl na pasta de
/// configurações), que vale por cima do embutido: dá para testar uma tradução
/// sem compilar. Quem abre o app preenche; null = sem arquivo.
pub var read_extra: ?*const fn (gpa: std.mem.Allocator, code: []const u8) ?[]const u8 = null;

pub fn set(l: Lang) void {
    // Monta antes de publicar o idioma: quem lê `.ja` já acha a tabela pronta.
    if (l == .ja) ja_table.build();
    lang.store(l, .release);
}

pub fn current() Lang {
    return lang.load(.acquire);
}

/// Inglês, ou outro idioma (que sem tradução mostra o inglês): nunca o português.
pub fn en() bool {
    return lang.load(.acquire) != .pt;
}

pub fn ja() bool {
    return lang.load(.acquire) == .ja;
}

pub fn tr(pt: []const u8, english: []const u8) []const u8 {
    return switch (lang.load(.acquire)) {
        .pt => pt,
        .en => english,
        .ja => ja_table.get(english) orelse english,
    };
}

pub fn trZ(pt: [:0]const u8, english: [:0]const u8) [:0]const u8 {
    return switch (lang.load(.acquire)) {
        .pt => pt,
        .en => english,
        .ja => ja_table.get(english) orelse english,
    };
}

/// Sem espaço, corta o texto (nunca no meio de um caractere) em vez de sumir.
pub fn fmt(buf: []u8, comptime pt: []const u8, comptime english: []const u8, args: anytype) []const u8 {
    var wr = std.Io.Writer.fixed(buf);
    switch (lang.load(.acquire)) {
        .pt => wr.print(pt, args) catch {},
        .en => wr.print(english, args) catch {},
        .ja => translated(&wr, ja_table.get(english), english, args) catch {},
    }
    const out = wr.buffered();
    if (out.len < buf.len) return out;
    // Encheu: tira o último caractere se ele ficou pela metade.
    var k = out.len;
    while (k > 0 and (out[k - 1] & 0xC0) == 0x80) k -= 1;
    if (k > 0 and out[k - 1] >= 0xC0) {
        const want = std.unicode.utf8ByteSequenceLength(out[k - 1]) catch 1;
        if (out.len - (k - 1) < want) return out[0 .. k - 1];
    }
    return out;
}

/// Sem espaço, devolve "" (como o bufPrintSentinel).
pub fn fmtZ(buf: []u8, comptime pt: []const u8, comptime english: []const u8, args: anytype) [:0]const u8 {
    switch (lang.load(.acquire)) {
        .pt => return std.fmt.bufPrintSentinel(buf, pt, args, 0) catch "",
        .en => return std.fmt.bufPrintSentinel(buf, english, args, 0) catch "",
        .ja => {
            if (buf.len == 0) return "";
            var wr = std.Io.Writer.fixed(buf[0 .. buf.len - 1]);
            translated(&wr, ja_table.get(english), english, args) catch return "";
            buf[wr.end] = 0;
            return buf[0..wr.end :0];
        },
    }
}

pub fn allocPrint(gpa: std.mem.Allocator, comptime pt: []const u8, comptime english: []const u8, args: anytype) ![]u8 {
    switch (lang.load(.acquire)) {
        .pt => return std.fmt.allocPrint(gpa, pt, args),
        .en => return std.fmt.allocPrint(gpa, english, args),
        .ja => {
            var aw: std.Io.Writer.Allocating = .init(gpa);
            defer aw.deinit();
            // O escritor que aloca só falha sem memória.
            translated(&aw.writer, ja_table.get(english), english, args) catch return error.OutOfMemory;
            return aw.toOwnedSlice();
        },
    }
}

/// A tradução de um texto de formato, ou o inglês quando não há tradução ou os
/// marcadores dela não batem com os do inglês. Em cada ponto de uso só entra o
/// `emit` (um print por marcador); o resto é uma função só para todos.
fn translated(w: *std.Io.Writer, tpl: ?[]const u8, comptime english: []const u8, args: anytype) std.Io.Writer.Error!void {
    const parsed = comptime marksOf(english);
    const Args = @TypeOf(args);
    if (comptime parsed != null) if (tpl) |t| {
        const P = struct {
            const p = parsed.?;
            fn emit(ctx: *const anyopaque, out: *std.Io.Writer, k: usize) std.Io.Writer.Error!void {
                const a: *const Args = @ptrCast(@alignCast(ctx));
                const names = @typeInfo(Args).@"struct".field_names;
                inline for (0..p.n) |j| if (j == k) {
                    const m = p.marks[j];
                    return out.print("{" ++ m.spec ++ "}", .{@field(a.*, names[m.arg])});
                };
            }
        };
        if (walk(t, &P.p, null, undefined, undefined)) {
            const ctx: *const anyopaque = if (@sizeOf(Args) == 0) @ptrCast(&no_args) else @ptrCast(&args);
            return walk(t, &P.p, w, ctx, P.emit) catch |e| switch (e) {
                error.WriteFailed => error.WriteFailed,
                error.Invalid => unreachable, // conferido logo acima
            };
        } else |_| {}
    };
    return w.print(english, args);
}

const no_args: u8 = 0;

// --- Marcadores -----------------------------------------------------------------
//
// Numa tradução de texto de formato (fmt, fmtZ, allocPrint), cada marcador é:
//   - uma cópia de um marcador do inglês ({s}, {d}, {d:.0}...), preenchido na
//     mesma ordem do inglês; ou
//   - {N}: o N-ésimo marcador do texto em inglês (do zero), com a formatação
//     dele, para trocar a ordem. Os dois jeitos não se misturam.
// Todo valor que o inglês mostra precisa aparecer; {{ e }} são as chaves.
// Fora disso a tradução não vale e o app mostra o inglês.

const max_marks = 32;

const Mark = struct {
    /// Que argumento o marcador mostra.
    arg: u8,
    /// O que fica entre as chaves no inglês ("s", "1s", "d:.0").
    inner: []const u8,
    /// `inner` sem o número do argumento: a formatação.
    spec: []const u8,
};

const Parsed = struct {
    marks: [max_marks]Mark = undefined,
    n: usize = 0,
    /// Argumentos que o inglês mostra (bit i = argumento i).
    args: u32 = 0,
};

fn marksOf(comptime english: []const u8) ?Parsed {
    @setEvalBranchQuota(20_000 + 200 * english.len);
    return parseFormat(english);
}

/// Os marcadores de um texto de formato, lidos como o std.fmt lê. null: não é
/// texto de formato (chave sem par), ou tem argumento com nome ou largura vinda
/// de argumento; esses ficam sempre em inglês.
fn parseFormat(text: []const u8) ?Parsed {
    var out: Parsed = .{};
    var next: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const ch = text[i];
        if (ch != '{' and ch != '}') {
            i += 1;
            continue;
        }
        if (i + 1 < text.len and text[i + 1] == ch) {
            i += 2;
            continue;
        }
        if (ch == '}') return null;
        const close = std.mem.indexOfScalarPos(u8, text, i + 1, '}') orelse return null;
        const inner = text[i + 1 .. close];
        if (std.mem.indexOfAny(u8, inner, "[{") != null) return null;
        var k: usize = 0;
        while (k < inner.len and std.ascii.isDigit(inner[k])) k += 1;
        const arg = if (k > 0) std.fmt.parseInt(usize, inner[0..k], 10) catch return null else blk: {
            next += 1;
            break :blk next - 1;
        };
        if (arg >= 32 or out.n == max_marks) return null;
        out.marks[out.n] = .{ .arg = @intCast(arg), .inner = inner, .spec = inner[k..] };
        out.n += 1;
        out.args |= @as(u32, 1) << @intCast(arg);
        i = close + 1;
    }
    return out;
}

const WalkError = error{ Invalid, WriteFailed };

const Emit = *const fn (ctx: *const anyopaque, w: *std.Io.Writer, k: usize) std.Io.Writer.Error!void;

/// Confere uma tradução (sem `w`) ou escreve: o texto vai direto, e cada marcador
/// (k = marcador do inglês) sai por `emit`.
fn walk(tpl: []const u8, p: *const Parsed, w: ?*std.Io.Writer, ctx: *const anyopaque, emit: Emit) WalkError!void {
    var mode: enum { none, copy, index } = .none;
    var seq: usize = 0;
    var used: u32 = 0;
    var i: usize = 0;
    while (i < tpl.len) {
        const brace = std.mem.indexOfAnyPos(u8, tpl, i, "{}") orelse tpl.len;
        if (brace > i) if (w) |out| try out.writeAll(tpl[i..brace]);
        if (brace == tpl.len) break;
        i = brace;
        const ch = tpl[i];
        if (i + 1 < tpl.len and tpl[i + 1] == ch) {
            if (w) |out| try out.writeByte(ch);
            i += 2;
            continue;
        }
        if (ch == '}') return error.Invalid;
        const close = std.mem.indexOfScalarPos(u8, tpl, i + 1, '}') orelse return error.Invalid;
        const inner = tpl[i + 1 .. close];
        var k: usize = undefined;
        if (inner.len > 0 and allDigits(inner)) {
            if (mode == .copy) return error.Invalid;
            mode = .index;
            k = std.fmt.parseInt(usize, inner, 10) catch return error.Invalid;
            if (k >= p.n) return error.Invalid;
        } else {
            if (mode == .index) return error.Invalid;
            mode = .copy;
            if (seq >= p.n or !std.mem.eql(u8, inner, p.marks[seq].inner)) return error.Invalid;
            k = seq;
            seq += 1;
        }
        used |= @as(u32, 1) << @intCast(p.marks[k].arg);
        if (w) |out| try emit(ctx, out, k);
        i = close + 1;
    }
    if (mode == .copy and seq != p.n) return error.Invalid;
    if (used != p.args) return error.Invalid;
}

fn allDigits(s: []const u8) bool {
    for (s) |ch| if (!std.ascii.isDigit(ch)) return false;
    return true;
}

/// Não serve para o texto de formato `english`.
fn badTemplate(tpl: []const u8, english: []const u8) bool {
    const p = parseFormat(english) orelse return false;
    walk(tpl, &p, null, undefined, undefined) catch return true;
    return false;
}

// --- A tabela --------------------------------------------------------------------

pub const Entry = struct { key: []const u8, value: []const u8, line: u32 };

pub const FileError = error{ SyntaxError, OutOfMemory, BadEntry };

/// As entradas de um arquivo de tradução: um nó `"inglês" "tradução"` por linha,
/// sem propriedades nem blocos, os dois textos não vazios.
pub fn parseFile(arena: std.mem.Allocator, src: []const u8, diag: ?*kdl.Diagnostic) FileError![]Entry {
    const nodes = try kdl.parse(arena, src, diag);
    const out = try arena.alloc(Entry, nodes.len);
    for (nodes, out) |n, *e| {
        const value = if (n.args.len == 1) n.args[0].asString() else null;
        if (value == null or n.props.len > 0 or n.children.len > 0 or n.name.len == 0 or value.?.len == 0) {
            if (diag) |d| d.* = .{ .line = n.line, .message = "esperava \"inglês\" \"tradução\"" };
            return error.BadEntry;
        }
        e.* = .{ .key = n.name, .value = value.?, .line = n.line };
    }
    return out;
}

const Table = struct {
    map: std.StringHashMapUnmanaged([:0]const u8) = .empty,
    built: bool = false,
    code: []const u8,
    source: []const u8,

    fn get(t: *const Table, english: []const u8) ?[:0]const u8 {
        return t.map.get(english);
    }

    /// Só na thread da interface e antes de o idioma ser publicado: depois
    /// disso a tabela nunca mais muda (por isso ninguém trava para ler).
    fn build(t: *Table) void {
        if (t.built) return;
        t.built = true;
        const a = table_arena.allocator();
        t.add(a, t.source, "embutido");
        if (read_extra) |read| if (read(a, t.code)) |extra| t.add(a, extra, "da pasta de configurações");
    }

    fn add(t: *Table, a: std.mem.Allocator, src: []const u8, what: []const u8) void {
        var diag: kdl.Diagnostic = .{};
        const list = parseFile(a, src, &diag) catch |e| {
            std.log.warn("tradução {s} ({s}) ilegível na linha {d}: {s} ({t})", .{ t.code, what, diag.line, diag.message, e });
            return;
        };
        t.map.ensureUnusedCapacity(a, @intCast(list.len)) catch return;
        for (list) |e| {
            const v = a.dupeSentinel(u8, e.value, 0) catch return;
            t.map.putAssumeCapacity(e.key, v);
        }
    }
};

var table_arena: std.heap.ArenaAllocator = .init(std.heap.c_allocator);
var ja_table: Table = .{ .code = "ja", .source = ja_source };

/// Idioma do sistema: português se a primeira preferência for "pt", japonês
/// se for "ja", inglês em qualquer outro caso.
pub fn system() Lang {
    var count: c_int = 0;
    const list = c.SDL_GetPreferredLocales(&count) orelse return .en;
    defer c.SDL_free(@ptrCast(list));
    if (count > 0) if (list[0]) |loc| {
        if (loc.*.language) |l| {
            const s = std.mem.span(l);
            if (std.mem.startsWith(u8, s, "pt")) return .pt;
            if (std.mem.startsWith(u8, s, "ja")) return .ja;
        }
    };
    return .en;
}

/// `language` das configurações: 0 = seguir o sistema, 1 = português,
/// 2 = inglês, 3 = japonês.
pub fn fromSetting(v: u8) Lang {
    return switch (v) {
        1 => .pt,
        2 => .en,
        3 => .ja,
        else => system(),
    };
}

// --- Testes ----------------------------------------------------------------------

const testing = std.testing;

test "idioma padrão e troca" {
    const old = current();
    defer set(old);
    set(.ja);
    try testing.expect(en());
    try testing.expectEqualStrings("言語", tr("Idioma", "Language"));
    // Sem tradução: o inglês.
    try testing.expectEqualStrings("Sign in to nowhere", tr("Entrar em lugar nenhum", "Sign in to nowhere"));
    try testing.expectEqualStrings("言語", trZ("Idioma", "Language"));
    set(.pt);
    try testing.expectEqualStrings("Idioma", tr("Idioma", "Language"));
    set(.en);
    try testing.expectEqualStrings("Language", tr("Idioma", "Language"));
}

// O japonês sem tradução cai no inglês também no fmt (não no português).
test "fallback do japonês no fmt" {
    const old = current();
    defer set(old);
    set(.ja);
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("Message in nowhere #geral", fmt(&buf, "Conversar em lugar nenhum #{s}", "Message in nowhere #{s}", .{"geral"}));
    set(.pt);
    try testing.expectEqualStrings("Conversar em #geral", fmt(&buf, "Conversar em #{s}", "Message in #{s}", .{"geral"}));
}

test "marcadores do inglês" {
    const p = parseFormat("Level: {d:.0} dB · {1s} {{x}} {}").?;
    try testing.expectEqual(@as(usize, 3), p.n);
    try testing.expectEqualStrings("d:.0", p.marks[0].inner);
    try testing.expectEqual(@as(u8, 0), p.marks[0].arg);
    try testing.expectEqualStrings("s", p.marks[1].spec);
    try testing.expectEqual(@as(u8, 1), p.marks[1].arg);
    // O implícito continua a contagem dos implícitos, como no std.fmt.
    try testing.expectEqual(@as(u8, 1), p.marks[2].arg);
    try testing.expect(parseFormat("sem par }") == null);
    try testing.expect(parseFormat("com nome {[x]s}") == null);
    try testing.expectEqual(@as(usize, 0), parseFormat("nada {{aqui}}").?.n);
}

test "tradução de texto de formato: cópia, {N}, chaves e recusas" {
    const english = "{s} reacted with {s} to {d} messages";
    try testing.expect(!badTemplate("{s}さんが{s}で{d}件に反応", english));
    try testing.expect(!badTemplate("{2}件に{0}さんが{1}で反応 {{ok}}", english));
    try testing.expect(!badTemplate("{1}{1}{0}{2}", english));
    // Falta um valor, sobra um, tipo trocado, mistura, chave sozinha, índice demais.
    try testing.expect(badTemplate("{s}さんが反応", english));
    try testing.expect(badTemplate("{s}{s}{d}{d}", english));
    try testing.expect(badTemplate("{s}{d}{d}", english));
    try testing.expect(badTemplate("{0}{s}{d}", english));
    try testing.expect(badTemplate("{s}{s}{d} }", english));
    try testing.expect(badTemplate("{0}{1}{3}", english));
    try testing.expect(badTemplate("{0}{1}", english));
    // Sem marcadores no inglês: só as chaves dobradas.
    try testing.expect(!badTemplate("ok {{}}", "fine {{}}"));
    try testing.expect(badTemplate("{0}", "fine"));
}

test "formatar com a tradução, na ordem dela" {
    var buf: [128]u8 = undefined;
    var wr = std.Io.Writer.fixed(&buf);
    try translated(&wr, "{1}: {0}件 ({2})", "{d} messages in {s} ({d:.1}%)", .{ @as(u32, 12), "geral", @as(f32, 3.14159) });
    try testing.expectEqualStrings("geral: 12件 (3.1)", wr.buffered());
    // Marcadores errados: o inglês.
    wr = std.Io.Writer.fixed(&buf);
    try translated(&wr, "{s}件", "{d} messages in {s}", .{ @as(u32, 12), "geral" });
    try testing.expectEqualStrings("12 messages in geral", wr.buffered());
    // O inglês com posições: {N} conta os marcadores do texto, não os argumentos
    // ({0} = {1s}, {1} = {0d}).
    wr = std.Io.Writer.fixed(&buf);
    try translated(&wr, "{2}年{0}{1}日", "{1s} {0d}, {2d}", .{ @as(u32, 8), "11月", @as(u32, 2026) });
    try testing.expectEqualStrings("2026年11月8日", wr.buffered());
    // Sem valores: só o texto, com as chaves dobradas.
    wr = std.Io.Writer.fixed(&buf);
    try translated(&wr, "{{ok}} はい", "fine", .{});
    try testing.expectEqualStrings("{ok} はい", wr.buffered());
    // Cheio: corta sem cair no inglês.
    var small: [6]u8 = undefined;
    wr = std.Io.Writer.fixed(&small);
    try testing.expectError(error.WriteFailed, translated(&wr, "{0}件のメッセージ", "{d} messages", .{@as(u32, 7)}));
    try testing.expectEqualStrings("7件", wr.buffered()[0..4]);
}

test "fmt, fmtZ e allocPrint traduzidos" {
    const old = current();
    defer set(old);
    try ja_table.map.put(table_arena.allocator(), "{d} new messages since {s}", "{1}から{0}件の新着メッセージ");
    try ja_table.map.put(table_arena.allocator(), "Broken {s}", "壊れた {d}");
    set(.ja);
    var buf: [96]u8 = undefined;
    try testing.expectEqualStrings("12:30から5件の新着メッセージ", fmt(&buf, "{d} novas desde {s}", "{d} new messages since {s}", .{ 5, "12:30" }));
    try testing.expectEqualStrings("12:30から5件の新着メッセージ", fmtZ(&buf, "{d} novas desde {s}", "{d} new messages since {s}", .{ 5, "12:30" }));
    try testing.expectEqualStrings("Broken x", fmt(&buf, "Quebrado {s}", "Broken {s}", .{"x"}));
    // fmt corta sem partir um caractere; fmtZ sem espaço devolve "".
    var tiny: [8]u8 = undefined;
    try testing.expectEqualStrings("12:30か", fmt(&tiny, "{d} novas desde {s}", "{d} new messages since {s}", .{ 5, "12:30" }));
    try testing.expectEqualStrings("", fmtZ(&tiny, "{d} novas desde {s}", "{d} new messages since {s}", .{ 5, "12:30" }));
    const s = try allocPrint(testing.allocator, "{d} novas desde {s}", "{d} new messages since {s}", .{ 5, "12:30" });
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("12:30から5件の新着メッセージ", s);
    const e = try allocPrint(testing.allocator, "Quebrado {s}", "Broken {s}", .{"y"});
    defer testing.allocator.free(e);
    try testing.expectEqualStrings("Broken y", e);
}

// O arquivo embutido precisa abrir, sem chave repetida, e cada tradução de texto
// de formato com os marcadores certos (faltar tradução não é erro).
test "i18n/ja.kdl: arquivo válido e marcadores certos" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: kdl.Diagnostic = .{};
    const list = parseFile(a.allocator(), ja_source, &diag) catch |e| {
        std.debug.print("i18n/ja.kdl:{d}: {s}\n", .{ diag.line, diag.message });
        return e;
    };
    try testing.expect(list.len > 0);
    var seen: std.StringHashMapUnmanaged(u32) = .empty;
    var bad: usize = 0;
    for (list) |e| {
        const gop = try seen.getOrPut(a.allocator(), e.key);
        if (gop.found_existing) {
            std.debug.print("i18n/ja.kdl:{d}: chave repetida (a primeira na linha {d}): {s}\n", .{ e.line, gop.value_ptr.*, e.key });
            bad += 1;
        } else gop.value_ptr.* = e.line;
        // Os textos com marcadores {…} só podem ser de formato: no inglês de um
        // tr() não há chaves (tools/i18n_strings.py --check confere de novo).
        const p = parseFormat(e.key) orelse continue;
        if (p.n == 0 and std.mem.indexOfAny(u8, e.value, "{}") == null) continue;
        if (badTemplate(e.value, e.key)) {
            std.debug.print("i18n/ja.kdl:{d}: marcadores não batem com o inglês: {s} -> {s}\n", .{ e.line, e.key, e.value });
            bad += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), bad);
}

test "arquivo de tradução: erros" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: kdl.Diagnostic = .{};
    try testing.expectError(error.BadEntry, parseFile(a.allocator(), "\"ok\" \"はい\"\n\"só a chave\"\n", &diag));
    try testing.expectEqual(@as(u32, 2), diag.line);
    try testing.expectError(error.BadEntry, parseFile(a.allocator(), "\"a\" \"b\" extra=1\n", null));
    try testing.expectError(error.BadEntry, parseFile(a.allocator(), "\"a\" \"\"\n", null));
    try testing.expectError(error.SyntaxError, parseFile(a.allocator(), "\"a\" \"sem fim\n", null));
    const ok = try parseFile(a.allocator(), "// comentário\n\"Line\\none\" \\\n    \"一行\\n目\"\n", null);
    try testing.expectEqual(@as(usize, 1), ok.len);
    try testing.expectEqualStrings("Line\none", ok[0].key);
    try testing.expectEqualStrings("一行\n目", ok[0].value);
}
