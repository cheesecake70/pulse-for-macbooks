# Privacy

Pulse keeps everything on your Mac. It has no network code and sends nothing anywhere.

## What Pulse reads

Pulse only looks at the state of your Mac, using macOS's own APIs and built-in tools:

- **Memory pressure** and **thermal state** (kernel and `ProcessInfo` values).
- **Disk space** on the startup volume, and `diskutil info /` for disk health.
- **Running apps** by name and bundle identifier, and their memory and CPU use, so it can suggest quitting one.
- **Battery** condition, through `system_profiler SPPowerDataType`. Skipped on Macs without a battery.
- **Protection settings**, read-only: FileVault (`fdesetup status`), the firewall (`socketfilterfw --getglobalstate`), and Time Machine (`tmutil latestbackup`, `tmutil destinationinfo`).
- **Software updates**, read-only: the system's `/Library/Preferences/com.apple.SoftwareUpdate.plist` is read directly as a file (no network, no update check).
- **Uptime** and **Low Power Mode**.

Pulse does not read your files, documents, browsing history, passwords, keystrokes, screen contents or microphone or camera.

## What Pulse stores

- **Action log:** `~/Library/Logs/Pulse-actions.log`. One line for each action you clicked (quit an app, relaunch Finder, restart, open a Settings page). It records what was asked and the outcome. You can read it or delete it at any time.
- **Settings and snoozes** in the app's preferences (`UserDefaults`, domain `com.mokssha.pulse`):
  - `welcomeSeen`: whether the first-run welcome has been shown.
  - `startAtLogin`: your start-at-login choice.
  - `notify`: whether the red-state notification is on.
  - `snoozes`: which fixes you snoozed, and until when.
  - `lastRedNotice`: when the red-state notification last fired, so it fires at most once every 6 hours.

Nothing is uploaded. Pulse keeps no history of health scores.

## Removing it

`bash scripts/uninstall.sh` (or the one-line `curl` command in the README) removes the app and keeps the log and settings. Adding `--purge` also deletes `~/Library/Logs/Pulse-actions.log` and the `UserDefaults` entries above.
