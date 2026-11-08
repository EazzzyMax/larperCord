//! Registro de depuração: ligado pelo botão em Configurações → Avançado, grava em
//! `<cache>/larpercord/debug.log` o que o app registra, para a pessoa poder mandar sem
//! precisar de terminal (no Windows o app nem tem console). Desligado, custa só uma leitura.
//! Ligado, o arquivo só fica aberto enquanto cada linha é escrita: dá para abrir, copiar
//! ou anexar o debug.log sem desligar antes, também no Windows.
const std = @import("std");
const c = @import("c");
const sys = @import("sys.zig");

/// Passando disso o arquivo recomeça: ninguém lê um registro de semanas.
const max_bytes: i64 = 4 * 1024 * 1024;

/// O botão das Configurações; o app liga e desliga o registro a partir dele.
pub var ui_on = false;
var enabled: std.atomic.Value(bool) = .init(false);
var mutex: ?*c.SDL_Mutex = null;
/// Quanto o arquivo já tem, contado a cada linha (para recomeçar em `max_bytes`).
var size: i64 = 0;
var path_buf: [640]u8 = undefined;
var path_len: usize = 0;
var dir_len: usize = 0;

pub fn isOn() bool {
    return enabled.load(.monotonic);
}

pub fn path() ?[:0]const u8 {
    if (path_len == 0 and !findPath()) return null;
    return path_buf[0..path_len :0];
}

fn findPath() bool {
    var hb: [400]u8 = undefined;
    const base = sys.cacheHome(&hb) orelse return false;
    const dir = std.fmt.bufPrint(&path_buf, "{s}/larpercord", .{base}) catch return false;
    dir_len = dir.len;
    var db: [460]u8 = undefined;
    const dz = std.fmt.bufPrintSentinel(&db, "{s}", .{dir}, 0) catch return false;
    _ = c.SDL_CreateDirectory(dz.ptr);
    const full = std.fmt.bufPrintSentinel(&path_buf, "{s}/debug.log", .{dz}, 0) catch return false;
    path_len = full.len;
    return true;
}

/// Abre a pasta do arquivo no gerenciador de arquivos.
pub fn openFolder() void {
    _ = path() orelse return;
    var ub: [700]u8 = undefined;
    const dir = path_buf[0..dir_len];
    const url = std.fmt.bufPrintSentinel(&ub, "file://{s}{s}", .{ if (dir.len > 0 and dir[0] != '/') "/" else "", dir }, 0) catch return;
    for (url) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    _ = c.SDL_OpenURL(url.ptr);
}

pub fn set(on: bool) void {
    if (mutex == null) mutex = c.SDL_CreateMutex();
    c.SDL_LockMutex(mutex);
    defer c.SDL_UnlockMutex(mutex);
    enabled.store(on and (isOn() or prepare()), .monotonic);
}

/// Confere na hora de ligar que dá para gravar lá (sem isso o botão ficaria ligado sem
/// gravar nada) e conta o que o arquivo de antes já tem.
fn prepare() bool {
    const p = path() orelse return false;
    const fd = open(p, false);
    if (fd < 0) return false;
    _ = c.close(fd);
    var info: c.SDL_PathInfo = undefined;
    size = if (c.SDL_GetPathInfo(p.ptr, &info)) @intCast(info.size) else 0;
    return true;
}

/// Pelo `open` do C, que no Windows divide o arquivo com quem quiser ler ou escrever. O
/// SDL_IOFromFile em modo de escrita não divide com ninguém: com o registro ligado, nem o
/// Bloco de Notas, nem uma cópia, nem o navegador ao anexar conseguiam abrir o arquivo.
fn open(p: [:0]const u8, restart: bool) c_int {
    const mode = c.O_WRONLY | c.O_CREAT | (if (restart) c.O_TRUNC else c.O_APPEND);
    const flags = if (sys.windows) mode | c.O_BINARY else mode | c.O_CLOEXEC;
    return c.open(p.ptr, flags, @as(c_uint, 0o600));
}

/// `std_options.logFn`: continua indo para o terminal e, ligado, também para o arquivo.
pub fn logFn(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    std.log.defaultLog(level, scope, format, args);
    if (!isOn()) return;
    var buf: [2048]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, level.asText() ++ ": " ++ format ++ "\n", args) catch return;
    scrub(line);
    write(line);
}

/// Abre, escreve no fim e fecha: entre uma linha e outra o arquivo fica livre para quem
/// for ler, e o que foi escrito já está nele (sem buffer para esvaziar).
fn write(line: []const u8) void {
    c.SDL_LockMutex(mutex);
    defer c.SDL_UnlockMutex(mutex);
    // Desligou entre a conferência do `logFn` e aqui.
    if (!isOn()) return;
    const p = path() orelse return;
    const restart = size + @as(i64, @intCast(line.len)) > max_bytes;
    const fd = open(p, restart);
    if (fd < 0) return;
    defer _ = c.close(fd);
    if (restart) size = 0;
    const n = c.write(fd, line.ptr, @intCast(line.len));
    if (n > 0) size += n;
}

fn tokenChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-';
}

/// Última barreira: o app não registra o token, mas nada com a cara de um vai para um
/// arquivo que a pessoa pode mandar para outros. Três pedaços separados por pontos.
pub fn scrub(line: []u8) void {
    var i: usize = 0;
    while (i < line.len) {
        if (!tokenChar(line[i])) {
            i += 1;
            continue;
        }
        const start = i;
        var dots: usize = 0;
        var part: usize = 0;
        var long_parts: usize = 0;
        while (i < line.len and (tokenChar(line[i]) or line[i] == '.')) : (i += 1) {
            if (line[i] == '.') {
                if (part >= 5) long_parts += 1;
                dots += 1;
                part = 0;
            } else part += 1;
        }
        if (part >= 5) long_parts += 1;
        const mfa = std.mem.startsWith(u8, line[start..i], "mfa.");
        if (dots >= 1 and i - start >= 30 and (long_parts >= 2 or mfa)) @memset(line[start..i], '*');
    }
}

test "o que parece token não vai para o registro" {
    // Em pedaços: inteiro, parece um token de verdade para quem procura segredos no repositório.
    var a = ("falhou com MTIzNDU2Nzg5MDEyMzQ1Njc4" ++ ".GabcDE." ++ "abcdefghijklmnopqrstuvwxyz0123 no gateway").*;
    scrub(&a);
    try std.testing.expect(std.mem.indexOf(u8, &a, "MTIzNDU2") == null);
    try std.testing.expect(std.mem.startsWith(u8, &a, "falhou com ***"));
    try std.testing.expect(std.mem.endsWith(u8, &a, "* no gateway"));
    var b = "voz: 12 pacotes de 3 pessoas, versão 0.6.1, canal 123456789012345678".*;
    const before = b;
    scrub(&b);
    try std.testing.expectEqualSlices(u8, &before, &b);
    var d = "mfa.abcdefghijklmnopqrstuvwxyz0123456789".*;
    scrub(&d);
    try std.testing.expect(d[0] == '*');
}
