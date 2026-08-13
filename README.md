# Shipped

A personal accountability app: it asks what you did today, reverse-engineers your goals into a daily plan, and stays visible until you check in.

## What this is

Most goal trackers let you write a plan once and forget it. Shipped works backward from a deadline (or a recurring routine) to tell you exactly what to do *today*, tracks a streak, and won't let you quietly fall behind without noticing.

## Features

- **Deadline goals** — describe what you're chasing, and Claude reverse-engineers a day-by-day plan around your real time capacity
- **Recurring routines** — for things with no end date (a workout split, a daily habit), scheduled by weekday
- **Capture** — paste notes, a brain dump, or an existing plan; nothing is created until you sign off on it
- **Coach** — a chat to talk through your execution, not motivate you
- **Lock/home screen widget** — an interactive progress grid you can check off without opening the app
- **Mac companion** — a full window app plus a menu bar nudge that pulses until you check in
- **Sync** — your goals and routines follow you between iPhone and Mac

## Architecture

SwiftUI + SwiftData across an iOS app, a widget extension, and a standalone macOS app, generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. Plan generation runs on the Claude API directly. Cross-device sync runs on Supabase (Postgres + REST).

## Setup

1. Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2. Copy `Shared/Secrets.swift.example` → `Shared/Secrets.swift` and fill in your own API keys
3. Copy `Config.xcconfig.example` → `Config.xcconfig` and fill in your Apple Developer Team ID
4. Run `xcodegen generate`, open `Shipped.xcodeproj`, and build

## Known limitations

Built on a free Apple Developer account: no App Store or TestFlight distribution, and on-device builds need re-signing roughly every 7 days.

## License

None yet — personal project.
