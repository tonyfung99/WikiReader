# Project: WikiReader — iOS Share Extension + Mobile Vault Viewer

## What I'm building

An iOS app with two parts:

1. **Share Extension** that clips URLs from the iOS share sheet into markdown
   files in an iCloud Drive vault folder.
2. **Host app vault viewer** that reads the same vault on iOS (file browser +
   markdown rendering + graph view), replacing the mobile-side role Obsidian
   would normally play.

The vault is a plain iCloud Drive folder (not inside any other app's
container). Apple's iCloud syncs it between iPhone and Mac. On the Mac:

- **llm_wiki** (github.com/nashsu/llm_wiki, v0.4.12) auto-watches the vault
  folder and ingests new files into a knowledge base.
- **Hermes agent** (github.com/nousresearch/hermes-agent), my personal AI
  assistant, reads and writes the vault as part of normal tasks.

End-to-end flow:

```
iOS share sheet → WikiReaderExtension → writes .md to iCloud Drive vault
folder → Apple iCloud syncs to Mac → llm_wiki ingests + Hermes reads/writes
+ WikiReader iOS host app browses/views.
```

## Why this architecture

Two design constraints drive the shape:

1. **Cross-device sync without an always-on server.** Apple iCloud Drive
   does it for free. No VPS, no auth tokens, no Tailscale. Considered a Go
   service and rejected — too many moving parts for a personal workflow.

2. **Mac-side tools (llm_wiki, Hermes agent) need a plain filesystem path
   to the vault.** Putting the vault inside Obsidian's iCloud container
   would bury it at `~/Library/Mobile Documents/iCloud~md~obsidian/...`,
   awkward and partly restricted from outside-of-Obsidian access. A plain
   iCloud Drive folder is trivially accessible from any tool, agent, or
   script on the Mac.

Each piece fails gracefully: the extension reports a clear error on network
failure; iCloud queues if Mac is offline; llm_wiki picks up files when sync
completes; Hermes works against whatever is locally materialized.

Cost of this choice: Obsidian iOS can't open vaults that live outside its
own container, so it can't be the mobile viewer. WikiReader takes over
that role.

Bonus: I'm prepping for an iOS interview, so building the viewer (file
browser, markdown rendering, graph view) in Swift has secondary value.

## Architecture

```
iOS Share Sheet
    │
    ▼
WikiReaderExtension (Swift, ~30s execution window)
    │
    ├─ Twitter/X URL → fxtwitter.com JSON → markdown
    ├─ Article URL   → fetch HTML → Readability → markdown
    ├─ Video URL     → direct extract + Whisper API → markdown
    │                  └─ if too long → write stub with
    │                     `status: pending_transcription` to pending/
    │
    ▼
Resolve security-scoped bookmark from App Group
    │
    ▼
Write .md atomically into iCloud Drive vault folder
    │
    ▼ (Apple iCloud Drive syncs to Mac)
    │
    ├─ Mac filesystem (vault path is plain user-visible folder)
    │   ├─ llm_wiki "Source Folder Auto-Watch" → ingests → wiki updates
    │   └─ Hermes agent → reads/writes vault as part of AI tasks
    │
    └─ iOS WikiReader host app
          ├─ File browser (folders, .md list)
          ├─ Markdown viewer
          └─ Graph view (parses [[wiki-links]] across vault)
```

One-time host-app setup:

```
WikiReader host app
    │
    ▼ user taps "Choose vault folder"
UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    │
    ▼ user navigates: iCloud Drive → <vault folder>
URL with security scope
    │
    ▼ bookmarkData(options: .withSecurityScope)
App Group container
    │
    ├─ Share Extension reads bookmark on every share
    └─ Host app reads bookmark on every launch (for the viewer)
```

Future: small home-machine script polls `pending/` for stubs, runs
yt-dlp + Whisper, writes finalized `.md`.

## Stack & constraints

- Xcode 16+, Swift, SwiftUI for both the host app viewer and any extension UI.
- Real iOS device for testing (simulator handles share sheet and iCloud poorly).
- Free Apple Developer account → 7-day provisioning profiles, re-sign weekly.
  - **No paid program needed.** Writing into and reading the vault uses
    security-scoped bookmarks from a user-chosen folder, not our own iCloud
    container. The iCloud capability (gated to paid program) is unnecessary.
- Two targets:
  - `WikiReader` (host app) — folder picker, bookmark persistence, file
    browser, markdown viewer, graph view.
  - `WikiReaderExtension` (Share Extension target) — URL extraction +
    markdown write.
- Capabilities on **both** targets:
  - App Groups with shared ID `group.com.<myname>.wikireader`
- `WikiReaderExtension/Info.plist` activation rule:

  ```xml
  <key>NSExtensionActivationRule</key>
  <dict>
    <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
    <integer>1</integer>
  </dict>
  ```

  So the extension only appears when sharing a URL.

## How vault access actually works

Sandbox rules forbid writing into another app's container directly. The
supported path is `UIDocumentPickerViewController` + security-scoped bookmark:

1. **Host app**: present picker in folder-open mode. User picks the vault
   folder inside iCloud Drive.
2. **Host app**: call `bookmarkData(options: .withSecurityScope, ...)` on
   the returned URL and store the resulting `Data` in the App Group container.
3. **Both processes** (host + extension) read the bookmark, resolve with
   `URL(resolvingBookmarkData:options: .withSecurityScope, ...)`, then
   `startAccessingSecurityScopedResource()` before any I/O and
   `stopAccessingSecurityScopedResource()` in a defer block.
4. **On stale**: if resolve returns `isStale: true`, host app re-prompts.
   Extension surfaces a clear "open WikiReader to re-link" error.

## Known gotchas to design around

1. Extension has ~30s execution budget before iOS kills it. Tweet/article
   paths should finish in 1-3s. Video transcription is tight; use background
   URLSession for Whisper uploads that might exceed the budget.
2. iCloud Drive creates zero-byte placeholders for files that haven't
   downloaded yet, and may briefly create empty files mid-write. Write to a
   temp name first, then rename atomically once content is complete, so
   llm_wiki's watcher doesn't trigger on empties.
3. iCloud Drive items may be **ubiquitous but not downloaded** on iOS.
   The viewer's file browser should call
   `FileManager.startDownloadingUbiquitousItem` for non-materialized files
   before reading, and present a placeholder state while download is in
   progress.
4. Bookmarks can go stale (folder moved, vault renamed). Detect `isStale`
   on resolve; host app re-prompts, extension degrades gracefully.

## Mobile vault viewer — scope

Read-only for v1. Three components:

1. **File browser** — navigate folders inside the vault, list `.md` files.
   Cache the file tree; refresh on pull-to-refresh and on view appear.
2. **Markdown viewer** — render a single `.md` file. Library candidates:
   `swift-markdown-ui`, `Down`. Pick one at milestone 3.
3. **Graph view** (stretch, but the differentiator vs. a plain MD reader)
   — parse `[[wiki-links]]` from every `.md` in the vault, build node/edge
   graph, render with force-directed layout in SwiftUI Canvas.

Explicitly **out of scope for v1**: edit/save, search, tags index,
backlinks panel, plugins, themes, canvas, sync conflict UI. Revisit after
viewer ships.

## Where I am right now

Existing Xcode scaffold: SwiftUI host app `WikiReader` already created
(`WikiReaderApp.swift`, `ContentView.swift`, asset catalog, `.xcodeproj`).
No extension target yet. llm_wiki not yet installed. Hermes agent already
configured on the Mac.

Plan:

1. Install llm_wiki on my Mac, configure with an LLM backend.
2. Verify smoke tests: drop `.md` manually into the chosen vault folder,
   confirm llm_wiki ingests it.
3. Add `WikiReaderExtension` Share Extension target. Configure App Groups
   on both targets. Set activation rule.
4. Host app: folder picker + bookmark persistence (App Group write).
5. **Swift milestone 1:** `ShareViewController` receives shared URL,
   resolves bookmark, writes a stub markdown file
   (`# Test\n\nURL: <shared url>\n`) into the vault folder, dismisses cleanly.
6. Add extraction handlers: Twitter (fxtwitter) → Article (Readability) →
   Video.
7. **Swift milestone 2:** Host app file browser — list folders/.md files
   in the vault.
8. **Swift milestone 3:** Host app markdown viewer — render a single .md file.
9. **Swift milestone 4 (stretch):** Graph view — parse wiki-links across
   vault, render force-directed graph in SwiftUI Canvas.

## Open questions

- Markdown renderer choice: `swift-markdown-ui` vs. `Down` vs. roll our own
  with Apple's `Markdown` framework. Decide at milestone 3.
- Frontmatter format llm_wiki expects (title, source_url, captured_at, tags).
  Decide after llm_wiki install.
- Filename convention: timestamp + slug? Hash? Behavior when the same URL
  is shared twice (overwrite, version, dedupe)?
- Graph view: SwiftUI Canvas with hand-rolled force layout vs. a
  third-party graph library. Decide at milestone 4.

## What I want from this session

Help me execute the plan from step 3 onward. Specifically:

- Walk me through Xcode target creation if I get stuck.
- Write the Swift code for: host app folder picker, bookmark store, share
  extension `ShareViewController`, URL classifier, vault writer, markdown
  composer, file browser, markdown viewer, graph view.
- Each piece small enough to test independently before moving on.

I'll handle Xcode-side work (creating targets, toggling capabilities, hitting
Cmd-R to run). You handle the Swift code, organization, and design decisions
that come up along the way.

## Code style preferences

- Modern Swift (async/await, not completion handlers).
- Plain structs and protocols; avoid heavy frameworks.
- Small files, single responsibility.
- Comments for non-obvious decisions only; let clean code speak for itself.
