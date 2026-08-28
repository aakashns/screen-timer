# Screen Timer

<img width="701" height="229" alt="image" src="https://github.com/user-attachments/assets/1bd751ca-7edb-49e0-b7c6-3620f68f4f02" />

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
./install.sh
```

This quits any running copy, rebuilds, copies the bundle to
`/Applications`, registers it as a login item, and relaunches it. It is safe to
re-run to update an existing install.

The app is ad-hoc signed by `build.sh`. Locally built bundles are not
quarantined, so Gatekeeper does not prompt.

Registering the login item needs automation access to System Events. macOS
prompts for this the first time; if it is denied, `install.sh` reports it and
finishes the rest of the install. To add the entry manually, or by hand later,
use System Settings > General > Login Items & Extensions > Open at Login > `+`,
and pick `/Applications/Screen Timer.app`. The equivalent command is:

```sh
osascript -e 'tell application "System Events" to make login item at end \
  with properties {path:"/Applications/Screen Timer.app", hidden:false}'
```

To check or remove the entry:

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
- **Size**: small, medium, or large, as 6%, 10%, or 15% of the screen height.
- **Transparency**: low, medium, or high, as 0.70, 0.45, or 0.25 opacity.
- **Quit Screen Timer**.

The app has no Dock icon (`LSUIElement`). The overlay's on/off state, corner,
size, and transparency are stored in `UserDefaults` and restored on launch.

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

Size and transparency are set from the menu. The values behind each choice are
in `OverlaySize.fontScale` and `OverlayTransparency.alpha` in
`Sources/Overlay.swift`. Layout constants are at the top of `OverlayController`
in the same file:

| Constant | Default | Effect |
| --- | --- | --- |
| `horizontalMargin` | `16` | Gap from the digits to the left or right screen edge |
| `verticalMargin` | `20` | Gap from the digits to the top or bottom screen edge |
| `shadowInset` | `fontSize * 0.14` | Slack around the text so the shadow is not clipped |

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
leading above the glyphs. At a 90 pt font that leading is about 39 pt, which
appears as an unwanted gap along the top edge that no margin value can remove.

The box is measured against a reference string with every digit replaced by a
zero, rather than against the live time. Digit ink widths differ even in a
monospaced-digit font, since a `1` inks about 13 pt narrower than a `0` at 90 pt,
so anchoring on the live string's own ink bounds would shift the number sideways
every time the minute changed. Digit advances are equal, so the real glyphs land
inside the reference box.

All four corners inset identically, by `horizontalMargin` on the x axis and
`verticalMargin` on the y axis. The gap is measured from the bottom of the menu
bar at the top and from the top of the Dock at the bottom, since `visibleFrame`
excludes both.

Core Text ignores the `.shadow` attribute of an attributed string, so the shadow
is applied to the `CGContext` in `draw(_:)`.

## Project layout

```
build.sh                          swiftc invocation, Info.plist, ad-hoc signing
install.sh                        quit, build, copy to /Applications, login item
Sources/main.swift                accessory activation policy, no Dock icon
Sources/AppDelegate.swift         status item, menu, timers, sleep/wake observers
Sources/Overlay.swift             panel, Core Text rendering, corners, hover
Sources/ScreenTimeTracker.swift   pmset parsing, live tracking, persistence
```
