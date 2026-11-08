# Demonstração no navegador

*[Read in English](README.md)*

A interface de verdade do larperCord rodando o modo demonstração (dados do gateway
falso, sem rede, sem conta) em WebAssembly no site. Ela só carrega quando quem visita
clica em "Começar a demonstração" na página
[Experimente](https://rshacudevidro.github.io/larperCord/pt/try/).

**Estado: liga e roda.** O `zig build web` liga com o Emscripten 6.0.13 e grava
`larpercord.js`, `.wasm` e `.data`. A demonstração abre no navegador sem erro no console,
e os únicos pedidos que ela faz são os dos próprios arquivos. O GitHub Actions compila a
demonstração a cada push na `main` que mexe no app ou no site
(`.github/workflows/pages.yml`), então ninguém precisa do Emscripten para publicar o site.
Nada daqui muda o build nativo: o binário do computador sai igual, byte a byte.

## Como as partes se encaixam

| Parte | Onde |
|---|---|
| Ponto de entrada (só a demonstração, laço do navegador) | `src/web_main.zig` |
| Uma volta do laço por quadro da página, sem nunca esperar | `App.webFrame` em `src/app.zig` |
| Gateway falso sem a thread dele | `Gateway.pump` em `src/net/fake_gateway.zig` |
| Imagens decodificadas na thread da página | `Cache.loadInline` em `src/ui/images.zig` |
| Plugins rodando dentro do laço do quadro, com as mesmas filas, limites e sandbox | `runtime.inline_mode` e `Worker.pump` em `src/plugins/runtime.zig` |
| Fontes que vão com a página | `resolveWeb` em `src/ui/fonts.zig`, geradas por `tools/web/fonts.py` |
| curl, Opus, WebP, fontconfig, DAVE, as funções de processo e de seletor de arquivo do SDL e os sockets respondendo "não dá" | `src/platform/web/stubs.c` |
| FreeType com PNG, para os emojis coloridos | `tools/web/freetype_png.py` (uma porta do Emscripten) |
| Passos do build | `addWeb` em `build.zig` |
| Página | `site/try.html`, gerada pelo `tools/gen_site.py` só quando `docs/try/` tem um build inteiro |

`sys.web` (em `src/platform/sys.zig`) só é verdadeiro quando a raiz do build declara
`larper_web`, e só o `src/web_main.zig` declara. Todo caminho exclusivo do navegador
fica atrás dele, então o binário do computador compila igual a antes. O RNNoise e a
conexão de voz ficam fora do build do navegador, porque a página não tem voz. Duas
mudanças pequenas de tipo deixam o wasm de 32 bits contente sem mexer no comportamento em
64 bits: `sys.Atomic` (o mesmo `std.atomic.Value` em todo lugar, menos no wasm32, onde o
Zig não tem atômicos de 64 bits e a página não tem threads) e alguns casts entre `usize`
e `u64`.

Escolhas de projeto:

- **Sem threads.** As threads do Emscripten precisam de `SharedArrayBuffer`, que precisa
  dos cabeçalhos COOP/COEP, e o GitHub Pages não manda esses cabeçalhos. Uma thread só
  também evita a thread principal do navegador travar esperando uma trava. O gateway
  falso, a decodificação de imagens, os plugins e o relógio rodam a partir do quadro. O
  `gen_site.py` recusa um `.wasm` que use memória compartilhada.
- **Nenhuma rede.** O curl é um stub, e `socket()` e `socketpair()` falham, porque senão o
  Emscripten transformaria um `connect()` num WebSocket. Nada sai da aba por acidente.
- **Laço do navegador.** `emscripten_set_main_loop(…, 0, …)` chama `App.webFrame` uma vez
  por `requestAnimationFrame`. Ele só desenha quando algo mudou, como o laço nativo, e a
  aba parada continua barata.
- **Fontes.** Inter (5 pesos), JetBrains Mono (2), DejaVu Sans para os símbolos que a
  Inter e a JetBrains Mono não têm, e os emojis usados em qualquer lugar de `src/` e dos
  plugins que vêm com o app, recortados para o latim: cerca de 640 KB sem compressão.
  Japonês, chinês, coreano, árabe e hebraico ficam só no app do computador.
- **Configurações.** A página passa `--lang` e `--mode`, mas eles só dão o valor inicial:
  Configurações → Idioma e Claro/Escuro continuam funcionando. A barra de status mostra a
  memória do wasm no lugar da RAM do processo.

## Compilando na sua máquina

Precisa do Zig 0.17, do **Emscripten 6.0.13** (a versão com que o build é conferido), do
Python 3 com o fontTools e das fontes que a página pega do seu sistema: Inter, JetBrains
Mono, DejaVu Sans e Noto Color Emoji. Os cabeçalhos de curl, Opus, WebP e fontconfig vêm
de `/usr/include` (só os tipos são usados; quem responde são os stubs).

**Com o emsdk** (qualquer distro):

```sh
git clone https://github.com/emscripten-core/emsdk.git && cd emsdk
./emsdk install 6.0.13 && ./emsdk activate 6.0.13 && cd ..
source emsdk/emsdk_env.sh               # o emcc acha o node, o python e a configuração dele

python3 tools/web/fonts.py              # -> zig-out/web-fonts/
zig build web -Demsdk=$PWD/emsdk        # -> zig-out/web/larpercord.{js,wasm,data}
```

**Com um pacote do sistema**, como o `emscripten` do Arch: o emcc fica em outro lugar,
então passe a pasta dele com `-Demscripten`. O cache do próprio pacote é só de leitura,
então aponte o `EM_CACHE` para uma pasta em que você pode gravar e passe o sysroot de
dentro dela:

```sh
sudo pacman -S emscripten python-fonttools inter-font ttf-jetbrains-mono ttf-dejavu noto-fonts-emoji
export PATH="$PATH:/usr/lib/emscripten"
export EM_CACHE="$HOME/.cache/emscripten"

python3 tools/web/fonts.py
zig build web \
  -Demscripten="$(dirname "$(command -v emcc)")" \
  -Dweb-sysroot="$(em-config CACHE)/sysroot"
```

O primeiro `zig build web` roda o `embuilder` para o sysroot e as portas de SDL3, zlib,
libpng e FreeType, o que leva alguns minutos; os builds seguintes aproveitam o cache. Um
build com o cache vazio gera o mesmo `.wasm`, byte a byte.

Para ver no site, copie os três arquivos e gere o site de novo:

```sh
mkdir -p docs/try && cp zig-out/web/larpercord.{js,wasm,data} docs/try/
python3 tools/gen_site.py               # gera try/, pt/try/ e o botão da página inicial
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs
```

Depois abra `http://127.0.0.1:8000/try/`. `docs/try/` está no `.gitignore`: o build nunca
entra no repositório.

Opções:

| Opção | |
|---|---|
| `-Demscripten=PASTA` | a pasta com o `emcc` e o `embuilder` |
| `-Demsdk=PASTA` | a pasta do emsdk (usa `PASTA/upstream/emscripten`) |
| `-Dweb-sysroot=PASTA` | o sysroot do Emscripten (padrão: `cache/sysroot` ao lado do emcc) |
| `-Dweb-host-include=PASTA` | onde ficam os cabeçalhos de curl, Opus, WebP e fontconfig (padrão: `/usr/include`) |
| `-Dweb-optimize=MODO` | `small` por padrão (o emcc com `-Oz`); `debug` liga com `-O1` |
| `-Dweb-fonts=PASTA` | as fontes da página (padrão: `zig-out/web-fonts`) |

Outros passos:

- `zig build web-lib -Dweb-sysroot=<sysroot do emscripten>` compila tudo em
  `zig-out/web/liblarpercord-web.a` e `liblarpercord-web-c.a`, sem ligar. Só precisa dos
  cabeçalhos do Emscripten, não das ferramentas.
- `zig build web-sim -- --shot saida.png` roda o mesmo caminho do navegador (sem threads,
  fontes da página, laço por quadro) numa janela comum do computador, para conferir sem
  navegador. `--fonts=<pasta>` usa outras fontes. Rode com o ambiente de sempre do QA
  (`env -u LARPER_TOKEN SDL_VIDEO_DRIVER=offscreen` e `XDG_*` numa pasta de rascunho).

## No CI

O `.github/workflows/pages.yml` compila a demonstração antes de publicar o site:

- Prepara o Zig 0.17.0 e o emsdk 6.0.13. O `actions/cache` guarda o emsdk e as portas já
  compiladas entre uma execução e outra, com a chave presa ao `tools/web/freetype_png.py`.
- Instala pelo apt os cabeçalhos de curl, Opus, WebP e fontconfig e copia todos para uma
  pasta só, para o `-Dweb-host-include`, porque o Ubuntu guarda o curl numa pasta multiarch.
- Baixa a Inter 4.1 e a JetBrains Mono 2.304 das releases oficiais, conferidas pelo
  SHA-256, e confere se o `fonts.py` pegou essas fontes e não uma substituta.
- Roda o `zig build web` com `-Dweb-optimize=small` e copia os três arquivos para
  `docs/try/` antes do `gen_site.py`.

Qualquer passo da demonstração pode falhar sem parar o site: ele sai sem a página `try/` e
sem o botão dela na página inicial, e o resumo do job mostra um aviso. A publicação é um
job separado.

## Tamanho

Do build ligado como o workflow faz (`-Dweb-optimize=small`):

| Arquivo | Sem compressão | gzip -9 |
|---|---|---|
| `larpercord.wasm` | 4,30 MB | 1,79 MB |
| `larpercord.js` | 215 KB | 53 KB |
| `larpercord.data` (fontes) | 639 KB | 430 KB |

Deixar o RNNoise e a conexão de voz de fora levou o wasm de 5,77 MB para 4,30 MB (de
3,00 MB para 1,79 MB com gzip). A página mostra o tamanho do download antes do clique.

## O que foi conferido

- O `zig build web` liga com o Emscripten 6.0.13, pelo emsdk e pelo pacote do Arch, e um
  cache vazio gera o mesmo `.wasm`.
- No Firefox sem janela: "Começar a demonstração" abre o app em cerca de meio segundo na
  máquina local, com 0 entradas no console e pedidos só ao servidor da própria página.
  Conferidos lá: servidores, canais, embeds, reações e emojis; digitar texto com acento e
  ✓ e enviar; trocar o tema com F2; Configurações, o modo claro e a troca de idioma na
  hora; a paleta do Ctrl+K; instalar os plugins que vêm com o app e abrir o painel de um
  deles; a página em português com densidade de pixels 2×.
- O `zig build web-sim` continua desenhando a demonstração, e o `zig build test` e os
  builds nativos não mudam.

## O que falta conferir

- A primeira execução do workflow no GitHub. Os mesmos comandos passam na máquina local,
  inclusive com o cache vazio.
- Outros navegadores além do Firefox, uma GPU de verdade (só o WebGL por software foi
  usado), celulares, a área de transferência e a entrada por IME ou teclas mortas no
  navegador.
- Escolher japonês em Configurações → Idioma mostra `?`, porque a página não tem fonte de
  CJK, e a dica ainda dá o conselho do computador.

## Pegadinhas

- **O translate-c do Zig cai no `/usr/include`** nos alvos para os quais ele não tem libc.
  Cabeçalho que falta no sysroot do Emscripten vem calado da glibc. Por isso o `c.h` pula
  o `sys/inotify.h` com `__EMSCRIPTEN__`. Cuidado ao somar includes.
- **A porta do SDL3 do Emscripten deixa de fora** as funções de processo e de seletor de
  arquivo. Os stubs respondem "sem suporte" para elas, como os backends "dummy" do SDL.
- **A porta do FreeType do Emscripten vem sem PNG**, e sem PNG os emojis coloridos (CBDT)
  não abrem. O `tools/web/freetype_png.py` é a mesma porta com PNG, passada ao `embuilder`
  e ao `emcc --use-port`.
- **Com o cache vazio**, o `embuilder` precisa montar o `sysroot` antes das portas, senão a
  porta do SDL3 cai ao gravar o `.pc` dela. O `build.zig` já pede nessa ordem.
- **O Zig não tem atômicos de 64 bits no wasm32**, nem com `+atomics`: daí o `sys.Atomic`.
- **O `struct timespec` da musl tem enchimento em campo de bits**, então o translate-c
  transforma o `struct stat` num tipo opaco. O `sys.ownerOnly` não chama `stat` na web.
