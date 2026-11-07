//! Proxy das conexões (Configurações → Privacidade → Rede): http, https,
//! socks5 ou socks5h (socks5h://127.0.0.1:9050 = Tor, com o DNS pelo proxy).
//! Por padrão só a mídia de fora (Tenor, Giphy) passa por ele; com "em
//! tudo", também o Discord (gateway, API, imagens e vídeos).
//! Sem dependências (testado no `zig build test`); quem tem o curl aplica.
const std = @import("std");
const media_url = @import("media_url.zig");

pub const max_len = 255;
pub const Buf = [max_len + 1]u8;

/// A URL é um proxy que a gente aceita? `esquema://[usuário[:senha]@]host[:porta][/]`
pub fn valid(url: []const u8) bool {
    if (url.len == 0 or url.len > max_len) return false;
    const schemes = [_][]const u8{ "http://", "https://", "socks5://", "socks5h://" };
    const rest = for (schemes) |s| {
        if (std.ascii.startsWithIgnoreCase(url, s)) break url[s.len..];
    } else return false;
    var hostport = if (std.mem.endsWith(u8, rest, "/")) rest[0 .. rest.len - 1] else rest;
    if (std.mem.indexOfScalar(u8, hostport, '/') != null) return false;
    // Usuário e senha (o @ é o último: a senha pode ter @ codificado como %40).
    if (std.mem.lastIndexOfScalar(u8, hostport, '@')) |at| {
        for (hostport[0..at]) |ch| if (!userChar(ch)) return false;
        if (at == 0) return false;
        hostport = hostport[at + 1 ..];
    }
    var host = hostport;
    var port: []const u8 = "";
    if (std.mem.startsWith(u8, hostport, "[")) {
        // IPv6: [::1]:1080
        const close = std.mem.indexOfScalar(u8, hostport, ']') orelse return false;
        host = hostport[1..close];
        if (host.len == 0) return false;
        for (host) |ch| if (!(std.ascii.isHex(ch) or ch == ':' or ch == '.')) return false;
        const after = hostport[close + 1 ..];
        if (after.len > 0) {
            if (after[0] != ':') return false;
            port = after[1..];
            if (port.len == 0) return false;
        }
    } else {
        if (std.mem.lastIndexOfScalar(u8, hostport, ':')) |colon| {
            host = hostport[0..colon];
            port = hostport[colon + 1 ..];
            if (port.len == 0) return false;
        }
        if (host.len == 0 or host.len > 253) return false;
        for (host) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-' or ch == '_')) return false;
        if (host[0] == '.' or host[0] == '-') return false;
    }
    if (port.len > 0) {
        const n = std.fmt.parseInt(u32, port, 10) catch return false;
        if (n == 0 or n > 65535) return false;
    }
    return true;
}

fn userChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or std.mem.indexOfScalar(u8, "-._~%!$&'()*+,;=:", ch) != null;
}

// --- Formulário (tipo, endereço, porta, login e senha) -------------------------
// A tela mostra o proxy em campos, mas as configurações guardam uma URL só (`s.proxy`):
// `build` monta a URL a partir dos campos e `fill` desmonta uma URL nos campos.

/// Os tipos, na ordem dos botões da tela.
pub const Kind = enum(u8) {
    http,
    https,
    socks5,
    socks5h,

    pub fn scheme(k: Kind) []const u8 {
        return @tagName(k);
    }

    /// A porta que o curl usa quando a URL não diz uma: 443 no https, 1080 nos outros.
    pub fn defaultPort(k: Kind) u16 {
        return if (k == .https) 443 else 1080;
    }
};

pub const BuildError = error{ NoHost, BadHost, BadPort, PassWithoutUser, TooLong };

/// Os campos da tela, cada um uma string C (é o buffer do ImGui). Login e senha ficam
/// decodificados aqui; o `%` só aparece na URL.
pub const Form = struct {
    /// Índice em `Kind` (o seletor da tela escreve direto aqui).
    kind: u8 = 0,
    host: [254]u8 = @splat(0),
    port: [6]u8 = @splat(0),
    user: [128]u8 = @splat(0),
    pass: [128]u8 = @splat(0),

    pub fn kindOf(f: *const Form) Kind {
        return @enumFromInt(@min(f.kind, @intFromEnum(Kind.socks5h)));
    }

    pub fn empty(f: *const Form) bool {
        return f.host[0] == 0 and f.port[0] == 0 and f.user[0] == 0 and f.pass[0] == 0;
    }

    /// Mostra o que está salvo. Vazio limpa os campos (o tipo fica); uma URL que não
    /// dá para desmontar vai inteira para o endereço, para a pessoa ver e corrigir.
    pub fn load(f: *Form, url: []const u8) void {
        if (url.len > 0 and f.fill(url)) return;
        const kind = f.kind;
        f.* = .{ .kind = kind };
        setText(&f.host, url);
    }

    /// Desmonta `esquema://[usuário[:senha]@]host[:porta][/]` nos campos (sem o esquema,
    /// `usuário:senha@host:porta` também serve e o tipo fica). false = não é uma URL de
    /// proxy que a gente aceita, e nada muda.
    pub fn fill(f: *Form, text_in: []const u8) bool {
        const text = std.mem.trim(u8, text_in, " \t\r\n");
        var kind = f.kindOf();
        var rest = text;
        if (std.mem.indexOf(u8, text, "://")) |sep| {
            var sb: [8]u8 = undefined;
            if (sep > sb.len) return false;
            kind = std.meta.stringToEnum(Kind, std.ascii.lowerString(&sb, text[0..sep])) orelse return false;
            rest = text[sep + 3 ..];
        } else if (std.mem.indexOfScalar(u8, text, '@') == null) return false;
        if (std.mem.endsWith(u8, rest, "/")) rest = rest[0 .. rest.len - 1];
        if (rest.len == 0 or std.mem.indexOfScalar(u8, rest, '/') != null) return false;
        var user: [128]u8 = @splat(0);
        var pass: [128]u8 = @splat(0);
        var hostport = rest;
        // O @ que separa é o último: a senha pode trazer um @ (codificado ou não).
        if (std.mem.lastIndexOfScalar(u8, rest, '@')) |at| {
            const info = rest[0..at];
            const colon = std.mem.indexOfScalar(u8, info, ':');
            if (!percentDecode(&user, info[0 .. colon orelse info.len])) return false;
            if (colon) |cc| if (!percentDecode(&pass, info[cc + 1 ..])) return false;
            hostport = rest[at + 1 ..];
        }
        const hp = splitHostPort(hostport) orelse return false;
        if (hp.host.len == 0 or hp.host.len >= f.host.len) return false;
        f.kind = @intFromEnum(kind);
        setText(&f.host, hp.host);
        setText(&f.port, hp.port);
        f.user = user;
        f.pass = pass;
        return true;
    }

    /// O endereço às vezes chega com mais coisa: a URL inteira (colada ou digitada),
    /// `host:porta` ou `[IPv6]:porta`. Espalha pelos campos. true = mudou algo.
    pub fn absorbHost(f: *Form) bool {
        var tmp: [254]u8 = undefined;
        const h = std.mem.trim(u8, std.mem.sliceTo(&f.host, 0), " \t");
        @memcpy(tmp[0..h.len], h);
        const text = tmp[0..h.len];
        if (std.mem.indexOf(u8, text, "://") != null or std.mem.indexOfScalar(u8, text, '@') != null) return f.fill(text);
        const hp = splitHostPort(text) orelse return false;
        if (hp.port.len == 0) return false;
        setText(&f.host, hp.host);
        setText(&f.port, hp.port);
        return true;
    }

    /// Monta a URL dos campos em `out` (com o zero no fim, para o curl). Login e senha
    /// vão com `%`: um @, : ou / neles não confunde quem lê a URL.
    pub fn build(f: *const Form, out: *Buf) BuildError![:0]const u8 {
        var host = std.mem.trim(u8, std.mem.sliceTo(&f.host, 0), " \t");
        if (host.len == 0) return error.NoHost;
        var v6 = false;
        if (host.len >= 2 and host[0] == '[' and host[host.len - 1] == ']') {
            host = host[1 .. host.len - 1];
            v6 = true;
        } else v6 = std.mem.indexOfScalar(u8, host, ':') != null;
        if (host.len == 0) return error.BadHost;
        if (v6) {
            if (std.mem.indexOfScalar(u8, host, ':') == null) return error.BadHost;
            for (host) |ch| if (!(std.ascii.isHex(ch) or ch == ':' or ch == '.')) return error.BadHost;
        } else {
            if (host.len > 253 or host[0] == '.' or host[0] == '-') return error.BadHost;
            for (host) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-' or ch == '_')) return error.BadHost;
        }
        const port_text = std.mem.trim(u8, std.mem.sliceTo(&f.port, 0), " \t");
        if (port_text.len > 0) {
            const n = std.fmt.parseInt(u16, port_text, 10) catch return error.BadPort;
            if (n == 0) return error.BadPort;
        }
        const user = std.mem.sliceTo(&f.user, 0);
        const pass = std.mem.sliceTo(&f.pass, 0);
        if (user.len == 0 and pass.len > 0) return error.PassWithoutUser;
        var w: Out = .{ .buf = out };
        w.put(f.kindOf().scheme());
        w.put("://");
        if (user.len > 0) {
            w.encoded(user);
            if (pass.len > 0) {
                w.put(":");
                w.encoded(pass);
            }
            w.put("@");
        }
        if (v6) w.put("[");
        w.put(host);
        if (v6) w.put("]");
        if (port_text.len > 0) {
            w.put(":");
            w.put(port_text);
        }
        if (w.over) return error.TooLong;
        out[w.len] = 0;
        const url = out[0..w.len :0];
        // A mesma regra de quem aplica: o que a tela salva, o `set` aceita.
        if (!valid(url)) return error.BadHost;
        return url;
    }
};

/// Escreve no buffer da URL; passar do tamanho só marca `over`.
const Out = struct {
    buf: *Buf,
    len: usize = 0,
    over: bool = false,

    fn put(o: *Out, s: []const u8) void {
        if (o.len + s.len > max_len) {
            o.over = true;
            return;
        }
        @memcpy(o.buf[o.len..][0..s.len], s);
        o.len += s.len;
    }

    /// Só letras, números e `-._~` passam como estão; o resto vira `%XX`.
    fn encoded(o: *Out, s: []const u8) void {
        for (s) |ch| {
            if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_' or ch == '~') {
                o.put(&[_]u8{ch});
            } else {
                const hex = "0123456789ABCDEF";
                o.put(&[_]u8{ '%', hex[ch >> 4], hex[ch & 15] });
            }
        }
    }
};

fn setText(buf: []u8, s: []const u8) void {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    @memset(buf[n..], 0);
}

/// `%XX` vira o byte; um `%` sem dois dígitos hexa depois fica como está (o curl faz
/// igual). false = não coube, ou um `%00` (o campo é uma string C).
fn percentDecode(out: []u8, s: []const u8) bool {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) {
        if (n + 1 >= out.len) return false;
        if (s[i] == '%' and i + 2 < s.len and std.ascii.isHex(s[i + 1]) and std.ascii.isHex(s[i + 2])) {
            const b = std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16) catch unreachable;
            if (b == 0) return false;
            out[n] = b;
            i += 3;
        } else {
            out[n] = s[i];
            i += 1;
        }
    }
    @memset(out[n..], 0);
    return true;
}

const HostPort = struct { host: []const u8, port: []const u8 };

/// `host`, `host:porta`, `[IPv6]` ou `[IPv6]:porta`. Um IPv6 sem colchetes é só host.
/// null = porta que não é número de 1 a 65535, ou colchete aberto.
fn splitHostPort(s: []const u8) ?HostPort {
    var host = s;
    var port: ?[]const u8 = null;
    if (std.mem.startsWith(u8, s, "[")) {
        const close = std.mem.indexOfScalar(u8, s, ']') orelse return null;
        host = s[1..close];
        const after = s[close + 1 ..];
        if (after.len > 0) {
            if (after[0] != ':') return null;
            port = after[1..];
        }
    } else if (std.mem.indexOfScalar(u8, s, ':')) |colon| {
        // Outro dois-pontos depois: IPv6 sem colchetes, e aí não há porta.
        if (std.mem.indexOfScalarPos(u8, s, colon + 1, ':') == null) {
            host = s[0..colon];
            port = s[colon + 1 ..];
        }
    }
    if (port) |p| {
        // Cabe no campo da porta (5 dígitos): "000080" não.
        if (p.len > 5) return null;
        const n = std.fmt.parseInt(u16, p, 10) catch return null;
        if (n == 0) return null;
    }
    return .{ .host = host, .port = port orelse "" };
}

// O valor em uso: escrito pela interface, lido pelas threads de rede.
var lock_flag: std.atomic.Value(bool) = .init(false);
var cur: Buf = @splat(0);
var cur_len: usize = 0;
var cur_all = false;

fn lock() void {
    while (lock_flag.swap(true, .acquire)) std.atomic.spinLoopHint();
}

fn unlock() void {
    lock_flag.store(false, .release);
}

/// Aplica o que está nas configurações (inválido = sem proxy). Barato se
/// nada mudou (o app chama a cada quadro).
pub fn set(url: []const u8, all: bool) void {
    // Chamado a cada quadro: sem mudança, nem valida.
    if (last_all == all and std.mem.eql(u8, last_raw[0..last_raw_len], url)) return;
    last_all = all;
    last_raw_len = @min(url.len, last_raw.len);
    @memcpy(last_raw[0..last_raw_len], url[0..last_raw_len]);
    const u = if (valid(url)) url else "";
    lock();
    defer unlock();
    if (cur_all == all and std.mem.eql(u8, cur[0..cur_len], u)) return;
    @memcpy(cur[0..u.len], u);
    cur[u.len] = 0;
    cur_len = u.len;
    cur_all = all;
}

var last_raw: [512]u8 = undefined;
var last_raw_len: usize = 0;
var last_all = false;

/// O proxy para baixar `url` (null = conexão direta).
pub fn forUrl(buf: *Buf, url: []const u8) ?[:0]const u8 {
    lock();
    defer unlock();
    if (cur_len == 0) return null;
    if (!cur_all and media_url.discordHost(url)) return null;
    @memcpy(buf[0 .. cur_len + 1], cur[0 .. cur_len + 1]);
    return buf[0..cur_len :0];
}

/// O proxy do gateway e da API do Discord (só com "em tudo").
pub fn forDiscord(buf: *Buf) ?[:0]const u8 {
    lock();
    defer unlock();
    if (cur_len == 0 or !cur_all) return null;
    @memcpy(buf[0 .. cur_len + 1], cur[0 .. cur_len + 1]);
    return buf[0..cur_len :0];
}

test "proxy: urls aceitas e recusadas" {
    for ([_][]const u8{ "socks5h://127.0.0.1:9050", "socks5://localhost:1080", "http://proxy.example.com:3128", "https://p.example.com", "HTTP://10.0.0.1:8080/", "socks5://user:pa%40ss@host:1080", "socks5h://[::1]:9050" }) |u| {
        if (!valid(u)) {
            std.debug.print("deveria aceitar {s}\n", .{u});
            return error.TestUnexpectedResult;
        }
    }
    for ([_][]const u8{ "", "127.0.0.1:9050", "ftp://x:21", "socks4://h:1", "socks5h://", "socks5h://:9050", "socks5h://h:0", "socks5h://h:70000", "socks5h://h:", "http://h/path", "http://h\"x", "http://a b", "http://h:80\\", "socks5://@h:1", "socks5h://[]:1", "http://-h" }) |u| {
        if (valid(u)) {
            std.debug.print("deveria recusar {s}\n", .{u});
            return error.TestUnexpectedResult;
        }
    }
}

test "proxy: só a mídia de fora, ou tudo" {
    var b: Buf = undefined;
    set("socks5h://127.0.0.1:9050", false);
    try std.testing.expectEqualStrings("socks5h://127.0.0.1:9050", forUrl(&b, "https://media.tenor.com/x.webp").?);
    try std.testing.expect(forUrl(&b, "https://cdn.discordapp.com/x.png") == null);
    try std.testing.expect(forDiscord(&b) == null);
    set("socks5h://127.0.0.1:9050", true);
    try std.testing.expect(forUrl(&b, "https://cdn.discordapp.com/x.png") != null);
    try std.testing.expect(forDiscord(&b) != null);
    set("lixo", true);
    try std.testing.expect(forUrl(&b, "https://media.tenor.com/x.webp") == null);
    set("", false);
    try std.testing.expect(forDiscord(&b) == null);
}

test "proxy: campos viram URL com login e senha codificados, e voltam" {
    var f: Form = .{ .kind = @intFromEnum(Kind.http) };
    setText(&f.host, "proxy.local");
    setText(&f.port, "3128");
    setText(&f.user, "eu@casa:1");
    setText(&f.pass, "p@ss:w/rd% ok");
    var b: Buf = undefined;
    const url = try f.build(&b);
    try std.testing.expectEqualStrings("http://eu%40casa%3A1:p%40ss%3Aw%2Frd%25%20ok@proxy.local:3128", url);
    try std.testing.expect(valid(url));
    var g: Form = .{};
    try std.testing.expect(g.fill(url));
    try std.testing.expectEqual(Kind.http, g.kindOf());
    try std.testing.expectEqualStrings("proxy.local", std.mem.sliceTo(&g.host, 0));
    try std.testing.expectEqualStrings("3128", std.mem.sliceTo(&g.port, 0));
    try std.testing.expectEqualStrings("eu@casa:1", std.mem.sliceTo(&g.user, 0));
    try std.testing.expectEqualStrings("p@ss:w/rd% ok", std.mem.sliceTo(&g.pass, 0));
    // Fora do ASCII: cada byte do UTF-8 vira %XX.
    setText(&f.user, "joão");
    setText(&f.pass, "");
    try std.testing.expectEqualStrings("http://jo%C3%A3o@proxy.local:3128", try f.build(&b));
    // Um % solto numa URL antiga fica como está (o curl lê igual) e volta codificado.
    try std.testing.expect(g.fill("socks5://user:pa%ss@h:1080"));
    try std.testing.expectEqualStrings("pa%ss", std.mem.sliceTo(&g.pass, 0));
    try std.testing.expectEqualStrings("socks5://user:pa%25ss@h:1080", try g.build(&b));
}

test "proxy: IPv6 com e sem colchetes" {
    var f: Form = .{ .kind = @intFromEnum(Kind.socks5h) };
    setText(&f.host, "::1");
    setText(&f.port, "9050");
    var b: Buf = undefined;
    try std.testing.expectEqualStrings("socks5h://[::1]:9050", try f.build(&b));
    setText(&f.host, "[2001:db8::7]");
    setText(&f.port, "");
    try std.testing.expectEqualStrings("socks5h://[2001:db8::7]", try f.build(&b));
    var g: Form = .{};
    try std.testing.expect(g.fill("socks5h://u:p@[::1]:9050/"));
    try std.testing.expectEqual(Kind.socks5h, g.kindOf());
    try std.testing.expectEqualStrings("::1", std.mem.sliceTo(&g.host, 0));
    try std.testing.expectEqualStrings("9050", std.mem.sliceTo(&g.port, 0));
    // Colado no endereço com a porta junto.
    setText(&g.host, "[::1]:1080");
    setText(&g.port, "");
    try std.testing.expect(g.absorbHost());
    try std.testing.expectEqualStrings("::1", std.mem.sliceTo(&g.host, 0));
    try std.testing.expectEqualStrings("1080", std.mem.sliceTo(&g.port, 0));
    // IPv6 sem colchetes não tem porta para separar.
    setText(&g.host, "fe80::1");
    try std.testing.expect(!g.absorbHost());
}

test "proxy: sem login, padrões e erros" {
    var g: Form = .{};
    try std.testing.expectEqual(Kind.http, g.kindOf());
    try std.testing.expect(g.empty());
    var b: Buf = undefined;
    try std.testing.expectError(error.NoHost, g.build(&b));
    // Sem login e sem porta: a URL sai sem os dois e o curl usa a porta padrão do tipo.
    try std.testing.expect(g.fill("HTTPS://p.example.com"));
    try std.testing.expectEqual(Kind.https, g.kindOf());
    try std.testing.expectEqualStrings("", std.mem.sliceTo(&g.port, 0));
    try std.testing.expectEqualStrings("", std.mem.sliceTo(&g.user, 0));
    try std.testing.expectEqual(@as(u16, 443), g.kindOf().defaultPort());
    try std.testing.expectEqual(@as(u16, 1080), Kind.socks5h.defaultPort());
    try std.testing.expectEqualStrings("https://p.example.com", try g.build(&b));
    // Só o login também vale; só a senha, não.
    setText(&g.user, "eu");
    try std.testing.expectEqualStrings("https://eu@p.example.com", try g.build(&b));
    setText(&g.user, "");
    setText(&g.pass, "x");
    try std.testing.expectError(error.PassWithoutUser, g.build(&b));
    setText(&g.pass, "");
    for ([_][]const u8{ "0", "70000", "abc", "-1" }) |p| {
        setText(&g.port, p);
        try std.testing.expectError(error.BadPort, g.build(&b));
    }
    setText(&g.port, "8080");
    for ([_][]const u8{ "ftp://h", "a b", "-h", "h/x", "zz::1", "[]" }) |h| {
        setText(&g.host, h);
        if (g.build(&b)) |u| {
            std.debug.print("deveria recusar {s} ({s})\n", .{ h, u });
            return error.TestUnexpectedResult;
        } else |_| {}
    }
    setText(&g.host, "h");
    @memset(g.pass[0..127], '@');
    setText(&g.user, "u");
    try std.testing.expectError(error.TooLong, g.build(&b));
    // O que não é proxy não mexe nos campos.
    var k: Form = .{ .kind = @intFromEnum(Kind.socks5) };
    setText(&k.host, "fica");
    for ([_][]const u8{ "ftp://x:21", "socks4://h:1", "socks5h://", "http://h:0", "http://h:", "http://h/caminho", "só texto" }) |u| {
        try std.testing.expect(!k.fill(u));
    }
    try std.testing.expectEqualStrings("fica", std.mem.sliceTo(&k.host, 0));
    // Sem esquema, com login: o tipo escolhido fica.
    try std.testing.expect(k.fill("eu:senha@10.0.0.2:1081"));
    try std.testing.expectEqual(Kind.socks5, k.kindOf());
    try std.testing.expectEqualStrings("senha", std.mem.sliceTo(&k.pass, 0));
    // Endereço com porta junto, ou a URL inteira digitada nele.
    setText(&k.host, "proxy.casa:3128");
    try std.testing.expect(k.absorbHost());
    try std.testing.expectEqualStrings("proxy.casa", std.mem.sliceTo(&k.host, 0));
    try std.testing.expectEqualStrings("3128", std.mem.sliceTo(&k.port, 0));
    setText(&k.host, "socks5h://127.0.0.1:9050");
    try std.testing.expect(k.absorbHost());
    try std.testing.expectEqual(Kind.socks5h, k.kindOf());
    try std.testing.expectEqualStrings("", std.mem.sliceTo(&k.user, 0));
    try std.testing.expectEqualStrings("socks5h://127.0.0.1:9050", try k.build(&b));
    // Salvo inválido: vai inteiro para o endereço.
    k.load("lixo://x");
    try std.testing.expectEqualStrings("lixo://x", std.mem.sliceTo(&k.host, 0));
    k.load("");
    try std.testing.expect(k.empty());
}
