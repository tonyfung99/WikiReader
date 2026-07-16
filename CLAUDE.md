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

# Run the unit tests (Swift Testing, covers Core logic)
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- Tests live in `WikiReaderTests/` (a hosted unit-test target, `@testable
  import WikiReader`, **Swift Testing** — not XCTest). Add new Core logic with a
  test, per `axiom-testing`/TDD. Don't bother unit-testing SwiftUI views or the
  non-deterministic `GraphLayout` force simulation.
- The Xcode project (extension + test targets) is managed; if you must edit
  `project.pbxproj`, use the `xcodeproj` Ruby gem rather than hand-editing.

## Dependencies

The app prefers **zero third-party dependencies** — Markdown parsing/rendering,
the graph layout, and the fxtwitter client are all hand-rolled. That policy was
deliberately amended once: take a well-maintained package when it's clearly the
right tool. Two are in use (both MIT, added via SPM); this is a documented
exception, not policy drift — don't reach for a dependency by default:

- `beautiful-mermaid-swift` — native Mermaid diagram rendering (no
  WebView/JavaScript). Linked into the **app** target.
- `ViewInspector` — structural SwiftUI view testing. Linked into the
  **`WikiReaderTests`** target only; never into the shipping app.

## Notes

- Free Apple account works — vault access is a security-scoped bookmark from the
  document picker, shared via App Group `group.com.anifoca.WikiReader`. No iCloud
  capability.
- iOS bookmarks use no `.withSecurityScope` (that option is macOS-only).
- Notes are written temp-then-rename (`VaultWriter`) so watchers never see a
  partial file.
- Twitter/X and article clipping are fully implemented; video URLs write a
  `pending/` stub for a (future) home-machine transcription job.
- The Ask tab talks to the companion `wiki-daemon` HTTP API (health + async
  query jobs, bearer token in Keychain). See
  `docs/wiki-daemon-ios-api-requirements.md`.
