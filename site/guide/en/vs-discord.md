# What Discord doesn't have

What larperCord does that the official Discord desktop app doesn't do on its own, compared in November 2026. Client mods for the official app don't count. Each feature links to where it's explained, and the [last section](#what-the-official-app-has-that-larpercord-doesn-t) lists what the official app still does better. If Discord gains one of these, [open an issue](https://github.com/RshaCuDeVidro/larperCord/issues) and the line goes away.

> [!WARNING]
> **Third-party clients break Discord's Terms of Service**, and your account can be banned. Use a secondary account. See [If Discord locks your account](page:privacy#if-discord-locks-your-account).

## Lightness and performance

Some items here are how larperCord stays light, and the official app may do similar things inside.

- **[No browser inside](page:architecture#the-rendering).** Native code that draws with Dear ImGui on SDL3. The official app runs on Electron, a browser packaged as an app, for now: on November 4, 2026, Discord's CTO showed a native rebuild in Rust that isn't out yet ([its early numbers](page:performance#the-numbers)).
- **[About 130 MB of RAM](page:performance#the-numbers)** with a real account. ¹
- **[0–0.4% CPU when idle](page:performance#the-numbers).** The app sleeps until a network event, a key or the clock wakes it. ²
- **[About 15 MB](page:performance#the-numbers)** for the Linux download, in a single file. ³
- **[Things start when you ask](page:performance#ten-decisions).** The voice thread when you join a call, stopped when you leave, FFmpeg on your first video, and no plugin thread while no plugin is on.
- **[Hidden means lighter](page:performance#ten-decisions).** After a minute in the tray or minimized, images leave memory, except small ones that were on screen.
- **[Memory limits you set](page:settings#the-pages).** Settings → Performance shows live RAM and where it goes, and sets how much goes to images, each GIF and messages.

¹ PSS: 125–140 MB in one account's normal use and about 70 MB right after opening, on one PC with Arch Linux, Hyprland, an i5-2400S, a GTX 1050 Ti and a 1280×800 window. About 35 MB of it is the NVIDIA driver, libraries and fonts. Measured on a build that uses the system's libraries; side by side in demo, the published file used about 2 MB more. Yours depends on your servers, members and images.

² Measured with `tools/membench.sh` across all 11 themes, with demo data, a real window on a hidden Hyprland workspace and GIF autoplay off. A window you're looking at can measure differently. An animated GIF on screen costs about 2.5%.

³ With SDL3, libcurl and OpenSSL inside. [How all of this was measured](page:performance).

## Privacy and control

- **[Open source](https://github.com/RshaCuDeVidro/larperCord)** under GPL-3.0. You can read every line and build it yourself.
- **[No telemetry or analytics](page:privacy#what-goes-over-the-network)** in the app, so there's nothing to opt out of.
- **[A proxy setting](page:privacy#proxy)** for HTTP, HTTPS, SOCKS5 and Tor, with login and password, for media from outside Discord only, or also for Discord's API, gateway and media. Voice calls always connect directly.
- **[Data saver](page:features#media).** Images, attachments and even profile pictures wait for a click, one at a time, and custom emoji show as `:name:`.
- **[Settings in one text file](page:settings#files-on-disk).** `settings.kdl` is plain text you can read, edit and back up.

## Reading and writing

- **[Offline search](page:features#finding-things).** `Ctrl+F` searches the messages you've already seen as you type, with no internet.
- **[Message log](page:settings#privacy-choices-worth-knowing)**, off by default. Deleted messages stay on screen, marked, and edited ones keep the original. Only on your computer.
- **[Saved messages](page:features#finding-things)** (`Ctrl+Shift+S`), free, with a note and kept only on your computer, up to 500. Discord's bookmarks need Nitro and live on its servers.
- **[Alert words](page:features#attention)** count as mentions: highlight, counter and notification.
- **[A word filter](page:features#attention)** folds matching messages behind a click, and they never notify.
- **[Focus mode](page:features#attention).** For 15 minutes, 30 minutes, an hour or until you turn it off, only DMs and mentions notify.
- **[Line numbers in code blocks](page:features#markdown)**, left out of what you copy.
- **[Errors while you type code](page:lsp).** A language server you choose checks the code block in your message box. Off by default.

## Power-user tools

- **[Split view](page:features#layout).** Up to three conversations side by side, each with its own history and scroll position.
- **[Tabs](page:shortcuts#keyboard)** for open channels: `Ctrl+Click` opens a new one, `Ctrl+Tab` and `Alt+1…9` switch, `Ctrl+W` closes.
- **[A command palette that does things](page:features#finding-things).** `Ctrl+K` also changes settings, themes and your status, not only jumps to channels.
- **[Vim keys](page:shortcuts#vim-navigation)**, off by default: `j`/`k`, `gg`/`G`, and `J`/`K` between channels.
- **[Command-line options](page:shortcuts#command-line).** Start with a theme, language or mode, open straight into settings, or save a screenshot and exit.
- **[Demo mode](page:getting-started).** The whole app on fake data, with no account and no network: `--demo`.

## Voice

- **[A call mixer](page:voice#using-it)** with everyone's volume and a mute button in one window. The official app sets them one person at a time, from each person's menu.

## Themes and plugins

- **[The whole layout is a text file](page:themes).** Move, resize and swap the parts of the window in a `.kdl` file, not only the colors.
- **[Reloads on save](page:themes).** Saving the file redraws the window right away. A mistake points to `file:line:column` and the previous theme stays on screen.
- **[11 built-in layouts](page:theme-gallery)**, not just color schemes, from an IRC terminal to a Mac-style desktop, each with light and dark modes and options of its own.
- **[Colors from your wallpaper](page:themes#colors)** through pywal, in themes with `palette "wal"`, on Linux (on Windows only with the `HOME` variable set, and not live).
- **[Real transparency](page:theme-gallery#vidro).** The `vidro` theme has a see-through background, and on Linux your compositor (Hyprland, KDE…) adds the blur. Windows has no blur.
- **[Every color, per theme and mode](page:themes#custom-colors-without-editing-the-kdl):** each of the theme's color tokens and the eight role colors, picked in hex in Settings, free and without editing the file. Discord's custom theme is a Nitro gradient of up to five colors.
- **[Lua plugins](page:plugins)** add panels, right-click entries, notes under messages, commands and keybinds, with no rebuild.
- **[Plugins in a sandbox](page:plugins#limits).** A thread apart from the interface, a Lua state and 8 MB for each plugin, about 5 million instructions per call, no files, processes or sockets, and HTTPS only to hosts you approve. They never see your token.
- **[Nine plugins come with the app](page:plugins#the-plugins-that-come-with-the-app):** scam guard, CVE radar, GitHub cards, what did I miss, translate, reminders, highlights, clean links, and links and files.

## What the official app has that larperCord doesn't

- **[Screen sharing (sending or watching), camera and video calls](page:voice#limits-today).** larperCord does voice only, and these aren't planned.
- **[Push-to-talk outside the window](page:voice#limits-today).** Here it only works while the window is focused, because SDL has no portable global shortcut. A global one is on the roadmap.
- **[Notifications that open the conversation](page:status#what-works-today).** Clicking one doesn't open the channel yet.
- **[Server and role settings](page:features#servers-and-groups).** Here you can edit a server's name, description, icon and banner, give or remove roles, and kick, ban, time out, or server-mute and deafen members. The rest is on the roadmap.
- **Creating servers and channels.** You can create threads and forum posts, but not servers or channels.
- **Stage channels.** A Stage shows up as a plain voice channel, with no speakers and audience sections and no way to ask to speak.
- **Activities and the soundboard.** Not in the app.
- **[Video in full quality](page:features#media).** Videos in the chat play up to 480p at about 30 fps and need FFmpeg: your distro's on Linux, the **Download FFmpeg** button in Settings → Chat on Windows. Without it, they open in the browser.
- **[macOS, phones and the web](page:getting-started#what-you-need).** larperCord runs on Linux and Windows 10/11.
- **[Accessibility](page:status#what-works-today).** There's font scale, reduced motion, the command palette and vim keys, but no visible keyboard focus, no high contrast mode and no screen reader support.

What works, what's partial and what comes next is in [Status and roadmap](page:status).
