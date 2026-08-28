#!/bin/bash
# Quits the installed app, rebuilds from source, copies it into /Applications,
# registers it as a login item, and relaunches it.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Screen Timer"
SRC="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

echo "==> Quitting any running copy"
if pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1; then
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    pkill -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1 || true
    for _ in $(seq 1 25); do
        pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1; then
        echo "    could not quit the running app; aborting" >&2
        exit 1
    fi
    echo "    quit"
else
    echo "    not running"
fi

echo "==> Building"
./build.sh

echo "==> Installing to ${DEST}"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "==> Registering login item"
# `exists` doubles as the permission check: if the terminal has not been granted
# automation access to System Events, this fails instead of the write failing
# halfway through.
if osascript -e 'tell application "System Events" to return (exists login item "'"${APP_NAME}"'")' >/dev/null 2>&1; then
    # Delete first so a stale entry pointing at an old path is replaced.
    osascript -e 'tell application "System Events" to delete login item "'"${APP_NAME}"'"' >/dev/null 2>&1 || true
    osascript -e 'tell application "System Events" to make login item at end with properties {path:"'"${DEST}"'", hidden:false}' >/dev/null
    echo "    registered"
else
    echo "    could not reach System Events, so the login item was not set." >&2
    echo "    Grant your terminal automation access when macOS prompts, then re-run," >&2
    echo "    or add it by hand in System Settings > General > Login Items & Extensions." >&2
fi

echo "==> Launching"
open "$DEST"

echo "Done. ${APP_NAME} is installed and will start at login."
