//! Quando o Discord desafia a conta numa resposta da API: pede captcha, pede
//! verificação (código 40002) ou recusa a sessão (HTTP 401). Cada um vira uma
//! linha no registro de depuração e conta desde que o app abriu (Configurações →
//! Avançado → Depuração), para saber se o Discord desconfia de quem usa o larperCord.
//! Nada do corpo vai para o registro: só o tipo, o status e a rota.
//! Sem dependências (testado no `zig build test`).
const std = @import("std");
const j = @import("jsonx.zig");

pub const Kind = enum { captcha, verification, unauthorized };

var counts: [3]std.atomic.Value(u32) = .{ .init(0), .init(0), .init(0) };

/// Quantas vezes desde que o app abriu (lido pela interface, escrito pela rede).
pub fn count(k: Kind) u32 {
    return counts[@intFromEnum(k)].load(.monotonic);
}

/// Corpo de erro do Discord é pequeno; de um maior só procura as chaves no texto.
const max_parse = 8 * 1024;

/// O que a resposta pede (null = nenhum desafio). Só olha respostas de erro: o
/// corpo das que deram certo (mensagens, perfis) nem é lido.
pub fn classify(status: c_long, body: []const u8) ?Kind {
    if (status < 400) return null;
    if (status == 401) return .unauthorized;
    if (body.len <= max_parse) {
        // Sem heap: o JSON de um erro cabe folgado aqui.
        var mem: [24 * 1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&mem);
        if (std.json.parseFromSliceLeaky(std.json.Value, fba.allocator(), body, .{})) |root| {
            if (j.get(root, "captcha_key") != null or j.get(root, "captcha_sitekey") != null) return .captcha;
            if (j.int(j.get(root, "code"))) |code| if (code == 40002) return .verification;
            if (j.str(j.get(root, "message"))) |m| {
                if (std.ascii.findIgnoreCase(m, "verify your account") != null) return .verification;
            }
            return null;
        } else |_| {}
    }
    // Não deu para ler como JSON (grande demais ou cortado): as chaves do captcha no texto.
    const head = body[0..@min(body.len, 64 * 1024)];
    if (std.mem.indexOf(u8, head, "\"captcha_key\"") != null or std.mem.indexOf(u8, head, "\"captcha_sitekey\"") != null) return .captcha;
    return null;
}

/// Chamado com cada resposta da API do Discord. Barato quando deu certo (< 400).
pub fn observe(status: c_long, method: []const u8, path: []const u8, body: []const u8) void {
    const k = classify(status, body) orelse return;
    const n = counts[@intFromEnum(k)].fetchAdd(1, .monotonic) + 1;
    // Só a rota: a consulta pode levar o que a pessoa buscou.
    const route = path[0..@min(std.mem.indexOfScalar(u8, path, '?') orelse path.len, 200)];
    const what = switch (k) {
        .captcha => "pediu captcha",
        .verification => "pediu verificação da conta",
        .unauthorized => "recusou a sessão",
    };
    std.log.warn("discord: {s} (HTTP {d}) em {s} {s}; {d}ª vez desde que o app abriu", .{ what, status, method, route, n });
}

test "desafios: captcha, verificação e sessão recusada" {
    // Como o Discord manda (chaves de mentira).
    try std.testing.expectEqual(Kind.captcha, classify(400, "{\"captcha_key\":[\"captcha-required\"],\"captcha_sitekey\":\"00000000-0000-0000-0000-000000000000\",\"captcha_service\":\"hcaptcha\"}").?);
    try std.testing.expectEqual(Kind.captcha, classify(400, "{\"captcha_sitekey\":\"x\",\"captcha_rqdata\":\"y\"}").?);
    try std.testing.expectEqual(Kind.verification, classify(403, "{\"message\": \"You need to verify your account in order to perform this action.\", \"code\": 40002}").?);
    try std.testing.expectEqual(Kind.verification, classify(403, "{\"message\":\"Please verify your account\",\"code\":0}").?);
    try std.testing.expectEqual(Kind.unauthorized, classify(401, "{\"message\": \"401: Unauthorized\", \"code\": 0}").?);
    try std.testing.expectEqual(Kind.unauthorized, classify(401, "").?);
    // Grande ou cortado: ainda acha o captcha pelo texto.
    try std.testing.expectEqual(Kind.captcha, classify(400, "{\"captcha_key\":[\"captcha-required\"],\"captcha_rqdata\":\"abc").?);
}

test "desafios: o resto não conta" {
    // Sucesso não é lido, nem se o texto de uma mensagem falar de captcha.
    try std.testing.expect(classify(200, "{\"content\":\"\\\"captcha_key\\\" 40002\"}") == null);
    try std.testing.expect(classify(204, "") == null);
    try std.testing.expect(classify(403, "{\"message\": \"Missing Access\", \"code\": 50001}") == null);
    try std.testing.expect(classify(404, "{\"message\": \"Unknown Invite\", \"code\": 10006}") == null);
    try std.testing.expect(classify(429, "{\"message\": \"You are being rate limited.\", \"retry_after\": 1.5, \"global\": false}") == null);
    try std.testing.expect(classify(500, "<html>erro</html>") == null);
    // Erro de formulário que cita o campo de captcha num valor não é pedido de captcha.
    try std.testing.expect(classify(400, "{\"code\":50035,\"errors\":{\"content\":{\"_errors\":[{\"message\":\"captcha_key\"}]}}}") == null);
}
