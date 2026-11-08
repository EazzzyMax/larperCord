# Shortcuts and CLI

The same keys on Linux and Windows. There is no macOS build, so it's always `Ctrl`, never `Cmd`. These tables come from `src/ui/atalhos.zig`, the list the app itself shows in **Settings → Keybinds**, so this page and the app can't drift apart.

## Keyboard

{{keys}}

### Mouse and other keys

- **Push to talk:** the key or mouse button you pick in Settings → Voice. It only works while the window is focused.
- **Right-click** works on messages, users, channels and servers.
- **Esc** closes whatever is on top: a menu, the image viewer, the palette, settings.
- **Zoom:** `Ctrl` with the `=`/`+` key or the keypad `+`, `-` and `0`. It goes from 75% to 200% and is saved.
- **Plugins** can add their own shortcuts with `larper.keybind`; each plugin's card in Settings → Plugins lists them. The app's own shortcuts don't use the Windows (Super) key, so it's free for them.
- If a shortcut does nothing, your desktop or window manager may be catching it first.

## Vim navigation

It's off by default. Turn it on in Settings → Keybinds. The keys work while the text box doesn't have focus, and `Esc` leaves the box keeping what you typed.

{{keys:vim}}

## Command line

```bash
larpercord [options]
```

| Option | What it does |
|---|---|
| `--theme NAME` | starts with this theme |
| `--list-themes` | lists the built-in themes and exits |
| `--mode MODE` | `claro` (or `light`) or `escuro`, ignoring your settings |
| `--lang LANG` | `pt` or `en`, ignoring your settings |
| `--demo` | uses the demo data even with a token |
| `--login` | shows the sign-in screen, ignoring the saved token |
| `--settings` | opens straight into settings |
| `--no-live` | turns off the demo mode's automatic messages |
| `--shot FILE.png` | saves a screenshot once the screen settles, then exits |
| `--stats` | shows the time to first frame |
| `--qa` | runs the automatic UI test, with screenshots in `qa-out/` |
| `--voice-test GUILD CHANNEL` | joins a voice channel for 25 s, always muted (needs `LARPER_TOKEN`) |
| `--help` | shows the usage text |

On Windows the program is `larpercord.exe`, and it isn't on `PATH`. In PowerShell, call it by its full path (this is where `install.ps1` puts it; if you unzipped it yourself, use that folder), or put the options at the end of a shortcut's **Target**:

```powershell
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" --theme vidro
```

The Windows build has no console, so the options that only print text (`--help`, `--list-themes`, `--stats`) show nothing in the terminal. To read that text, send it to a file:

```powershell
Start-Process "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" -ArgumentList '--list-themes' -NoNewWindow -Wait -RedirectStandardError out.txt; Get-Content out.txt
```

The built-in themes are also listed in Settings → Appearance.

On both systems, if larperCord is already open, even only in the tray, starting it again just brings that window back and ignores the other options. Quit it first (**Quit** in the tray icon's menu). `--demo`, `--shot`, `--list-themes`, `--help` and `--voice-test` work either way.

## Environment variables

Set them for one run, in the terminal you start the app from:

```bash
LARPER_RENDERER=software larpercord
```

```powershell
# Windows, PowerShell: lasts until you close this window
$env:LARPER_RENDERER = 'software'
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe"
```

In `cmd`, it's `set LARPER_RENDERER=software` before running the `.exe`. Variables only count when the app starts: if it's already open, even only in the tray, quit it first, or the new start just brings the open window back.

| Variable | What it does |
|---|---|
| `LARPER_TOKEN` | the account token (see [Connect your account](page:account)) |
| `LARPER_RENDERER` | picks the SDL render backend: `opengl`, `vulkan`, `gpu` or `software`, and on Windows also `direct3d11` or `direct3d12` |
| `LARPER_HIDDEN` | opens with a hidden window. The app draws nothing while hidden, so memory reads much lower than with a real window |
| `LARPER_BENCH` | redraws nonstop, to measure the cost of a frame |
| `LARPER_VOICE_DEBUG` | prints what happens in a call (opcodes, close codes, DAVE) to the terminal. It never prints tokens or keys. On Windows there's no terminal: turn on Settings → Advanced → Save debug log, which records the same |
| `LARPER_DEBUG_MEDIA` | logs why an image failed to load. On Windows, use the debug log, as above |
| `LARPER_NO_FFMPEG` | pretends FFmpeg isn't installed |
| `LARPER_EGL_ALL` | Linux only: turns off the trick that skips unneeded EGL drivers |
| `LARPER_SCENE` | sets up a scene for documentation screenshots |
| `LARPER_RECORD`, `LARPER_RECORD_FRAMES` | records the sign-in screen as frames in a folder |
| `LARPER_FLOOD` | sends N presence changes per second in demo mode (load test) |

`XDG_CONFIG_HOME` and `XDG_CACHE_HOME` are respected on both systems (on Windows they take the place of `%APPDATA%` and `%LOCALAPPDATA%`), and they're handy for running with a clean configuration.
