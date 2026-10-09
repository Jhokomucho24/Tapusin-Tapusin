# Tapusin-Tapusin

A lightweight macOS menu bar task manager built with SwiftUI.

## Requirements

- macOS 14 or later
- Swift 5.10+ (Xcode Command Line Tools is enough: `xcode-select --install`)

## Build

```sh
./scripts/build-app.sh
```

This produces `build/Tapusin-Tapusin.app`. Drag it into `/Applications` and open it.
The first time, macOS may block it because it isn't notarized. Right-click the app
and choose **Open**.

## Privacy and security

- **Local only.** Tasks, notes, and logos are saved on your Mac in
  `~/Library/Application Support/Tapusin-Tapusin/`. The app has no network code:
  nothing is uploaded, synced, or sent anywhere.
- **Yours only.** Each person who builds the app gets an empty, separate copy.
  This repository contains code only, never anyone's tasks or notes, and
  `.gitignore` blocks app data files from being committed by mistake.
- **Owner-only files.** The data folder is locked to your macOS user account
  (folders `700`, files `600`), so other accounts on the same Mac can't read it.
- **Encrypted at rest** when FileVault is on (System Settings → Privacy & Security → FileVault).
- **Notifications** show task titles. To hide them on the lock screen, set
  System Settings → Notifications → Show previews to **When Unlocked**.

## License

MIT
