# Browser demo (prototype)

*[Leia em português](README.pt-BR.md)*

The goal: the real larperCord interface running its demo mode (fake gateway data,
no network, no account) as WebAssembly on the website, loaded only when the visitor
clicks "Start demo".

**Status: compiles, not linked yet.** The whole app (Zig, Dear ImGui, FreeType
bindings, FriBidi, Lua, RNNoise) builds for `wasm32-emscripten`. The final link with
`emcc` and a run in a real browser have not happened yet: the Emscripten SDK was not
installed on the build machine. Nothing here changes the native build.

## How it fits together

| Piece | Where |
|---|---|
| Entry point (demo only, browser main loop) | `src/web_main.zig` |
| One loop turn per animation frame, never blocks | `App.webFrame` in `src/app.zig` |
| Fake gateway without its thread | `Gateway.pump` in `src/net/fake_gateway.zig` |
| Images decoded on the page's thread | `Cache.loadInline` in `src/ui/images.zig` |
| Fonts shipped with the page | `resolveWeb` in `src/ui/fonts.zig`, made by `tools/web/fonts.py` |
| curl, Opus, WebP, fontconfig, DAVE answering "unavailable" | `src/platform/web/stubs.c` |
| Build steps | `addWeb` in `build.zig` |
| Page | `site/try.html`, emitted by `tools/gen_site.py` only when `docs/try/` has a build |

`sys.web` (in `src/platform/sys.zig`) is true only when the build root declares
`larper_web`, which only `src/web_main.zig` does. Every browser-only path is behind it,
so the desktop binary compiles exactly as before. Two small type changes keep 32-bit
wasm happy without touching 64-bit behavior: `sys.Atomic` (the same `std.atomic.Value`
everywhere except wasm32, where Zig has no 64-bit atomics and the page has no threads),
and a few `usize`/`u64` casts.

Design choices:

- **No threads.** Emscripten threads need `SharedArrayBuffer`, which needs COOP/COEP
  headers that GitHub Pages can't send. Single-threaded also avoids the main browser
  thread blocking on a lock. The fake gateway, image decoding and the clock all run
  from the frame callback instead.
- **No network at all.** curl is stubbed, so nothing can leave the tab by accident.
- **Browser main loop.** `emscripten_set_main_loop(…, 0, …)` calls `App.webFrame` once
  per `requestAnimationFrame`. It only draws when something changed, like the native
  loop, so an idle tab stays cheap.
- **Fonts.** Inter (5 weights), JetBrains Mono (2), DejaVu Sans symbols and the emoji
  the demo uses, subset to Latin: about 555 KB uncompressed. CJK, Arabic and Hebrew stay
  desktop-only.

## Building

```sh
# 1. Emscripten SDK, pinned (6.0.13 is the version the build was checked against)
git clone https://github.com/emscripten-core/emsdk.git && cd emsdk
./emsdk install 6.0.13 && ./emsdk activate 6.0.13 && cd ..

# 2. Fonts for the page (needs fontTools and the fonts installed on this system)
python3 tools/web/fonts.py              # -> zig-out/web-fonts/

# 3. Build and link (runs embuilder for the SDL3, FreeType and zlib ports first)
source emsdk/emsdk_env.sh               # emcc finds its node, python and config
zig build web -Demsdk=$PWD/emsdk        # -> zig-out/web/larpercord.{js,wasm,data}

# 4. Publish on the site: the page and the home page link appear on their own
cp zig-out/web/larpercord.{js,wasm,data} docs/try/
python3 tools/gen_site.py
```

Other steps:

- `zig build web-lib -Dweb-sysroot=<emscripten sysroot>` compiles everything into
  `zig-out/web/liblarpercord-web.a` and `liblarpercord-web-c.a` without linking. It only
  needs Emscripten's headers, not its tools.
- `zig build web-sim -- --shot out.png` runs the same browser code path (no threads,
  page fonts, frame loop) as a normal desktop window, for checking without a browser.
  Pass `--fonts=<dir>` to use other fonts. Run it with the usual QA environment
  (`env -u LARPER_TOKEN SDL_VIDEO_DRIVER=offscreen` and `XDG_*` inside the worktree).

## What's verified

- `zig build web-lib` builds both archives for `wasm32-emscripten` against the
  Emscripten 6.0.13 headers (SDL 3.4, FreeType 2.14, zlib headers alongside).
- The only undefined symbols left are libc/POSIX, compiler-rt, Emscripten's setjmp
  helpers, SDL3, FreeType and zlib, which `emcc` provides with `-sUSE_SDL=3
  -sUSE_FREETYPE=1 -sUSE_ZLIB=1`. Everything from curl, Opus, WebP, fontconfig and
  DAVE is covered by the stubs.
- Zig emits position-independent objects for Emscripten (it refuses `-fno-PIC` there).
  A static link with `wasm-ld` resolves `__memory_base` and `__table_base` internally,
  with no imports left over.
- `zig build web-sim -- --shot out.png` opens the demo through the browser path
  (`App.webFrame`, `Gateway.pump`, `Cache.loadInline`, the subset fonts from
  `tools/web/fonts.py`) and renders the whole demo: servers, channels, members,
  generated images, embeds, reactions and emoji.
- `zig build test` and the native debug build still pass.

## What's left, in order

1. **Link with emcc.** Expect a short round of missing symbols or flags. Most likely:
   compiler-rt helpers Zig emits (if any are missing, set `bundle_compiler_rt = true`
   on the Zig archive), `-sSUPPORT_LONGJMP=emscripten` agreeing with Lua's
   `-mllvm -enable-emscripten-sjlj`, and `callMain` finding Zig's entry point (Zig
   exports `__main_argc_argv`, the wasm name for `main(argc, argv)`).
2. **First run in a browser.** Things to watch: the canvas size and pixel density
   (`larper_web_resize` is called from a `ResizeObserver`), keyboard focus (SDL is told
   to listen on `#canvas` only), text input (SDL's IME support in the browser is limited,
   so check accented letters), clipboard (async in browsers), the 2 s clock
   (`SDL_AddTimer` uses `emscripten_set_timeout` without threads), and the `.data` file
   with the fonts at `/fonts`.
3. **Size.** Measure the compressed size (`gen_site.py` prints it on the page). Levers:
   `-Oz` with `wasm-opt` (already on), `IMGUI_DISABLE_DEBUG_TOOLS`, dropping Lua and
   RNNoise from the browser build behind `sys.web` (the demo doesn't need them), and a
   smaller emoji set. Rough estimate before measuring: 3 to 5 MB of wasm, 1.5 to 2 MB
   compressed.
4. **Behavior checks** in the browser: every settings page opens; switching theme and
   light/dark; sending a message, reactions, threads, the GIF picker (all fake data);
   a call shows up without sound; nothing tries a file dialog or a subprocess.
5. **Polish:** a loading bar from Emscripten's `setStatus`, a phone layout hint, and
   picking the page's current theme (already passed as `--theme`).

## Blockers hit in this run

- **The Emscripten SDK could not be installed here.** Running the official `emsdk`
  installer was refused by the machine's permission policy (it downloads and runs code).
  Without `emcc` there is no final link and no browser test. The compile check above
  used only Emscripten's header files (`system/include`, musl and libc++ headers from
  the 6.0.13 tag), copied into a sysroot layout, with nothing from Emscripten executed.
- **Zig's translate-c falls back to `/usr/include`** for targets it has no libc for.
  Headers missing from Emscripten's sysroot get silently picked from glibc. `c.h` skips
  `sys/inotify.h` under `__EMSCRIPTEN__` for that reason. Watch for this when adding
  includes.
- **Zig has no 64-bit atomics on wasm32**, even with `+atomics`, hence `sys.Atomic`.
- **musl's `struct timespec` has bit-field padding**, so translate-c turns `struct stat`
  into an opaque type. `sys.ownerOnly` doesn't call `stat` on the web.
