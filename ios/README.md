# Screen Timer for iOS

Lock Screen and Home Screen widgets showing how long your screen has been on
today, plus an app that displays the same figure in large digits.

> **Status: unfinished, and never compiled.** This is a design that was worked out
> and written down, not a working app. It is parked because shipping it needs a
> paid Apple Developer Program membership ($99/year) — App Groups and Family
> Controls both require one, and the widget cannot work without them. See
> [Requirements](#requirements).
>
> What *is* verified: the shared tick arithmetic is compiled and tested by
> `./test.sh`, which needs no Xcode, and the generated Xcode project is
> structurally valid. Everything touching SwiftUI, WidgetKit or DeviceActivity has
> never been through a compiler and should be assumed to have build errors.

## The constraint everything else follows from

Screen Time data cannot reach a widget. There is no API that returns "minutes of
screen time today" as a number your code can hold.

What exists instead is `DeviceActivityReport`: a SwiftUI view, rendered inside an
extension whose sandbox blocks *every* way out of its own address space. Network
requests, app-group `UserDefaults`, app-group file writes, local notifications,
`UIPasteboard` and iCloud key-value storage have all been tried and all are
blocked. [Apple's documentation](https://developer.apple.com/documentation/familycontrols)
states the intent plainly: the sandbox exists to prevent "moving sensitive
content outside the extension's address space." Its views also throw runtime
errors if you try to host them inside WidgetKit.

So the accurate total can be *displayed in the app* and nowhere else.

A second constraint compounds it: WidgetKit will not re-render a widget every
second. Refreshes are budgeted at a few dozen a day and the schedule is the
system's to decide, so no timeline you return can produce a live-updating number.

## How this app works around both

Two mechanisms, layered.

**A staircase of confirmations.** `DeviceActivityMonitor` is a *different* Screen
Time extension point from the report one, and it is allowed to write to a shared
app group. It cannot be asked for a total, but it can be told to call you when
usage *crosses a threshold*. So the app registers a ladder of thresholds — 15
minutes, 30, 45, and so on — and each time one fires, the extension writes that
figure into the app group where the widget can read it. Real device-wide Screen
Time data, arriving in 15-minute steps.

**A timer that ticks itself.** `Text(timerInterval:)` is drawn and animated by
the system rather than by a widget refresh, so it ticks every second with no
refreshes at all. Its limitation is that it can only count from a fixed anchor,
which is exactly enough: the anchor is placed `confirmed` seconds *before* the
moment the last milestone landed, so the timer reads the confirmed total at that
instant and carries on from there.

Between milestones the widget therefore ticks as though the screen stayed on. The
tick is frozen one step later, where the next milestone should have arrived — so
a long screen-off stretch overstates the total by at most 15 minutes before the
display simply stops moving, and the next confirmation corrects it.

There is a neat coincidence that makes the optimism reasonable: **a widget is
only ever visible when the screen is on.** When you are looking at the ticking
number, the thing it is counting is genuinely happening.

### What it measures

Screen Time measures time spent in apps and on websites, not display power
state. It is the figure in Settings → Screen Time, and it is what "screen on
today" means in this app — a slightly different quantity from the macOS build's,
which reads actual display power events.

## Requirements

- iOS 17 or later.
- **Xcode.** Unlike the macOS build, this cannot be built with a bare `swiftc`
  call: three app extensions have to be embedded, signed and provisioned.
- **A paid Apple Developer Program membership** ($99/year). Not optional: a free
  personal team cannot use capabilities that require entitlements, and this app
  needs two — App Groups and Family Controls. The App Group is what carries data
  from the monitor extension to the widget, and nothing else can do that job, so
  there is no free-account version of this app. The Simulator will run it without
  any account, but Screen Time reports no real usage there.

## Build

```sh
cd ios
open ScreenTimer.xcodeproj
```

Set a team under Signing & Capabilities for **all four targets**, then run.

`ScreenTimer.xcodeproj` is generated from [`project.yml`](project.yml) by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) but committed, so XcodeGen is
only needed if you change the target layout:

```sh
brew install xcodegen
./build.sh          # regenerates, runs the tests, then xcodebuild
```

### Tests

```sh
./test.sh
```

Checks the tick arithmetic the widget and the app share. Runs without Xcode and
without an iOS SDK — everything under `Shared/` is Foundation-only by design, so
it compiles for the host Mac.

## Identifiers

Bundle IDs and App Group IDs must be unique across all of Apple, so the defaults
here will not work for anyone else. The prefix is hardcoded in `project.yml`,
three entitlements files and one Swift constant, and all of them have to agree or
the widget silently reads an empty app group. To change all five at once:

```sh
./set-identifiers.sh com.yourname
```

## Entitlements

Screen Time needs `com.apple.developer.family-controls`. This repo uses the
`.development` variant, which needs **no Apple approval** — but it still needs a
paid membership, as does the App Group.

Shipping requires the non-development entitlement, requested via
[Apple's form](https://developer.apple.com/contact/request/family-controls-distribution)
and reviewed by hand — commonly a few days to a few weeks. Every extension bundle
ID carrying the frameworks must be covered by the request.

The app group is `group.com.aakashns.screentimer`, declared by the app, the
monitor extension and the widget. The report extension deliberately does not
declare it, since it could not use it anyway.

## Setup on device

1. Run the app and grant Screen Time access when prompted. Without it no
   thresholds are registered and the widget stays at `0:00:00`.
2. Add the widget: long-press the Home Screen or Lock Screen → **+** → Screen
   Timer. `systemSmall`, `systemMedium`, `accessoryCircular`,
   `accessoryRectangular` and `accessoryInline` are supported.
3. The first confirmation arrives after 15 minutes of use. Until then the widget
   ticks from zero.

The **Screen Time** button in the app shows today's true total via the report
extension, which is the way to check the widget against reality.

## Known rough edges

These are properties of the Screen Time API, not of this code, and are the
reason the app treats confirmations as a floor rather than as truth.

- `eventDidReachThreshold` has a history of firing late, firing twice, and
  firing with zero minutes recorded. The store never lowers the total, so a
  duplicate or out-of-order event is harmless.
- `DeviceActivity` has an undocumented ceiling on events per activity. If no
  confirmation ever arrives, lower `Milestones.count` in
  [`Shared/Milestones.swift`](Shared/Milestones.swift) first.
- Monitoring is a daily interval from 00:00 to 23:59. An interval whose end
  equals its start is rejected, so the last minute of the day goes unmeasured.
- Past `Milestones.step * Milestones.count` (8 hours by default) no further
  confirmation arrives and the widget shows the final milestone plus one step.

## Configuration

Both constants are in [`Shared/Milestones.swift`](Shared/Milestones.swift):

| Constant | Default | Effect |
| --- | --- | --- |
| `step` | `15 * 60` | Gap between confirmations, and the widget's worst-case error |
| `count` | `32` | How many thresholds to register; `step * count` is the daily coverage |

Lowering `step` tightens accuracy but needs a proportionally larger `count` for
the same coverage, which risks the undocumented event ceiling.

The in-app display's position, size and transparency are in the Settings sheet.
The transparency scale matches the macOS build, so a given setting looks the same
on both.

## Layout

```
project.yml                            XcodeGen spec: four targets, entitlements
build.sh                               regenerate, test, xcodebuild
test.sh                                tick arithmetic, no Xcode needed
set-identifiers.sh                     rewrite the bundle ID prefix everywhere

Shared/Milestones.swift                the threshold ladder
Shared/ScreenTimeStore.swift           app-group storage, tick maths
Tests/main.swift                       checks for the above

App/ScreenTimerApp.swift               entry point
App/ScreenTimeMonitor.swift            authorization, threshold registration
App/RootView.swift                     digits, settings and report sheets
App/BigDigitsView.swift                the large ticking readout
App/SettingsView.swift                 position, size, transparency
App/Appearance.swift                   the ported macOS overlay settings

Monitor/                               DeviceActivityMonitor: writes milestones
Report/                                DeviceActivityReport: shows the true total
Widget/ScreenTimerWidget.swift         the self-ticking widgets
ScreenTime/ReportContext.swift         report context shared by app and extension
```

`Shared/` is Foundation-only so it can compile into the widget, which links
neither DeviceActivity nor FamilyControls.
