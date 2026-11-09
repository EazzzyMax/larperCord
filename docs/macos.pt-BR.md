# macOS (experimental)

[English](macos.md) · **Português**

Build nativo para Apple Silicon com SDL3, Metal e Dear ImGui. Testado no M1 com
macOS 15.3.2. O alvo ARM64 básico também roda em CPUs da série M mais novas,
mas essas máquinas não foram testadas individualmente. Macs Intel não estão cobertos.

## Compilar e empacotar

Instale Xcode ou suas Command Line Tools, Zig 0.17 e as dependências do Homebrew:

```sh
brew install sdl3 curl opus webp freetype fontconfig openssl@3 pkgconf
sh tools/macos_build.sh -j4
python3 tools/macos_bundle.py /caminho/para/LarperCord.app
```

Use `ZIG=/caminho/para/zig` se o Zig não estiver no `PATH`. O script escolhe o
curl do Homebrew com suporte a WebSocket e o SDK do macOS. O bundle de destino
não pode existir ainda. O empacotamento precisa de Python 3.9 ou mais novo.

O bundle inclui suas bibliotecas não pertencentes ao sistema, a configuração
do fontconfig e as licenças das dependências; não precisa de Homebrew para rodar.
A versão mínima do macOS é 15.0 ou o maior mínimo exigido pelas bibliotecas,
o que for mais novo. O empacotamento verifica que cada Mach-O é ARM64 e troca
os caminhos das bibliotecas para permitir mover o app. A assinatura é ad-hoc,
sem Developer ID nem notarização.

## Comportamento na plataforma

- Os atalhos principais usam Command. Trocar abas e navegar no modo vim usam
  Control físico; os atalhos dos plugins mantêm seus modificadores Ctrl/Super literais.
- Fechar para a bandeja usa a barra de menus. Clicar no ícone da barra de menus
  abre o menu dele (Abrir, Sair); o clique esquerdo que mostra ou esconde a janela
  no Linux e no Windows não existe aqui. O Dock pode reabrir a janela escondida.
- Tokens salvos usam o Chaveiro de Início de Sessão, com a alternativa existente
  de arquivo privado caso não seja possível gravar no Chaveiro.
- As configurações ficam em `~/Library/Application Support/larpercord`; o cache,
  em `~/Library/Caches/larpercord`. `XDG_CONFIG_HOME` e `XDG_CACHE_HOME` substituem
  esses caminhos.
- As fontes vêm do fontconfig, como no Linux, lendo as pastas de fontes do macOS
  (o bundle traz o próprio `fonts.conf`). Isso inclui as fontes reserva de outras
  escritas: japonês, chinês e coreano, árabe e hebraico (da direita para a
  esquerda, moldados pelo FriBidi que vem junto) e qualquer letra que falte na
  fonte do tema. A interface em japonês usa as mesmas fontes. Se o fontconfig não
  achar nada, o app abre direto San Francisco, Times New Roman e Apple Color Emoji.
  As fontes reserva por escrita e o texto da direita para a esquerda ainda não
  foram testados num Mac.
- Mudanças de tema usam kqueue, sem sondagem. A estatística de memória mostra RSS.
- O Rich Presence para jogos e apps escuta em `$TMPDIR/discord-ipc-N`, onde o
  cliente oficial também fica. Ainda não testado num Mac.
- As atualizações são manuais. O atualizador de Linux/Windows fica desligado no
  macOS, e Configurações → Atualizações só oferece o botão de reiniciar.
- A demonstração e o QA nunca abrem uma sessão de verdade, nunca leem o Chaveiro e
  nunca pedem permissão de notificação.
- O FFmpeg opcional não vem no bundle. O vídeo toca dentro do app com as
  bibliotecas do FFmpeg 7, 8 ou 9 da pasta escolhida em Configurações → Chat →
  Vídeos (no Homebrew, `/opt/homebrew/lib`); sem elas, abre no navegador. Ainda
  não testado num Mac. Compartilhar tela e câmera não foram adicionados.

## Testes

```sh
zig build test --summary all
SDL_VIDEO_DRIVER=cocoa LARPER_RENDERER=metal QA_SLOW=2 tools/qa.sh
```

`tools/qa.sh` compila em debug com checagens de segurança e roda a bateria geral,
as baterias de cada recurso (extras, envio, limites, social, mídia, Rich Presence,
moderação, entrada, interações, outras escritas, sem fontes, mixer da call), a
persistência dos plugins entre processos, os dois modos do login e todos os 11
temas no escuro e no claro. Salva prints e um registro por execução em `qa-out/`.
Use `ZIG=/caminho/para/zig` se necessário. O macOS usa a mesma matriz do Linux; o
roteiro de LSP específico do Linux fica de fora no macOS. A bateria sem fontes
supõe que o fontconfig é o único caminho até as fontes, o que não vale no macOS
(veja a reserva acima).

O QA abre janelas nativas e usa dados falsos do Discord. Mantenha o idioma padrão,
português: os alvos dos testes incluem rótulos traduzidos. A demonstração sem
conta abre com `--demo --no-live`. Os testes automáticos da interface não
exercitam chamadas reais nem os pedidos de permissão do macOS.

## CI

Um job experimental nas máquinas Apple Silicon do GitHub (`macos` em
`.github/workflows/ci.yml`) instala as dependências do Homebrew acima, compila o
app, roda os testes unitários e a bateria geral do QA numa janela nativa (a
máquina tem tela; `LARPER_RENDERER=software`, porque a máquina virtual não tem
Metal; o driver offscreen do SDL não abre janela no macOS) e publica o artefato
`larpercord-macos-arm64`: o `.app` dentro de um `.tar.gz`. Enquanto o port for
experimental, ele não segura os outros jobs. O bundle só tem assinatura ad-hoc,
então o macOS pode recusar abrir uma cópia baixada; nesse caso, rode
`xattr -dr com.apple.quarantine LarperCord.app` uma vez.
