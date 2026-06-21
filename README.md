# WikiReader

An iOS app that clips links into a plain-Markdown knowledge vault and reads
them back — a lightweight, Obsidian-style vault viewer plus a Share Extension,
built in SwiftUI with **no third-party dependencies**.

WikiReader writes Markdown files into a folder you choose (e.g. in iCloud
Drive). A share extension clips Twitter/X posts straight from the iOS share
sheet; the host app browses, renders, and visualizes the vault — including a
force-directed graph of `[[wiki-links]]`. Because the vault is just a folder of
`.md` files, desktop tools (Obsidian, knowledge-base ingesters, scripts) can
read and write it too.

## Features

- **Share Extension** — clip a Twitter/X post from any app's share sheet; the
  post content is fetched via fxtwitter and written as a Markdown note (YAML
  frontmatter + body), including links found in the post.
- **Vault viewer** — browse folders and notes in a vault you pick once
  (persisted via a security-scoped bookmark).
- **Markdown rendering** — a hand-written parser + SwiftUI renderer: headings,
  lists, code blocks, blockquotes, **tables** (with column alignment), YAML
  frontmatter, and Obsidian `[[wiki-links]]`.
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

- ✅ Vault viewer, Markdown rendering (incl. tables and wiki-links), graph view.
- ✅ Twitter/X clipping via the share extension.
- 🚧 Article and video clipping are stubbed — `ClipService` returns a clear
  "not built yet" message. Adding them is a new case in `ClipService.clip`
  plus a fetcher in `Core/`.
