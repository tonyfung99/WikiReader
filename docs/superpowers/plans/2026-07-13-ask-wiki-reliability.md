# Ask Wiki Reliability & Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Ask tab's soft-lock bug (query state tied to view lifecycle) and redesign it into a persisted, resumable doc-list of past questions with a pinned input bar, settings hidden behind a gear icon, and a manual Cancel affordance.

**Architecture:** Query lifecycle (task, state) moves from `AskWikiView`'s `@State` into a new session-scoped `@Observable` class (`AskWikiSession`), created once in `MainTabs` and injected via `.environment()` — the same pattern `VaultIndex` already established. History persists as JSON in the App Group (`AskHistoryStore`), resolving both the soft-lock (polling no longer tied to view appear/disappear) and the "query is gone after backgrounding" bug (state survives relaunch and resumes automatically).

**Tech Stack:** Swift / SwiftUI (iOS 26, Xcode 26), Swift Testing, zero third-party dependencies. Spec: `docs/superpowers/specs/2026-07-13-ask-wiki-reliability-design.md`.

## Global Constraints

- **No third-party dependencies.**
- **Apple-native "MV" pattern, never MVVM:** `@Observable` classes for shared state (never `ObservableObject`); `@State` only for view-owned models; `@Environment` for app-wide/session state. No inline `Binding(get:set:)` in a view body.
- **Every new SwiftUI view gets a `#Preview`.**
- **Tests are Swift Testing** (`import Testing`, `@testable import WikiReader`, `@MainActor struct XxxTests`, `@Test`, `#expect`/`#require`) — never XCTest.
- **The app target (`WikiReader/`) is a filesystem-synchronized Xcode group** — new app source files need no project registration.
- **`WikiReaderTests` is a PLAIN group, NOT synchronized** — any new test file must be registered in the `WikiReaderTests` target via the `xcodeproj` Ruby gem (per CLAUDE.md; never hand-edit `project.pbxproj` any other way). After registering, confirm the RED run's failure is a genuine compile error naming the missing type — a silent "0 new tests ran" pass means the file wasn't actually linked into the target.
- **Existing persisted keys must not change**: `@AppStorage("wikiDaemon.baseURL")`, `@AppStorage("wikiDaemon.saveAnswers")`, and the Keychain service `com.anifoca.WikiReader.wiki-daemon` (`WikiDaemonTokenStore`) carry over unchanged so a user's existing settings survive this redesign with no migration.
- **Build command:**
  ```bash
  xcodebuild -project WikiReader.xcodeproj -scheme WikiReader \
    -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug build
  ```
- **Test command** (append `-only-testing:WikiReaderTests/<SuiteName>` to scope):
  ```bash
  xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
    -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  ```
- **Known flake:** if the simulator reports "Busy / failed preflight checks", run `xcrun simctl shutdown all` and retry the same command.
- Run all commands from the repo root: `/Users/tonyfung/workspace/WikiReader`.

---

### Task 1: `AskQueryEntry` model

One history item: the question, its lifecycle status, the resolved answer once known, and staleness classification against the daemon's own 10-minute job window.

**Files:**
- Create: `WikiReader/WikiDaemon/AskQueryEntry.swift`
- Test: `WikiReaderTests/AskQueryEntryTests.swift`

**Interfaces:**
- Consumes: `WikiDaemonCitation` (existing, `WikiReader/WikiDaemon/WikiDaemonClient.swift`).
- Produces: `AskQueryEntry` — `Codable, Identifiable, Equatable`, `id: UUID`, `question: String`, `status: Status`, `jobID: String?`, `save: Bool`, `submittedAt: Date`, `answerMarkdown: String?`, `citations: [WikiDaemonCitation]`, `saved: Bool?`, `saveError: String?`, `provider: String?`, `errorMessage: String?`; `Status` enum `.submitting | .running | .done | .failed | .cancelled`; `var isResolved: Bool`; `static let staleThreshold: TimeInterval`; `func isStale(now: Date) -> Bool`. The custom init signature (used verbatim by every later task):
  ```swift
  init(
      id: UUID = UUID(),
      question: String,
      status: Status = .submitting,
      jobID: String? = nil,
      save: Bool,
      submittedAt: Date,
      answerMarkdown: String? = nil,
      citations: [WikiDaemonCitation] = [],
      saved: Bool? = nil,
      saveError: String? = nil,
      provider: String? = nil,
      errorMessage: String? = nil
  )
  ```

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/AskQueryEntryTests.swift`:

```swift
import Testing
import Foundation
@testable import WikiReader

@MainActor
struct AskQueryEntryTests {
    @Test func codableRoundTripsAllStatusCases() throws {
        let statuses: [AskQueryEntry.Status] = [.submitting, .running, .done, .failed, .cancelled]
        for status in statuses {
            let entry = AskQueryEntry(
                question: "What changed?",
                status: status,
                jobID: "qry_1",
                save: true,
                submittedAt: Date(timeIntervalSince1970: 1_700_000_000),
                answerMarkdown: "# Answer",
                citations: [WikiDaemonCitation(wikiLink: "Note", title: "Note")],
                saved: true,
                saveError: nil,
                provider: "codex",
                errorMessage: status == .failed ? "boom" : nil
            )
            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(AskQueryEntry.self, from: data)
            #expect(decoded == entry)
        }
    }

    @Test func resolvedStatusesAreNeverStale() {
        let old = Date(timeIntervalSinceNow: -3600)
        for status: AskQueryEntry.Status in [.done, .failed, .cancelled] {
            let entry = AskQueryEntry(question: "q", status: status, save: false, submittedAt: old)
            #expect(!entry.isStale(now: Date()))
        }
    }

    @Test func unresolvedRecentEntryIsNotStale() {
        let entry = AskQueryEntry(question: "q", status: .running, save: false, submittedAt: Date())
        #expect(!entry.isStale(now: Date()))
    }

    @Test func unresolvedOldEntryIsStale() {
        let submitted = Date(timeIntervalSince1970: 0)
        let now = submitted.addingTimeInterval(AskQueryEntry.staleThreshold + 1)
        let entry = AskQueryEntry(question: "q", status: .running, save: false, submittedAt: submitted)
        #expect(entry.isStale(now: now))
    }

    @Test func unresolvedEntryExactlyAtThresholdIsNotStale() {
        let submitted = Date(timeIntervalSince1970: 0)
        let now = submitted.addingTimeInterval(AskQueryEntry.staleThreshold)
        let entry = AskQueryEntry(question: "q", status: .submitting, save: false, submittedAt: submitted)
        #expect(!entry.isStale(now: now))
    }
}
```

- [ ] **Step 2: Register the test file in the Xcode project**

`WikiReaderTests` is a plain (non-synchronized) group. Use the `xcodeproj` Ruby gem to add `WikiReaderTests/AskQueryEntryTests.swift` as a file reference in the `WikiReaderTests` group and to the `WikiReaderTests` target's Sources build phase. Do not hand-edit `project.pbxproj` any other way.

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/AskQueryEntryTests
```
Expected: compile FAILURE naming `AskQueryEntry` (type does not exist yet). If instead it reports "0 tests ran" with no compile error, the file registration in Step 2 didn't take — fix that before continuing.

- [ ] **Step 4: Implement**

Create `WikiReader/WikiDaemon/AskQueryEntry.swift`:

```swift
import Foundation

/// One Ask-wiki history item: the question, its lifecycle status, and the
/// resolved answer once known. `.cancelled` and the fail-fast "timed out"
/// use of `.failed` are client-only states — the daemon's own
/// `WikiDaemonQueryStatus` has no equivalent, since there's no cancel
/// endpoint and no server-side notion of a client giving up.
nonisolated struct AskQueryEntry: Codable, Identifiable, Equatable {
    enum Status: String, Codable, Equatable {
        case submitting, running, done, failed, cancelled
    }

    let id: UUID
    var question: String
    var status: Status
    var jobID: String?
    var save: Bool
    var submittedAt: Date

    var answerMarkdown: String?
    var citations: [WikiDaemonCitation]
    var saved: Bool?
    var saveError: String?
    var provider: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        question: String,
        status: Status = .submitting,
        jobID: String? = nil,
        save: Bool,
        submittedAt: Date,
        answerMarkdown: String? = nil,
        citations: [WikiDaemonCitation] = [],
        saved: Bool? = nil,
        saveError: String? = nil,
        provider: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.question = question
        self.status = status
        self.jobID = jobID
        self.save = save
        self.submittedAt = submittedAt
        self.answerMarkdown = answerMarkdown
        self.citations = citations
        self.saved = saved
        self.saveError = saveError
        self.provider = provider
        self.errorMessage = errorMessage
    }

    var isResolved: Bool {
        switch status {
        case .done, .failed, .cancelled: true
        case .submitting, .running: false
        }
    }

    /// Matches the daemon's own `JobStore(expiry_seconds: 600.0)` — past
    /// this, a still-unresolved entry's job has certainly been evicted
    /// server-side, so there's no point polling for it.
    static let staleThreshold: TimeInterval = 600

    func isStale(now: Date) -> Bool {
        !isResolved && now.timeIntervalSince(submittedAt) > Self.staleThreshold
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Same command as Step 3. Expected: PASS, 5/5.

- [ ] **Step 6: Build**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/WikiDaemon/AskQueryEntry.swift WikiReaderTests/AskQueryEntryTests.swift WikiReader.xcodeproj/project.pbxproj
git commit -m "feat: add AskQueryEntry history-item model"
```

---

### Task 2: `AskHistoryStore`

Pure JSON persistence for the entry list, in the App Group container — local-only, never synced, never written into the vault.

**Files:**
- Create: `WikiReader/WikiDaemon/AskHistoryStore.swift`
- Test: `WikiReaderTests/AskHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `AppGroup.defaults` (existing, `WikiReader/Core/AppGroup.swift`), `AskQueryEntry` (Task 1).
- Produces: `AskHistoryStore` (`nonisolated enum`) — `static func load(defaults: UserDefaults = AppGroup.defaults) -> [AskQueryEntry]` (newest-first by `submittedAt`, empty on missing/corrupt data), `static func save(_ entries: [AskQueryEntry], defaults: UserDefaults = AppGroup.defaults)`, `static func clear(defaults: UserDefaults = AppGroup.defaults)`. Storage key: `"askWiki.history"`.

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/AskHistoryStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import WikiReader

@MainActor
struct AskHistoryStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "askhistorystore-tests-\(UUID().uuidString)")!
    }

    @Test func missingDataReturnsEmptyList() {
        let defaults = makeDefaults()
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }

    @Test func savesAndLoadsRoundTrip() {
        let defaults = makeDefaults()
        let entries = [
            AskQueryEntry(question: "First", status: .done, save: true, submittedAt: Date(timeIntervalSince1970: 200)),
            AskQueryEntry(question: "Second", status: .running, save: false, submittedAt: Date(timeIntervalSince1970: 100)),
        ]
        AskHistoryStore.save(entries, defaults: defaults)
        let loaded = AskHistoryStore.load(defaults: defaults)
        #expect(Set(loaded.map(\.id)) == Set(entries.map(\.id)))
        #expect(loaded.count == 2)
    }

    @Test func loadSortsNewestFirstRegardlessOfSaveOrder() {
        let defaults = makeDefaults()
        let older = AskQueryEntry(question: "Older", save: false, submittedAt: Date(timeIntervalSince1970: 100))
        let newer = AskQueryEntry(question: "Newer", save: false, submittedAt: Date(timeIntervalSince1970: 200))
        AskHistoryStore.save([older, newer], defaults: defaults)
        let loaded = AskHistoryStore.load(defaults: defaults)
        #expect(loaded.map(\.question) == ["Newer", "Older"])
    }

    @Test func corruptDataReturnsEmptyList() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "askWiki.history")
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }

    @Test func clearRemovesPersistedHistory() {
        let defaults = makeDefaults()
        AskHistoryStore.save([AskQueryEntry(question: "Q", save: true, submittedAt: Date())], defaults: defaults)
        AskHistoryStore.clear(defaults: defaults)
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }
}
```

- [ ] **Step 2: Register the test file in the Xcode project**

Same as Task 1 Step 2 — add `WikiReaderTests/AskHistoryStoreTests.swift` via the `xcodeproj` gem.

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/AskHistoryStoreTests
```
Expected: compile FAILURE naming `AskHistoryStore`.

- [ ] **Step 4: Implement**

Create `WikiReader/WikiDaemon/AskHistoryStore.swift`:

```swift
import Foundation

/// Persists Ask-wiki query history as JSON in the App Group's UserDefaults
/// — local-only, never synced across devices, never written into the vault
/// (the daemon owns `wiki/` as sole writer).
nonisolated enum AskHistoryStore {
    private static let key = "askWiki.history"

    static func load(defaults: UserDefaults = AppGroup.defaults) -> [AskQueryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let entries = (try? JSONDecoder().decode([AskQueryEntry].self, from: data)) ?? []
        return entries.sorted { $0.submittedAt > $1.submittedAt }
    }

    static func save(_ entries: [AskQueryEntry], defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Same command as Step 3. Expected: PASS, 5/5.

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/WikiDaemon/AskHistoryStore.swift WikiReaderTests/AskHistoryStoreTests.swift WikiReader.xcodeproj/project.pbxproj
git commit -m "feat: add AskHistoryStore App Group persistence"
```

---

### Task 3: `AskWikiSession`

The session-scoped engine: owns history, submits questions, polls, resumes on launch/foreground, and cancels — all independent of any view's lifecycle. This is the direct fix for the soft-lock bug (root cause: `AskWikiView.swift:53-56`'s `.onDisappear` used to cancel the poll task without resetting state; polling now lives here instead, so no view lifecycle event can orphan it).

**Files:**
- Create: `WikiReader/WikiDaemon/AskWikiSession.swift`

**Interfaces:**
- Consumes: `AskQueryEntry`, `AskHistoryStore` (Tasks 1–2), `WikiDaemonClient`, `WikiDaemonQueryStatus`, `WikiDaemonClientError` (existing, `WikiDaemonClient.swift`), `WikiDaemonTokenStore.load()` (existing), `AppGroup.defaults` (existing).
- Produces: `AskWikiSession` (`@MainActor @Observable final class`) —
  `init(defaults: UserDefaults = AppGroup.defaults)`,
  `private(set) var entries: [AskQueryEntry]`,
  `var configuredBaseURL: URL?` (computed),
  `func submit(question: String, save: Bool)`,
  `func cancel(_ entryID: UUID)`,
  `func clearHistory()`,
  `func resumeUnresolvedEntries()`,
  `static let baseURLKey: String`,
  `static let defaultBaseURLString: String`.
  No unit tests for this task — session-state classes with async task orchestration are verified by build + manual testing in this project, matching `VaultStore`/`VaultIndex` (untested precedent).

- [ ] **Step 1: Implement**

Create `WikiReader/WikiDaemon/AskWikiSession.swift`:

```swift
import Foundation
import Observation

/// Owns Ask-wiki query state and its lifecycle — submission, polling,
/// resumption, cancellation — independent of any view's appear/disappear.
/// Created once in MainTabs and shared via the environment, so switching
/// tabs (or backgrounding, or relaunching the app) never orphans an
/// in-flight query the way view-scoped @State used to.
@MainActor
@Observable
final class AskWikiSession {
    static let baseURLKey = "wikiDaemon.baseURL"
    static let defaultBaseURLString = "https://wiki.artanis-tech.com"

    private(set) var entries: [AskQueryEntry]

    private let defaults: UserDefaults
    private var pollTasks: [UUID: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.entries = AskHistoryStore.load(defaults: defaults)
        resumeUnresolvedEntries()
    }

    /// Resolves the configured daemon URL from the same
    /// `@AppStorage("wikiDaemon.baseURL")` key the settings sheet edits.
    var configuredBaseURL: URL? {
        var text = (UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURLString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        return URL(string: text)
    }

    func submit(question: String, save: Bool) {
        guard let baseURL = configuredBaseURL else {
            insert(AskQueryEntry(
                question: question, status: .failed, save: save, submittedAt: Date(),
                errorMessage: "Enter a valid daemon URL in Settings."
            ))
            return
        }
        let token = WikiDaemonTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            insert(AskQueryEntry(
                question: question, status: .failed, save: save, submittedAt: Date(),
                errorMessage: "Set a bearer token in Settings."
            ))
            return
        }

        let entry = AskQueryEntry(question: question, save: save, submittedAt: Date())
        insert(entry)
        startPolling(entryID: entry.id, baseURL: baseURL, token: token, resuming: false)
    }

    /// Call on init and whenever the app becomes active: resumes polling
    /// for any entry still submitting/running, or fails it fast (no wasted
    /// request) if it's past the daemon's own job-expiry window.
    func resumeUnresolvedEntries() {
        guard let baseURL = configuredBaseURL else { return }
        let token = WikiDaemonTokenStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let now = Date()
        for entry in entries where !entry.isResolved {
            guard pollTasks[entry.id] == nil else { continue }
            if entry.isStale(now: now) {
                update(entry.id) {
                    $0.status = .failed
                    $0.errorMessage = "Timed out — the daemon's job window expired."
                }
                continue
            }
            if entry.status == .submitting, entry.jobID == nil {
                update(entry.id) {
                    $0.status = .failed
                    $0.errorMessage = "Interrupted before the daemon confirmed the question."
                }
                continue
            }
            startPolling(entryID: entry.id, baseURL: baseURL, token: token, resuming: true)
        }
    }

    /// Stops local polling and marks the entry cancelled. No daemon cancel
    /// endpoint exists — the server job keeps running unattended; the app
    /// simply stops waiting for it.
    func cancel(_ entryID: UUID) {
        guard let existing = entry(entryID), !existing.isResolved else { return }
        pollTasks[entryID]?.cancel()
        pollTasks[entryID] = nil
        update(entryID) { $0.status = .cancelled }
    }

    func clearHistory() {
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
        entries.removeAll()
        persist()
    }

    // MARK: - Private

    private func startPolling(entryID: UUID, baseURL: URL, token: String, resuming: Bool) {
        let client = WikiDaemonClient(baseURL: baseURL, token: token)
        pollTasks[entryID] = Task { [weak self] in
            await self?.run(entryID: entryID, client: client, resuming: resuming)
        }
    }

    private func run(entryID: UUID, client: WikiDaemonClient, resuming: Bool) async {
        do {
            let jobID: String
            if resuming {
                guard let existing = entry(entryID)?.jobID else { return }
                jobID = existing
            } else {
                guard let question = entry(entryID)?.question, let save = entry(entryID)?.save else { return }
                let start = try await client.startQuery(question: question, save: save)
                jobID = start.jobID
                update(entryID) {
                    $0.status = .running
                    $0.jobID = jobID
                }
            }

            while !Task.isCancelled {
                let status = try await client.queryStatus(jobID: jobID)
                switch status.status {
                case .queued, .running:
                    break
                case .done:
                    update(entryID) {
                        $0.status = .done
                        $0.answerMarkdown = status.answerMarkdown
                        $0.citations = status.citations
                        $0.saved = status.saved
                        $0.saveError = status.saveError
                        $0.provider = status.provider
                    }
                    pollTasks[entryID] = nil
                    return
                case .failed:
                    update(entryID) {
                        $0.status = .failed
                        $0.errorMessage = status.error?.message ?? "The daemon reported a failed query."
                    }
                    pollTasks[entryID] = nil
                    return
                }
                guard !Task.isCancelled else { return }
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        } catch is CancellationError {
            return
        } catch {
            update(entryID) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
            pollTasks[entryID] = nil
        }
    }

    private func entry(_ id: UUID) -> AskQueryEntry? {
        entries.first { $0.id == id }
    }

    private func insert(_ entry: AskQueryEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    private func update(_ id: UUID, _ mutate: (inout AskQueryEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        persist()
    }

    private func persist() {
        AskHistoryStore.save(entries, defaults: defaults)
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WikiReader/WikiDaemon/AskWikiSession.swift
git commit -m "feat: add AskWikiSession — polling and history independent of view lifecycle"
```

---

### Task 4: Wire `AskWikiSession` into `MainTabs`

**Files:**
- Modify: `WikiReader/ContentView.swift`

**Interfaces:**
- Consumes: `AskWikiSession()` (Task 3).
- Produces: `AskWikiSession` available via `.environment()` to every view under `MainTabs` (all tabs, all pushed/sheeted descendants).

- [ ] **Step 1: Add the session and inject it**

In `WikiReader/ContentView.swift`, inside `private struct MainTabs`, add the stored property, initialize it, inject it, and extend the existing scenePhase handler:

```swift
    @State private var index: VaultIndex
    @State private var askSession: AskWikiSession
    @State private var selection: MainTab = .home
    @State private var pendingQuestion: String?

    init(root: URL, store: VaultStore, onChangeVault: @escaping () -> Void) {
        self.root = root
        self.store = store
        self.onChangeVault = onChangeVault
        _index = State(initialValue: VaultIndex(root: root))
        _askSession = State(initialValue: AskWikiSession())
    }
```

Change the end of `body`:

```swift
        .environment(index)
        .environment(askSession)
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                index.rebuild()
                askSession.resumeUnresolvedEntries()
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WikiReader/ContentView.swift
git commit -m "feat: inject AskWikiSession into the tab environment, resume on foreground"
```

---

### Task 5: `AskSettingsSheet`

Connection settings and history management, moved out of the main Ask flow into a modal sheet behind a gear icon.

**Files:**
- Create: `WikiReader/Views/AskSettingsSheet.swift`

**Interfaces:**
- Consumes: `AskWikiSession` (Task 3, read via `@Environment`), `WikiDaemonClient`, `WikiDaemonHealthResponse`, `WikiDaemonTokenStore` (existing).
- Produces: `AskSettingsSheet` — a `View` taking no required parameters (`AskSettingsSheet()`), reads its session from `@Environment(AskWikiSession.self)`.

- [ ] **Step 1: Implement**

Create `WikiReader/Views/AskSettingsSheet.swift`:

```swift
import SwiftUI

/// Connection settings and history management for the Ask tab, presented
/// as a modal sheet — kept out of the main Ask flow.
struct AskSettingsSheet: View {
    @Environment(AskWikiSession.self) private var session: AskWikiSession?
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AskWikiSession.baseURLKey) private var baseURLString = AskWikiSession.defaultBaseURLString

    @State private var token = ""
    @State private var hasLoadedToken = false
    @State private var health: WikiDaemonHealthResponse?
    @State private var healthError: String?
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("http://host:7880", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        Label("Check Connection", systemImage: "waveform.path.ecg")
                    }
                    if let health {
                        HStack(spacing: 12) {
                            Label(health.vaultName ?? "Vault", systemImage: "checkmark.circle")
                            if let provider = health.provider {
                                Text(provider).foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(health.queryAvailable ? .green : .secondary)
                    }
                    if let healthError {
                        Text(healthError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Clear History", role: .destructive) {
                        showClearConfirmation = true
                    }
                }
            }
            .navigationTitle("Ask Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !hasLoadedToken else { return }
            token = WikiDaemonTokenStore.load()
            hasLoadedToken = true
        }
        .onChange(of: token) { _, newValue in
            guard hasLoadedToken else { return }
            WikiDaemonTokenStore.save(newValue)
        }
        .confirmationDialog(
            "Clear all Ask history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                session?.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func checkHealth() async {
        healthError = nil
        health = nil
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            healthError = "Enter a valid daemon URL."
            return
        }
        if !text.contains("://") { text = "http://\(text)" }
        guard let baseURL = URL(string: text) else {
            healthError = "Enter a valid daemon URL."
            return
        }
        do {
            health = try await WikiDaemonClient(baseURL: baseURL, token: token).health()
        } catch {
            healthError = error.localizedDescription
        }
    }
}

#Preview {
    AskSettingsSheet()
        .environment(AskWikiSession(defaults: UserDefaults(suiteName: "asksettings-preview-\(UUID().uuidString)")!))
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WikiReader/Views/AskSettingsSheet.swift
git commit -m "feat: add AskSettingsSheet for connection settings and clear history"
```

---

### Task 6: `AskEntryDetailView`

The full-answer reading view for one history entry. Looks up the entry live by ID from the session on every render (not a captured snapshot), so a still-running entry's detail screen updates automatically once polling resolves it.

**Files:**
- Create: `WikiReader/Views/AskEntryDetailView.swift`

**Interfaces:**
- Consumes: `AskQueryEntry`, `AskWikiSession` (Tasks 1, 3, via `@Environment`), `AskHistoryStore` (Task 2, preview only), existing `MarkdownView`, `MarkdownParser`, `MarkdownInline`, `WikiLinkResolver`, `VaultFile`, `MarkdownFileView`.
- Produces: `AskEntryDetailView(entryID: UUID, root: URL)` — no other task depends on its internals.

- [ ] **Step 1: Implement**

Create `WikiReader/Views/AskEntryDetailView.swift`:

```swift
import SwiftUI

/// Reading view for one Ask history entry. Looks up the live entry by ID
/// from the environment-injected session on every render (not a captured
/// snapshot) so it updates automatically as polling resolves it.
struct AskEntryDetailView: View {
    let entryID: UUID
    let root: URL

    @Environment(AskWikiSession.self) private var session: AskWikiSession?

    @State private var selectedFile: VaultFile?
    @State private var missingTarget: String?
    @State private var showMissingAlert = false

    private var entry: AskQueryEntry? {
        session?.entries.first { $0.id == entryID }
    }

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.question)
                        .font(.title3.weight(.semibold))
                    statusBody(for: entry)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "Entry removed",
                    systemImage: "trash",
                    description: Text("This question was cleared from history.")
                )
                .padding(.top, 40)
            }
        }
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .alert("Note not found", isPresented: $showMissingAlert) {
            Button("OK", role: .cancel) { missingTarget = nil }
        } message: {
            Text(missingTarget ?? "")
        }
    }

    @ViewBuilder
    private func statusBody(for entry: AskQueryEntry) -> some View {
        switch entry.status {
        case .submitting:
            ProgressView("Sending…")
        case .running:
            VStack(alignment: .leading, spacing: 12) {
                ProgressView("Running…")
                Button("Cancel", role: .destructive) { session?.cancel(entry.id) }
            }
        case .cancelled:
            ContentUnavailableView(
                "Cancelled",
                systemImage: "xmark.circle",
                description: Text("You stopped waiting for this answer.")
            )
        case .failed:
            ContentUnavailableView(
                "Query failed",
                systemImage: "exclamationmark.triangle",
                description: Text(entry.errorMessage ?? "Unknown error.")
            )
        case .done:
            doneBody(for: entry)
        }
    }

    @ViewBuilder
    private func doneBody(for entry: AskQueryEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(entry.provider ?? "Answer", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if entry.saved == true {
                    Label("Saved", systemImage: "tray.and.arrow.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownView(blocks: MarkdownParser.parse(entry.answerMarkdown ?? ""))
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in open(url) })

            if !entry.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Related Notes", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    ForEach(entry.citations) { citation in
                        Button {
                            openWikiLink(citation.wikiLink)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                    if citation.title != citation.wikiLink {
                                        Text(citation.wikiLink)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func open(_ url: URL) -> OpenURLAction.Result {
        guard let target = MarkdownInline.wikiLinkTarget(from: url) else { return .systemAction }
        openWikiLink(target)
        return .handled
    }

    private func openWikiLink(_ target: String) {
        if let file = WikiLinkResolver.resolve(target, in: root) {
            selectedFile = file
        } else {
            missingTarget = target
            showMissingAlert = true
        }
    }
}

#if DEBUG
private func previewSetup() -> (session: AskWikiSession, entryID: UUID) {
    let suite = UserDefaults(suiteName: "askentrydetail-preview-\(UUID().uuidString)")!
    let sample = AskQueryEntry(
        question: "What's the latest on Project X?",
        status: .done,
        jobID: "qry_preview",
        save: true,
        submittedAt: Date(),
        answerMarkdown: "# Project X\n\nHere's a summary with a [[Linked Note]].",
        citations: [WikiDaemonCitation(wikiLink: "Linked Note", title: "Linked Note")],
        saved: true,
        provider: "codex"
    )
    AskHistoryStore.save([sample], defaults: suite)
    return (AskWikiSession(defaults: suite), sample.id)
}
#endif

#Preview {
    let setup = previewSetup()
    return NavigationStack {
        AskEntryDetailView(entryID: setup.entryID, root: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    .environment(setup.session)
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WikiReader/Views/AskEntryDetailView.swift
git commit -m "feat: add AskEntryDetailView, a live-updating reading view per history entry"
```

---

### Task 7: Rewrite `AskWikiView` — doc-list landing + pinned input bar

Replaces the entire file: the old technical-test-harness layout (`connectionSection`/`questionSection`/`statusSection`/`answerSection`, the `QueryPhase` enum, `runQuery`/`checkHealth`/`submit`, and `AnswerResultView`) is deleted and replaced by the doc-list + pinned-input design, reading all query state from `AskWikiSession`.

**Files:**
- Modify: `WikiReader/Views/AskWikiView.swift` (full replacement)

**Interfaces:**
- Consumes: `AskQueryEntry`, `AskWikiSession` (Tasks 1, 3, via `@Environment`), `AskSettingsSheet` (Task 5), `AskEntryDetailView` (Task 6).
- Produces: `AskWikiView(root: URL, pendingQuestion: Binding<String?> = .constant(nil))` — unchanged public signature, so `WikiReader/ContentView.swift`'s existing call site (`AskWikiView(root: root, pendingQuestion: $pendingQuestion)`) needs no change.

- [ ] **Step 1: Replace the entire contents of `WikiReader/Views/AskWikiView.swift`**

```swift
import SwiftUI

/// The Ask tab: a doc-list of past questions (newest first) with a
/// persistent input bar pinned at the bottom. Connection settings live
/// behind the toolbar gear icon, out of the main flow. Query state lives in
/// the environment-injected AskWikiSession, not here — so it survives tab
/// switches, backgrounding, and app relaunch.
struct AskWikiView: View {
    let root: URL
    @Binding var pendingQuestion: String?

    init(root: URL, pendingQuestion: Binding<String?> = .constant(nil)) {
        self.root = root
        self._pendingQuestion = pendingQuestion
    }

    @Environment(AskWikiSession.self) private var session: AskWikiSession?
    @AppStorage("wikiDaemon.saveAnswers") private var saveAnswer = true

    @State private var composeText = ""
    @State private var showSettings = false

    private var entries: [AskQueryEntry] {
        session?.entries ?? []
    }

    private var canSend: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            historyList
            AskInputBar(text: $composeText, saveAnswer: $saveAnswer, canSend: canSend, onSend: send)
        }
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape", action: { showSettings = true })
            }
        }
        .sheet(isPresented: $showSettings) {
            AskSettingsSheet()
        }
        .onAppear { consumePendingQuestion() }
        .onChange(of: pendingQuestion) { _, _ in consumePendingQuestion() }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No questions yet",
                        systemImage: "questionmark.bubble",
                        description: Text("Ask the wiki something below.")
                    )
                }
                ForEach(entries) { entry in
                    NavigationLink {
                        AskEntryDetailView(entryID: entry.id, root: root)
                    } label: {
                        AskEntryRow(entry: entry) {
                            session?.cancel(entry.id)
                        }
                    }
                    .id(entry.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: entries.first?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation { proxy.scrollTo(newValue, anchor: .top) }
            }
        }
    }

    private func consumePendingQuestion() {
        guard let pending = pendingQuestion, !pending.isEmpty else { return }
        composeText = pending
        pendingQuestion = nil
    }

    private func send() {
        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.submit(question: trimmed, save: saveAnswer)
        composeText = ""
    }
}

private struct AskEntryRow: View {
    let entry: AskQueryEntry
    var onCancel: () -> Void

    private var isRunning: Bool {
        entry.status == .submitting || entry.status == .running
    }

    private var statusText: String {
        switch entry.status {
        case .submitting: "Sending…"
        case .running: "Running…"
        case .cancelled: "Cancelled"
        case .failed: entry.errorMessage ?? "Failed"
        case .done: snippet
        }
    }

    private var snippet: String {
        guard let markdown = entry.answerMarkdown else { return "" }
        let flattened = markdown.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > 120 ? String(flattened.prefix(120)) + "…" : flattened
    }

    private var statusColor: Color {
        switch entry.status {
        case .submitting, .running, .done: .secondary
        case .failed: .red
        case .cancelled: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.question)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            HStack {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Spacer()
                Text(entry.submittedAt.formatted(.relative(presentation: .named)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isRunning {
                Button("Cancel", role: .destructive, action: onCancel)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AskInputBar: View {
    @Binding var text: String
    @Binding var saveAnswer: Bool
    let canSend: Bool
    var onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the wiki…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Toggle(isOn: $saveAnswer) {
                    Image(systemName: "tray.and.arrow.down")
                }
                .toggleStyle(.button)
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

#Preview {
    NavigationStack {
        AskWikiView(root: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    .environment(AskWikiSession(defaults: UserDefaults(suiteName: "askwikiview-preview-\(UUID().uuidString)")!))
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the full test suite (regression check)**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all tests PASS (78 total: the 68 from before this plan, plus 5 `AskQueryEntryTests` + 5 `AskHistoryStoreTests`).

- [ ] **Step 4: Commit**

```bash
git add WikiReader/Views/AskWikiView.swift
git commit -m "feat: redesign Ask tab as a doc-list with a pinned input bar"
```

---

## Final verification

- [ ] Run the full test suite one more time (command in Global Constraints). Expected: all PASS.
- [ ] Manual smoke test in the simulator, targeting each originally-reported bug directly:
  1. **Soft-lock fix (#1):** submit a question, immediately switch to another tab (Files/Graph/Home), then switch back to Ask. The entry must still be visibly polling (not stuck) and must resolve to done/failed normally.
  2. **Persistence/resume (#2):** submit a question, background the app (or force-quit via app switcher) while it's running, then reopen. The question must still be there in history and either resume polling or show its resolved result — never silently vanish.
  3. **Question visibility (#3):** confirm the history list and detail view show the actual question text, never a bare `qry_...` job ID.
  4. **Redesign (#4):** confirm the landing screen is the doc-list (no connection fields visible), the input bar is pinned at the bottom, the gear icon opens connection settings in a sheet, and submitting a question auto-scrolls the list to the top.
  5. **Cancel:** submit a question, tap Cancel on its row (or in the detail view) while running — it must immediately show `.cancelled`, not keep spinning.
  6. **Settings round-trip:** open Settings, run Check Connection, confirm it reports the real daemon (use `.claude/local/wiki-daemon.env` for the real URL/token), then Clear History and confirm the list empties.
- [ ] Use superpowers:verification-before-completion before claiming done, then superpowers:finishing-a-development-branch.
