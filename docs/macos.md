# macOS (experimental)

**English** · [Português](macos.pt-BR.md)

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
- Closing to the tray uses the menu bar. Clicking the menu-bar icon opens its
  menu (Open, Quit); the left click that shows or hides the window on Linux and
  Windows isn't there. The Dock can reopen the hidden window.
- Saved tokens use the login Keychain, with the existing private-file fallback
  if storing in the Keychain fails.
- Settings live in `~/Library/Application Support/larpercord`; caches live in
  `~/Library/Caches/larpercord`. `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` override
  these locations.
- Fonts come from fontconfig, as on Linux, reading the macOS font folders (the
  bundle carries its own `fonts.conf`). That includes the fallback fonts for
  other scripts: Japanese, Chinese and Korean, Arabic and Hebrew (right to left,
  shaped by the bundled FriBidi), and any character a theme font lacks. The
  Japanese interface uses the same fonts. If fontconfig finds nothing, the app
  opens San Francisco, Times New Roman and Apple Color Emoji directly. The
  per-script fallback and right-to-left text haven't been tried on a Mac yet.
- Theme changes use kqueue, without polling. Memory statistics report RSS.
- Rich Presence for games and apps listens on `$TMPDIR/discord-ipc-N`, where the
  official client puts it. Not tried on a Mac yet.
- Updates are manual. The Linux/Windows updater is disabled on macOS, and
  Settings → Updates only offers the restart button.
- The demo and QA never open a real session, never read the Keychain and never
  ask for notification permission.
- Optional FFmpeg is not bundled. Video plays inside the app with FFmpeg 7, 8
  or 9 libraries from the folder chosen in Settings → Chat → Videos (for
  Homebrew, `/opt/homebrew/lib`); otherwise it opens in the browser. Not tried
  on a Mac yet. Screen sharing and camera are not added.

## Tests

```sh
zig build test --summary all
SDL_VIDEO_DRIVER=cocoa LARPER_RENDERER=metal QA_SLOW=2 tools/qa.sh
```

`tools/qa.sh` builds in debug mode with safety checks, then runs the general
suite, the per-feature suites (extras, sending, limits, social, media, Rich
Presence, moderation, onboarding, interactions, other scripts, no fonts, call
mixer), plugin persistence across processes, both sign-in modes and all 11
themes in dark and light modes. It saves screenshots and a log per run in
`qa-out/`. Set `ZIG=/path/to/zig` if needed. The macOS build uses the same matrix
as Linux; the Linux-specific LSP harness is excluded on macOS. The no-fonts
suite assumes fontconfig is the only way to fonts, which isn't true on macOS
(see the fallback above).

The UI suite opens native test windows and uses fake Discord data. Keep the
default Portuguese language: test targets include translated labels. A demo
without an account can be opened with `--demo --no-live`. Automated UI tests
do not exercise real voice calls or macOS permission prompts.

## CI

An experimental job on GitHub's Apple Silicon runners (`macos` in
`.github/workflows/ci.yml`) installs the Homebrew dependencies above, builds the
app, runs the unit tests and the general QA suite in a native window (the
runner has a display; `LARPER_RENDERER=software`, since the VM has no Metal;
SDL's offscreen driver doesn't open a window on macOS), and uploads the
`larpercord-macos-arm64` artifact: the `.app` inside a `.tar.gz`. It doesn't
block the other jobs while the port is experimental. The bundle is only signed
ad hoc, so macOS may refuse to open a downloaded copy; in that case run
`xattr -dr com.apple.quarantine LarperCord.app` once.
