# WikiReader — status & how to run

The app **and** the share extension are fully wired and build together. Verified:

- Host app builds and launches in the iOS 26 simulator (vault viewer).
- `WikiReaderExtension.appex` builds, embeds into `WikiReader.app/PlugIns/`,
  and the app installs + launches on the simulator.
- Twitter clip pipeline verified end-to-end against the **live** fxtwitter API
  (classify → fetch → compose markdown → write `.md`).

## What's already configured (no Xcode GUI needed)

- **Share Extension target** `WikiReaderExtension` (created via the `xcodeproj`
  toolkit, so the project file is valid).
- **Shared Core**: the `WikiReader/Core/*.swift` files compile into both the
  app and the extension.
- **Embed + dependency**: the app embeds the appex ("Embed Foundation
  Extensions" phase) and depends on it.
- **App Groups** entitlement `group.com.anifoca.WikiReader` on both targets
  (`WikiReader.entitlements`, `WikiReaderExtension/WikiReaderExtension.entitlements`).
- **Activation rule**: extension only appears for URLs
  (`NSExtensionActivationSupportsWebURLWithMaxCount = 1`), code-only principal
  class `ShareViewController` (no storyboard).
- Bundle ids: app `com.anifoca.WikiReader`, extension
  `com.anifoca.WikiReader.WikiReaderExtension`. Signing team is preset to
  `QUX9EWZ335` — change it to yours in *Signing & Capabilities* if needed.

> The project file was edited outside Xcode. If Xcode is open, close and reopen
> it so it reloads the new target.

## Run it on a device

A real device is recommended (the simulator handles the share sheet + iCloud
poorly).

1. Open `WikiReader.xcodeproj`, pick your Team for both targets if `QUX9EWZ335`
   isn't yours, build & run on the device.
2. In the app, tap **Choose Vault Folder** and pick your iCloud Drive vault.
3. In Safari, open a tweet (e.g. `https://x.com/jack/status/20`), tap Share ▸
   **WikiReader** → "Saved to vault".
4. Back in the app ▸ **Files** tab: the new `.md` appears; tap to read it.
   **Graph** tab: notes with `[[wiki-links]]` render as a force-directed graph.

## Decisions baked in

- Free Apple account is fine — App Groups work for development; **no iCloud
  capability** is used (vault access is via a security-scoped bookmark from the
  document picker, which also crosses the app/extension boundary via the App
  Group).
- `.withSecurityScope` is macOS-only; iOS bookmarks use no option (guarded with
  `#if os(macOS)` in `VaultAccess`).
- Files are written temp-then-renamed (`VaultWriter`) so iCloud / llm_wiki
  never observe a partial file.
- Twitter/X **and** article clipping are fully implemented in `ClipService`;
  video URLs write a `pending/` stub for a (future) home-machine transcription
  job to pick up. Extending = a new case in `ClipService.clip` + a fetcher in
  `Core/`.
