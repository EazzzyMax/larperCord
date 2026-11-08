# Browser demo

*[Leia em português](README.pt-BR.md)*

The real larperCord interface running its demo mode (fake gateway data, no network, no
account) as WebAssembly on the website. It only loads when the visitor clicks "Start
demo" on the [Try it](https://rshacudevidro.github.io/larperCord/try/) page.

**Status: links and runs.** `zig build web` links with Emscripten 6.0.13 and writes
`larpercord.js`, `.wasm` and `.data`. The demo opens in the browser with no console
errors, and the only requests it makes are for its own files. GitHub Actions builds it on
every push to `main` that touches the app or the site (`.github/workflows/pages.yml`), so
nobody needs Emscripten to publish the site. Nothing here changes the native build: the
desktop binary comes out byte for byte the same.

## How it fits together

| Piece | Where |
|---|---|
| Entry point (demo only, browser main loop) | `src/web_main.zig` |
| One loop turn per animation frame, never blocks | `App.webFrame` in `src/app.zig` |
| Fake gateway without its thread | `Gateway.pump` in `src/net/fake_gateway.zig` |
| Images decoded on the page's thread | `Cache.loadInline` in `src/ui/images.zig` |
| Plugins run inside the frame loop, with the same queues, limits and sandbox | `runtime.inline_mode` and `Worker.pump` in `src/plugins/runtime.zig` |
| Fonts shipped with the page | `resolveWeb` in `src/ui/fonts.zig`, made by `tools/web/fonts.py` |
| curl, Opus, WebP, fontconfig, DAVE, SDL's process and file dialog functions, and sockets answering "unavailable" | `src/platform/web/stubs.c` |
| FreeType with PNG, for the color emoji | `tools/web/freetype_png.py` (an Emscripten port) |
| Build steps | `addWeb` in `build.zig` |
| Page | `site/try.html`, emitted by `tools/gen_site.py` only when `docs/try/` has a complete build |

`sys.web` (in `src/platform/sys.zig`) is true only when the build root declares
`larper_web`, which only `src/web_main.zig` does. Every browser-only path is behind it,
so the desktop binary compiles exactly as before. RNNoise and the voice connection stay
out of the browser build, since the page has no voice. Two small type changes keep 32-bit
wasm happy without touching 64-bit behavior: `sys.Atomic` (the same `std.atomic.Value`
everywhere except wasm32, where Zig has no 64-bit atomics and the page has no threads),
and a few `usize`/`u64` casts.

Design choices:

- **No threads.** Emscripten threads need `SharedArrayBuffer`, which needs COOP/COEP
  headers that GitHub Pages can't send. Single-threaded also avoids the main browser
  thread blocking on a lock. The fake gateway, image decoding, plugins and the clock all
  run from the frame callback instead. `gen_site.py` refuses a `.wasm` that uses shared
  memory.
- **No network at all.** curl is stubbed, and `socket()` and `socketpair()` fail, since
  Emscripten would otherwise turn a `connect()` into a WebSocket. Nothing can leave the tab
  by accident.
- **Browser main loop.** `emscripten_set_main_loop(…, 0, …)` calls `App.webFrame` once
  per `requestAnimationFrame`. It only draws when something changed, like the native
  loop, so an idle tab stays cheap.
- **Fonts.** Inter (5 weights), JetBrains Mono (2), DejaVu Sans for the symbols Inter and
  JetBrains Mono lack, and the emoji used anywhere in `src/` and the bundled plugins,
  subset to Latin: about 640 KB uncompressed. Japanese, Chinese, Korean, Arabic and Hebrew
  stay desktop-only.
- **Settings.** The page passes `--lang` and `--mode`, but they only set the starting
  value: Settings → Language and Light/Dark still work. The status bar shows the wasm
  memory instead of the process RAM.

## Building locally

You need Zig 0.17, **Emscripten 6.0.13** (the version the build is checked against),
Python 3 with fontTools, and the fonts the page takes from your system: Inter, JetBrains
Mono, DejaVu Sans and Noto Color Emoji. The curl, Opus, WebP and fontconfig headers come
from `/usr/include` (only their types are used; the stubs answer for them).

**With the emsdk** (any distro):

```sh
git clone https://github.com/emscripten-core/emsdk.git && cd emsdk
./emsdk install 6.0.13 && ./emsdk activate 6.0.13 && cd ..
source emsdk/emsdk_env.sh               # emcc finds its node, python and config

python3 tools/web/fonts.py              # -> zig-out/web-fonts/
zig build web -Demsdk=$PWD/emsdk        # -> zig-out/web/larpercord.{js,wasm,data}
```

**With a system package**, like Arch's `emscripten`: emcc lives somewhere else, so pass
its folder with `-Demscripten`. The package's own cache is read-only, so point `EM_CACHE`
at a folder you can write to, and pass the sysroot inside it:

```sh
sudo pacman -S emscripten python-fonttools inter-font ttf-jetbrains-mono ttf-dejavu noto-fonts-emoji
export PATH="$PATH:/usr/lib/emscripten"
export EM_CACHE="$HOME/.cache/emscripten"

python3 tools/web/fonts.py
zig build web \
  -Demscripten="$(dirname "$(command -v emcc)")" \
  -Dweb-sysroot="$(em-config CACHE)/sysroot"
```

The first `zig build web` runs `embuilder` for the sysroot and the SDL3, zlib, libpng and
FreeType ports, which takes a few minutes; later builds reuse the cache. A rebuild with an
empty cache gives a byte-identical `.wasm`.

To see it on the site, copy the three files and regenerate it:

```sh
mkdir -p docs/try && cp zig-out/web/larpercord.{js,wasm,data} docs/try/
python3 tools/gen_site.py               # emits try/, pt/try/ and the home page button
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs
```

Then open `http://127.0.0.1:8000/try/`. `docs/try/` is in `.gitignore`: the build never
goes into the repository.

Options:

| Option | |
|---|---|
| `-Demscripten=DIR` | the folder with `emcc` and `embuilder` |
| `-Demsdk=DIR` | the emsdk folder (uses `DIR/upstream/emscripten`) |
| `-Dweb-sysroot=DIR` | Emscripten's sysroot (default: `cache/sysroot` next to emcc) |
| `-Dweb-host-include=DIR` | where the curl, Opus, WebP and fontconfig headers are (default: `/usr/include`) |
| `-Dweb-optimize=MODE` | `small` by default (emcc with `-Oz`); `debug` links with `-O1` |
| `-Dweb-fonts=DIR` | the page fonts (default: `zig-out/web-fonts`) |

Other steps:

- `zig build web-lib -Dweb-sysroot=<emscripten sysroot>` compiles everything into
  `zig-out/web/liblarpercord-web.a` and `liblarpercord-web-c.a` without linking. It only
  needs Emscripten's headers, not its tools.
- `zig build web-sim -- --shot out.png` runs the same browser code path (no threads,
  page fonts, frame loop) as a normal desktop window, for checking without a browser.
  Pass `--fonts=<dir>` to use other fonts. Run it with the usual QA environment
  (`env -u LARPER_TOKEN SDL_VIDEO_DRIVER=offscreen` and `XDG_*` in a scratch folder).

## In CI

`.github/workflows/pages.yml` builds the demo before publishing the site:

- It sets up Zig 0.17.0 and emsdk 6.0.13. `actions/cache` keeps the emsdk and its compiled
  ports between runs, keyed on `tools/web/freetype_png.py`.
- It installs the curl, Opus, WebP and fontconfig headers from apt and copies them into one
  folder for `-Dweb-host-include`, since Ubuntu keeps curl in a multiarch folder.
- It downloads Inter 4.1 and JetBrains Mono 2.304 from their official releases, checked by
  SHA-256, and makes sure `fonts.py` picked them up instead of a substitute.
- It runs `zig build web` with `-Dweb-optimize=small` and copies the three files into
  `docs/try/` before `gen_site.py`.

Every demo step can fail without stopping the site: it then goes out without the `try/`
page and its home page button, and the job summary shows a warning. Deploying is a job of
its own.

## Size

From the build linked like the workflow does (`-Dweb-optimize=small`):

| File | Raw | gzip -9 |
|---|---|---|
| `larpercord.wasm` | 4.30 MB | 1.79 MB |
| `larpercord.js` | 215 KB | 53 KB |
| `larpercord.data` (fonts) | 639 KB | 430 KB |

Leaving RNNoise and the voice connection out took the wasm from 5.77 MB to 4.30 MB
(3.00 MB to 1.79 MB with gzip). The page shows the size it will download before the click.

## What's verified

- `zig build web` links with Emscripten 6.0.13, from the emsdk layout and from Arch's
  package, and an empty cache rebuilds the same `.wasm`.
- In headless Firefox: "Start demo" opens the app in about half a second locally, with
  0 console entries and requests only to the page's own server. Checked there: servers,
  channels, embeds, reactions and emoji; typing accented text and ✓ and sending it; F2 theme
  switching; Settings, Light mode and switching the language live; the Ctrl+K palette;
  installing the bundled plugins and opening a plugin panel; the Portuguese page at
  2× pixel density.
- `zig build web-sim` still renders the demo, and `zig build test` and the native builds
  are unchanged.

## Not verified yet

- The first run of the workflow on GitHub. The same commands pass locally, including with
  an empty cache.
- Browsers other than Firefox, a real GPU (only software WebGL was used), phones, the
  clipboard and IME or dead-key input in the browser.
- Choosing Japanese in Settings → Language shows `?`, since the page has no CJK font, and
  its hint still gives desktop advice.

## Gotchas

- **Zig's translate-c falls back to `/usr/include`** for targets it has no libc for.
  Headers missing from Emscripten's sysroot get silently picked from glibc. `c.h` skips
  `sys/inotify.h` under `__EMSCRIPTEN__` for that reason. Watch for this when adding
  includes.
- **Emscripten's SDL3 port leaves out** the process and file dialog functions. The stubs
  answer "unsupported" for them, like SDL's own dummy backends.
- **Emscripten's FreeType port has no PNG**, and without it the color emoji (CBDT) don't
  open. `tools/web/freetype_png.py` is the same port with PNG added, passed to `embuilder`
  and to `emcc --use-port`.
- **With an empty cache**, `embuilder` has to build `sysroot` before the ports, or the SDL3
  port fails writing its `.pc` file. `build.zig` already asks for it in that order.
- **Zig has no 64-bit atomics on wasm32**, even with `+atomics`, hence `sys.Atomic`.
- **musl's `struct timespec` has bit-field padding**, so translate-c turns `struct stat`
  into an opaque type. `sys.ownerOnly` doesn't call `stat` on the web.
