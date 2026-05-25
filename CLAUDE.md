# CLAUDE.md — WikiReader

iOS app (Xcode 26 / iOS 26, SwiftUI): a Markdown vault viewer + a Share
Extension that clips Twitter/X posts. Two targets share a UI-free `Core`.
See `README.md` (overview), `PRIMER.md` (design), `SETUP.md` (signing).

## Follow Axiom practices

This project uses the **Axiom** iOS/Swift skills. For ANY iOS/Swift/SwiftUI
work here, consult the matching Axiom skill before writing code:

- SwiftUI views, state, navigation, layout, architecture → `axiom-swiftui`
- async/actors/`@MainActor`/Sendable → `axiom-concurrency`
- tests → `axiom-testing`
- data/persistence/Codable → `axiom-data`
- networking/URLSession → `axiom-networking`
- App Store / signing / capabilities → `axiom-shipping`, `axiom-security`
- not sure which → `axiom:ask`

Prefer the skill's guidance over ad-hoc patterns. When a fix maps to a named
Axiom anti-pattern, apply the skill's prescribed fix.

## Architecture conventions (Apple Native "MV", not MVVM)

Per `axiom-swiftui` architecture guidance, this app uses Apple's native pattern
— **do not introduce MVVM/ViewModel-per-view**:

- **`@Observable` classes** for state/logic (`VaultStore`, `GraphLayout`); never
  `ObservableObject`.
- **Property wrappers**: `@State` only for view-*owned* models; plain `let` for
  passed-in models; `@Bindable` when bindings are needed; `@Environment` for
  app-wide. No wrapper just to "hold" a passed model.
- **UI-free `Core/`**: all business logic and side effects live in `nonisolated`
  structs/enums (parsing, clip pipeline, fxtwitter, vault I/O). It must stay
  importable/testable **without SwiftUI**.
- **No inline `Binding(get:set:)` in a view body** (Axiom Anti-Pattern 6) — use a
  real `@State` Bool + `.onChange`, or `@Bindable`.
- Presentation should be a **function of a value** where practical (e.g.
  `ShareStatusView(phase:)`), so it previews/tests without running side effects.
- Add a presentation-adapter `@Observable` only when a view gains real
  filtering/sorting/formatting — not preemptively.
- Every SwiftUI view gets a `#Preview` (use `#if DEBUG` sample-data helpers for
  views that need inputs).

## Build & verify

```bash
# Build app + extension for the simulator
xcodebuild -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

- Because `Core/` is `nonisolated` and Foundation-only, you can unit-check its
  logic fast with plain `swiftc` (copy the needed `Core/*.swift` + a small
  `main.swift` with assertions) without a test target.
- The Xcode project (incl. the extension target) is managed; if you must edit
  `project.pbxproj`, use the `xcodeproj` Ruby gem rather than hand-editing.

## Notes

- Free Apple account works — vault access is a security-scoped bookmark from the
  document picker, shared via App Group `group.com.anifoca.WikiReader`. No iCloud
  capability.
- iOS bookmarks use no `.withSecurityScope` (that option is macOS-only).
- Notes are written temp-then-rename (`VaultWriter`) so watchers never see a
  partial file.
- Only the Twitter/X clip path is implemented; article/video return a clear
  "not built yet" error in `ClipService`.
