//! Decisões sobre a janela que não dependem do SDL (testadas em `zig build
//! test`): o que fechar faz, onde uma lista flutuante cabe e o arquivo com que
//! um segundo larperCord acha o primeiro.
const std = @import("std");
const layout = @import("../theme/layout.zig");
const Rect = layout.Rect;

/// Fechar a janela pode virar "ficar na bandeja"? Na tela de login não há
/// conexão nenhuma para manter: ali fechar é sair.
pub fn wantsTray(close_to_tray: bool, logged_in: bool) bool {
    return close_to_tray and logged_in;
}

/// Quantas verificações seguidas sem bandeja até devolver a janela: uma só
/// pode ser o painel reiniciando.
pub const tray_misses_max: u8 = 2;

/// Como a janela está quando alguém clica no ícone da bandeja. Coberta por
/// outras janelas conta como minimizada: o clique é para vê-la.
pub const Vista = enum { aberta, minimizada, na_bandeja };

/// O que o clique no ícone faz.
pub const Clique = enum { mostrar, para_bandeja, minimizar };

/// Clicar no ícone alterna a janela: escondida ou minimizada, ela volta na
/// frente; aberta, vai para a bandeja quando fechar iria (opção ligada e depois
/// do login), senão minimiza.
pub fn trayClick(vista: Vista, close_to_tray: bool, logged_in: bool) Clique {
    return switch (vista) {
        .minimizada, .na_bandeja => .mostrar,
        .aberta => if (wantsTray(close_to_tray, logged_in)) .para_bandeja else .minimizar,
    };
}

/// O Windows manda um "soltou o botão" em cada metade do clique duplo: o segundo,
/// dentro do tempo do clique duplo do sistema, não desfaz o primeiro.
pub fn trayClickCounts(since_last_ms: i64, double_click_ms: i64) bool {
    return since_last_ms < 0 or since_last_ms >= double_click_ms;
}

/// O que fazer com o ícone de "sempre na bandeja" agora. `kept`: o ícone que está
/// lá é o desta opção (e não só o de uma ida à bandeja).
pub const Icone = enum { nada, criar, tirar, refazer };

pub fn trayIcon(always: bool, kept: bool, in_tray: bool, active: bool, lang_changed: bool) Icone {
    // Escondida, quem cuida do ícone é a volta da bandeja: tirar seria perder o caminho de volta.
    if (in_tray) return .nada;
    if (!always) return if (kept and active) .tirar else .nada;
    if (!active) return .criar;
    // Os rótulos do menu são do idioma de quando o ícone nasceu.
    return if (kept and lang_changed) .refazer else .nada;
}

/// Espera até tentar pôr o ícone de novo (sem painel ainda, ou o processo do ícone
/// caiu): dobra a cada tentativa, de 5 s a 5 min. Sem painel nenhum (um GNOME sem a
/// extensão), a pergunta ao D-Bus fica rara em vez de a cada tique.
pub fn trayRetryMs(tries: u8) i64 {
    return @min(@as(i64, 5_000) << @intCast(@min(tries, 6)), 300_000);
}

/// Na bandeja ou minimizada há esse tempo, as imagens saem da memória. Coberta por
/// outra janela não: trocar de workspace não pode virar download de novo.
pub const hidden_release_ms: i64 = 60_000;
pub const hidden_keep_bytes: usize = 128 * 1024;

/// Não há cópia das imagens em disco: o que sai é baixado de novo ao voltar. Fica o
/// que é pequeno e estava na tela (avatares, ícones), para a janela voltar inteira.
pub fn keepsImageHidden(bytes: usize, frames: usize, idle_ms: i64) bool {
    return frames == 1 and bytes <= hidden_keep_bytes and idle_ms <= 1000;
}

/// Onde uma lista flutuante fica: embaixo de `anchor` se couber; senão, do lado
/// com mais espaço, com a altura limitada a esse espaço (o resto rola).
pub fn place(anchor: Rect, want_w: f32, want_h: f32, win: Rect) Rect {
    const margin: f32 = 8;
    const gap: f32 = 4;
    const below = win.bottom() - anchor.bottom() - gap - margin;
    const above = anchor.y - win.y - gap - margin;
    const up = want_h > below and above > below;
    const room = @max(if (up) above else below, 0);
    const h = @min(want_h, room);
    const w = @min(want_w, @max(win.w - margin * 2, 0));
    const x = std.math.clamp(anchor.x, win.x + margin, @max(win.x + margin, win.right() - margin - w));
    return .{ .x = x, .y = if (up) anchor.y - gap - h else anchor.bottom() + gap, .w = w, .h = h };
}

/// O que o primeiro larperCord deixa no arquivo `instance.port`.
pub const Instance = struct {
    port: u16,
    nonce: []const u8,

    pub const nonce_len = 16;

    pub fn parse(text: []const u8) ?Instance {
        var it = std.mem.tokenizeAny(u8, text, " \r\n");
        const port = std.fmt.parseInt(u16, it.next() orelse return null, 10) catch return null;
        const nonce = it.next() orelse return null;
        if (port == 0 or nonce.len != nonce_len) return null;
        return .{ .port = port, .nonce = nonce };
    }
};

test "fechar só vira bandeja com a opção ligada e depois do login" {
    try std.testing.expect(wantsTray(true, true));
    try std.testing.expect(!wantsTray(false, true));
    try std.testing.expect(!wantsTray(true, false));
    try std.testing.expect(!wantsTray(false, false));
}

test "clique no ícone: janela × fechar para a bandeja × login" {
    const T = struct {
        fn f(v: Vista, ctt: bool, li: bool) Clique {
            return trayClick(v, ctt, li);
        }
    };
    // Escondida ou minimizada: sempre volta, com qualquer opção.
    for ([_]Vista{ .na_bandeja, .minimizada }) |v| {
        for ([_]bool{ true, false }) |ctt| for ([_]bool{ true, false }) |li| {
            try std.testing.expectEqual(Clique.mostrar, T.f(v, ctt, li));
        };
    }
    // Aberta: para a bandeja só onde fechar também iria.
    try std.testing.expectEqual(Clique.para_bandeja, T.f(.aberta, true, true));
    try std.testing.expectEqual(Clique.minimizar, T.f(.aberta, false, true));
    try std.testing.expectEqual(Clique.minimizar, T.f(.aberta, true, false));
    try std.testing.expectEqual(Clique.minimizar, T.f(.aberta, false, false));
}

test "clique duplo no ícone conta uma vez" {
    try std.testing.expect(trayClickCounts(-1, 500));
    try std.testing.expect(trayClickCounts(500, 500));
    try std.testing.expect(trayClickCounts(10_000, 500));
    try std.testing.expect(!trayClickCounts(0, 500));
    try std.testing.expect(!trayClickCounts(499, 500));
}

test "ícone sempre na bandeja: quando criar, tirar e refazer" {
    // Opção ligada, janela aberta: cria se não há ícone; com ele lá, nada.
    try std.testing.expectEqual(Icone.criar, trayIcon(true, false, false, false, false));
    try std.testing.expectEqual(Icone.nada, trayIcon(true, true, false, true, false));
    // O ícone de uma ida à bandeja vira o da opção, sem refazer.
    try std.testing.expectEqual(Icone.nada, trayIcon(true, false, false, true, true));
    // Trocou o idioma: refaz para o menu acompanhar.
    try std.testing.expectEqual(Icone.refazer, trayIcon(true, true, false, true, true));
    // Desligou: tira o ícone da opção; sem ícone, não há o que tirar.
    try std.testing.expectEqual(Icone.tirar, trayIcon(false, true, false, true, false));
    try std.testing.expectEqual(Icone.nada, trayIcon(false, true, false, false, false));
    // Desligada desde sempre: nada (o de hoje: ícone só com a janela escondida).
    try std.testing.expectEqual(Icone.nada, trayIcon(false, false, false, false, false));
    try std.testing.expectEqual(Icone.nada, trayIcon(false, false, false, true, false));
    // Na bandeja nunca mexe, com qualquer combinação.
    for ([_]bool{ true, false }) |a| for ([_]bool{ true, false }) |k| for ([_]bool{ true, false }) |act| {
        try std.testing.expectEqual(Icone.nada, trayIcon(a, k, true, act, true));
    };
}

test "tentar o ícone de novo: espera dobra e para em 5 min" {
    try std.testing.expectEqual(@as(i64, 5_000), trayRetryMs(0));
    try std.testing.expectEqual(@as(i64, 10_000), trayRetryMs(1));
    try std.testing.expectEqual(@as(i64, 160_000), trayRetryMs(5));
    try std.testing.expectEqual(@as(i64, 300_000), trayRetryMs(6));
    try std.testing.expectEqual(@as(i64, 300_000), trayRetryMs(255));
}

test "escondida, só fica a imagem pequena que estava na tela" {
    try std.testing.expect(keepsImageHidden(40 * 40 * 4, 1, 0));
    try std.testing.expect(keepsImageHidden(hidden_keep_bytes, 1, 1000));
    // Grande, animada ou fora da tela.
    try std.testing.expect(!keepsImageHidden(hidden_keep_bytes + 1, 1, 0));
    try std.testing.expect(!keepsImageHidden(1024, 2, 0));
    try std.testing.expect(!keepsImageHidden(1024, 1, 1001));
}

test "lista flutuante: embaixo, em cima se não couber, sempre dentro da janela" {
    const win: Rect = .{ .x = 0, .y = 0, .w = 800, .h = 600 };
    // Cabe embaixo.
    const a = place(.{ .x = 100, .y = 100, .w = 200, .h = 40 }, 200, 150, win);
    try std.testing.expectEqual(@as(f32, 144), a.y);
    try std.testing.expectEqual(@as(f32, 150), a.h);
    // Perto do fim da janela: vira para cima, encostada na caixa.
    const b = place(.{ .x = 100, .y = 500, .w = 200, .h = 40 }, 200, 150, win);
    try std.testing.expectEqual(@as(f32, 150), b.h);
    try std.testing.expectEqual(@as(f32, 500 - 4), b.bottom());
    // Maior que os dois lados: fica no maior, com a altura limitada.
    const c = place(.{ .x = 100, .y = 200, .w = 200, .h = 40 }, 200, 900, win);
    try std.testing.expectEqual(@as(f32, 244), c.y);
    try std.testing.expectEqual(@as(f32, 600 - 244 - 8), c.h);
    try std.testing.expect(c.bottom() <= win.bottom());
    // Na borda direita: entra para dentro.
    const e = place(.{ .x = 750, .y = 10, .w = 40, .h = 20 }, 300, 100, win);
    try std.testing.expectEqual(@as(f32, 800 - 8 - 300), e.x);
    // Janela minúscula: nunca altura negativa.
    const f = place(.{ .x = 0, .y = 0, .w = 40, .h = 40 }, 300, 100, .{ .x = 0, .y = 0, .w = 50, .h = 44 });
    try std.testing.expect(f.h >= 0 and f.w >= 0);
}

test "arquivo da instância" {
    const i = Instance.parse("41234 0123456789abcdef\n").?;
    try std.testing.expectEqual(@as(u16, 41234), i.port);
    try std.testing.expectEqualStrings("0123456789abcdef", i.nonce);
    try std.testing.expect(Instance.parse("") == null);
    try std.testing.expect(Instance.parse("41234") == null);
    try std.testing.expect(Instance.parse("0 0123456789abcdef") == null);
    try std.testing.expect(Instance.parse("99999 0123456789abcdef") == null);
    try std.testing.expect(Instance.parse("41234 curto") == null);
}
