# Atalhos e linha de comando

As mesmas teclas no Linux e no Windows. Não existe versão para macOS, então é sempre `Ctrl`, nunca `Cmd`. Estas tabelas saem de `src/ui/atalhos.zig`, a lista que o próprio app mostra em **Configurações → Atalhos de teclado**, então esta página e o app não ficam diferentes.

## Teclado

{{keys}}

### Mouse e outras teclas

- **Aperte para falar:** a tecla ou o botão do mouse que você escolher em Configurações → Voz. Só funciona com a janela em foco.
- O **botão direito** funciona em mensagens, usuários, canais e servidores.
- **Esc** fecha o que estiver por cima: um menu, o visualizador de imagem, a paleta, as configurações.
- **Zoom:** `Ctrl` com a tecla `=`/`+` ou o `+`, `-` e `0` do teclado numérico. Vai de 75% a 200% e fica salvo.
- **Plugins** podem somar atalhos próprios com `larper.keybind`; o cartão de cada plugin em Configurações → Plugins lista os dele. Os atalhos do próprio app não usam a tecla do Windows (Super), então ela fica livre para eles.
- Se um atalho não faz nada, o seu ambiente de trabalho ou gerenciador de janelas pode estar pegando ele antes.

## Navegação estilo vim

Vem desligada. Ligue em Configurações → Atalhos de teclado. As teclas funcionam enquanto a caixa de texto não está em foco, e o `Esc` sai da caixa mantendo o que você digitou.

{{keys:vim}}

## Linha de comando

```bash
larpercord [options]
```

| Opção | O que faz |
|---|---|
| `--theme NAME` | começa com esse tema |
| `--list-themes` | lista os temas embutidos e sai |
| `--mode MODE` | `claro` (ou `light`) ou `escuro`, ignorando as suas configurações |
| `--lang LANG` | `pt` ou `en`, ignorando as suas configurações |
| `--demo` | usa os dados de demonstração mesmo com token |
| `--login` | mostra a tela de login, ignorando o token salvo |
| `--settings` | abre direto nas configurações |
| `--no-live` | desliga as mensagens automáticas do modo demonstração |
| `--shot FILE.png` | salva uma captura de tela quando a tela se acalma e sai |
| `--stats` | mostra o tempo até o primeiro quadro |
| `--qa` | roda o teste automático da interface, com capturas de tela em `qa-out/` |
| `--voice-test GUILD CHANNEL` | entra num canal de voz por 25 s, sempre mudo (precisa de `LARPER_TOKEN`) |
| `--help` | mostra o texto de uso |
| `--version` | mostra a versão e sai |

No Windows o programa é o `larpercord.exe`, e ele não fica no `PATH`. No PowerShell, chame pelo caminho completo (é onde o `install.ps1` instala; se você descompactou o zip, use essa pasta), ou ponha as opções no fim do **Destino** de um atalho:

```powershell
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" --theme vidro
```

A versão para Windows não tem console, então as opções que só imprimem texto (`--help`, `--list-themes`, `--stats`, `--version`) não mostram nada no terminal. Para ler esse texto, mande para um arquivo:

```powershell
Start-Process "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" -ArgumentList '--list-themes' -NoNewWindow -Wait -RedirectStandardError saida.txt; Get-Content saida.txt
```

O `--version` escreve na saída padrão, então para ele use `-RedirectStandardOutput` no lugar de `-RedirectStandardError`.

Os temas embutidos também aparecem em Configurações → Aparência.

Nos dois sistemas, se o larperCord já estiver aberto, mesmo só na bandeja, abrir de novo só traz aquela janela de volta e ignora as outras opções. Encerre antes (**Sair** no menu do ícone da bandeja). `--demo`, `--shot`, `--list-themes`, `--help`, `--version` e `--voice-test` funcionam de qualquer jeito.

## Variáveis de ambiente

Defina para uma execução, no terminal de onde você abre o app:

```bash
LARPER_RENDERER=software larpercord
```

```powershell
# Windows, PowerShell: vale até você fechar esta janela
$env:LARPER_RENDERER = 'software'
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe"
```

No `cmd`, é `set LARPER_RENDERER=software` antes de rodar o `.exe`. As variáveis só valem quando o app abre: se ele já estiver aberto, mesmo só na bandeja, encerre antes, senão abrir de novo só traz de volta a janela aberta.

| Variável | O que faz |
|---|---|
| `LARPER_TOKEN` | o token da conta (veja [Conectar a sua conta](page:account)) |
| `LARPER_RENDERER` | escolhe o backend de renderização do SDL: `opengl`, `vulkan`, `gpu` ou `software`, e no Windows também `direct3d11` ou `direct3d12` |
| `LARPER_HIDDEN` | abre com a janela oculta. O app não desenha nada enquanto ela está oculta, então a memória mede bem menos do que com uma janela de verdade |
| `LARPER_BENCH` | redesenha sem parar, para medir o custo de um quadro |
| `LARPER_VOICE_DEBUG` | imprime no terminal o que acontece numa call (opcodes, códigos de fechamento, DAVE). Nunca imprime tokens nem chaves. No Windows não há terminal: ligue Configurações → Avançado → Salvar registro de depuração, que grava o mesmo |
| `LARPER_DEBUG_MEDIA` | registra por que uma imagem não carregou. No Windows, use o registro de depuração, como acima |
| `LARPER_NO_FFMPEG` | finge que o FFmpeg não está instalado |
| `LARPER_EGL_ALL` | só no Linux: desliga o truque que pula drivers EGL desnecessários |
| `LARPER_SCENE` | monta uma cena para as capturas de tela da documentação |
| `LARPER_RECORD`, `LARPER_RECORD_FRAMES` | grava a tela de login como quadros numa pasta |
| `LARPER_FLOOD` | manda N mudanças de presença por segundo no modo demonstração (teste de carga) |

`XDG_CONFIG_HOME` e `XDG_CACHE_HOME` são respeitadas nos dois sistemas (no Windows elas tomam o lugar de `%APPDATA%` e `%LOCALAPPDATA%`), e ajudam a rodar com uma configuração limpa.
