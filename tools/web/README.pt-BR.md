# Demonstração no navegador (protótipo)

*[Read in English](README.md)*

O objetivo: a interface de verdade do larperCord rodando o modo demonstração (dados do
gateway falso, sem rede, sem conta) em WebAssembly no site, carregada só quando quem
visita clica em "Começar a demonstração".

**Estado: compila, ainda não liga.** O app inteiro (Zig, Dear ImGui, as ligações do
FreeType, FriBidi, Lua) compila para `wasm32-emscripten`. O RNNoise e a conexão de voz
ficam de fora, porque a página não tem voz (`sys.web` em `src/core/ruido.zig` e
`src/net/discord.zig`). A ligação final com o
`emcc` e um teste num navegador de verdade ainda não aconteceram: o SDK do Emscripten não
foi instalado na máquina do build. Nada daqui muda o build nativo.

## Como as partes se encaixam

| Parte | Onde |
|---|---|
| Ponto de entrada (só a demonstração, laço do navegador) | `src/web_main.zig` |
| Uma volta do laço por quadro da página, sem nunca esperar | `App.webFrame` em `src/app.zig` |
| Gateway falso sem a thread dele | `Gateway.pump` em `src/net/fake_gateway.zig` |
| Imagens decodificadas na thread da página | `Cache.loadInline` em `src/ui/images.zig` |
| Fontes que vão com a página | `resolveWeb` em `src/ui/fonts.zig`, geradas por `tools/web/fonts.py` |
| curl, Opus, WebP, fontconfig e DAVE respondendo "não dá" | `src/platform/web/stubs.c` |
| Passos do build | `addWeb` em `build.zig` |
| Página | `site/try.html`, gerada pelo `tools/gen_site.py` só quando `docs/try/` tem um build |

`sys.web` (em `src/platform/sys.zig`) só é verdadeiro quando a raiz do build declara
`larper_web`, e só o `src/web_main.zig` declara. Todo caminho exclusivo do navegador
fica atrás dele, então o binário do computador compila igual a antes. Duas mudanças
pequenas de tipo deixam o wasm de 32 bits contente sem mexer no comportamento em 64 bits:
`sys.Atomic` (o mesmo `std.atomic.Value` em todo lugar, menos no wasm32, onde o Zig não
tem atômicos de 64 bits e a página não tem threads) e alguns casts entre `usize` e `u64`.

Escolhas de projeto:

- **Sem threads.** As threads do Emscripten precisam de `SharedArrayBuffer`, que precisa
  dos cabeçalhos COOP/COEP, e o GitHub Pages não manda esses cabeçalhos. Uma thread só
  também evita a thread principal do navegador travar esperando uma trava. O gateway
  falso, a decodificação de imagens e o relógio rodam a partir do quadro.
- **Nenhuma rede.** O curl é um stub, então nada sai da aba por acidente.
- **Laço do navegador.** `emscripten_set_main_loop(…, 0, …)` chama `App.webFrame` uma vez
  por `requestAnimationFrame`. Ele só desenha quando algo mudou, como o laço nativo, e a
  aba parada continua barata.
- **Fontes.** Inter (5 pesos), JetBrains Mono (2), os símbolos da DejaVu Sans e os emojis
  que a demonstração usa, recortados para o latim: cerca de 555 KB sem compressão. CJK,
  árabe e hebraico ficam só no app do computador.

## Compilando

```sh
# 1. SDK do Emscripten, numa versão fixa (6.0.13 é a usada na conferência do build)
git clone https://github.com/emscripten-core/emsdk.git && cd emsdk
./emsdk install 6.0.13 && ./emsdk activate 6.0.13 && cd ..

# 2. Fontes da página (precisa do fontTools e das fontes instaladas neste sistema)
python3 tools/web/fonts.py              # -> zig-out/web-fonts/

# 3. Compilar e ligar (roda o embuilder antes, para as portas de SDL3, FreeType e zlib)
source emsdk/emsdk_env.sh               # o emcc acha o node, o python e a configuração dele
zig build web -Demsdk=$PWD/emsdk        # -> zig-out/web/larpercord.{js,wasm,data}

# 4. Publicar no site: a página e o link da inicial aparecem sozinhos
cp zig-out/web/larpercord.{js,wasm,data} docs/try/
python3 tools/gen_site.py
```

Outros passos:

- `zig build web-lib -Dweb-sysroot=<sysroot do emscripten>` compila tudo em
  `zig-out/web/liblarpercord-web.a` e `liblarpercord-web-c.a`, sem ligar. Só precisa dos
  cabeçalhos do Emscripten, não das ferramentas.
- `zig build web-sim -- --shot saida.png` roda o mesmo caminho do navegador (sem threads,
  fontes da página, laço por quadro) numa janela comum do computador, para conferir sem
  navegador. `--fonts=<pasta>` usa outras fontes. Rode com o ambiente de sempre do QA
  (`env -u LARPER_TOKEN SDL_VIDEO_DRIVER=offscreen` e `XDG_*` dentro do worktree).

## O que foi conferido

- `zig build web-lib` gera os dois arquivos para `wasm32-emscripten` com os cabeçalhos do
  Emscripten 6.0.13 (e os de SDL 3.4, FreeType 2.14 e zlib ao lado).
- Os únicos símbolos indefinidos que sobram são da libc/POSIX, do compiler-rt, das ajudas
  de setjmp do Emscripten, do SDL3, do FreeType e da zlib, que o `emcc` fornece com
  `-sUSE_SDL=3 -sUSE_FREETYPE=1 -sUSE_ZLIB=1`. Tudo o que vinha de curl, Opus, WebP,
  fontconfig e DAVE está coberto pelos stubs.
- O Zig gera objetos independentes de posição para o Emscripten (ele recusa `-fno-PIC`
  lá). Uma ligação estática com o `wasm-ld` resolve `__memory_base` e `__table_base` por
  dentro, sem sobrar importação.
- `zig build web-sim -- --shot saida.png` abre a demonstração pelo caminho do navegador
  (`App.webFrame`, `Gateway.pump`, `Cache.loadInline`, as fontes recortadas pelo
  `tools/web/fonts.py`) e desenha a demonstração inteira: servidores, canais, membros,
  imagens geradas, prévias de link, reações e emojis.
- `zig build test` e o build nativo de debug continuam passando.

## O que falta, em ordem

1. **Ligar com o emcc.** Deve vir uma rodada curta de símbolos ou opções faltando. O mais
   provável: ajudas do compiler-rt que o Zig gera (se faltar alguma, ligue
   `bundle_compiler_rt = true` no arquivo do Zig), o `-sSUPPORT_LONGJMP=emscripten`
   batendo com o `-mllvm -enable-emscripten-sjlj` do Lua e o `callMain` achando a
   entrada do Zig (o Zig exporta `__main_argc_argv`, o nome do `main(argc, argv)` no wasm).
2. **Primeira execução num navegador.** O que observar: tamanho e densidade de pixels do
   canvas (`larper_web_resize` é chamado por um `ResizeObserver`), foco do teclado (o SDL
   escuta só o `#canvas`), entrada de texto (o IME do SDL no navegador é limitado, então
   confira letras com acento), área de transferência (assíncrona nos navegadores), o
   relógio de 2 s (`SDL_AddTimer` usa `emscripten_set_timeout` sem threads) e o arquivo
   `.data` com as fontes em `/fonts`.
3. **Tamanho.** Medir o tamanho comprimido (o `gen_site.py` mostra na página). Alavancas:
   `-Oz` com `wasm-opt` (já ligado), `IMGUI_DISABLE_DEBUG_TOOLS`, tirar o Lua do build
   do navegador atrás de `sys.web` e um conjunto menor de emojis. O RNNoise e a conexão
   de voz já saíram: o wasm foi de 5,77 MB para 4,30 MB (de 3,00 MB para 1,79 MB com
   gzip -9).
4. **Conferir o comportamento** no navegador: toda página de configurações abre; trocar
   de tema e de claro/escuro; mandar mensagem, reações, threads, o seletor de GIF (tudo com
   dados falsos); uma chamada aparece sem som; nada tenta abrir seletor de arquivo ou
   processo.
5. **Acabamento:** barra de carregamento a partir do `setStatus` do Emscripten, um aviso
   de layout no celular e o tema atual da página (já vai como `--theme`).

## Bloqueios desta rodada

- **O SDK do Emscripten não pôde ser instalado aqui.** Rodar o instalador oficial
  `emsdk` foi recusado pela política de permissões da máquina (ele baixa e executa
  código). Sem o `emcc` não há ligação final nem teste no navegador. A conferência de
  compilação acima usou só os arquivos de cabeçalho do Emscripten (`system/include` e os
  cabeçalhos da musl e da libc++ da tag 6.0.13), copiados num layout de sysroot, sem
  executar nada do Emscripten.
- **O translate-c do Zig cai no `/usr/include`** nos alvos para os quais ele não tem libc.
  Cabeçalho que falta no sysroot do Emscripten vem calado da glibc. Por isso o `c.h` pula
  o `sys/inotify.h` com `__EMSCRIPTEN__`. Cuidado ao somar includes.
- **O Zig não tem atômicos de 64 bits no wasm32**, nem com `+atomics`: daí o `sys.Atomic`.
- **O `struct timespec` da musl tem enchimento em campo de bits**, então o translate-c
  transforma o `struct stat` num tipo opaco. O `sys.ownerOnly` não chama `stat` na web.
