# Screen Timer

Shows how long your screen has been on today, as large semi-transparent digits.

- [`macos/`](macos/) — a menu bar app with a click-through overlay pinned to a
  screen corner, above every other window.
- [`ios/`](ios/) — Lock Screen and Home Screen widgets that tick live, backed by
  Apple's Screen Time API. **Unfinished and never compiled**: it needs a paid
  Apple Developer membership to build at all. The design and the reasoning behind
  it are written up in [`ios/README.md`](ios/README.md).

## The two apps are not ports of each other

They measure different things by different means, because the platforms allow
very different things. This is worth understanding before reading either
subdirectory.

| | macOS | iOS |
| --- | --- | --- |
| Where the number appears | Floating overlay over all apps | Widgets, plus the app itself |
| Where the number comes from | `pmset -g log` and `CGDisplayIsAsleep` | Screen Time threshold events |
| What it measures | Time the display was powered on | Time spent in apps and on websites |
| Accuracy | Second-level | Confirmed every 15 min, interpolated between |
| Build | `swiftc`, no Xcode project | Xcode project with three app extensions |

On macOS an app can read display power state directly and draw a borderless
window above everything, so the overlay is exactly as accurate and as visible as
you would want.

iOS allows neither. Third-party apps cannot draw over other apps, and an app
receives no screen on/off events while backgrounded, so the macOS approach has no
equivalent. The closest available surface is a widget, and the only device-wide
usage figure available is Screen Time's — which is reported through a deliberately
narrow channel. [`ios/README.md`](ios/README.md) explains what that channel is and
what it costs.

## Layout

```
macos/    menu bar app, overlay panel, pmset parsing
ios/      SwiftUI app, Screen Time monitor, report and widget extensions
```
