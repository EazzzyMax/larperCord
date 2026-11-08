# Getting started

larperCord is a native Discord client for Linux and Windows, written in Zig. You can run it without an account: `--demo` starts **demo mode**, with fake servers and fake people, and it doesn't connect to anything. With no token configured, the app opens the sign-in screen, which also offers the demo.

> [!WARNING]
> **Third-party clients break Discord's Terms of Service**, and your account can be banned. Use a real account at your own risk, ideally a secondary one. This project has no affiliation with Discord Inc.

## What you need

| | Linux | Windows |
|---|---|---|
| System | x86_64 with glibc 2.34 or newer, distros from about 2022 on (tested daily on Arch with Hyprland) | Windows 10 or 11, x64 |
| To run the download | FreeType, fontconfig, libwebp, Opus and zlib from the system; a desktop distro usually has them. SDL3, libcurl and OpenSSL come inside the file | Nothing else: SDL3, libcurl and OpenSSL come as DLLs next to `larpercord.exe` |
| Fonts | Inter, JetBrains Mono and Noto Color Emoji are recommended. fontconfig picks substitutes if one is missing | Nothing to install: Segoe UI, Consolas, Georgia and Segoe UI Emoji from `C:\Windows\Fonts` ([why](page:themes#fonts-on-windows)) |
| Video inside the app (optional) | FFmpeg 7, 8 or 9 (libavformat 61–63) from your distro. Any other version is ignored and videos open in the browser | Settings → Chat → **Download FFmpeg**, about 80 MB, checked against a fixed SHA-256, or **Choose FFmpeg folder…** for a shared build you already have |
| To build | Zig 0.17, SDL3, FreeType, fontconfig, libcurl (with WebSocket support, 7.86 or newer), zlib, libwebp, Opus, OpenSSL | Built from Linux with Zig 0.17: `tools/windows_deps.sh` downloads the Windows libraries |

## Install

Pick your system. The site shows yours first; the others are one click away.

:::: os-pick
::: os arch | Arch Linux and Arch-based distros
The package is [`larpercord-bin`](https://aur.archlinux.org/packages/larpercord-bin) on the AUR. Install it with your AUR helper:

```bash
yay -S larpercord-bin
# or
paru -S larpercord-bin
```

It's the same file as the Linux download, installed into `/usr/bin` with the launcher icon. Updates come through your AUR helper: when there's a new version, Settings → Updates says so and leaves the install to the package.
:::
::: os linux | Other Linux distros
One command installs it, no sudo: the program goes in `~/.local/bin`, with a menu entry and an icon. It checks the download against `SHA256SUMS` and lists any system library that's missing:

```bash
curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.sh | sh
```

Or take the portable file: [larpercord-linux-x86_64](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-linux-x86_64). Make it executable and run it: `chmod +x larpercord-linux-x86_64 && ./larpercord-linux-x86_64`. It can keep that name: an update replaces that same file. Keep it in a folder you own, like `~/.local/bin`, so it can update itself.

It runs on distros from about 2022 onward (glibc 2.34 or newer). SDL3, libcurl and OpenSSL come inside it. FreeType, fontconfig, libwebp, Opus and zlib come from the system, and a desktop distro usually has them already. Before each release it's opened in Ubuntu 22.04 and 24.04, Debian 12 and 13, Fedora, openSUSE and Arch containers, in demo mode with no GPU.

GitHub Actions builds that file from this repository's code. With the GitHub CLI you can check it: `gh attestation verify larpercord-linux-x86_64 --repo RshaCuDeVidro/larperCord`. In the folder with the file and `SHA256SUMS` from the same release, `sha256sum -c --ignore-missing SHA256SUMS` checks it against the release's list.
:::
::: os windows | Windows 10 and 11
In PowerShell, for your user, no administrator. It installs into `%LOCALAPPDATA%\Programs\larperCord` with a Start menu entry, closes larperCord first if it's open, and checks the download against `SHA256SUMS`:

```powershell
irm https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.ps1 | iex
```

Or download the [zip](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-windows-x86_64.zip), unzip it and open `larpercord.exe` in the `larperCord` folder. Keep the three DLLs next to it (`SDL3.dll`, `libcurl-x64.dll`, `libcrypto-3-x64.dll`), and unzip it somewhere you can write to, not `C:\Program Files`, so it can update itself. It isn't code-signed yet: if SmartScreen says "Windows protected your PC", click **More info**, then **Run anyway**. On the releases page, take the zip: the loose `.exe` and DLLs there are for the updater and the install script.

The Windows files have no attestation yet. To check the zip against `SHA256SUMS` from the same release, in PowerShell, in the folder with both files (`True` means it matches):

```powershell
(Get-FileHash .\larpercord-windows-x86_64.zip).Hash -eq ((Select-String 'larpercord-windows-x86_64.zip' .\SHA256SUMS).Line -split '\s+')[0]
```
:::
::::

After that the app updates itself from Settings → Updates (except the AUR package, which updates through your AUR helper, like yay or paru). Running an install script again also installs the newest version. Older versions and checksums: [all releases](https://github.com/RshaCuDeVidro/larperCord/releases).

The last row of the table matters if you build from source, below.

## Build and run

```bash
# Arch Linux
sudo pacman -S zig sdl3 freetype2 fontconfig curl zlib libwebp opus openssl \
    inter-font ttf-jetbrains-mono noto-fonts-emoji

git clone https://github.com/RshaCuDeVidro/larperCord
cd larperCord

zig build -Doptimize=ReleaseFast
./zig-out/bin/larpercord --demo
```

Everything else is already in the repository: Dear ImGui, Lua, stb_image, libdave, MLSpp and nlohmann/json are copied into `third_party/`, so the Linux build downloads nothing.

The Windows version is built from Linux too. `tools/windows_deps.sh` downloads its libraries once, at fixed versions with checked hashes:

```bash
tools/windows_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

`zig-out/bin/` gets `larpercord.exe` with `SDL3.dll`, `libcurl-x64.dll` and `libcrypto-3-x64.dll`. Copy the four files together to the Windows machine and open `larpercord.exe`.

## Your first five minutes

1. Press `F2` a few times. Every press swaps the whole theme file.
2. Press `Ctrl+K` and type `theme`, or a channel name. That's the command palette, and almost everything is in it.
3. Press `Ctrl+,` to open settings. Look at Appearance, where each theme has its own options.
4. Right-click a message, a user, a channel and a server. Everything has a menu.
5. Copy a theme and edit it while the app is open. The built-in themes live inside the app, so download the file (or copy it from `themes/` if you cloned the repository). On Linux:

```bash
mkdir -p ~/.config/larpercord/themes
curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/themes/orbital.kdl -o ~/.config/larpercord/themes/mine.kdl
${EDITOR:-nano} ~/.config/larpercord/themes/mine.kdl
```

On Windows, in PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\larpercord\themes" | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/themes/orbital.kdl -OutFile "$env:APPDATA\larpercord\themes\mine.kdl" -UseBasicParsing
notepad "$env:APPDATA\larpercord\themes\mine.kdl"
```

If the `themes` folder is new, restart larperCord once (Settings → Updates → **Restart larperCord**) so it starts watching the folder. Closing the window isn't enough, because by default it only hides the app in the tray. Change the `theme "orbital"` line to `theme "mine"`, pick it with `F2` or in the palette, and every save reloads the window. If you make a mistake, a notice shows `file:line:column` and the previous version stays on screen. [Writing themes](page:themes) has the whole language.

## Next steps

- [Connect your account](page:account), if you accept the risk.
- [Feature tour](page:features), to see what's in there.
- [Shortcuts and CLI](page:shortcuts), for every key and flag.
