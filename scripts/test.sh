#!/bin/bash
# Command Line Tools keeps Testing.framework outside the default search paths. The manifest
# handles the test target's own flags, but SwiftPM's generated runner module only sees global
# flags. Without -F it silently runs zero tests and exits 0, so always test through this script.
# The flag is only added when the folder exists (full Xcode doesn't need it).
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [ -d "$F" ]; then
  exec swift test -Xswiftc -F -Xswiftc "$F" "$@"
fi
exec swift test "$@"
