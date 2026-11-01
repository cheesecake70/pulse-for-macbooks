#!/bin/bash
# Installs Pulse into /Applications from a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/cheesecake70/pulse-for-macbooks/main/scripts/install.sh | bash
#
# Optional settings (environment variables):
#   PULSE_REPO     owner/repo that publishes releases. CHANGE THE DEFAULT BELOW if the repo is renamed.
#   PULSE_VERSION  a version such as 1.0.0. Default: the latest release.
#   PULSE_SHA256   a checksum you obtained yourself. If set, the download must match it too.
#
# Trust model: the .sha256 file is downloaded from the same release as the zip, so it protects
# against a corrupted or truncated download only. It is NOT proof of who made the app, because
# whoever can replace the zip can replace that file too. Pulse is signed ad hoc, which only shows the
# app was not altered after signing. For a stronger check, pass PULSE_SHA256 from a trusted source.
set -euo pipefail

PULSE_REPO="${PULSE_REPO:-cheesecake70/pulse-for-macbooks}"   # <- the one place to change the repository name
PULSE_VERSION="${PULSE_VERSION:-}"
PULSE_SHA256="${PULSE_SHA256:-}"
DEST="/Applications/Pulse.app"
STAGE="/Applications/.Pulse-new.app"
OLD="/Applications/.Pulse-old.app"
BUNDLE_ID="com.mokssha.pulse"

say() { printf '%s\n' "$*"; }
die() { printf 'pulse install: %s\n' "$*" >&2; exit 1; }

# macOS 14 or newer.
[ "$(uname -s)" = "Darwin" ] || die "Pulse only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  die "Pulse needs macOS 14 (Sonoma) or newer. This Mac is on macOS $(sw_vers -productVersion), so nothing was installed."
fi

case "$PULSE_REPO" in */*) ;; *) die "PULSE_REPO should look like owner/repo." ;; esac
printf '%s' "$PULSE_REPO" | grep -Eq '^[0-9A-Za-z._-]+/[0-9A-Za-z._-]+$' || die "PULSE_REPO has unexpected characters."

if [ -n "$PULSE_VERSION" ]; then
  PULSE_VERSION="${PULSE_VERSION#v}"
  printf '%s' "$PULSE_VERSION" | grep -Eq '^[0-9A-Za-z._-]+$' || die "PULSE_VERSION may only contain letters, digits, dot, underscore and hyphen."
  name="Pulse-$PULSE_VERSION.zip"
  base="https://github.com/$PULSE_REPO/releases/download/v$PULSE_VERSION"
else
  name="Pulse.zip"
  base="https://github.com/$PULSE_REPO/releases/latest/download"
fi

if [ -n "$PULSE_SHA256" ]; then
  PULSE_SHA256="$(printf '%s' "$PULSE_SHA256" | tr 'A-F' 'a-f')"
  printf '%s' "$PULSE_SHA256" | grep -Eq '^[0-9a-f]{64}$' || die "PULSE_SHA256 must be 64 hexadecimal characters."
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"; rm -rf "$STAGE" 2>/dev/null || true' EXIT

fetch() {
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 -o "$2" "$1" \
    || die "could not download $1. Check your connection and that the release exists."
}

say "Downloading $base/$name"
fetch "$base/$name" "$work/$name"
fetch "$base/$name.sha256" "$work/$name.sha256"

actual="$(shasum -a 256 "$work/$name" | awk '{print tolower($1)}')"
expected="$(awk '{print tolower($1); exit}' "$work/$name.sha256")"
printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' || die "the release checksum file is not valid. Nothing was installed."
if [ "$expected" != "$actual" ]; then
  die "checksum mismatch (the download is damaged). Expected $expected but got $actual. Nothing was installed."
fi
if [ -n "$PULSE_SHA256" ] && [ "$PULSE_SHA256" != "$actual" ]; then
  die "the download does not match the PULSE_SHA256 you supplied. Expected $PULSE_SHA256 but got $actual. Nothing was installed."
fi
say "Download is intact."

mkdir "$work/unzipped"
ditto -x -k "$work/$name" "$work/unzipped"
[ -d "$work/unzipped/Pulse.app" ] || die "the download doesn't contain Pulse.app."

# Verify the bundle before touching the existing install.
app="$work/unzipped/Pulse.app"
codesign --verify --deep --strict "$app" 2>/dev/null || die "the app's code signature is not intact. Nothing was installed."
bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
[ "$bid" = "$BUNDLE_ID" ] || die "unexpected bundle identifier '$bid'. Nothing was installed."

# Copy to a staging path first so the old app stays until the new one is ready.
rm -rf "$STAGE" "$OLD" 2>/dev/null || sudo rm -rf "$STAGE" "$OLD"
ditto "$app" "$STAGE" 2>/dev/null || sudo ditto "$app" "$STAGE"

# Pulse is ad hoc signed (no paid developer account), so Gatekeeper would block a downloaded copy.
# curl does not set the quarantine flag, but this clears it if present, from this app only.
if xattr -p com.apple.quarantine "$STAGE" >/dev/null 2>&1; then
  say "Removing macOS's quarantine flag from the new Pulse.app."
  xattr -dr com.apple.quarantine "$STAGE"
fi

# Stop a running copy, by bundle id.
if pgrep -x Pulse >/dev/null 2>&1; then
  say "Quitting the running Pulse."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x Pulse >/dev/null 2>&1 || break
    sleep 0.5
  done
fi
STILL_RUNNING=0
pgrep -x Pulse >/dev/null 2>&1 && STILL_RUNNING=1

if [ -e "$DEST" ]; then
  say "Replacing the existing $DEST"
  mv "$DEST" "$OLD" 2>/dev/null || sudo mv "$DEST" "$OLD"
fi
if ! { mv "$STAGE" "$DEST" 2>/dev/null || sudo mv "$STAGE" "$DEST"; }; then
  [ -e "$OLD" ] && { mv "$OLD" "$DEST" 2>/dev/null || sudo mv "$OLD" "$DEST"; }
  die "could not move the new app into place. The previous version was restored."
fi
rm -rf "$OLD" 2>/dev/null || sudo rm -rf "$OLD"

if [ "$STILL_RUNNING" = "1" ]; then
  say "Installed, but the old Pulse is still running. Quit Pulse, then open it again to use the new version."
else
  say "Installed. Opening Pulse."
  open "$DEST"
fi
