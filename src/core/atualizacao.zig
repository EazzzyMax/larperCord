//! Onde a atualização (net/updater.zig) põe cada arquivo. O executável é trocado
//! no caminho de quem está rodando, com o nome que ele tiver: o arquivo baixado da
//! página de releases chama larpercord-linux-x86_64 (ou o que a pessoa deu), o do
//! install.sh chama larpercord. As DLLs do Windows ficam na mesma pasta dele, com
//! os nomes de sempre. Só contas com caminhos: quem pergunta o caminho ao sistema
//! é `sys.selfExe`.
const std = @import("std");

/// Arquivo publicado na release -> lugar dele. `name` null: o próprio executável.
pub const File = struct { asset: []const u8, name: ?[]const u8 };

pub const files_linux: []const File = &.{
    .{ .asset = "larpercord-linux-x86_64", .name = null },
};
pub const files_windows: []const File = &.{
    .{ .asset = "larpercord-windows-x86_64.exe", .name = null },
    .{ .asset = "SDL3.dll", .name = "SDL3.dll" },
    .{ .asset = "libcurl-x64.dll", .name = "libcurl-x64.dll" },
    .{ .asset = "libcrypto-3-x64.dll", .name = "libcrypto-3-x64.dll" },
};

pub fn files(windows: bool) []const File {
    return if (windows) files_windows else files_linux;
}

/// O /proc/self/exe de um executável trocado com o app aberto aponta para o
/// arquivo velho, que saiu do nome: o kernel põe " (deleted)" no fim. O nome sem
/// isso é onde a versão nova está.
pub fn liveExe(link: []const u8) []const u8 {
    const tail = " (deleted)";
    return if (std.mem.endsWith(u8, link, tail)) link[0 .. link.len - tail.len] else link;
}

/// A pasta do executável, com a barra do fim ("" sem pasta). No Windows vale \ e /.
pub fn dirOf(exe: []const u8, windows: bool) []const u8 {
    const i = if (windows) std.mem.lastIndexOfAny(u8, exe, "\\/") else std.mem.lastIndexOfScalar(u8, exe, '/');
    return if (i) |n| exe[0 .. n + 1] else "";
}

/// O lugar de `f` ao lado de `exe`, com `suffix` no fim (".old" para o que sobra
/// da troca): o executável no próprio caminho, o resto na pasta dele.
pub fn place(buf: []u8, exe: []const u8, f: File, suffix: []const u8, windows: bool) ?[:0]const u8 {
    const name = f.name orelse return std.fmt.bufPrintSentinel(buf, "{s}{s}", .{ exe, suffix }, 0) catch null;
    return std.fmt.bufPrintSentinel(buf, "{s}{s}{s}", .{ dirOf(exe, windows), name, suffix }, 0) catch null;
}

/// A pasta onde tudo é baixado antes da troca, ao lado do executável.
pub fn stageDir(buf: []u8, exe: []const u8, windows: bool) ?[:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, "{s}.update", .{dirOf(exe, windows)}, 0) catch null;
}

/// O arquivo de `f` dentro da pasta do download (pelo nome publicado: dois
/// arquivos da release nunca têm o mesmo).
pub fn staged(buf: []u8, stage: []const u8, f: File) ?[:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, "{s}/{s}", .{ stage, f.asset }, 0) catch null;
}

// --- Testes -----------------------------------------------------------------------

const t = std.testing;

test "Linux: o arquivo baixado é trocado no próprio nome, não num 'larpercord' ao lado" {
    var b: [256]u8 = undefined;
    const exe = "/home/ana/Downloads/larpercord-linux-x86_64";
    const f = files_linux[0];
    try t.expectEqualStrings("larpercord-linux-x86_64", f.asset);
    try t.expectEqualStrings(exe, place(&b, exe, f, "", false).?);
    try t.expectEqualStrings(exe ++ ".old", place(&b, exe, f, ".old", false).?);
    // O do install.sh continua no nome dele.
    try t.expectEqualStrings("/home/ana/.local/bin/larpercord", place(&b, "/home/ana/.local/bin/larpercord", f, "", false).?);
    try t.expectEqualStrings("/home/ana/Downloads/.update", stageDir(&b, exe, false).?);
    try t.expectEqualStrings("/home/ana/Downloads/.update/larpercord-linux-x86_64", staged(&b, "/home/ana/Downloads/.update", f).?);
}

test "Linux: o caminho do /proc/self/exe depois da troca" {
    try t.expectEqualStrings("/opt/lc/larpercord-linux-x86_64", liveExe("/opt/lc/larpercord-linux-x86_64 (deleted)"));
    try t.expectEqualStrings("/opt/lc/larpercord", liveExe("/opt/lc/larpercord"));
    // Uma pasta com espaço no nome não perde nada.
    try t.expectEqualStrings("/home/ana/meus apps/larpercord", liveExe("/home/ana/meus apps/larpercord"));
    try t.expectEqualStrings("/opt/lc/", dirOf("/opt/lc/larpercord", false));
    // No Linux a contrabarra é só mais uma letra do nome.
    try t.expectEqualStrings("/opt/", dirOf("/opt/a\\b", false));
    try t.expectEqualStrings("", dirOf("larpercord", false));
}

test "Windows: o .exe no próprio caminho, as DLLs na pasta dele" {
    var b: [256]u8 = undefined;
    const exe = "C:\\Users\\Ana\\Downloads\\larpercord-windows-x86_64.exe";
    const dir = "C:\\Users\\Ana\\Downloads\\";
    try t.expectEqual(@as(usize, 4), files_windows.len);
    // Só o executável vai para o caminho de quem roda; nenhuma DLL fica sem nome.
    var exes: usize = 0;
    for (files_windows) |f| {
        if (f.name == null) {
            exes += 1;
            try t.expectEqualStrings(exe, place(&b, exe, f, "", true).?);
            try t.expectEqualStrings(exe ++ ".old", place(&b, exe, f, ".old", true).?);
        } else {
            try t.expect(std.mem.endsWith(u8, f.asset, ".dll"));
            try t.expectEqualStrings(f.asset, f.name.?);
            const p = place(&b, exe, f, "", true).?;
            try t.expect(std.mem.startsWith(u8, p, dir));
            try t.expectEqualStrings(f.asset, p[dir.len..]);
        }
    }
    try t.expectEqual(@as(usize, 1), exes);
    // O do install.ps1 (larpercord.exe) e caminho com barra normal.
    try t.expectEqualStrings("C:/lc/SDL3.dll", place(&b, "C:/lc/larpercord.exe", files_windows[1], "", true).?);
    try t.expectEqualStrings("C:\\Users\\Ana\\Downloads\\.update", stageDir(&b, exe, true).?);
}

test "caminho que não cabe não vira um pela metade" {
    var b: [16]u8 = undefined;
    try t.expect(place(&b, "/um/caminho/muito/comprido/larpercord", files_linux[0], "", false) == null);
    try t.expect(stageDir(&b, "/um/caminho/muito/comprido/larpercord", false) == null);
}

test "nenhum arquivo publicado aparece duas vezes na lista" {
    for ([_][]const File{ files_linux, files_windows }) |list| {
        for (list, 0..) |a, i| for (list[i + 1 ..]) |z| {
            try t.expect(!std.mem.eql(u8, a.asset, z.asset));
        };
    }
}
