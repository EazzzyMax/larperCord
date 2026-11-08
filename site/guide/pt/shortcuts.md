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

## Variáveis de ambiente

| Variável | O que faz |
|---|---|
| `LARPER_TOKEN` | o token da conta (veja [Conectar a sua conta](page:account)) |
| `LARPER_RENDERER` | escolhe o backend de renderização do SDL: `opengl`, `vulkan`, `gpu` ou `software` |
| `LARPER_HIDDEN` | abre com a janela oculta. O app não desenha nada enquanto ela está oculta, então a memória mede bem menos do que com uma janela de verdade |
| `LARPER_BENCH` | redesenha sem parar, para medir o custo de um quadro |
| `LARPER_VOICE_DEBUG` | imprime o que acontece numa call (opcodes, códigos de fechamento, DAVE). Nunca imprime tokens nem chaves |
| `LARPER_DEBUG_MEDIA` | registra por que uma imagem não carregou |
| `LARPER_NO_FFMPEG` | finge que o FFmpeg não está instalado |
| `LARPER_EGL_ALL` | desliga o truque que pula drivers EGL desnecessários |
| `LARPER_SCENE` | monta uma cena para as capturas de tela da documentação |
| `LARPER_RECORD`, `LARPER_RECORD_FRAMES` | grava a tela de login como quadros numa pasta |
| `LARPER_FLOOD` | manda N mudanças de presença por segundo no modo demonstração (teste de carga) |

`XDG_CONFIG_HOME` e `XDG_CACHE_HOME` são respeitadas, e ajudam a rodar com uma configuração limpa.
