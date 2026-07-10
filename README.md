# WikiReader

An iOS app that clips links into a plain-Markdown knowledge vault and reads
them back — a lightweight, Obsidian-style vault viewer plus a Share Extension,
built in SwiftUI with **no third-party dependencies**.

WikiReader writes Markdown files into a folder you choose (e.g. in iCloud
Drive). A share extension clips Twitter/X posts and articles straight from the
iOS share sheet; the host app browses, searches, renders, and visualizes the
vault — including a force-directed graph of `[[wiki-links]]` — and can ask the
companion wiki daemon questions. Because the vault is just a folder of
`.md` files, desktop tools (Obsidian, knowledge-base ingesters, scripts) can
read and write it too.

## Features

- **Share Extension** — clip a link from any app's share sheet. Twitter/X posts
  (fetched via fxtwitter) **and** articles are clipped fully and written as
  Markdown notes (YAML frontmatter + body), including links found in the source.
  Video URLs write a `pending/` stub awaiting a home-machine transcription job.
- **Vault viewer** — browse folders and notes in a vault you pick once
  (persisted via a security-scoped bookmark).
- **Markdown rendering** — a hand-written parser + SwiftUI renderer: headings,
  nested/task lists, code blocks (with minimal syntax highlighting), blockquotes,
  callouts, standalone images, **tables** (with column alignment), YAML
  frontmatter, and Obsidian `[[wiki-links]]`.
- **Full-text search** — the Files tab searches note bodies, not just titles;
  when nothing matches you can hand the query straight to the wiki.
- **Backlinks** — a panel on each note lists the other notes that link to it.
- **Home tab** — recents, a wiki index, and the companion daemon's log at a
  glance.
- **Ask the wiki** — the Ask tab talks to the companion `wiki-daemon` HTTP API
  (`/api/v1/health`, async `/api/v1/query` jobs) over LAN/Tailscale with a bearer
  token stored in the Keychain; answers cite `[[wiki-links]]` that open the local
  notes.
- **Graph view** — a scrollable force-directed graph of the vault's wiki-links,
  paired with a searchable topic list; tap nodes or topics to open notes.

## Architecture

Two targets sharing a pure, UI-free core:

```
WikiReader (app)              WikiReaderExtension (share)
  vault viewer UI               ShareViewController
  file browser                  clip status UI
  markdown renderer                   │
  graph view                          │
        └─────────────┬───────────────┘
                WikiReader/Core   (shared, UI-free)
     URL classifier · fxtwitter client · markdown
     composer · vault writer · bookmark store
```

- The vault is a **plain folder** the user grants access to via
  `UIDocumentPickerViewController`. Access is persisted as a **security-scoped
  bookmark** in an **App Group**, so both the app and the extension can
  read/write it. No iCloud entitlement is required — it works on a **free**
  Apple Developer account.
- Notes are written **atomically** (temp file → rename) so filesystem watchers
  never observe a partial or zero-byte file.
- Sync is whatever you put the folder in (iCloud Drive, etc.) — the app stays
  out of the sync business.

See **[PRIMER.md](PRIMER.md)** for the design rationale and
**[SETUP.md](SETUP.md)** for signing/build details.

## Tech highlights

- SwiftUI + `@Observable`, `async/await`; the core is marked `nonisolated` so
  parsing, file I/O, and networking run off the main actor.
- **Zero third-party dependencies** — Markdown parsing/rendering, the
  force-directed graph layout, and the fxtwitter client are all hand-rolled on
  Foundation/SwiftUI.
- Single-image app icon with light/dark/tinted variants.

## Requirements

- Xcode 26+, iOS 26 SDK.
- A real device is recommended (the simulator handles the share sheet and
  iCloud poorly).
- Any Apple ID — a free account is enough.

## Build & run

```bash
git clone git@github.com:tonyfung99/WikiReader.git
cd WikiReader
open WikiReader.xcodeproj
```

1. Select both targets ▸ *Signing & Capabilities* and set **your** Team. The
   bundle IDs use `com.anifoca.*` and team `QUX9EWZ335` — change them to your
   own.
2. The App Group `group.com.anifoca.WikiReader` is already configured on both
   targets; keep it or rename it (it must match on both).
3. Build & run on a device.
4. In the app, tap **Choose Vault Folder** and pick a folder.
5. Share a tweet from Safari ▸ **WikiReader** to clip it, read it in the
   **Files** tab, and explore links in the **Graph** tab.

## Project layout

```
WikiReader/
  Core/        shared, UI-free logic (bookmark, clip pipeline, fxtwitter, markdown composer)
  Vault/       vault store, file model, directory listing
  Views/       folder picker, browser, file reader
  Markdown/    block parser + SwiftUI renderer + inline/wiki-link handling
  Graph/       wiki-link graph model + force-directed Canvas view
WikiReaderExtension/   share extension (ShareViewController + status UI)
```

## Status

- ✅ Vault viewer, Markdown rendering (incl. tables and wiki-links), graph view,
  full-text search, backlinks, and the Home tab.
- ✅ Twitter/X **and** article clipping via the share extension.
- ✅ Ask the wiki via the companion `wiki-daemon` HTTP API.
- 🚧 Video clipping writes a `pending/` stub — a home-machine transcription job
  is meant to pick it up and turn it into a note later.
