# WikiReader — Xcode wiring (one-time)

Everything in Swift is written and the **host app compiles clean** for the
iOS 26 simulator. Two things must be done in Xcode's GUI because they can't be
done safely from the command line: creating the Share Extension *target* and
toggling capabilities. Follow these once.

> Quit other Xcode windows for this project first — Xcode races with external
> file changes.

## 0. What's already done

- All host-app code lives under `WikiReader/` and is auto-included via Xcode's
  synchronized-folder feature (no manual file adding needed). It builds today.
- Shared logic is in `WikiReader/Core/`.
- The extension's code + Info.plist are written in `WikiReaderExtension/`
  (not yet attached to any target).
- App Group id used throughout: **`group.com.anifoca.WikiReader`**.

## 1. Create the Share Extension target

1. `File ▸ New ▸ Target… ▸ iOS ▸ Share Extension`.
2. Product Name: **`WikiReaderExtension`**. Finish. (If asked to activate the
   scheme, Cancel — keep the WikiReader scheme.)
3. Xcode scaffolds template files. **Remove** the generated
   `ShareViewController.swift` and `MainInterface.storyboard` (Move to Trash),
   and the generated `Info.plist` if it added one.

## 2. Attach the real files

1. Add the on-disk files to the extension target (drag into the
   `WikiReaderExtension` group, or they may already appear via a synchronized
   group): `ShareViewController.swift`, `ShareFlow.swift`, `Info.plist`.
2. Select the extension target ▸ **Build Settings** ▸ set
   `INFOPLIST_FILE = WikiReaderExtension/Info.plist`.
3. The provided Info.plist uses `NSExtensionPrincipalClass`
   (`$(PRODUCT_MODULE_NAME).ShareViewController`) — no storyboard needed —
   and the activation rule `NSExtensionActivationSupportsWebURLWithMaxCount = 1`
   so the extension only appears when sharing a URL.

## 3. Share the Core code with the extension

The extension uses `ClipService` and friends. Select the **`WikiReader/Core`**
group in the navigator, select all files in it, open the File Inspector
(right panel) ▸ **Target Membership** ▸ tick **`WikiReaderExtension`** (leave
`WikiReader` ticked too).

Core files the extension needs: `AppGroup`, `VaultBookmarkStore`, `VaultAccess`,
`ClipError`, `URLClassifier`, `TweetContent`, `FxTwitterClient`,
`MarkdownComposer`, `Filename`, `VaultWriter`, `ClipService`.

## 4. App Groups on BOTH targets

For **each** target (`WikiReader` and `WikiReaderExtension`):

1. Select target ▸ **Signing & Capabilities**.
2. Pick your Team (free account is fine — no iCloud capability is needed).
3. `+ Capability ▸ App Groups`.
4. `+` under App Groups ▸ add **`group.com.anifoca.WikiReader`**.

Xcode generates and wires the `.entitlements` files automatically. (For
reference, each entitlements file just contains:)

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.anifoca.WikiReader</string></array>
```

> No iCloud capability. We reach the vault through a security-scoped bookmark
> from the document picker, which works on a free account and across the
> app/extension boundary via the App Group.

## 5. Run & test on a device

A real device is recommended (the simulator handles the share sheet and iCloud
poorly).

1. Run `WikiReader`. Tap **Choose Vault Folder**, pick your iCloud Drive vault.
2. Open Safari, go to any tweet (e.g. `https://x.com/jack/status/20`), tap
   Share ▸ **WikiReader**. You should see “Saved to vault”.
3. Back in WikiReader ▸ **Files** tab: the new `.md` appears; tap to read it.
4. **Graph** tab: notes with `[[wiki-links]]` show as a force-directed graph;
   tap a node to open that note.

## Notes / decisions baked in

- `.withSecurityScope` is **macOS-only**; on iOS we create/resolve bookmarks
  with no option (guarded by `#if os(macOS)` in `VaultAccess`).
- Files are written temp-then-renamed so llm_wiki / iCloud never see a partial
  file (`VaultWriter`).
- Only the Twitter/X path is implemented in `ClipService`; article and video
  URLs return a clear "not built yet" message. Adding them later means new
  cases in `ClipService.clip` + a fetcher in `Core/`.
