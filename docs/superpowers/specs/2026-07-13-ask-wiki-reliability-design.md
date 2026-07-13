# Ask Wiki Reliability & Redesign — Design

**Date:** 2026-07-13
**Status:** Approved scope, pending implementation plan

## Context

Root-cause debugging (this session) found the Ask tab's "keeps loading forever"
report is a genuine, severe client-side bug, not an unhandled API error. Every
daemon error path was verified live against the real API (`.claude/local/wiki-daemon.env`
holds a working token) and decodes correctly today:

| Server condition | Verified response | Client handling |
|---|---|---|
| Bad/missing token | `401 unauthorized` | `.failed(message)` |
| Unknown/expired job | `404 not_found` | `.failed(message)` |
| Empty question | `400 bad_request` | `.failed(message)` |
| Malformed JSON | `400 bad_request` | `.failed(message)` |
| Provider hangs | daemon's `run_agent` has a hard 300s subprocess timeout (`wiki-daemon/src/wiki_daemon/agent.py:151`) → clean `failed` job | `.failed(message)` |

The actual defect is `WikiReader/Views/AskWikiView.swift:53-56`:

```swift
.onDisappear {
    queryTask?.cancel()
    queryTask = nil
}
```

`TabView` triggers `.onDisappear` on tab switches, not just true dismissal.
The cancel is caught by `catch is CancellationError { return }`
(`AskWikiView.swift:225-226`) — `phase` is never reset. Since the Ask button
is disabled while `phase.isBusy`, leaving the Ask tab mid-query (even
briefly) produces a **permanent soft-lock**: spinner forever, button
disabled, no error, no recovery short of force-quitting the app. That
force-quit is the separately-reported "the query is gone" bug — `phase`,
`question`, and `jobID` live only in view-scoped `@State` with no
persistence.

The daemon's own HTTP API has no history/list endpoint — confirmed by
reading `wiki-daemon/docs/specs/2026-06-23-http-api-design.md:388`, which
explicitly scopes page/history endpoints out ("the iOS app has local [vault
access already]"). The only durable server-side trace of a query is a
`wiki/queries/*.md` vault page, written only when `save=true`. On-device
history is therefore necessary, not just convenient — it's the only way to
cover unsaved queries and to know what to resume after a relaunch.

## Scope

1. Fix the soft-lock: query lifecycle (task, state) moves to a session-scoped
   object that survives tab switches and view teardown.
2. Persist query state (App Group, local only) so app relaunch resumes an
   in-flight query instead of losing it.
3. On-device history: every question ever asked (saved or not) is listed,
   newest first, as a scannable doc-list — not a threaded chat, since
   questions across sessions are unrelated.
4. Redesign the Ask tab: doc-list landing with a persistent input bar pinned
   at the bottom (no separate compose screen); connection settings (URL,
   token, health check) move behind a gear icon into a modal sheet, out of
   the main flow.
5. Manual Cancel for a running query, independent of the persistence fix.

## Design

### Architecture

- **`AskQueryEntry`** (Core, `Codable`, `Identifiable`) — one history item:
  `id: UUID`, `question: String`, `status: Status`, `jobID: String?`,
  `save: Bool`, `submittedAt: Date`, and once resolved:
  `answerMarkdown: String?`, `citations: [WikiDaemonCitation]`,
  `saved: Bool?`, `saveError: String?`, `provider: String?`,
  `errorMessage: String?`.
  `Status` is `.submitting | .running | .done | .failed | .cancelled` — a
  strict superset of `WikiDaemonQueryStatus`, adding the two client-only
  terminal states needed for the fixes in this design.
- **`AskHistoryStore`** (Core, `nonisolated` enum) — reads/writes the full
  `[AskQueryEntry]` list as JSON in the App Group container (same container
  `VaultBookmarkStore`/`AppGroup.swift` already use), under a new key. Pure
  I/O: `load() -> [AskQueryEntry]`, `save([AskQueryEntry])`. A corrupt or
  missing file yields an empty list, never a crash.
- **`AskWikiSession`** (`@MainActor @Observable`) — owns `entries:
  [AskQueryEntry]` (loaded once via `AskHistoryStore` at init) and the
  in-flight polling `Task`s, keyed by entry `id`. Created once in
  `MainTabs` alongside `VaultIndex` and injected via `.environment()`.
  Because it lives above `AskWikiView` in the ownership hierarchy, tab
  switches no longer touch it — polling continues regardless of which tab
  is visible, which is the direct fix for the soft-lock.

`AskWikiView` becomes a thin presentation layer reading `AskWikiSession`
from the environment; it owns no query state itself beyond the composing
text field and Save toggle.

### Data flow

1. **Submit** — creates an `AskQueryEntry` with status `.submitting`,
   inserts it at index 0 of `entries`, persists immediately (optimistic:
   visible before the network call resolves), then POSTs. Success →
   `.running(jobID)`; failure (bad URL/token/network) → `.failed` with the
   error message, right there in the list — submit and poll failures share
   one path, no separate UI state.
2. **Poll** — a `Task` owned by `AskWikiSession` polls every 1.5s, updates
   the matching entry, and persists on every status change, until
   `.done`/`.failed`.
3. **Resume** — on `AskWikiSession.init()` and on `scenePhase == .active`
   (observed via `MainTabs`, forwarded to the session), every entry still
   `.submitting`/`.running` is checked: if `submittedAt` is more than ~10
   minutes ago (the daemon `JobStore`'s own expiry,
   `wiki-daemon/src/wiki_daemon/api.py`'s `JobStore(expiry_seconds: float =
   600.0)`), it's marked `.failed("Timed out — the daemon's job window
   expired.")` immediately, no wasted request. Otherwise polling resumes
   transparently, silently, with no user action required.
4. **Cancel** — stops the local polling `Task` for that entry and sets
   status `.cancelled`. No daemon cancel endpoint exists (confirmed: the
   API surface is health/query-start/query-status only) — the server job
   keeps running unattended; the app simply stops waiting and frees the
   entry for a fresh look.
5. **Retention** — unlimited; a "Clear history" action in settings wipes
   the store. No automatic cap/eviction.

### UI layout

- **Landing (list)** — `entries`, newest-first (same convention as Home's
  Recents). Each row: the question, a plain-text truncated snippet of the
  answer (or a status label — "sending…", "running…", "failed", "cancelled"
  — while unresolved), and a relative timestamp. Submitting a question
  inserts at the top and **auto-scrolls to top** so the new entry is
  immediately visible under the input bar.
- **Input bar** — pinned at the bottom: `TextEditor` + Save toggle (stays
  here — it's a per-question choice, not a connection setting) + send
  button. No separate compose screen.
- **Gear icon** (toolbar) opens a **modal sheet**: daemon base URL, bearer
  token, health check button, "Clear history". Fully removed from the main
  flow.
- **Row tap** pushes a detail view: question header, then a spinner
  (running/submitting), the failure/cancellation message with reason
  (failed/cancelled), or the full rendered answer + citations (done) —
  reusing the existing `AnswerResultView`/`MarkdownView` rendering and
  citation-to-local-note resolution unchanged.
- **Cancel affordance** appears on running rows (list and detail).

### Error handling

Every previously-verified server error shape (401/404/400, provider
failures via the daemon's 300s timeout) continues to map to `.failed` with
the server's message — unchanged, already correct. Two new client-only
terminal states close the actual gap: `.cancelled` (user-initiated, no
server call) and the fail-fast `.failed("timed out")` for resumed entries
past the daemon's job window. Between these, no `AskQueryEntry` can ever be
left in a `.submitting`/`.running` state with no active polling task behind
it — the invariant that caused the original bug.

### Testing

Swift Testing coverage for the new Core pieces, in `WikiReaderTests`:
- `AskHistoryStore`: JSON round-trip (write then read back equal), missing
  file → empty list, corrupt file → empty list (no crash).
- `AskQueryEntry`: `Codable` round-trip including all status cases;
  staleness classification (a `.submitting`/`.running` entry with
  `submittedAt` older than the threshold is stale; a fresh one isn't;
  boundary at exactly the threshold).

`AskWikiSession`'s task scheduling/polling and all SwiftUI views are not
unit-tested, matching the existing `VaultStore`/`VaultIndex` convention
(session-state classes and views are verified by build + manual testing,
per project convention).

## Out of scope (this release)

- Multi-turn conversational context (each question is independent — the
  daemon's `/api/v1/query` is stateless per-call; no session/thread ID
  exists to build on).
- Syncing history across devices, or writing it into the vault (would make
  WikiReader a second writer alongside the daemon, which treats `wiki/` as
  single-writer).
- Server-side query cancellation (no such endpoint exists; cancel is
  local-only, as designed above).
- History search/filtering (the list is chronological; full-text search
  over past answers is a future enhancement, not required here).
- Automatic history retention limits (deferred per the "unlimited, manual
  clear" decision).

## Implementation deviations & follow-ups (recorded 2026-07-13)

- Final whole-branch review found (and the controller fixed) two issues
  beyond the plan's original design:
  - The generic `catch` in `AskWikiSession.run()` could overwrite an
    already-`.cancelled` entry back to `.failed`, since Foundation's
    URLSession async APIs often surface a cancelled in-flight request as
    `URLError.cancelled` rather than Swift's `CancellationError`. Fixed by
    guarding the generic catch against mutating an already-resolved entry.
  - A poll `Task` keeps its owning `AskWikiSession` alive for the task's
    full duration (any instance method call across suspension points must
    keep its receiver alive). Since `MainTabs` — and the `AskWikiSession`
    it owns — is recreated via `.id(root)` on a vault switch, an in-flight
    query at switch time could leave the old session polling independently
    of the new one, both racing to persist the same App Group history.
    Fixed with `deinit { for task in pollTasks.values { task.cancel() } }`,
    which required marking `pollTasks` `nonisolated(unsafe)` (`deinit` on an
    actor-isolated class is itself nonisolated; safe here since deinit has
    no concurrent access to race with by construction).
- **Follow-up, not blocking:** the exact bug this branch fixes (task
  orphaned independent of view lifecycle) has no automated regression test.
  `AskWikiSession` constructs `WikiDaemonClient` directly with no injection
  seam, so a `URLProtocol`-mocked test reproducing "cancel mid-request"
  isn't feasible without adding a small `clientFactory` seam. Worth a
  fast-follow given how subtle this class of bug is to catch by inspection
  alone.
