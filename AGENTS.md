# Agent guide for Routey (Swift and SwiftUI)

This repository contains a Swift package (`RouteyKit`) plus thin app shells, written with Swift and SwiftUI. Routey is an **offline-first iOS app for rural mail carriers** — *sort → snap → deliver*. Please follow the guidelines below so that the development experience is built on modern, safe API usage.

> **Carrier-agnostic, always.** This repo is **public**. Never commit the employer's name, real route data, real street/site/place names, civic numbers, or carrier-specific jargon — in code, docs, sample/seed/test data, or copy. Use invented placeholders. See `CLAUDE.md`.


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SQLiteData/GRDB, CloudKit, and Vision. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines. Routey is **offline-first**: every feature must work in a dead zone; sync is a background nicety layered on top of a local source of truth, and the UI never blocks on the network.


## Core instructions

- Target **iOS 18.0** for the app. The `RouteyKit` package floors at **iOS 17 / macOS 14** so `swift test` runs on the Mac. watchOS (V1.1) and CarPlay (V1.2 — scenes inside the iOS target, not a separate one) are deferred but designed-for now; keep iOS-only / Vision / CarPlay code behind `#if os(iOS)` so the watch target stays lean. Adopt the newest APIs available within those targets.
- **Swift 6 or later**, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- **Persistence is SQLiteData (Point-Free, on GRDB) + private CloudKit — NOT SwiftData or Core Data.** Established dependencies are SQLiteData/GRDB; do not introduce other third-party frameworks without asking first.
- Avoid UIKit views unless requested. (Vision, AVFoundation capture for OCR, and CarPlay templates are expected — guard them with `#if os(iOS)`.)


## Swift instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app's documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap's location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don't apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Place view logic into view models or the `RouteyDomain` module, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.


## Persistence instructions (SQLiteData + CloudKit)

Routey uses **SQLiteData (Point-Free, on GRDB)**, not SwiftData. Local SQLite is the **source of truth** (offline-first by construction); `SyncEngine` is a best-effort background **private-CloudKit** layer for backup + multi-device. Confidence in the library is **medium** (young, last-write-wins-only), so the agreed first build step is a throwaway **two-physical-device sync proof-of-concept** before fully committing (fallback: Core Data + `NSPersistentCloudKitContainer`).

Because the schema syncs to CloudKit, it is **append-only once sync is live**:

- Use **globally-unique UUID primary keys** on every synced table — never auto-increment.
- **No non-primary-key `UNIQUE` constraints** on synced tables (they throw at SyncEngine construction). Promote a natural key to the primary key (e.g. a Tag's canonical name), or enforce uniqueness in app logic plus a *local* index.
- Foreign-key cascades are restricted to **`ON DELETE CASCADE` / `SET NULL` / `SET DEFAULT`** — `RESTRICT` / `NO ACTION` throw.
- **No rename / drop / retype** of synced tables or columns after sync is live — new tables and new optional/defaulted columns only. Pre-add future-era columns (e.g. per-stop GPS) or accept they ship `Optional` later.
- Reorderable sequences use a fractional/gap `sortIndex` column (one row touched per move), never a native ordered relationship.
- Reserve real migration freedom for **local, non-synced tables** (FTS index, OCR caches, derived data) — exclude them from the sync list and rebuild freely.
- Use parameterized queries / StructuredQueries — **never** string-interpolated SQL. Run writes on a background `DatabaseWriter`; never freeze the UI on a data operation.
- SQLiteData derives table names by lower-casing + pluralizing the type (`Route`→`routes`, `DeliveryPoint`→`deliveryPoints`); migration `CREATE TABLE` names must match exactly.


## Project structure

- One Swift package, **`RouteyKit`** (library targets only), consumed by thin app shells. Modules depend downward: `RouteyModel` ← `RouteyPersistence` ← `RouteySearch` / `RouteyDomain` ← `RouteyOCR` / `RouteyExport` / `RouteyNavigation`. Use a consistent layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and model types.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic with **Swift Testing** (not XCTest). Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- **Never commit employer- or route-specific data** — real names, streets, sites, or civic numbers. Use invented placeholders in samples, mockups, and tests.
- If the project uses Localizable.xcstrings, prefer to add user-facing strings using symbol keys (e.g. `helloWorld`) in the string catalog with `extractionState` set to "manual", accessing them via generated symbols such as `Text(.helloWorld)`.


## PR instructions

- Normal feature work branches from **`nightly`** and opens PRs against **`nightly`**. Promotion PRs flow one way: `nightly` → `weekly` → `main`. `main` remains Routey's stable default branch.
- Run `cd RouteyKit && swift test` and confirm green before committing.
- Keep every committed file **carrier-agnostic** — no employer name or real route data.
- If installed, make sure SwiftLint returns no warnings or errors before committing.

## Release Engineering — Promotion Ladder

Routey uses the standard release ladder: `feature/*` → `nightly` → `weekly` → `main`. `nightly` is the integration branch and daily TestFlight train, `weekly` is the Monday beta train, and `main` is stable.

| Branch | Source | Protection |
| --- | --- | --- |
| `nightly` | feature PRs | Required `Build gate + tests`; PR review optional |
| `weekly` | `nightly` | Strict `Build gate + tests`; review approval optional |
| `main` | `weekly` | Strict `Build gate + tests`; review approval optional |

Hotfix exception: branch from `main`, PR to `main`, then merge `main` back down into `weekly` and `nightly`.


## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:

- `DocumentationSearch` — verify API availability and correct usage before writing code
- `BuildProject` — build the project after making changes to confirm compilation succeeds
- `GetBuildLog` — inspect build errors and warnings
- `RenderPreview` — visually verify SwiftUI views using Xcode Previews
- `XcodeListNavigatorIssues` — check for issues visible in the Xcode Issue Navigator
- `ExecuteSnippet` — test a code snippet in the context of a source file
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` — prefer these over generic file tools when working with Xcode project files

---

## Attribution

This agent guide is adapted from [Paul Hudson's SwiftAgents `AGENTS.md`](https://github.com/twostraws/SwiftAgents), customized for Routey's offline-first SQLiteData + CloudKit architecture, Swift 6 conventions, `RouteyKit` package layout, and carrier-agnostic public-repo rule.
