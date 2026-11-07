# macOS (experimental)

Native Apple Silicon build using SDL3, Metal and Dear ImGui. Tested on M1 with
macOS 15.3.2. The baseline ARM64 target also runs on newer M-series CPUs, but
those machines have not been tested individually. Intel Macs are not covered.

## Build and package

Install Xcode or its Command Line Tools, Zig 0.17 and the Homebrew dependencies:

```sh
brew install sdl3 curl opus webp freetype fontconfig openssl@3 pkgconf
sh tools/macos_build.sh -j4
python3 tools/macos_bundle.py /path/to/LarperCord.app
```

Set `ZIG=/path/to/zig` if Zig is not on `PATH`. The script selects Homebrew's
curl with WebSocket support and the macOS SDK. The destination bundle must not
already exist. Packaging requires Python 3.9 or newer.

The bundle includes its non-system libraries, fontconfig configuration and
dependency licenses; Homebrew is not needed to run it. The minimum macOS version
is 15.0 or the highest minimum required by a bundled library, whichever is newer.
Packaging checks that every Mach-O file is ARM64 and rewrites library paths so
the app can be moved. It applies an ad-hoc signature, not Developer ID signing
or notarization.

## Platform behavior

- Primary shortcuts use Command. Tab switching and vim navigation use physical
  Control; plugin bindings retain their literal Ctrl/Super modifiers.
- Closing to the tray uses the menu bar. The Dock can reopen the hidden window.
- Saved tokens use the login Keychain, with the existing private-file fallback
  if storing in the Keychain fails.
- Settings live in `~/Library/Application Support/larpercord`; caches live in
  `~/Library/Caches/larpercord`. `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` override
  these locations.
- Theme changes use kqueue, without polling. Memory statistics report RSS.
- Updates are manual. The Linux/Windows updater is disabled on macOS.
- Optional FFmpeg is not bundled; without compatible libraries the existing
  browser fallback handles video. Screen sharing and camera are not added.

## Tests

```sh
zig build test --summary all
sh tools/macos_build.sh -j4 -Dqa=true -p .zig-cache/macos-qa
SDL_VIDEO_DRIVER=cocoa LARPER_RENDERER=metal QA_SLOW=2 \
  ./.zig-cache/macos-qa/bin/larpercord --qa --theme classico
```

The UI suite opens a native test window and uses fake Discord data. Keep the
default Portuguese language: test targets include translated labels. A demo
without an account can be opened with `--demo --no-live`. Automated UI tests
do not exercise real voice calls or macOS permission prompts.
