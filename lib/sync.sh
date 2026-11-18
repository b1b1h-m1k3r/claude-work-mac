#!/bin/bash
# Rebuilds the cloned Claude app whenever the original Claude.app changes.
# Usage: sync.sh <slug> [--force]
# Runs from launchd (login, every 30 min, and whenever Claude.app's Info.plist changes).
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
RECIPE=2   # bump when the build steps change, so existing clones get rebuilt

HERE="$(cd "$(dirname "$0")" && pwd)"
SLUG="${1:?usage: sync.sh <slug> [--force]}"
FORCE="${2:-}"
CONF="$HERE/instances/$SLUG.conf"
[ -f "$CONF" ] || { echo "no such instance: $SLUG" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"   # NAME, SRC, DEST_DIR, ICON (dark|original)

DST="$DEST_DIR/$NAME.app"
TMP="$DEST_DIR/.$NAME.new.app"
DATA="$HOME/Library/Application Support/$NAME"
STAMP="$HERE/instances/$SLUG.stamp"
LOG="$HOME/Library/Logs/claude-clone-$SLUG.log"
WORK="$HERE/tmp/$SLUG"
LOCK="$HERE/tmp/$SLUG.lock"
PB=/usr/libexec/PlistBuddy
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

log() { echo "$(date '+%F %T') $*" >> "$LOG"; [ -t 1 ] && echo "$*"; return 0; }

[ -d "$SRC" ] || exit 0
SP="$SRC/Contents/Info.plist"
ver="$($PB -c 'Print CFBundleVersion' "$SP" 2>/dev/null)-$($PB -c 'Print CFBundleShortVersionString' "$SP" 2>/dev/null)"
[ "$ver" != "-" ] || exit 0
want="$ver|$RECIPE"
if [ "$FORCE" != "--force" ] && [ -d "$DST" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$want" ]; then exit 0; fi

mkdir -p "$HERE/tmp"
if ! mkdir "$LOCK" 2>/dev/null; then
  # stale lock (older than 30 min) is removed, otherwise another run is active
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then rm -rf "$LOCK"; mkdir "$LOCK" || exit 0; else exit 0; fi
fi
trap 'rm -rf "$LOCK" "$WORK" "$TMP"' EXIT

# The source must be fully installed (a half-written update fails verification). Retry next trigger.
if ! codesign --verify --deep "$SRC" 2>/dev/null; then log "Claude.app is not fully installed yet, will retry"; exit 0; fi
# Never swap the app while it is open. Retry next trigger.
if pgrep -f "$DST/Contents/MacOS" >/dev/null; then log "$NAME is open, will retry after it is closed"; exit 0; fi

log "Building $NAME from Claude $ver"
rm -rf "$TMP" "$WORK"; mkdir -p "$WORK"
mkdir -p "$DEST_DIR" || { log "cannot create $DEST_DIR"; exit 1; }
ditto "$SRC" "$TMP" || { log "copy failed"; exit 1; }
xattr -dr com.apple.quarantine "$TMP" 2>/dev/null

C="$TMP/Contents"; P="$C/Info.plist"
exe="$($PB -c 'Print CFBundleExecutable' "$P")"
$PB -c "Set CFBundleName $NAME" -c "Set CFBundleIdentifier com.anthropic.claude.$SLUG" "$P"
$PB -c "Set CFBundleDisplayName $NAME" "$P" 2>/dev/null || $PB -c "Add CFBundleDisplayName string $NAME" "$P"
$PB -c "Delete CFBundleIconName" "$P" 2>/dev/null   # forces the loose .icns instead of Assets.car
icon="$($PB -c 'Print CFBundleIconFile' "$P" 2>/dev/null)"; icon="${icon%.icns}"
[ -n "$icon" ] || { icon=electron; $PB -c "Add CFBundleIconFile string electron" "$P"; }

# Dark icon, generated from this Mac's own Claude icon (skipped if Swift is unavailable)
if [ "$ICON" = "dark" ]; then
  src_icns="$SRC/Contents/Resources/$icon.icns"
  if [ -f "$src_icns" ] && xcode-select -p >/dev/null 2>&1 \
     && swift "$HERE/make-icon.swift" "$src_icns" "$WORK/dark.png" >>"$LOG" 2>&1; then
    mkdir -p "$WORK/d.iconset"
    for s in 16 32 128 256 512; do
      sips -z $s $s "$WORK/dark.png" --out "$WORK/d.iconset/icon_${s}x${s}.png" >/dev/null
      sips -z $((s*2)) $((s*2)) "$WORK/dark.png" --out "$WORK/d.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$WORK/d.iconset" -o "$WORK/dark.icns" && cp "$WORK/dark.icns" "$C/Resources/$icon.icns"
  else
    log "dark icon skipped (needs Xcode Command Line Tools: xcode-select --install); keeping the original icon"
  fi
fi

# Electron looks for helper apps named "<CFBundleName> Helper*", so rename them to match.
for h in "$C/Frameworks/$exe Helper"*.app; do
  [ -d "$h" ] || continue
  b="$(basename "$h" .app)"; suffix="${b#"$exe "}"; new="$NAME $suffix"
  hp="$h/Contents/Info.plist"; hexe="$($PB -c 'Print CFBundleExecutable' "$hp")"
  mv "$h/Contents/MacOS/$hexe" "$h/Contents/MacOS/$new"
  $PB -c "Set CFBundleExecutable $new" -c "Set CFBundleName $new" "$hp"
  $PB -c "Set CFBundleDisplayName $new" "$hp" 2>/dev/null
  mv "$h" "$C/Frameworks/$new.app"
done

# Launcher wrapper: always starts the real binary with its own data directory
mv "$C/MacOS/$exe" "$C/MacOS/$exe.real"
cat > "$C/MacOS/$exe" <<WRAP
#!/bin/bash
APP_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$APP_DIR/$exe.real" --user-data-dir="$DATA" "\$@"
WRAP
chmod +x "$C/MacOS/$exe"

codesign --force --deep --sign - "$TMP" >>"$LOG" 2>&1 || { log "codesign failed"; exit 1; }
rm -rf "$DST" && mv "$TMP" "$DST" || { log "could not replace $DST"; exit 1; }
touch "$DST"
"$LSREG" -f "$DST" >/dev/null 2>&1
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null
killall Dock 2>/dev/null
echo "$want" > "$STAMP"
log "Done: $NAME is up to date with Claude $ver"
osascript -e "display notification \"Rebuilt for Claude $ver\" with title \"$NAME updated\"" >/dev/null 2>&1
exit 0
