# Screen Timer

A macOS menu bar app that displays how long the screen has been on today, as a
large semi-transparent `HH:MM` overlay in a corner of the screen.

The overlay is click-through and fades out while the cursor is over it, so it
never blocks the content or the interface underneath it.

## Requirements

macOS 13 or later, and a Swift toolchain (Xcode or the Command Line Tools:
`xcode-select --install`). There is no Xcode project; `build.sh` calls `swiftc`
directly and assembles the app bundle.

## Build

```sh
git clone https://github.com/aakashns/screen-timer.git
cd screen-timer
./build.sh
open "build/Screen Timer.app"
```

## Install

```sh
./build.sh
pkill -f "Screen Timer.app"                       # if an older copy is running
cp -R "build/Screen Timer.app" /Applications/
open "/Applications/Screen Timer.app"
```

The app is ad-hoc signed by `build.sh`. Locally built bundles are not
quarantined, so Gatekeeper does not prompt.

## Run at login

Use System Settings > General > Login Items & Extensions > Open at Login > `+`,
and pick `/Applications/Screen Timer.app`. Or from a terminal:

```sh
osascript -e 'tell application "System Events" to make login item at end \
  with properties {path:"/Applications/Screen Timer.app", hidden:false}'
```

macOS asks once to let the terminal control System Events. To check or remove
the entry:

```sh
osascript -e 'tell application "System Events" to get the name of every login item'
osascript -e 'tell application "System Events" to delete login item "Screen Timer"'
```

`SMAppService` is not used, because it requires a signed bundle and fails
silently on ad-hoc signed builds.

## Usage

The menu bar item opens a menu with:

- The current total for today.
- **Show Overlay**, which toggles the overlay. While the overlay is off, the
  menu bar item shows the time next to its icon, so the number is never on
  screen in two places at once.
- **Position**, a submenu for the four screen corners.
- **Quit Screen Timer**.

The app has no Dock icon (`LSUIElement`). The overlay's on/off state and corner
are stored in `UserDefaults` and restored on launch.

## How the time is measured

Two sources, in `Sources/ScreenTimeTracker.swift`. The larger of the two wins:

1. `pmset -g log`, which records `Display is turned on` and `Display is turned
   off` events. Today's on-intervals are integrated from local midnight, so the
   total is already correct at launch rather than starting from zero. The log is
   re-read once a minute and on every sleep or wake notification.
2. Live accumulation while the app runs, using `CGDisplayIsAsleep`, persisted
   per day in `UserDefaults`. This covers the case where `pmset`'s log has been
   rotated away, and it survives app restarts.

Deltas larger than five seconds are discarded from the live count, since they
indicate the process was suspended rather than the screen being on. Only the
last 14 days are kept in storage. The total resets at local midnight.

## Configuration

Constants at the top of `OverlayController` in `Sources/Overlay.swift`:

| Constant | Default | Effect |
| --- | --- | --- |
| `fontScale` | `0.10` | Font size as a fraction of the screen height |
| `restingAlpha` | `0.45` | Overlay opacity when not hovered |
| `horizontalMargin` | `16` | Gap from the digits to the left or right screen edge |
| `verticalMargin` | `6` | Gap from the digits to the top or bottom screen edge |
| `shadowInset` | `12` | Slack around the text so the shadow is not clipped |

There is no plate or border behind the digits, just white text with a soft
shadow, which is what keeps them readable over light content. Set `shadowBlur`
to `0` in `layout()` for bare text.

## Implementation notes

The overlay is a borderless `NSPanel` at `.statusBar` level with
`ignoresMouseEvents = true`, and a collection behavior of
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, so it
appears on every Space and over full-screen apps. It is positioned against
`NSScreen.visibleFrame`, which already excludes the menu bar and the Dock.

Because the panel ignores mouse events it receives no enter and exit callbacks,
so hover is detected by polling `NSEvent.mouseLocation` every 100 ms against the
panel's frame.

Margins are measured against the ink bounds of the digits, not the text box.
`DigitsView` draws the line with Core Text and pins `CTLineGetImageBounds` to a
known inset, because an `NSTextField` sized with `sizeToFit` carries the font's
leading above the glyphs, which appears as an unwanted gap along the top edge.
Core Text ignores the `.shadow` attribute of an attributed string, so the shadow
is applied to the `CGContext` in `draw(_:)`.

## Project layout

```
build.sh                          swiftc invocation, Info.plist, ad-hoc signing
Sources/main.swift                accessory activation policy, no Dock icon
Sources/AppDelegate.swift         status item, menu, timers, sleep/wake observers
Sources/Overlay.swift             panel, Core Text rendering, corners, hover
Sources/ScreenTimeTracker.swift   pmset parsing, live tracking, persistence
```
