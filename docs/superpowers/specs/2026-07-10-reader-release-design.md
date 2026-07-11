# Reader Release — Design

**Date:** 2026-07-10
**Status:** Approved scope, pending implementation plan

## Context

WikiReader is the mobile viewer + capture surface for an LLM-maintained wiki
vault (`ai-second-brain`, currently ~750 notes / ~5 MB). A Mac-side
`wiki-daemon` ingests clips from `raw/sources/` and maintains `wiki/`; the app
already talks to it over HTTP (health + async query jobs, bearer token in
Keychain) via the Ask tab.

An implementation review (2026-07-10) found the app↔daemon protocol correct and
matching on both sides, but identified gaps in the app's core promise of being
an Obsidian-iOS alternative. This release focuses on **reading & finding**:
making the app a first-class vault reader. Daemon-loop features (ingest
status, clarifications) and capture features are deferred to later releases
(see Future Roadmap).

### Retrieval principle

**Local search is how you navigate; wiki query (Ask) is how you synthesize.**
Search is instant, offline, and free; Ask requires the daemon and a Claude
invocation but answers across notes. The search UI bridges to Ask when local
results look thin.

## Scope

1. Wikilink navigation fix (bug)
2. Full-text search with Ask escalation
3. Backlinks panel in the note view
4. Rendering upgrades: images, callouts, task lists, nested lists, minimal
   syntax highlighting
5. Home tab (recents, index, daemon log)
6. Housekeeping: refresh stale README/SETUP, delete dead `ClipError.unsupported`

## Design

### 1. Wikilink navigation fix

`MarkdownFileView` already resolves `[[links]]` when constructed with a vault
`root`, but `VaultBrowserView` and `GraphScreen` omit it, so taps are silently
swallowed. Fix: pass `root` at both call sites (same resolution path the Ask
tab uses via `WikiLinkResolver`). Unresolved links show the existing "Note not
found" alert.

### 2. Full-text search

**Core (UI-free):** `VaultSearcher` — a `nonisolated` struct that crawls the
vault's `.md` files (same traversal approach as `VaultGraph.build`), holds
contents in an in-memory index, and answers queries with ranked results:

- Ranking: title match > heading match > body match; more query-token hits
  rank higher.
- Results carry the file, a snippet around the first body match, and match
  ranges for highlighting.
- Case-insensitive, tokenized substring matching. No persistence — at current
  scale (and 10–20× it) a rebuild on vault open is instant. Revisit only past
  ~10k notes.
- iCloud dataless files: skipped from the index; `startDownloadingUbiquitousItem`
  is triggered so they appear on the next refresh. The UI shows a count of
  not-yet-indexed files.

**UI:** `.searchable` on the Files tab root. Result rows show note title +
snippet; tap pushes `MarkdownFileView`. Below results (always, and especially
when few/none), an "Ask the wiki instead" row forwards the query text to the
Ask tab.

**State:** the index lives on `VaultStore` (`@Observable`), built lazily on
first search, invalidated on pull-to-refresh and vault change.

### 3. Backlinks panel

A "Linked from (N)" `DisclosureGroup` at the bottom of `MarkdownFileView`,
listing notes whose `[[wikilinks]]` target this note; each row navigates to
that note.

The data already exists in `VaultGraph` (`GraphTopic.incoming`). Change: build
the graph once, owned by `VaultStore`, shared by the Graph tab and note views
(instead of the Graph tab building its own). Rebuild triggers match the search
index (refresh / vault change).

### 4. Rendering upgrades

All in the hand-written Markdown stack (`MarkdownParser` / `MarkdownBlock` /
`MarkdownView`), keeping the zero-third-party-dependency stance:

- **Images:** a standalone-image block (`![alt](src)` alone on a line).
  Remote URLs render via `AsyncImage` (progress + failure placeholder);
  relative paths resolve against the note's folder and load from the vault
  (materializing iCloud files if needed).
- **Callouts:** Obsidian syntax `> [!note] Title` inside blockquotes becomes a
  styled callout view — icon + tint per type (note, info, tip, warning,
  danger, quote; unknown types fall back to a neutral style). Foldable
  callouts (`[!note]-`) render as `DisclosureGroup`.
- **Task lists:** `- [ ]` / `- [x]` list items render a checkbox glyph
  (read-only; the app does not edit notes in this release).
- **Nested lists:** indent-aware list parsing (2-space or tab levels),
  rendered with per-level indentation; ordered/unordered can mix across
  levels.
- **Minimal syntax highlighting:** one lightweight generic tokenizer
  (comments, strings, numbers, keywords from a small shared set) applied to
  fenced code blocks regardless of language tag. Approximate by design — no
  per-language grammars, no third-party library. A new Core file
  (`CodeHighlighter`) producing an `AttributedString`.

### 5. Home tab

Tabs become **Home / Files / Ask / Graph**. Home is a scrollable dashboard:

- **Recents:** ~10 most recently modified notes (by `contentModificationDate`),
  tap to open.
- **Wiki index:** one row opening `wiki/index.md` (the daemon-maintained
  catalog) in the normal note view.
- **Daemon activity:** the last ~5 entries parsed from `wiki/log.md`
  (`## [YYYY-MM-DD] op | summary` lines), read-only. This gives passive
  visibility into ingestion without any new daemon endpoint, and is the
  natural future home for ingest status / clarifications.

Core logic (recents scan, log parsing) lives in UI-free structs.

### 6. Housekeeping

- README/SETUP: correct the stale "article/video not built" claims, document
  the Ask tab + daemon connection, and describe this release's features.
- Delete dead `ClipError.unsupported`.

## Error handling

- Search over unreadable/dataless files: skip and count, never fail the query.
- Image loads: placeholder on failure; no retry storms (AsyncImage default).
- `log.md` / `index.md` missing (non-daemon vaults): the Home sections hide
  rather than error.
- Wikilink resolution keeps existing behavior: alert on unresolved.

## Testing

Swift Testing in `WikiReaderTests` for all new Core logic: `VaultSearcher`
(ranking, snippets, tokenization), callout/task-list/nested-list/image-block
parsing, `CodeHighlighter` tokenization, `log.md` parsing, recents ordering.
No SwiftUI view tests (project convention). Every new view gets a `#Preview`.

## Implementation deviations (recorded 2026-07-11)

- Search results carry a plain snippet, not match ranges; result rows render
  the snippet unhighlighted. Highlighting is deferred.
- Vault-relative images do not materialize dataless iCloud files; a
  not-yet-downloaded image shows the placeholder until iCloud fetches it.
- Unresolved wikilink taps in the note view are silent no-ops (the "Note not
  found" alert exists only in the Ask tab). Follow-up candidate.

## Out of scope (this release)

- Note editing/creation (read-only stands; also avoids colliding with the
  daemon's single-writer ownership of `wiki/`).
- Ingest-status surface and clarification (`wiki/review/`) answering.
- New capture surfaces (quick text capture, Shortcuts/Siri, more clip types,
  video transcription job).
- Query history / saved-answer browsing in the Ask tab.
- Per-language syntax highlighting.
- Persistent search index.

## Future roadmap (brainstormed, unscheduled)

1. **Trust the pipeline:** per-clip ingest status (daemon already has
   `status --source` semantics; would need an HTTP endpoint or reading
   `status.json`-adjacent data), and answering `wiki/review/*.md`
   clarifications from the phone — the human-in-the-loop half of the LLM wiki.
   Note: answering requires daemon-side apply, so it needs either a new HTTP
   endpoint or writing answer files for the daemon to pick up.
2. **Capture more:** in-app quick note → `raw/sources/`, Shortcuts/Siri
   ("clip this", "note this thought"), share-extension support for plain text
   and PDFs (daemon already converts PDFs), home-machine video transcription
   worker consuming `pending/`.
3. **Deepen Ask:** query history, browse `wiki/queries/` saved answers,
   follow-up questions with conversation context.
4. **Reader polish:** frontmatter/tag browsing, Mermaid rendering, footnotes,
   theming.
