//! Os atalhos de teclado do app, numa lista só. Configurações → Atalhos de
//! teclado desenha a partir dela, e tools/gen_site.py lê este arquivo para
//! gerar a página de atalhos do site: as duas nunca ficam diferentes.
//!
//! Quem trata cada tecla continua no lugar dela (ui/root.zig, ui/vim.zig, a
//! caixa de texto em ui/comp_messages.zig, a lista de sugestões em
//! ui/autocomplete.zig). Mudou uma tecla lá, mude a linha aqui.
//!
//! O gerador do site lê com expressão regular: uma entrada por linha, no
//! formato `.{ .campo = "texto", ... },`, e os grupos na ordem de `grupos`.
//! As teclas levam `+` entre as que vão juntas e ` / ` entre alternativas.

pub const Grupo = enum { geral, janela, abas, voz, caixa, vim };

pub const Atalho = struct {
    grupo: Grupo,
    pt: []const u8,
    en: []const u8,
    teclas: []const u8,
    /// As teclas em português, quando o nome muda ("Ctrl+Clique").
    teclas_pt: ?[]const u8 = null,
};

pub const NomeGrupo = struct { id: Grupo, pt: []const u8, en: []const u8 };

pub const grupos = [_]NomeGrupo{
    .{ .id = .geral, .pt = "Geral", .en = "General" },
    .{ .id = .janela, .pt = "Janela e tema", .en = "Window and theme" },
    .{ .id = .abas, .pt = "Abas", .en = "Tabs" },
    .{ .id = .voz, .pt = "Voz", .en = "Voice" },
    .{ .id = .caixa, .pt = "Caixa de texto", .en = "Message box" },
    .{ .id = .vim, .pt = "Navegação vim", .en = "Vim navigation" },
};

pub const lista = [_]Atalho{
    .{ .grupo = .geral, .pt = "Paleta de comandos", .en = "Command palette", .teclas = "Ctrl+K" },
    .{ .grupo = .geral, .pt = "Paleta com as ações primeiro", .en = "Palette, actions first", .teclas = "Ctrl+Shift+P" },
    .{ .grupo = .geral, .pt = "Buscar mensagens", .en = "Search messages", .teclas = "Ctrl+F" },
    .{ .grupo = .geral, .pt = "Configurações", .en = "Settings", .teclas = "Ctrl+," },
    .{ .grupo = .geral, .pt = "Caixa de entrada", .en = "Inbox", .teclas = "Ctrl+I" },
    .{ .grupo = .geral, .pt = "Mensagens salvas", .en = "Saved messages", .teclas = "Ctrl+Shift+S" },
    .{ .grupo = .geral, .pt = "Copiar o texto selecionado nas mensagens", .en = "Copy the text selected in messages", .teclas = "Ctrl+C" },
    .{ .grupo = .janela, .pt = "Próximo tema", .en = "Next theme", .teclas = "F2 / Ctrl+T" },
    .{ .grupo = .janela, .pt = "Tema anterior", .en = "Previous theme", .teclas = "Shift+F2 / Ctrl+Shift+T" },
    .{ .grupo = .janela, .pt = "Aumentar ou diminuir a interface", .en = "Make the interface bigger or smaller", .teclas = "Ctrl + / Ctrl -" },
    .{ .grupo = .janela, .pt = "Interface no tamanho normal", .en = "Interface at normal size", .teclas = "Ctrl 0" },
    .{ .grupo = .janela, .pt = "Tela cheia", .en = "Fullscreen", .teclas = "F11 / Alt+Enter" },
    .{ .grupo = .abas, .pt = "Próxima aba", .en = "Next tab", .teclas = "Ctrl+Tab" },
    .{ .grupo = .abas, .pt = "Aba anterior", .en = "Previous tab", .teclas = "Ctrl+Shift+Tab" },
    .{ .grupo = .abas, .pt = "Ir para a aba N", .en = "Go to tab N", .teclas = "Alt+1…9" },
    .{ .grupo = .abas, .pt = "Fechar aba", .en = "Close tab", .teclas = "Ctrl+W" },
    .{ .grupo = .abas, .pt = "Abrir canal em nova aba", .en = "Open channel in a new tab", .teclas = "Ctrl+Click", .teclas_pt = "Ctrl+Clique" },
    .{ .grupo = .abas, .pt = "Fechar aba com o mouse", .en = "Close tab with the mouse", .teclas = "Middle click", .teclas_pt = "Botão do meio" },
    .{ .grupo = .voz, .pt = "Mutar ou desmutar o microfone", .en = "Mute or unmute", .teclas = "Ctrl+Shift+M" },
    .{ .grupo = .voz, .pt = "Ensurdecer ou voltar a ouvir", .en = "Deafen or undeafen", .teclas = "Ctrl+Shift+D" },
    .{ .grupo = .caixa, .pt = "Nova linha", .en = "New line", .teclas = "Shift+Enter / Ctrl+Enter" },
    .{ .grupo = .caixa, .pt = "Editar a última mensagem (caixa vazia)", .en = "Edit your last message (empty box)", .teclas = "↑" },
    .{ .grupo = .caixa, .pt = "Cancelar resposta ou edição", .en = "Cancel a reply or edit", .teclas = "Esc" },
    .{ .grupo = .caixa, .pt = "Escolher na lista de @, #, :ab ou /", .en = "Pick from the @, #, :ab or / list", .teclas = "Tab / Enter" },
    .{ .grupo = .caixa, .pt = "Colar uma imagem copiada", .en = "Paste a copied image", .teclas = "Ctrl+V" },
    .{ .grupo = .vim, .pt = "Rolar para baixo / para cima", .en = "Scroll down / up", .teclas = "j / k" },
    .{ .grupo = .vim, .pt = "Topo / fim da conversa", .en = "Top / bottom of the conversation", .teclas = "gg / G" },
    .{ .grupo = .vim, .pt = "Meia página para baixo / para cima", .en = "Half page down / up", .teclas = "Ctrl+d / Ctrl+u" },
    .{ .grupo = .vim, .pt = "Próximo / anterior canal", .en = "Next / previous channel", .teclas = "J / K" },
    .{ .grupo = .vim, .pt = "Voltar para a caixa de texto", .en = "Back to the text box", .teclas = "i / Enter" },
    .{ .grupo = .vim, .pt = "Sair da caixa de texto", .en = "Leave the text box", .teclas = "Esc" },
    .{ .grupo = .vim, .pt = "Buscar (paleta)", .en = "Search (palette)", .teclas = "/" },
};

pub fn nome(g: Grupo, en: bool) []const u8 {
    for (grupos) |n| if (n.id == g) return if (en) n.en else n.pt;
    unreachable;
}

const std = @import("std");

test "atalhos: cada grupo aparece uma vez, na ordem, e toda linha tem texto" {
    var i: usize = 0;
    for (grupos) |g| {
        // Os de um grupo ficam juntos: a página e o site põem um título por grupo.
        while (i < lista.len and lista[i].grupo == g.id) : (i += 1) {
            const a = lista[i];
            try std.testing.expect(a.pt.len > 0 and a.en.len > 0 and a.teclas.len > 0);
            if (a.teclas_pt) |k| try std.testing.expect(k.len > 0);
        }
    }
    try std.testing.expectEqual(lista.len, i);
    try std.testing.expectEqualStrings("Voice", nome(.voz, true));
}
