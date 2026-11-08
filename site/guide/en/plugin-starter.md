# Plugin starter

Pick what your plugin should do and download a ready-to-edit `.lua` file. A plugin is one file: the comments at the top are its manifest (name, description, what it asks for) and the code below them is the plugin. The starter only offers what the [plugin API](page:plugins) really has, fills in the `@capabilities` line for you and keeps every call where the app allows it.

{{starter}}

## Where to put it

| System | Folder |
|---|---|
| Linux | `~/.config/larpercord/plugins/` (or `$XDG_CONFIG_HOME/larpercord/plugins/`) |
| Windows | `%APPDATA%\larpercord\plugins\` |

Then open **Settings → Plugins** (`Ctrl+,`) and click **Reload**. The plugin's card shows its name, what it asks for and any error, with `file:line`. If it uses the internet, nothing goes out until you approve the host on that card.

Start larperCord from a terminal to see what the plugin `print`s: the starter writes a `loaded` line when it starts.

## What the starter checks

- The name (48 bytes), the description (320 bytes) and the version (16 bytes) fit what the app reads. Longer text would be cut.
- Commands are `/` followed by up to 31 letters, numbers, `_` or `-`.
- Shortcuts follow the app's rules: only F1–F24 can go alone, every other key needs `ctrl`, `alt` or `super`, and `ctrl` with `a`, `c`, `v`, `x`, `y` or `z` is left to typing. If the combination is also one of the app's [shortcuts](page:shortcuts), the starter says so: both would run.
- “Only messages with” takes up to 16 words of up to 64 bytes each. Past that, the app wouldn't load the plugin.
- Hosts are plain names like `api.example.com`: no `https://`, port or IP address, nothing from Discord, at most 8.
- Sending, typing in the message box, opening links and opening the panel only happen inside your command, shortcut, menu entry or panel button, never in an event or a timer. The app refuses them anywhere else.

The file is plain Lua: open it in any editor and change it from there. The [API page](page:plugins) has every function, and the [plugin directory](page:plugin-directory) lists the plugins that come with the app, which are good examples to read.
