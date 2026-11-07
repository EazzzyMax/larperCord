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
- Fechar para a bandeja usa a barra de menus. O Dock pode reabrir a janela escondida.
- Tokens salvos usam o Chaveiro de Início de Sessão, com a alternativa existente
  de arquivo privado caso não seja possível gravar no Chaveiro.
- As configurações ficam em `~/Library/Application Support/larpercord`; o cache,
  em `~/Library/Caches/larpercord`. `XDG_CONFIG_HOME` e `XDG_CACHE_HOME` substituem
  esses caminhos.
- Mudanças de tema usam kqueue, sem sondagem. A estatística de memória mostra RSS.
- As atualizações são manuais. O atualizador de Linux/Windows fica desligado no macOS.
- O FFmpeg opcional não vem no bundle; sem bibliotecas compatíveis, o vídeo abre
  no navegador. Compartilhar tela e câmera não foram adicionados.

## Testes

```sh
zig build test --summary all
SDL_VIDEO_DRIVER=cocoa LARPER_RENDERER=metal QA_SLOW=2 tools/qa.sh
```

`tools/qa.sh` compila em debug com checagens de segurança e roda as baterias geral
e extra, a persistência dos plugins entre processos, os dois modos do login e
todos os 11 temas no escuro e no claro. Salva prints e um registro por execução
em `qa-out/`. Use `ZIG=/caminho/para/zig` se necessário. O macOS usa a mesma matriz
do Linux; o roteiro de LSP específico do Linux fica de fora no macOS.

O QA abre janelas nativas e usa dados falsos do Discord. Mantenha o idioma padrão,
português: os alvos dos testes incluem rótulos traduzidos. A demonstração sem
conta abre com `--demo --no-live`. Os testes automáticos da interface não
exercitam chamadas reais nem os pedidos de permissão do macOS.
