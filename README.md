# BitFi

Native macOS battery monitor with charge-threshold reminders. Built with Swift, SwiftUI, IOKit, ServiceManagement, UserNotifications. No Electron, web views, private charger APIs, privileged helpers, dependencies.

## What works

- Live battery percentage, charge state, power source, time estimates, health, condition, temperature, voltage, current, cycle count when macOS reports each field.
- Automatic IOKit power-source updates, wake refresh, menu bar extra with live status.
- Persistent 50–100% custom threshold; 70%, 80%, 85%, 90% presets.
- Real local notification at threshold. `Charge to 100% This Session` pauses reminder until power disconnects.
- Login-at-login via `SMAppService.mainApp`.
- Native settings: General, Battery, Menu Bar, Notifications, About.

## Important limitation

Public macOS APIs expose battery monitoring, not arbitrary hardware charge caps. BitFi never claims to stop charging; it provides honest threshold reminders so user can unplug power. It does not modify firmware or use undocumented IORegistry controls.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later

## Build and run

1. Open `BitFi.xcodeproj` in Xcode.
2. Select `BitFi` scheme, then **Run**.
3. If Xcode asks for signing, choose local development team for installed builds.

Command-line compile check:

```sh
swift build
```

## Project layout

```text
BitFi/
  Models/       Battery snapshot domain model
  Services/     IOKit monitor, reminders, notifications, settings, login item
  Views/        SwiftUI window, menu bar, settings
  Resources/    App metadata
```

## Release

`v1.0.0` publishes complete source and Xcode project. Build locally in Xcode for unsigned development use; distribute signed/notarized `.app` only from trusted release pipeline.
