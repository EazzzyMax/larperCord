//! Onde procurar as bibliotecas do FFmpeg e o que cada pasta tem. Um ffmpeg no
//! PATH nem sempre serve: as versões estáticas (a do winget, a do choco e as
//! "essentials" e "full" do gyan.dev) são só o ffmpeg.exe, sem as DLLs que o app
//! carrega. Daqui saem a conferência da pasta escolhida à mão e o diagnóstico de
//! Configurações → Chat → Vídeos.
//!
//! Sem SDL nem libc: quem chama diz como saber se um arquivo existe (o app usa o
//! SDL; os testes, pastas temporárias com arquivos vazios).
const std = @import("std");

pub const Os = enum { windows, linux };
pub const native: Os = if (@import("builtin").os.tag == .windows) .windows else .linux;

/// Versões com o layout conferido (FFmpeg 9, 8 e 7; ver platform/ffmpeg.zig).
pub const Set = struct { lavf: u32, lavc: u32, lavu: u32, sws: u32 };
pub const sets = [_]Set{
    .{ .lavf = 63, .lavc = 63, .lavu = 61, .sws = 10 },
    .{ .lavf = 62, .lavc = 62, .lavu = 60, .sws = 9 },
    .{ .lavf = 61, .lavc = 61, .lavu = 59, .sws = 8 },
};

/// As quatro que o app carrega, na ordem (cada uma só pede as de antes).
pub const Lib = enum { avutil, swscale, avcodec, avformat };

pub fn major(s: Set, lib: Lib) u32 {
    return switch (lib) {
        .avutil => s.lavu,
        .swscale => s.sws,
        .avcodec => s.lavc,
        .avformat => s.lavf,
    };
}

/// A versão do FFmpeg de cada libavformat: 58 é o 4, 61 o 7, 62 o 8.
pub fn ffmpegVersion(lavf: u32) u32 {
    return lavf -| 54;
}

pub fn supportedLavf(lavf: u32) bool {
    for (sets) |s| if (s.lavf == lavf) return true;
    return false;
}

/// avcodec-61.dll no Windows, libavcodec.so.61 no Linux (com o zero no fim).
/// `base` sem o "lib": "avcodec", "swresample".
pub fn libFile(buf: []u8, os: Os, base: []const u8, m: u32) ?[:0]const u8 {
    return switch (os) {
        .windows => std.fmt.bufPrintSentinel(buf, "{s}-{d}.dll", .{ base, m }, 0),
        .linux => std.fmt.bufPrintSentinel(buf, "lib{s}.so.{d}", .{ base, m }, 0),
    } catch null;
}

pub fn exeName(os: Os) []const u8 {
    return if (os == .windows) "ffmpeg.exe" else "ffmpeg";
}

/// `dir` + o separador do sistema + `name`, com o zero no fim. O LoadLibrary do
/// Windows não aceita a barra normal no caminho, então o separador é sempre o daqui.
pub fn join(buf: []u8, dir: []const u8, name: []const u8) ?[:0]const u8 {
    const sep = std.fs.path.sep;
    const d = std.mem.trimEnd(u8, dir, if (sep == '\\') "\\/" else "/");
    // A raiz ("/") vira "" sem a barra: ela volta aqui.
    if (d.len == 0) return std.fmt.bufPrintSentinel(buf, "{c}{s}", .{ sep, name }, 0) catch null;
    return std.fmt.bufPrintSentinel(buf, "{s}{c}{s}", .{ d, sep, name }, 0) catch null;
}

/// Diz se `path` é um arquivo.
pub const IsFile = *const fn (path: [:0]const u8) bool;

fn has(os: Os, is_file: IsFile, dir: []const u8, base: []const u8, m: u32) bool {
    var nb: [48]u8 = undefined;
    var pb: [640]u8 = undefined;
    const name = libFile(&nb, os, base, m) orelse return false;
    const path = join(&pb, dir, name) orelse return false;
    return is_file(path);
}

pub fn hasExe(dir: []const u8, os: Os, is_file: IsFile) bool {
    var pb: [640]u8 = undefined;
    const path = join(&pb, dir, exeName(os)) orelse return false;
    return is_file(path);
}

/// O que uma pasta tem.
pub const Check = union(enum) {
    /// Um conjunto inteiro que o app sabe usar.
    ok: Set,
    /// Parte de um conjunto: a primeira biblioteca que falta.
    incomplete: struct { set: Set, missing: Lib },
    /// Só bibliotecas de uma versão que o app não conhece (o major do libavformat).
    unsupported: u32,
    /// Só o ffmpeg(.exe), sem bibliotecas: uma versão estática.
    static_exe,
    nothing,
};

/// Na ordem: um conjunto inteiro; parte de um (diz o que falta); uma versão que o
/// app não conhece; só o ffmpeg; nada. Os números de cada biblioteca não se repetem
/// entre as versões, então "parte de um conjunto" é sempre da mesma versão.
pub fn check(dir: []const u8, os: Os, is_file: IsFile) Check {
    var best: ?struct { set: Set, n: u32, missing: Lib } = null;
    for (sets) |s| {
        var n: u32 = 0;
        var missing: ?Lib = null;
        for (std.enums.values(Lib)) |lib| {
            if (has(os, is_file, dir, @tagName(lib), major(s, lib))) {
                n += 1;
            } else if (missing == null) missing = lib;
        }
        const miss = missing orelse return .{ .ok = s };
        if (n > 0 and (best == null or n > best.?.n)) best = .{ .set = s, .n = n, .missing = miss };
    }
    if (best) |b| return .{ .incomplete = .{ .set = b.set, .missing = b.missing } };
    if (otherMajor(dir, os, is_file)) |m| return .{ .unsupported = m };
    if (hasExe(dir, os, is_file)) return .static_exe;
    return .nothing;
}

/// O libavformat de uma versão que o app não conhece, do mais novo para o mais velho.
pub fn otherMajor(dir: []const u8, os: Os, is_file: IsFile) ?u32 {
    var m: u32 = 80;
    while (m >= 52) : (m -= 1) {
        if (supportedLavf(m)) continue;
        if (has(os, is_file, dir, "avformat", m)) return m;
    }
    return null;
}

/// As pastas do PATH que valem: só caminhos absolutos (um "." faria a pasta atual
/// contar), sem as aspas que o Windows aceita em volta de cada uma.
pub const PathIter = struct {
    it: std.mem.TokenIterator(u8, .scalar),
    os: Os,

    pub fn next(p: *PathIter) ?[]const u8 {
        while (p.it.next()) |raw| {
            var dir = std.mem.trim(u8, raw, " \t");
            if (p.os == .windows) dir = std.mem.trim(u8, dir, "\"");
            if (dir.len == 0) continue;
            if (absolute(dir, p.os)) return dir;
        }
        return null;
    }
};

pub fn pathDirs(path_env: []const u8, os: Os) PathIter {
    return .{ .it = std.mem.tokenizeScalar(u8, path_env, if (os == .windows) ';' else ':'), .os = os };
}

/// No Windows, só com a letra do disco (C:\...) ou de rede (\\servidor\...): "\pasta"
/// sozinho depende do disco atual.
fn absolute(dir: []const u8, os: Os) bool {
    return switch (os) {
        .linux => dir[0] == '/',
        .windows => (dir.len >= 3 and std.ascii.isAlphabetic(dir[0]) and dir[1] == ':' and (dir[2] == '\\' or dir[2] == '/')) or
            std.mem.startsWith(u8, dir, "\\\\"),
    };
}

/// Mais do que isso no PATH é lixo de instaladores; cada pasta custa uns 13 stat.
pub const max_path_dirs = 128;

pub const PathScan = struct {
    /// Primeira pasta com um conjunto inteiro, e qual.
    libs_dir: ?[]const u8 = null,
    libs: Set = sets[0],
    /// Primeira pasta com o ffmpeg, e o que mais tem nela.
    exe_dir: ?[]const u8 = null,
    exe_check: Check = .nothing,
    /// Uma pasta com o ffmpeg de uma versão que o app não conhece.
    other_dir: ?[]const u8 = null,
    other: u32 = 0,
};

/// Passa pelas pastas do PATH. As fatias apontam para `path_env`. Versão que o app
/// não conhece só é procurada onde tem o ffmpeg: uma versão "shared" sempre o traz
/// junto das bibliotecas, e assim cada pasta comum custa só os 12 nomes conhecidos.
pub fn scanPath(path_env: []const u8, os: Os, is_file: IsFile) PathScan {
    var out: PathScan = .{};
    var it = pathDirs(path_env, os);
    var n: usize = 0;
    while (it.next()) |dir| : (n += 1) {
        if (n == max_path_dirs) break;
        const exe = hasExe(dir, os, is_file);
        const ch: Check = if (exe) check(dir, os, is_file) else for (sets) |s| {
            const full = for (std.enums.values(Lib)) |lib| {
                if (!has(os, is_file, dir, @tagName(lib), major(s, lib))) break false;
            } else true;
            if (full) break .{ .ok = s };
        } else .nothing;
        switch (ch) {
            .ok => |s| if (out.libs_dir == null) {
                out.libs_dir = dir;
                out.libs = s;
            },
            .unsupported => |m| if (out.other_dir == null) {
                out.other_dir = dir;
                out.other = m;
            },
            else => {},
        }
        if (exe and out.exe_dir == null) {
            out.exe_dir = dir;
            out.exe_check = ch;
        }
    }
    return out;
}

/// "avutil-61/60/59.dll, swscale-10/9/8.dll, avcodec-63/62/61.dll, avformat-63/62/61.dll":
/// os nomes que o app procura, para o diagnóstico.
pub fn searchedNames(buf: []u8, os: Os) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    for (std.enums.values(Lib), 0..) |lib, i| {
        if (i > 0) w.writeAll(", ") catch break;
        w.print("{s}{s}", .{ if (os == .linux) "lib" else "", @tagName(lib) }) catch break;
        w.writeAll(if (os == .linux) ".so." else "-") catch break;
        for (sets, 0..) |s, k| w.print("{s}{d}", .{ if (k > 0) "/" else "", major(s, lib) }) catch break;
        if (os == .windows) w.writeAll(".dll") catch break;
    }
    return w.buffered();
}

/// "7, 8 e 9" (com `last` = " e "/" or "...): as versões do FFmpeg que o app usa.
pub fn supportedVersions(buf: []u8, last: []const u8) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    var i: usize = sets.len;
    while (i > 0) {
        i -= 1;
        const sep: []const u8 = if (i == sets.len - 1) "" else if (i == 0) last else ", ";
        w.print("{s}{d}", .{ sep, ffmpegVersion(sets[i].lavf) }) catch break;
    }
    return w.buffered();
}

/// O SDL diz "Failed loading <arquivo>: <motivo>". No Linux, o motivo de uma
/// biblioteca que não existe é ela mesma "cannot open shared object file: No such
/// file or directory"; se é outro arquivo que falta (uma dependência) ou outro erro,
/// a biblioteca existe e não carregou, e isso entra no diagnóstico.
pub fn loadErrorIsMissing(err: []const u8, name: []const u8) bool {
    if (std.mem.indexOf(u8, err, "No such file") == null) return false;
    return std.mem.count(u8, err, name) >= 2;
}

/// Só o motivo, sem o "Failed loading <caminho>: " do começo.
pub fn loadErrorReason(err: []const u8) []const u8 {
    const prefix = "Failed loading ";
    if (!std.mem.startsWith(u8, err, prefix)) return err;
    // O caminho pode ter ": " (C:\...): o motivo vem depois do último ".dll: "/".so.N: ".
    var rest = err[prefix.len..];
    if (std.mem.indexOf(u8, rest, ".dll: ")) |i| return rest[i + 6 ..];
    if (std.mem.indexOf(u8, rest, ".so.")) |i| {
        rest = rest[i..];
        if (std.mem.indexOf(u8, rest, ": ")) |j| return rest[j + 2 ..];
    }
    return err;
}

// --- Testes ------------------------------------------------------------------

const testing = std.testing;

/// Pasta temporária com os arquivos pedidos (vazios), pelo caminho absoluto.
const Fixture = struct {
    tmp: testing.TmpDir,
    path_buf: [512]u8 = undefined,
    path_len: usize = 0,

    fn init() !Fixture {
        var f: Fixture = .{ .tmp = testing.tmpDir(.{}) };
        f.path_len = try f.tmp.dir.realPath(testing.io, &f.path_buf);
        return f;
    }

    fn path(f: *const Fixture) []const u8 {
        return f.path_buf[0..f.path_len];
    }

    /// `sub/arquivo`: cria a subpasta se precisar.
    fn file(f: *Fixture, sub_path: []const u8) !void {
        if (std.fs.path.dirname(sub_path)) |d| try f.tmp.dir.createDirPath(testing.io, d);
        try f.tmp.dir.writeFile(testing.io, .{ .sub_path = sub_path, .data = "" });
    }

    fn sub(f: *const Fixture, buf: []u8, name: []const u8) []const u8 {
        return join(buf, f.path(), name).?;
    }

    fn deinit(f: *Fixture) void {
        f.tmp.cleanup();
    }
};

fn testIsFile(p: [:0]const u8) bool {
    const st = std.Io.Dir.cwd().statFile(testing.io, p, .{}) catch return false;
    return st.kind == .file;
}

/// Os quatro arquivos de `s` em `dir` (nomes de `os`).
fn addSet(f: *Fixture, dir: []const u8, os: Os, s: Set) !void {
    for (std.enums.values(Lib)) |lib| {
        var nb: [48]u8 = undefined;
        var pb: [128]u8 = undefined;
        const name = libFile(&nb, os, @tagName(lib), major(s, lib)).?;
        try f.file(try std.fmt.bufPrint(&pb, "{s}/{s}", .{ dir, name }));
    }
}

test "pasta do FFmpeg: conjunto inteiro, incompleto, versão que o app não conhece, estático e vazio" {
    for ([_]Os{ .windows, .linux }) |os| {
        var f = try Fixture.init();
        defer f.deinit();
        var b: [600]u8 = undefined;
        // "shared" do FFmpeg 8: as quatro DLLs (e o ffmpeg junto, como vem no zip).
        try addSet(&f, "shared", os, sets[1]);
        try f.file(if (os == .windows) "shared/ffmpeg.exe" else "shared/ffmpeg");
        try testing.expectEqual(Check{ .ok = sets[1] }, check(f.sub(&b, "shared"), os, testIsFile));
        // Com a barra no fim também.
        var b2: [600]u8 = undefined;
        const slash = try std.fmt.bufPrint(&b2, "{s}{c}", .{ f.sub(&b, "shared"), std.fs.path.sep });
        try testing.expectEqual(Check{ .ok = sets[1] }, check(slash, os, testIsFile));
        // Faltando o swscale: diz qual.
        var nb: [48]u8 = undefined;
        var pb: [128]u8 = undefined;
        for ([_]Lib{ .avutil, .avcodec, .avformat }) |lib| try f.file(try std.fmt.bufPrint(&pb, "falta/{s}", .{libFile(&nb, os, @tagName(lib), major(sets[2], lib)).?}));
        const inc = check(f.sub(&b, "falta"), os, testIsFile);
        try testing.expectEqual(Lib.swscale, inc.incomplete.missing);
        try testing.expectEqual(sets[2].lavf, inc.incomplete.set.lavf);
        // FFmpeg 6 inteiro (avformat 60): versão que o app não conhece.
        try addSet(&f, "antigo", os, .{ .lavf = 60, .lavc = 60, .lavu = 58, .sws = 7 });
        try testing.expectEqual(Check{ .unsupported = 60 }, check(f.sub(&b, "antigo"), os, testIsFile));
        try testing.expectEqual(@as(u32, 6), ffmpegVersion(60));
        // Só o ffmpeg: estático.
        try f.file(if (os == .windows) "estatico/ffmpeg.exe" else "estatico/ffmpeg");
        try testing.expectEqual(Check.static_exe, check(f.sub(&b, "estatico"), os, testIsFile));
        // Nomes do outro sistema não contam.
        try addSet(&f, "outro", if (os == .windows) .linux else .windows, sets[0]);
        try testing.expectEqual(Check.nothing, check(f.sub(&b, "outro"), os, testIsFile));
        // Pasta que não existe.
        try testing.expectEqual(Check.nothing, check(f.sub(&b, "nao-existe"), os, testIsFile));
        // Uma pasta com o nome da DLL não é a DLL.
        try f.tmp.dir.createDirPath(testing.io, if (os == .windows) "pasta/avformat-61.dll" else "pasta/libavformat.so.61");
        try testing.expectEqual(Check.nothing, check(f.sub(&b, "pasta"), os, testIsFile));
    }
}

test "PATH: acha as bibliotecas, o ffmpeg estático e a versão que o app não conhece" {
    const os = native;
    var f = try Fixture.init();
    defer f.deinit();
    try f.file(if (os == .windows) "estatico/ffmpeg.exe" else "estatico/ffmpeg");
    try addSet(&f, "antigo", os, .{ .lavf = 59, .lavc = 59, .lavu = 57, .sws = 6 });
    try f.file(if (os == .windows) "antigo/ffmpeg.exe" else "antigo/ffmpeg");
    try addSet(&f, "shared", os, sets[2]);
    var path: std.ArrayList(u8) = .empty;
    defer path.deinit(testing.allocator);
    const sep: u8 = if (os == .windows) ';' else ':';
    var b: [600]u8 = undefined;
    var b2: [600]u8 = undefined;
    // Uma relativa e uma vazia no meio: ficam de fora.
    try path.print(testing.allocator, "relativa{c}{c}{s}{c}", .{ sep, sep, f.sub(&b, "estatico"), sep });
    try path.print(testing.allocator, "{s}{c}{s}", .{ f.sub(&b, "antigo"), sep, f.sub(&b2, "shared") });
    const r = scanPath(path.items, os, testIsFile);
    try testing.expectEqualStrings(f.sub(&b, "estatico"), r.exe_dir.?);
    try testing.expectEqual(Check.static_exe, r.exe_check);
    try testing.expectEqualStrings(f.sub(&b, "shared"), r.libs_dir.?);
    try testing.expectEqual(sets[2].lavf, r.libs.lavf);
    try testing.expectEqualStrings(f.sub(&b, "antigo"), r.other_dir.?);
    try testing.expectEqual(@as(u32, 59), r.other);
    // PATH sem nada disso.
    const empty = scanPath("relativa", os, testIsFile);
    try testing.expect(empty.exe_dir == null and empty.libs_dir == null and empty.other_dir == null);
}

test "PATH: separadores, aspas e caminhos relativos" {
    var it = pathDirs("C:\\a;;\"C:\\Program Files\\ffmpeg\\bin\";.;bin; D:/x ;\\\\srv\\share;\\sem-disco", .windows);
    try testing.expectEqualStrings("C:\\a", it.next().?);
    try testing.expectEqualStrings("C:\\Program Files\\ffmpeg\\bin", it.next().?);
    try testing.expectEqualStrings("D:/x", it.next().?);
    try testing.expectEqualStrings("\\\\srv\\share", it.next().?);
    try testing.expect(it.next() == null);
    var lin = pathDirs("/usr/bin::.:bin:/opt/ffmpeg/bin", .linux);
    try testing.expectEqualStrings("/usr/bin", lin.next().?);
    try testing.expectEqualStrings("/opt/ffmpeg/bin", lin.next().?);
    try testing.expect(lin.next() == null);
}

test "nomes procurados, versões aceitas e o erro do carregamento" {
    var b: [256]u8 = undefined;
    try testing.expectEqualStrings("avutil-61/60/59.dll, swscale-10/9/8.dll, avcodec-63/62/61.dll, avformat-63/62/61.dll", searchedNames(&b, .windows));
    try testing.expectEqualStrings("libavutil.so.61/60/59, libswscale.so.10/9/8, libavcodec.so.63/62/61, libavformat.so.63/62/61", searchedNames(&b, .linux));
    try testing.expectEqualStrings("7, 8 e 9", supportedVersions(&b, " e "));
    // Não existe: o nome aparece duas vezes (no "Failed loading" e no motivo).
    try testing.expect(loadErrorIsMissing("Failed loading libavcodec.so.61: libavcodec.so.61: cannot open shared object file: No such file or directory", "libavcodec.so.61"));
    // Existe, mas falta uma dependência dela, ou um símbolo.
    try testing.expect(!loadErrorIsMissing("Failed loading libavcodec.so.61: libdav1d.so.7: cannot open shared object file: No such file or directory", "libavcodec.so.61"));
    try testing.expect(!loadErrorIsMissing("Failed loading libavcodec.so.61: /usr/lib/libavcodec.so.61: undefined symbol: x", "libavcodec.so.61"));
    try testing.expectEqualStrings("The specified module could not be found.", loadErrorReason("Failed loading C:\\Program Files\\ff: x\\avcodec-61.dll: The specified module could not be found."));
    try testing.expectEqualStrings("libdav1d.so.7: cannot open shared object file", loadErrorReason("Failed loading /opt/ff/libavcodec.so.61: libdav1d.so.7: cannot open shared object file"));
    try testing.expectEqualStrings("outra coisa", loadErrorReason("outra coisa"));
}
