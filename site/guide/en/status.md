# Status and roadmap

larperCord is a young project: version 0.6.2, with its first commit on November 2, 2026. It's usable, but it isn't complete.

## What works today

| Area | State | Detail |
|---|---|---|
| Messages, DMs, reactions, replies | **works** | Send, edit, delete, history, mentions, send options, poll voting, who reacted |
| Bots and apps | **works** | Buttons, select menus, forms (modals) and slash commands. App commands in the right-click menu and files in bot forms are missing |
| Images | **works** | Avatars and attachments, with a fixed-size cache |
| Video in chat | **works** | Attachments and direct links. Needs FFmpeg 7, 8 or 9: your distro's on Linux, or the **Download FFmpeg** button in Settings → Chat on Windows |
| Inbox, saved messages, offline search | **works** | All local, can be turned off and erased |
| Multiple accounts, proxy, Lua plugins | **works** | |
| Account settings | **works** | Block, ignore, friend requests, mute and notification levels, status with a duration, custom status, display name, pronouns and About me, synced with your Discord account. The picture and banner are still changed in the official app |
| Moderation | **works** | Kick, ban, timeout, server mute and deafen, the bans list. Only the actions your role allows appear |
| Rich Presence | **works** | Off by default |
| Threads and forums | **works** | Nested threads, forum post lists, creating and editing threads and posts, archived and private ones |
| Custom emoji, stickers, autocomplete | **works** | Animated too. The picker warns when an emoji needs Nitro, and the GIF picker sends stickers |
| Arabic, Hebrew and other scripts | partial | They display, and a system font fills in letters any theme lacks. Typed right-to-left text goes left to right in the message box, and scripts that need shaping (Devanagari, Thai…) show their letters without it |
| Read state, pins, Discord links | **works** | Synced with your other devices |
| Themes | **works** | 11 built-in, each light and dark, reload on save |
| Voice | partial | Server voice channels and DM and group calls. E2EE (DAVE), mixer, mute, device picker, push-to-talk, high-pass filter, noise gate and RNNoise noise suppression work. Push-to-talk needs the window focused, and no automated test covers a real call |
| Permissions | partial | Channels without access get a padlock, voice without permission is blocked, and the message box says why you can't send (no permission, a locked thread, a timeout, slowmode). Those channels still appear, and reactions and the member list don't check permissions |
| System tray, updates | **works** | Closing keeps it in the tray; signed updates from Settings. On Linux the tray needs a StatusNotifier panel |
| Windows | partial | Windows 10/11 from the same code. Newer than Linux and less used |
| Notifications | partial | Through `notify-send` on Linux and the tray on Windows. Clicking doesn't open the channel |
| Accessibility | partial | Font scale, reduced motion, palette and vim navigation. No visible focus and no high contrast |
| First run | partial | Sign-in screen and demo mode, no introduction to the app |
| Platforms | partial | Linux and Windows. The Linux build needs glibc 2.34 or newer. It's used daily on Arch with Hyprland, and opened in Ubuntu, Debian, Fedora, openSUSE and Arch containers, in demo mode, before each release. The Windows build has only been run in CI and in a sandbox, in demo mode |
| Joining a server by invite | **works** | From an invite card, a link or a code, with a warning first. Servers with rules or onboarding open them in the app |
| Screen sharing and camera | missing | |

## Roadmap

**Done**

- [x] Real gateway (WebSocket, heartbeat, reconnects) and REST respecting rate limits
- [x] Session RESUME and zlib-stream
- [x] Presences, members and server and channel events
- [x] Images: avatars, attachments and custom emoji with a fixed-size cache
- [x] Voice: voice gateway, UDP, Opus and DAVE/MLS
- [x] Voice settings: device picker, push-to-talk, filters and call sounds
- [x] Threads and forums
- [x] Stickers, the full emoji picker and autocomplete
- [x] Read state synced with Discord, pinned messages, Discord links in the app
- [x] Theme engine: gradients, patterns, grain, vignette, display typography, shapes and rules, procedural backgrounds
- [x] Joining a server by invite
- [x] Calls in DMs and groups
- [x] Rich Presence: show the game you're playing, off by default
- [x] Moderation: kick, ban, timeout, and server mute and deafen
- [x] Bot buttons, menus, forms and slash commands
- [x] Account settings synced with Discord: block, ignore, friends, mute, status and profile
- [x] Arabic and Hebrew, and fonts for any script
- [x] On the site: a theme builder, a community theme gallery and a demo in the browser

**Next**

- [ ] Open from the saved servers, channels and messages, then sync when Discord answers
- [ ] A texture atlas for avatars and emoji
- [ ] Server and role settings
- [ ] A better theme editor
- [ ] More versatile and more powerful plugins
- [ ] Windows as a single `.exe` (an experimental build option already makes one)

**To make the app complete**

- [ ] Real permissions: hide what you can't see, disable reactions, filter members
- [ ] Typing right-to-left text in the message box, and shaping for complex scripts
- [ ] Native D-Bus notifications with "open conversation"
- [ ] Voice: a global push-to-talk and an automated call test
- [ ] Accessibility and first run: visible focus, high contrast, a welcome screen

**Themes**

- [ ] Engine: overlay and z-order, fonts and images bundled with a theme
- [ ] Gallery and editor: real thumbnails, import and export `.kdl`, a component inspector
- [ ] Theme components written in Lua (sandboxed)

**Later**

- [ ] A software backend (`wl_shm`, no GPU), to get to about 15–20 MB
