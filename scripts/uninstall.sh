#!/bin/bash
# Quits Pulse, removes its login item (best effort) and deletes /Applications/Pulse.app.
# Logs and saved settings are kept unless you pass --purge.
# Works from a clone or straight from the web, no repo needed:
#   curl -fsSL https://raw.githubusercontent.com/cheesecake70/pulse-for-macbooks/main/scripts/uninstall.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/cheesecake70/pulse-for-macbooks/main/scripts/uninstall.sh | bash -s -- --purge
# (cheesecake70/pulse-for-macbooks is the default repo name; change it in these lines if the repo is renamed.)
set -uo pipefail

APP="/Applications/Pulse.app"
BUNDLE_ID="com.mokssha.pulse"
purge=0
for a in "$@"; do [ "$a" = "--purge" ] && purge=1; done

say() { printf '%s\n' "$*"; }

if pgrep -x Pulse >/dev/null 2>&1; then
  say "Quitting Pulse."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pgrep -x Pulse >/dev/null 2>&1 && pkill -x Pulse
fi

# The login item is registered by the app itself (SMAppService). Ask the installed copy to drop it.
# If that isn't possible, macOS forgets it once the app is gone; check System Settings > General > Login Items.
if [ -x "$APP/Contents/MacOS/Pulse" ]; then
  "$APP/Contents/MacOS/Pulse" --unregister-login >/dev/null 2>&1 || true
fi

if [ -d "$APP" ]; then
  rm -rf "$APP" 2>/dev/null || sudo rm -rf "$APP"
  say "Removed $APP"
else
  say "$APP wasn't installed."
fi

if [ "$purge" -eq 1 ]; then
  rm -f "$HOME/Library/Logs/Pulse-actions.log"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  say "Removed Pulse's log and saved settings."
else
  say "Kept ~/Library/Logs/Pulse-actions.log and your settings. Run with --purge to remove them too."
fi
