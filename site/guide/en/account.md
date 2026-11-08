# Connect your account

> [!WARNING]
> **Using a user account outside the official client breaks Discord's Terms of Service, and the account can be banned.** Use it at your own risk, ideally with a secondary account. Nothing in this project makes that risk go away.

## How the app finds your token

The token is never stored in the code, and it never goes into logs or error messages. It's also wiped from memory when the app exits.

The simplest way, on Linux and Windows, is the sign-in screen with **Remember on this computer** on (below). The token goes to the system's safe storage: the keyring on Linux, Credential Manager on Windows.

When it opens, the app looks in this order:

1. The `LARPER_TOKEN` environment variable. It's never saved anywhere.
2. The accounts you saved with **Remember**, starting with the last one used.
3. Linux only, from before multiple accounts: the keyring entry `service larpercord`, then the file `~/.config/larpercord/token`, which must have `chmod 600` (if other users can read it, the app ignores it and says so in the log). To put a token in the keyring yourself:
   ```bash
   secret-tool store --label='larperCord' service larpercord   # paste the token when asked
   ```
   `secret-tool` needs a keyring running, such as GNOME Keyring. Without one, **Remember** saves to a file instead.

To use `LARPER_TOKEN` for one run without saving it anywhere, in bash or zsh:

```bash
read -rs LARPER_TOKEN && LARPER_TOKEN="$LARPER_TOKEN" larpercord
```

On Windows, in PowerShell. The last line clears the variable from the window; the app already has its own copy:

```powershell
$env:LARPER_TOKEN = [Net.NetworkCredential]::new('', (Read-Host 'Token' -AsSecureString)).Password
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe"
Remove-Item Env:LARPER_TOKEN
```

That path is where `install.ps1` puts the app; if you unzipped it yourself, use that folder. If larperCord is already open, even only in the tray, quit it first (**Quit** in the tray icon's menu): a second start just brings the open window back and ignores the variable.

## The sign-in screen

Without a token, the app opens the sign-in screen (`--login` forces it). You can paste a token or choose **Explore the demo**, and the screen has its own help link. With **Remember on this computer** on, the token is only saved after Discord accepts it.

## Multiple accounts

Click your own name to open the account menu. It lists saved accounts with name and avatar, and switching takes effect right away. **Add account** goes back to the sign-in screen without forgetting the others.

The sign-in screen lists saved accounts too, so you can get into another one if a session ends. When Discord refuses a token, the app forgets it instead of trying it again every time it opens.

| What | Linux | Windows |
|---|---|---|
| Each remembered token | Its own keyring entry (`service larpercord-account account <ID>`). Without a keyring: `~/.config/larpercord/tokens/<ID>`, `chmod 600` | Its own entry in Credential Manager (Windows Credentials → Generic Credentials, `larperCord/account/<ID>`). If that fails: `%APPDATA%\larpercord\tokens\<ID>` |
| The list of accounts (ID, name and avatar only) | `~/.config/larpercord/accounts` | `%APPDATA%\larpercord\accounts` |

On Linux, the keyring entry from the first section still works for the account that was already in it. **Log Out** deletes the account's token from wherever it was.

## Sign out

Settings → **Log Out**. To force demo mode even with a token saved, start the app with `--demo`: `larpercord --demo` on Linux. On Windows, add ` --demo` to the end of a shortcut's **Target**, or run `& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" --demo` in PowerShell. `--demo` opens even while another copy is in the tray.

## What goes over the network

With a token, the app talks to Discord's gateway and REST API, and to Discord's media servers for images. See [Privacy and security](page:privacy) for the details, including the optional proxy.
