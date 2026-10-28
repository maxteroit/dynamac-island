# Dynamic Island for Mac

An iPhone-style Dynamic Island for MacBooks with a notch. When nothing is going on, the island hides behind the camera housing. It expands with spring animations to show music, timers, volume and brightness, charging, and incoming messages or calls.

Native Swift 6 + SwiftUI app. No Electron, no web views, about 0% CPU when idle.

<!-- Add a demo GIF here, e.g. docs/demo.gif -->

## Features

| Feature | What it does |
|---|---|
| **Hidden when idle** | On notched MacBooks the island is invisible and blends into the physical notch |
| **Hover to expand** | Point at the notch and it opens into a panel. Move away and it collapses |
| **Now Playing** | A spectrum to the right of the notch while music plays, tinted from the album art. Hover for artwork, title, a scrubbable progress bar and playback controls. Works with Spotify, Apple Music, browsers (YouTube etc.) and any app that reports Now Playing |
| **Paused music** | Disappears from the notch 5 s after pausing. Hover to bring the player back and resume |
| **Timer** | Quick presets (1/5/15/25 min) from the hover panel. Live countdown in the notch, pause/resume/+1 min/stop, and a sound plus "Done" alert at the end |
| **Volume & brightness HUD** | Icon and level bar in the notch when you press the volume or brightness keys |
| **Battery** | Charging alert when you plug in. Warnings at 20% and 10% |
| **Messages & calls** | Notification banners from any app (WhatsApp, Messages, Telegram, Mail…) drop out of the notch as a card. Incoming calls get Accept/Decline buttons |
| **Two activities at once** | The most important activity sits beside the notch and the second one becomes a small bubble, like on iPhone |

## Requirements

- **macOS 14 Sonoma or later.** Tested on macOS 26.6 Tahoe.
- **Mac with a notch.** Other displays get a pill-shaped fallback at the top of the screen.
- **Xcode 16 or later** (Swift 6 toolchain), for building from source.
- Optional: an **Apple Development certificate** (a free Apple ID in Xcode is enough). It lets the Accessibility permission survive rebuilds, see [Signing](#signing).

## Installation

There is no prebuilt release yet, so build it from source:

```bash
git clone https://github.com/maxteroit/dynamac-island.git
cd dynamac-island

make adapter   # builds the Now Playing helper (once, ~10 s)
make run       # builds DynamicIsland.app and launches it
```

The app ends up in `build/DynamicIsland.app`. To keep it, copy it to `/Applications`:

```bash
make release
cp -R build/DynamicIsland.app /Applications/
```

The app has no Dock icon. Look for the **capsule icon** in the menu bar.

### Make targets

| Command | Description |
|---|---|
| `make adapter` | Builds `MediaRemoteAdapter.framework` from `Vendor/` with clang (no CMake needed) |
| `make build` | Debug build into `build/DynamicIsland.app` |
| `make release` | Optimized build |
| `make run` | Build, quit the running instance, launch |
| `make test` | Run the unit tests |
| `make clean` | Remove `.build/` and `build/` |

If you run `make clean`, run `make adapter` again before `make run`. Without the adapter, Now Playing falls back to Spotify and Music only (see [Troubleshooting](#troubleshooting)).

### Signing

`scripts/build-app.sh` signs the app with the first **Apple Development** identity in your keychain. If there is none, it falls back to ad-hoc signing.

This matters for the Accessibility permission (used for notifications). macOS ties the grant to the app's signature. Ad-hoc signatures change on every build, so you would have to re-grant after each rebuild.

To pick a specific identity:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make run
```

List your identities with `security find-identity -v -p codesigning`.

## Permissions

The app only asks for a permission when the feature that needs it is turned on.

| Permission | Needed for | How to grant |
|---|---|---|
| **Accessibility** | Showing messages and calls in the island | Capsule menu → Notifications → *Enable Notification Access…*, then turn on **Dynamic Island** in System Settings → Privacy & Security → Accessibility |
| **Automation** (Spotify / Music) | Playback controls, only in fallback mode without the adapter | macOS prompts on first use |

Volume, brightness, battery, timer and Now Playing (with the adapter) need no permission.

## Usage

### The island

| You do | The island does |
|---|---|
| Nothing | Stays hidden behind the notch |
| Hover over the notch | Expands into a panel after 150 ms |
| Move the pointer away | Collapses |
| Click the second activity's bubble | Opens that activity |
| Click a notification card | Opens the app it came from |

With nothing running, the hover panel shows the time, date, battery level and timer presets.

### Menu bar menu (capsule icon)

| Item | Description |
|---|---|
| Demo Live Activity | Fake activity for trying out layouts |
| Start 10s Timer | Quick way to see the timer and its "Done" alert |
| Simulate Charger | Shows the charging alert without plugging in |
| Expand on Hover | Off = hovering only grows the island slightly, and a click opens it |
| Notifications → *Enable Notification Access…* | Asks for the Accessibility permission |
| Notifications → display mode | See below |
| Notifications → Log Notification Tree (debug) | See [Troubleshooting](#troubleshooting) |
| Quit Dynamic Island | |

### Notification display modes

| Mode | Island | macOS banner |
|---|---|---|
| **Island + macOS Banner** (default) | Shows card | Shows as usual |
| **Island Only** | Shows card | Closed right away (it may flash for about 1 s, see [Limitations](#known-limitations)) |
| **macOS Banner Only** | Ignores notifications | Shows as usual |

Incoming calls always keep their macOS alert, because closing it could hang up the call.

The mode is saved. You can also set it from Terminal:

```bash
defaults write com.maxteroit.dynamicisland notificationDisplayMode islandOnly   # both | islandOnly | systemOnly
```

### Launch at login

There is no built-in setting yet. Add the app in System Settings → General → Login Items.

## Troubleshooting

**Now Playing only works with Spotify/Music, without artwork.**
The adapter was not bundled. Run `make adapter && make run`. A running app should have a child process `/usr/bin/perl …mediaremote-adapter.pl … stream`.

**Notifications do not appear in the island.**
1. Check that the capsule menu says *Notification Access Enabled*.
2. If you rebuilt with ad-hoc signing, remove **Dynamic Island** from the Accessibility list and add it again, or set up [signing](#signing).
3. Focus / Do Not Disturb hides banners, and the island only sees banners macOS actually shows.
4. Set an app's notification style to *Banners* or *Alerts*, not *None*, in System Settings → Notifications.

**A banner or call is not recognised after a macOS update.**
Turn on *Log Notification Tree (debug)*, trigger a notification, and look at `~/Library/Logs/DynamicIsland/notification-ax.txt`. It shows the structure the parser expects (`AXNotificationCenterBanner`, fields tagged `title` / `subtitle` / `body`). The file contains notification text, so turn the option off and delete the file afterwards.

**Brightness HUD does not show.**
It only works for the built-in display. The app reads brightness through the private `DisplayServices` framework, which a future macOS could change.

**Reading logs.**

```bash
/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.maxteroit.dynamicisland"' --style compact
```

Use the full path: in zsh, plain `log` is a shell builtin.

## Known limitations

- **The macOS banner flashes in Island Only mode.** The app closes it within about 40 ms, but the macOS close animation takes about 1 s. Third-party apps cannot stop a banner from appearing.
- **Incoming calls are only lightly tested.** Detection relies on Accept/Decline buttons in the alert. If it fails for you, please open an issue with a (redacted) debug tree.
- **Private APIs.** Now Playing (MediaRemote via the adapter) and brightness (DisplayServices) use undocumented frameworks that may break in future macOS releases. Each module turns itself off when its API is missing.
- **The system volume/brightness HUD still appears.** The island only shows the change, it does not replace the macOS HUD.
- **Not sandboxed.** It cannot be shipped through the Mac App Store.

## Privacy

- Everything runs locally. The app makes **no network requests**.
- Notification content is read only to draw the card, and is not stored. The optional debug tree is the one exception: it writes to a local file and is off by default.
- Accessibility access is used only to read and press elements in Notification Center.

## How it works

```
CoreAudio · IOKit · DisplayServices · MediaRemote (adapter) · Notification Center (AX)
                │ async callbacks
                ▼
        Modules (Timer, NowPlaying, Battery, HUD, Notifications)
                │
                ▼
   ActivityManager ── priority queue: primary · secondary · transient · banner
                │
                ▼
   IslandViewModel (@Observable) ◄── pointer tracking
                │
                ▼
   SwiftUI IslandView ── spring morphs inside a fixed-size NSPanel above the menu bar
```

- **Window.** A borderless, non-activating `NSPanel` sits above the menu bar on every Space. The window never resizes; SwiftUI animates the shape inside it. Outside the island, clicks pass through to the menu bar.
- **Shape.** `IslandShape` draws the notch outline (flared top corners, rounded bottom) and animates its radii.
- **Priority.** The most important activity is shown beside the notch and the second as a bubble. Short alerts (HUD, charging) temporarily replace them. Notification cards take precedence over everything.

### Adding a module

Make an `@Observable` class conform to `LiveActivity`, then register it in `AppDelegate`:

```swift
@MainActor
@Observable
final class MyActivity: LiveActivity {
    let id = "my-activity"
    let priority = ActivityPriority.normal
    private(set) var activatedAt: Date?           // set to .now to show, nil to hide

    func compactLeading() -> AnyView { AnyView(Image(systemName: "star.fill")) }
    func compactTrailing() -> AnyView { AnyView(Text("Hi")) }
    func minimal() -> AnyView { AnyView(Image(systemName: "star.fill")) }
    func expanded() -> AnyView { AnyView(Text("Expanded content")) }
}
```

Optional: `compactStyle = .trailingOnly` to use only the right side of the notch, and `offersExpandedWhileInactive` to open on hover while hidden. For one-off alerts, call `activityManager.present(TransientEvent(...))` or `present(BannerEvent(...))`.

## Project structure

```
Sources/DynamicIsland/
├── App/            entry point, app delegate, menu bar menu
├── Window/         NSPanel, positioning, notch geometry, click-through
├── Core/           state, layout metrics, ActivityManager, LiveActivity protocol
├── UI/             island shape, root view, home panel, shared components
└── Modules/
    ├── NowPlaying/     adapter + Spotify/Music fallback, player UI
    ├── Timer/
    ├── Battery/
    ├── HUD/            volume (CoreAudio), brightness (DisplayServices)
    ├── Notifications/  Notification Center via Accessibility
    └── Demo/
Tests/DynamicIslandTests/   unit tests (Swift Testing)
Vendor/mediaremote-adapter/ vendored Now Playing helper (BSD-3-Clause)
scripts/                    app bundling and adapter build
```

## Roadmap

- [ ] Settings window (toggle modules, hover delay, launch at login)
- [ ] Calendar: upcoming meeting with a *Join* button
- [ ] Mic/camera in-use indicator
- [ ] AirPods / Bluetooth connection alert
- [ ] File shelf with AirDrop (drag files onto the notch)
- [ ] Download progress
- [ ] Hide in full-screen apps, multi-display options
- [ ] Signed and notarized release builds with auto-update

The full plan is in [PLAN.md](PLAN.md) (Indonesian).

## Contributing

Issues and pull requests are welcome. Before opening a PR:

```bash
make test
```

Keep modules self-contained in `Modules/` and talk to the island only through `LiveActivity` / `ActivityManager`.

## Credits

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (BSD-3-Clause). It provides Now Playing on macOS 15.4+. Vendored in `Vendor/mediaremote-adapter`, with its license at `Vendor/mediaremote-adapter/LICENSE`.
- Inspired by Apple's Dynamic Island and by open-source notch apps such as [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## License

[MIT](LICENSE) © 2026 Maxteroit

The vendored `mediaremote-adapter` keeps its own [BSD-3-Clause license](Vendor/mediaremote-adapter/LICENSE).
