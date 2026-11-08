# Gerador de plugin

Escolha o que o seu plugin vai fazer e baixe um `.lua` pronto para editar. Um plugin é um arquivo só: os comentários do começo são o cabeçalho (nome, descrição, o que ele pede) e o código embaixo deles é o plugin. O gerador só oferece o que a [API de plugins](page:plugins) tem de verdade, preenche a linha `@capabilities` por você e deixa cada chamada onde o app permite.

{{starter}}

## Onde colocar

| Sistema | Pasta |
|---|---|
| Linux | `~/.config/larpercord/plugins/` (ou `$XDG_CONFIG_HOME/larpercord/plugins/`) |
| Windows | `%APPDATA%\larpercord\plugins\` |

Depois abra **Configurações → Plugins** (`Ctrl+,`) e clique em **Recarregar**. O cartão do plugin mostra o nome, o que ele pede e qualquer erro, com `arquivo:linha`. Se ele usa a internet, nada sai antes de você aprovar o host nesse cartão.

Abra o larperCord por um terminal para ver o que o plugin escreve com `print`: o gerador põe uma linha `carregado` quando ele começa.

## O que o gerador confere

- O nome (48 bytes), a descrição (320 bytes) e a versão (16 bytes) cabem no que o app lê. Um texto maior seria cortado.
- Comandos são `/` seguida de até 31 letras, números, `_` ou `-`.
- Atalhos seguem as regras do app: só F1–F24 vão sozinhas, toda outra tecla pede `ctrl`, `alt` ou `super`, e `ctrl` com `a`, `c`, `v`, `x`, `y` ou `z` fica para a digitação.
- Hosts são só nomes, como `api.exemplo.com`: sem `https://`, porta ou endereço IP, nada do Discord, no máximo 8.
- Enviar, escrever na caixa de mensagem, abrir links e abrir o painel só acontecem dentro do seu comando, atalho, entrada de menu ou botão do painel, nunca num evento ou temporizador. O app recusa em qualquer outro lugar.

O arquivo é Lua comum: abra em qualquer editor e mude a partir dali. A [página da API](page:plugins) tem todas as funções, e o [diretório de plugins](page:plugin-directory) lista os plugins que vêm com o app, que são bons exemplos para ler.
