#!/bin/bash
# Installs a second, independent Claude Desktop ("Claude Work") that keeps itself
# up to date with the original Claude.app.
#
#   curl -fsSL https://raw.githubusercontent.com/b1b1h-m1k3r/claude-work-mac/main/install.sh | bash
#
# Options (pass after `bash -s --` when piping):
#   --name "Claude Work"   name of the second app (default: Claude Work)
#   --no-icon              keep the original orange icon instead of the dark one
#   --cli [alias]          also add a shell alias with its own Claude Code config (default alias: claude-work)
#   --uninstall            remove the app, updater and LaunchAgent (add --purge-data to delete its login/chats too)
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
REPO="b1b1h-m1k3r/claude-work-mac"
BRANCH="main"

# When run through curl there are no sibling files: fetch the repo and run from there.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ ! -f "$SELF_DIR/lib/sync.sh" ]; then
  echo "Downloading installer..."
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$T" --strip-components=1 \
    || { echo "Download failed"; exit 1; }
  bash "$T/install.sh" "$@"; exit $?
fi

NAME="Claude Work"; ICON=dark; CLI=""; UNINSTALL=0; PURGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:?--name needs a value}"; shift 2 ;;
    --no-icon) ICON=original; shift ;;
    --cli) if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then CLI="$2"; shift 2; else CLI="claude-work"; shift; fi ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge-data) PURGE=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SLUG="$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
[ -n "$SLUG" ] || { echo "Invalid name"; exit 1; }
case "$NAME" in *[\"\\\$\`]*) echo "Name cannot contain quotes, backslashes, \$ or backticks"; exit 1 ;; esac
[ "$NAME" != "Claude" ] || { echo "Pick a name other than \"Claude\""; exit 1; }

HOME_DIR="$HOME/.claude-clone"
LABEL="com.claude-clone.$SLUG"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_="$(id -u)"

if [ "$UNINSTALL" = 1 ]; then
  launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null
  rm -f "$AGENT"
  if [ -f "$HOME_DIR/instances/$SLUG.conf" ]; then . "$HOME_DIR/instances/$SLUG.conf"; fi
  pkill -f "/$NAME.app/Contents/MacOS" 2>/dev/null; sleep 1
  rm -rf "${DEST_DIR:-/Applications}/$NAME.app"
  rm -f "$HOME_DIR/instances/$SLUG".* "$HOME/Library/Logs/claude-clone-$SLUG.log"
  if [ "$PURGE" = 1 ]; then rm -rf "$HOME/Library/Application Support/$NAME"; echo "Deleted its login and data."
  else echo "Kept its login and data in ~/Library/Application Support/$NAME (add --purge-data to delete)."; fi
  rmdir "$HOME_DIR/instances" "$HOME_DIR/tmp" 2>/dev/null
  if [ -z "$(ls "$HOME_DIR/instances" 2>/dev/null)" ]; then rm -rf "$HOME_DIR"; fi
  echo "Removed $NAME."; exit 0
fi

echo "== Claude second-account installer =="
[ "$(uname)" = "Darwin" ] || { echo "macOS only."; exit 1; }
SRC="/Applications/Claude.app"
[ -d "$SRC" ] || { echo "Claude Desktop is not installed at $SRC. Install it from https://claude.ai/download first."; exit 1; }
if [ -w /Applications ]; then DEST_DIR=/Applications; else DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi
if pgrep -f "$DEST_DIR/$NAME.app/Contents/MacOS" >/dev/null; then
  echo "$NAME is open. Quit it (Cmd+Q) and run the installer again."; exit 1
fi

# Install the updater scripts
mkdir -p "$HOME_DIR/instances" "$HOME_DIR/tmp" "$HOME/Library/LaunchAgents"
cp "$SELF_DIR/lib/sync.sh" "$SELF_DIR/lib/make-icon.swift" "$HOME_DIR/"
chmod +x "$HOME_DIR/sync.sh"
{ printf 'NAME=%q\n' "$NAME"; printf 'SRC=%q\n' "$SRC"; printf 'DEST_DIR=%q\n' "$DEST_DIR"; printf 'ICON=%q\n' "$ICON"; } > "$HOME_DIR/instances/$SLUG.conf"

# LaunchAgent: at login, every 30 minutes, and whenever Claude.app updates
cat > "$AGENT" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$HOME_DIR/sync.sh</string><string>$SLUG</string></array>
<key>RunAtLoad</key><true/>
<key>StartInterval</key><integer>1800</integer>
<key>WatchPaths</key><array><string>$SRC/Contents/Info.plist</string></array>
<key>ThrottleInterval</key><integer>60</integer>
</dict></plist>
PL

if [ "$ICON" = dark ] && ! xcode-select -p >/dev/null 2>&1; then
  echo "Note: Xcode Command Line Tools are missing, so the dark icon will be skipped."
  echo "      Run 'xcode-select --install', then re-run this installer to get it."
fi

echo "Building $NAME (about a minute)..."
"$HOME_DIR/sync.sh" "$SLUG" --force
if [ ! -d "$DEST_DIR/$NAME.app" ]; then
  echo "Build failed. Log: ~/Library/Logs/claude-clone-$SLUG.log"; tail -20 "$HOME/Library/Logs/claude-clone-$SLUG.log" 2>/dev/null; exit 1
fi

launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$UID_" "$AGENT" 2>/dev/null

if [ -n "$CLI" ]; then
  RC="$HOME/.zshrc"; LINE="alias $CLI='CLAUDE_CONFIG_DIR=\$HOME/.$CLI claude'"
  grep -qF "alias $CLI=" "$RC" 2>/dev/null || { echo "$LINE" >> "$RC"; echo "Added '$CLI' alias to ~/.zshrc (open a new terminal, run $CLI, then /login)."; }
fi

echo
echo "Done. $NAME is installed in $DEST_DIR and keeps itself updated."
echo "  1. Quit the original Claude (Cmd+Q) while you sign in, so the login lands in the right app."
echo "  2. Open \"$NAME\" and sign in with your other account."
echo "  After each Claude update it rebuilds itself (once $NAME is closed) and sends a notification."
echo "  Log: ~/Library/Logs/claude-clone-$SLUG.log   Uninstall: bash install.sh --uninstall --name \"$NAME\""
