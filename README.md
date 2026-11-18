# claude-work-mac

Run **two Claude Desktop accounts at the same time on a Mac** (for example personal and work), with one command. The second app is a full copy of Claude with its own name, dark icon, login and chats, and it **rebuilds itself automatically every time the original Claude updates**.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/b1b1h-m1k3r/claude-work-mac/main/install.sh | bash
```

Then:

1. Quit the original Claude (Cmd+Q) while you sign in, so the login lands in the right app.
2. Open **Claude Work** from Launchpad, Spotlight or the Dock and sign in with your other account.

Requires macOS 12+ and Claude Desktop in `/Applications`. The dark icon needs the Xcode Command Line Tools (`xcode-select --install`); without them you get the normal orange icon.

## Options

Pass options after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/b1b1h-m1k3r/claude-work-mac/main/install.sh | bash -s -- --name "Claude Personal" --cli
```

| Option | What it does |
|---|---|
| `--name "Claude Work"` | Name of the second app. Run again with another name for a third account. |
| `--no-icon` | Keep the original orange icon. |
| `--cli [alias]` | Also add a shell alias (default `claude-work`) with its own Claude Code login and settings. |
| `--uninstall` | Remove the app, the updater and the background job. Add `--purge-data` to also delete its login and chats. |

## What it does

1. Copies `/Applications/Claude.app` to `/Applications/Claude Work.app`.
2. Gives the copy its own app ID, name and helper apps, so macOS treats it as a separate app (own Dock icon, own notifications).
3. Generates the dark icon (white logo on near-black) from your own Claude icon.
4. Starts the copy with its own data folder (`~/Library/Application Support/Claude Work`), so logins and chats never mix.
5. Re-signs the copy ad hoc so macOS will open it.
6. Installs a background job (a LaunchAgent) that repeats steps 1 to 5 whenever the original Claude updates.

## Auto-update

The job runs at login, every 30 minutes, and whenever Claude's `Info.plist` changes.

- It does nothing until the Claude version changes.
- It never replaces **Claude Work** while it is open. It retries until you close it, then rebuilds and sends a notification.
- It waits if the original Claude is still being updated.
- Your login and chats are untouched, because they live in the data folder, not the app.

Log: `~/Library/Logs/claude-clone-claude-work.log`. Rebuild now (with Claude Work closed): `~/.claude-clone/sync.sh claude-work --force`.

## Good to know

- **Login lands in the wrong app:** Claude signs in through `claude://` links. Quit the other Claude while signing in.
- **Permissions:** the copy is a different app to macOS, so it asks for its own microphone, screen recording and notification permissions once.
- **Updates:** Claude's built-in updater only updates the original app. The background job takes care of the copy.
- **Not affiliated with Anthropic.** This only modifies a copy of the Claude app already installed on your Mac. Nothing from Anthropic is included in this repo; the icon is generated locally.

## Files

| File | Purpose |
|---|---|
| `install.sh` | One-command installer and uninstaller |
| `lib/sync.sh` | Builds the copy and keeps it current |
| `lib/make-icon.swift` | Recolors your Claude icon (dark background, white logo) |

Installed to `~/.claude-clone/` and `~/Library/LaunchAgents/com.claude-clone.<name>.plist`.
