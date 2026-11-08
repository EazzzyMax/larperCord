# Settings and files

Open settings with `Ctrl+,`. Changes apply right away and are saved in `settings.kdl`, in the larperCord folder: `~/.config/larpercord/` on Linux and `%APPDATA%\larpercord\` on Windows.

## The pages

| Page | What's there |
|---|---|
| **My Account** | Account details and log out |
| **Privacy** | Typing indicator, Tenor and Giphy animation, streamer mode, message log, keep messages on disk, clear cache, and the network proxy |
| **Alerts & Filters** | Alert words, word filter, ignored people and focus mode |
| **Appearance** | Mode (dark, light, follow the system), theme with thumbnails and its options, font scale, compact mode, avatars, 24-hour clock, status ring, accent color, corners, custom theme colors, member list, status bar and resetting panel sizes |
| **Accessibility** | Reduce motion, role colors, underline links |
| **Chat** | Autoplay GIFs, images from links, data saver, video, always show spoilers, markdown preview, open at the first unread. Without FFmpeg, the video section says which package to install on Linux and has a **Download FFmpeg** button on Windows |
| **Voice** | Microphone and output, volumes, voice activity or push-to-talk, microphone test, filters and call sounds. See [Voice calls](page:voice) |
| **Notifications** | Desktop notifications and taskbar flashing |
| **Keybinds** | The shortcut list and vim navigation |
| **Language** | Follow the system, Português (Brasil) or English (US) |
| **Advanced** | Developer mode (message IDs, "Copy ID"), reload themes on save, close to tray, text weight, and the debug log |
| **Performance** | RAM, CPU per frame, idle CPU and messages per channel |
| **Plugins** | A card for each plugin (what it is and what it asks for), on/off, errors, host approvals, its panel, Reload and Install bundled plugins |
| **About** | Version and what it's built with |

**Close to tray** is on by default: closing the window keeps the app connected, and **Quit** in the tray icon's menu really closes it. Windows always has a tray. On Linux it needs a panel with a StatusNotifier tray, and without one closing the window quits.

**Save debug log** writes `debug.log` in the cache folder (`~/.cache/larpercord/` on Linux, `%LOCALAPPDATA%\larpercord\` on Windows) until you turn it off or close the app. **Open the log folder** and **Copy the file path** take you to it. The token never goes in the file. On Windows this is how you see the app's log, since the Windows build has no console.

## Privacy choices worth knowing

| Option | Default | Effect |
|---|---|---|
| Send typing indicator | on | Others see "typing…" while you write |
| Animate Tenor and Giphy GIFs | off | Downloads from their site, which sees your IP. When off, you get a still preview through Discord |
| Streamer mode | off | Hides your email and username in settings |
| Message log | off | Deleted messages stay visible, marked, and edits keep the original. Local only |
| Keep messages on disk | on | Chats open instantly and `Ctrl+F` works offline. Only your user can read the files |

## Files on disk

Everything lives in two folders:

| | Linux | Windows |
|---|---|---|
| Settings and your files | `~/.config/larpercord/` | `%APPDATA%\larpercord\` |
| Cache and log | `~/.cache/larpercord/` | `%LOCALAPPDATA%\larpercord\` |

`XDG_CONFIG_HOME` and `XDG_CACHE_HOME` replace the first part when they're set, on either system. On Windows, type `%APPDATA%\larpercord` in File Explorer's address bar (or in `Win+R`) to open the folder. Settings → Plugins shows the full path of the plugins folder.

In the settings folder:

| File | What it is |
|---|---|
| `settings.kdl` | Settings, including per-theme options and colors |
| `themes/*.kdl` | Your themes. Create the folder before opening the app, or restart it once (Settings → Updates → Restart larperCord) |
| `plugins/*.lua` | Your plugins |
| `plugins.kdl` | Which plugins are off, the hosts you approved, and the side panel |
| `plugin-data/` | What each plugin stores, per account |
| `drafts.kdl` | Unsent drafts per channel |
| `saved-<account>.json` | Saved messages and notes |
| `accounts` | Saved accounts: ID, name and avatar only |
| `tokens/<ID>` | Remembered tokens, only when there's no keyring (Linux) or Credential Manager fails (Windows) |
| `sons/` | Copies of the sound files you picked in Settings → Voice |
| `instance.lock`, `instance.port` | Keep a second copy of the app from opening; it brings up the first one instead |

In the cache folder:

| File | What it is |
|---|---|
| `messages/` | Message cache: 200 messages per channel, 50 MB cap |
| `debug.log` | Written only while Settings → Advanced → Save debug log is on. Starts over past 4 MB |
| `lsp-scratch/` | Folder the [code diagnostics](page:lsp) server runs in; emptied before each start |
| `ffmpeg/` | Windows only: what Settings → Chat → Download FFmpeg installs |

On Linux, the app's folders are `700` and the files with your data are `600`, so only your user can read them. On Windows they're inside your user profile, which other users can't open.

Two more, which stay under your home folder even with `XDG_CONFIG_HOME` or `XDG_CACHE_HOME` set:

| Path | What it is |
|---|---|
| `~/.config/larpercord/token` | Linux only: optional token file (`chmod 600`), from before multiple accounts |
| `~/.cache/wal/colors` | Read only: pywal's palette, for themes that use it. On Windows it's read only when `HOME` is set (`%HOME%\.cache\wal\colors`), and changes aren't followed |

To go back to defaults, quit the app and delete `settings.kdl` from the settings folder (`~/.config/larpercord/` on Linux, `%APPDATA%\larpercord\` on Windows). Closing the window isn't enough while the app stays in the tray: use **Quit** in the tray icon's menu.
