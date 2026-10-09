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

## Your data

Tasks, notes, and logos are stored locally on your Mac in
`~/Library/Application Support/Tapusin-Tapusin/`. Nothing is synced or shared,
and none of it is part of this repository.

## License

MIT
