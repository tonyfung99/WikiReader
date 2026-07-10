# Reader Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make WikiReader a first-class vault reader: fix wikilink navigation, add full-text search (with "Ask the wiki" escalation), a backlinks panel, richer Markdown rendering (nested/task lists, callouts, images, minimal syntax highlighting), and a Home tab.

**Architecture:** All new logic follows the existing pattern — UI-free `nonisolated` structs/enums for parsing and vault crawling (testable via the hosted `WikiReaderTests` target), thin SwiftUI views on top, `@Observable` classes only for shared session state. A new `VaultIndex` `@Observable` (owned by `MainTabs`, injected via `.environment`) builds the wiki-link graph and search index once per vault session and shares them across tabs. Spec: `docs/superpowers/specs/2026-07-10-reader-release-design.md`.

**Tech Stack:** Swift / SwiftUI (iOS 26, Xcode 26), Swift Testing (`@Test`, `#expect`, `#require`), zero third-party dependencies.

## Global Constraints

- **No third-party dependencies.** Everything is hand-rolled (existing convention).
- **Apple-native "MV" pattern, never MVVM:** `@Observable` classes for shared state (never `ObservableObject`); `@State` only for view-owned models; plain `let` for passed-in models; `@Environment` for app-wide. No inline `Binding(get:set:)` in a view body.
- **Every new SwiftUI view gets a `#Preview`** (use `#if DEBUG` sample-data helpers when inputs are needed).
- **Tests are Swift Testing**, not XCTest: `import Testing`, `@testable import WikiReader`, `@MainActor struct XxxTests`, `@Test func`, `#expect` / `#require`. Test all new UI-free logic; do NOT unit-test SwiftUI views.
- **The Xcode project uses filesystem-synchronized groups** — new `.swift` files placed under `WikiReader/`, `WikiReaderExtension/`, or `WikiReaderTests/` are picked up automatically. Do NOT edit `project.pbxproj`.
- **Build command** (used by every "verify it builds" step):
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
- Run all commands from the repo root: `/Users/tonyfung/workspace/WikiReader`.

---

### Task 1: Fix wikilink navigation from the file browser and graph

Wikilink taps are silently swallowed when a note is opened from the Files or Graph tab, because `MarkdownFileView` only resolves `[[links]]` when constructed with a non-nil `root` — and those two call sites omit it. Pure view wiring; no unit test (project convention: don't test views). Verified by build + manual check.

**Files:**
- Modify: `WikiReader/Views/VaultBrowserView.swift`
- Modify: `WikiReader/Graph/GraphView.swift` (line ~28)
- Modify: `WikiReader/ContentView.swift` (line ~54)

**Interfaces:**
- Consumes: existing `MarkdownFileView(file:root:)` initializer.
- Produces: `VaultBrowserView(directory:title:root:)` — a new required `root: URL` parameter that later tasks (Task 8's `FilesTabView`) also use.

- [ ] **Step 1: Add `root` to `VaultBrowserView` and pass it through**

In `WikiReader/Views/VaultBrowserView.swift`, add the property and thread it through both navigation destinations:

```swift
struct VaultBrowserView: View {
    let directory: URL
    let title: String
    let root: URL
```

Change the two `NavigationLink` destinations:

```swift
                if file.isDirectory {
                    NavigationLink {
                        VaultBrowserView(directory: file.url, title: file.name, root: root)
                    } label: {
                        Label(file.name, systemImage: "folder")
                    }
                } else {
                    NavigationLink {
                        MarkdownFileView(file: file, root: root)
                    } label: {
                        Label(file.displayName, systemImage: file.isPlaceholder ? "arrow.down.circle" : "doc.text")
                    }
                }
```

Update the preview at the bottom of the file:

```swift
#Preview {
    NavigationStack {
        VaultBrowserView(directory: previewVaultDirectory(), title: "Vault", root: previewVaultDirectory())
    }
}
```

- [ ] **Step 2: Pass `root` at the two call sites**

In `WikiReader/ContentView.swift` (inside `MainTabs`), change:

```swift
                VaultBrowserView(directory: root, title: store.displayName ?? "Vault", root: root)
```

In `WikiReader/Graph/GraphView.swift` (inside `GraphScreen`), change the navigation destination:

```swift
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
```

- [ ] **Step 3: Build**

Run the build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add WikiReader/Views/VaultBrowserView.swift WikiReader/Graph/GraphView.swift WikiReader/ContentView.swift
git commit -m "fix: resolve wikilinks when notes are opened from browser or graph"
```

---

### Task 2: Nested lists and task lists

Replace the flat `bulletList`/`numberedList` block kinds with a single `.list` kind whose items carry nesting depth, an optional ordered number (assigned at parse time), and an optional task-checkbox state. The parser currently trims lines before matching, losing indentation — the rewrite must read indentation from the raw line.

**Files:**
- Modify: `WikiReader/Markdown/MarkdownBlock.swift`
- Modify: `WikiReader/Markdown/MarkdownParser.swift`
- Modify: `WikiReader/Markdown/MarkdownView.swift`
- Test: `WikiReaderTests/MarkdownParserTests.swift` (update 2 lines + add new tests)

**Interfaces:**
- Produces: `MarkdownListItem` (`text: String`, `depth: Int`, `number: Int?`, `checked: Bool?`) and `MarkdownBlock.Kind.list(items: [MarkdownListItem])`. The old `bulletList`/`numberedList` cases are deleted. Task 5 and later tasks render against this shape.

- [ ] **Step 1: Write the failing tests**

Add to `WikiReaderTests/MarkdownParserTests.swift`:

```swift
    private func firstList(_ blocks: [MarkdownBlock]) -> [MarkdownListItem]? {
        for block in blocks {
            if case .list(let items) = block.kind { return items }
        }
        return nil
    }

    @Test func parsesNestedListDepths() throws {
        let md = """
        - top
          - child
            - grandchild
        - top two
        """
        let items = try #require(firstList(MarkdownParser.parse(md)))
        #expect(items.map(\.text) == ["top", "child", "grandchild", "top two"])
        #expect(items.map(\.depth) == [0, 1, 2, 0])
        #expect(items.allSatisfy { $0.number == nil && $0.checked == nil })
    }

    @Test func parsesTaskListStates() throws {
        let md = """
        - [ ] open item
        - [x] done item
        - plain item
        """
        let items = try #require(firstList(MarkdownParser.parse(md)))
        #expect(items.map(\.checked) == [false, true, nil])
        #expect(items.map(\.text) == ["open item", "done item", "plain item"])
    }

    @Test func numbersOrderedItemsPerDepth() throws {
        let md = """
        1. first
        2. second
           - detail
        3. third
        """
        let items = try #require(firstList(MarkdownParser.parse(md)))
        #expect(items.map(\.number) == [1, 2, nil, 3])
        #expect(items.map(\.depth) == [0, 0, 1, 0])
    }

    @Test func mixedMarkersStayOneListBlock() throws {
        let md = """
        1. step
           - note under step
        2. next step
        """
        let blocks = MarkdownParser.parse(md)
        let listBlocks = blocks.filter { if case .list = $0.kind { true } else { false } }
        #expect(listBlocks.count == 1)
    }
```

Also update the two existing expectations that use the old cases (currently lines 66–67):

```swift
        #expect(kinds.contains { if case .list(let items) = $0 { items.map(\.text) == ["a", "b"] && items.allSatisfy { $0.number == nil } } else { false } })
        #expect(kinds.contains { if case .list(let items) = $0 { items.compactMap(\.number) == [1, 2] } else { false } })
```

(If the sample markdown in that existing test has the bullet list and numbered list adjacent with no blank line, they now merge into one `.list` block — separate them with a blank line in the sample if needed.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/MarkdownParserTests
```
Expected: compile FAILURE (`MarkdownListItem` and `.list` do not exist yet). A compile failure is the failing state here.

- [ ] **Step 3: Implement the model change**

In `WikiReader/Markdown/MarkdownBlock.swift`, replace the two list cases and add the item struct:

```swift
nonisolated struct MarkdownListItem: Equatable {
    let text: String
    /// 0-based nesting level (2 spaces or 1 tab per level).
    let depth: Int
    /// 1-based number for ordered items, nil for bullets.
    let number: Int?
    /// nil unless the item is a `- [ ]` / `- [x]` task.
    let checked: Bool?
}
```

In `MarkdownBlock.Kind`, delete `bulletList(items: [String])` and `numberedList(items: [String])` and add:

```swift
        case list(items: [MarkdownListItem])
```

- [ ] **Step 4: Rewrite `parseList` in `MarkdownParser.swift`**

Replace the current `parseList` and its two call sites. In the main `parse` loop, replace the two list branches with one:

```swift
            } else if isBullet(trimmed) || isOrdered(trimmed) {
                let (block, next) = parseList(lines, start: index)
                blocks.append(block)
                index = next
            }
```

New implementation (replaces the old `parseList`; keep `isBullet`, `isOrdered`, `listItemText` as they are):

```swift
    private static func parseList(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        var items: [MarkdownListItem] = []
        var counters: [Int: Int] = [:]
        var index = start
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ordered = isOrdered(trimmed)
            guard ordered || isBullet(trimmed) else { break }

            let depth = indentDepth(raw)
            for key in counters.keys where key > depth { counters[key] = nil }

            var number: Int?
            if ordered {
                let next = (counters[depth] ?? 0) + 1
                counters[depth] = next
                number = next
            } else {
                counters[depth] = nil
            }

            var text = listItemText(trimmed, ordered: ordered)
            var checked: Bool?
            if text.hasPrefix("[ ]") {
                checked = false
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("[x]") || text.hasPrefix("[X]") {
                checked = true
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }

            items.append(MarkdownListItem(text: text, depth: depth, number: number, checked: checked))
            index += 1
        }
        return (MarkdownBlock(kind: .list(items: items)), index)
    }

    private static func indentDepth(_ raw: String) -> Int {
        var width = 0
        for char in raw {
            if char == " " { width += 1 }
            else if char == "\t" { width += 2 }
            else { break }
        }
        return width / 2
    }
```

Note: ordered items indented 3 spaces (`   - detail` under `1. first`) land at depth 1 because `3 / 2 == 1` — that is the behavior the tests pin down.

- [ ] **Step 5: Update `MarkdownView.swift` rendering**

Replace the `.bulletList` and `.numberedList` cases in `view(for:)` with:

```swift
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(for: item)
                        Text(MarkdownInline.attributed(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 20)
                }
            }
```

Add the marker helper to `MarkdownView`:

```swift
    @ViewBuilder
    private func listMarker(for item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.callout)
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        } else if let number = item.number {
            Text("\(number).").monospacedDigit()
        } else {
            Text("•")
        }
    }
```

Extend the `#Preview` sample in `MarkdownView.swift` — inside the `## A list` section, add nested and task items so the preview exercises the new rendering:

```
    - first item
    - second item
      - nested item
    - [ ] open task
    - [x] done task
```

- [ ] **Step 6: Run the parser tests**

Same command as Step 2.
Expected: PASS (all `MarkdownParserTests`, including the pre-existing ones).

- [ ] **Step 7: Build the app (catches any other usage of the deleted cases)**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add WikiReader/Markdown/ WikiReaderTests/MarkdownParserTests.swift
git commit -m "feat: nested lists and task-list checkboxes in markdown"
```

---

### Task 3: Obsidian callouts

`> [!note] Title` blockquotes become styled callout boxes; `> [!note]-` renders folded (a `DisclosureGroup`). Unknown types fall back to a neutral style.

**Files:**
- Modify: `WikiReader/Markdown/MarkdownBlock.swift`
- Modify: `WikiReader/Markdown/MarkdownParser.swift` (extend `parseQuote`)
- Modify: `WikiReader/Markdown/MarkdownView.swift` (new `CalloutView`)
- Test: `WikiReaderTests/MarkdownParserTests.swift`

**Interfaces:**
- Produces: `MarkdownBlock.Kind.callout(type: String, title: String, lines: [String], foldable: Bool)`. `type` is lowercased; `title` defaults to the capitalized type when the header has no title text.

- [ ] **Step 1: Write the failing tests**

Add to `WikiReaderTests/MarkdownParserTests.swift`:

```swift
    private func firstCallout(_ blocks: [MarkdownBlock]) -> (type: String, title: String, lines: [String], foldable: Bool)? {
        for block in blocks {
            if case .callout(let type, let title, let lines, let foldable) = block.kind {
                return (type, title, lines, foldable)
            }
        }
        return nil
    }

    @Test func parsesCalloutWithTitle() throws {
        let md = """
        > [!warning] Watch out
        > This is the body.
        > Second line.
        """
        let callout = try #require(firstCallout(MarkdownParser.parse(md)))
        #expect(callout.type == "warning")
        #expect(callout.title == "Watch out")
        #expect(callout.lines == ["This is the body.", "Second line."])
        #expect(callout.foldable == false)
    }

    @Test func calloutWithoutTitleUsesCapitalizedType() throws {
        let md = "> [!note]\n> body"
        let callout = try #require(firstCallout(MarkdownParser.parse(md)))
        #expect(callout.type == "note")
        #expect(callout.title == "Note")
    }

    @Test func foldableCalloutDetected() throws {
        let md = "> [!tip]- Folded tip\n> hidden body"
        let callout = try #require(firstCallout(MarkdownParser.parse(md)))
        #expect(callout.foldable == true)
        #expect(callout.title == "Folded tip")
    }

    @Test func plainQuoteStaysQuote() {
        let blocks = MarkdownParser.parse("> just a quote\n> second line")
        #expect(blocks.contains { if case .quote = $0.kind { true } else { false } })
        #expect(!blocks.contains { if case .callout = $0.kind { true } else { false } })
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/MarkdownParserTests
```
Expected: compile FAILURE (`.callout` does not exist).

- [ ] **Step 3: Implement**

Add to `MarkdownBlock.Kind`:

```swift
        case callout(type: String, title: String, lines: [String], foldable: Bool)
```

In `MarkdownParser.swift`, change the end of `parseQuote` to try callout detection first:

```swift
    private static func parseQuote(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        var quoted: [String] = []
        var index = start
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            line.removeFirst()
            quoted.append(line.hasPrefix(" ") ? String(line.dropFirst()) : line)
            index += 1
        }
        if let callout = parseCallout(quoted) {
            return (callout, index)
        }
        return (MarkdownBlock(kind: .quote(lines: quoted)), index)
    }

    private static func parseCallout(_ quoted: [String]) -> MarkdownBlock? {
        guard let first = quoted.first,
              let regex = try? NSRegularExpression(pattern: "^\\[!([A-Za-z]+)\\](-?)\\s*(.*)$") else {
            return nil
        }
        let ns = first as NSString
        guard let match = regex.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let type = ns.substring(with: match.range(at: 1)).lowercased()
        let foldable = ns.substring(with: match.range(at: 2)) == "-"
        let title = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock(kind: .callout(
            type: type,
            title: title.isEmpty ? type.capitalized : title,
            lines: Array(quoted.dropFirst()),
            foldable: foldable
        ))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Render callouts in `MarkdownView.swift`**

Add the case to `view(for:)`:

```swift
        case .callout(let type, let title, let lines, let foldable):
            CalloutView(type: type, title: title, lines: lines, foldable: foldable)
```

Add the view (file-private, below `FrontmatterView`):

```swift
private struct CalloutView: View {
    let type: String
    let title: String
    let lines: [String]
    let foldable: Bool

    @State private var expanded = false

    private var icon: String {
        switch type {
        case "note": "pencil"
        case "info": "info.circle"
        case "tip", "hint": "lightbulb"
        case "warning", "caution": "exclamationmark.triangle"
        case "danger", "error", "bug": "xmark.octagon"
        case "quote", "cite": "quote.opening"
        case "success", "check", "done": "checkmark.circle"
        case "question", "help", "faq": "questionmark.circle"
        default: "pin"
        }
    }

    private var tint: Color {
        switch type {
        case "note", "info": .blue
        case "tip", "hint": .teal
        case "warning", "caution": .orange
        case "danger", "error", "bug": .red
        case "success", "check", "done": .green
        case "question", "help", "faq": .purple
        default: .gray
        }
    }

    var body: some View {
        Group {
            if foldable {
                DisclosureGroup(isExpanded: $expanded) {
                    bodyText.padding(.top, 4)
                } label: {
                    header
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if !lines.isEmpty {
                        bodyText
                    }
                }
            }
        }
        .padding(12)
        .background(tint.opacity(0.1))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var bodyText: some View {
        Text(MarkdownInline.attributed(lines.joined(separator: "\n")))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

Extend the `#Preview` sample in `MarkdownView.swift` with:

```
    > [!warning] Careful
    > Callouts render with icon and tint.

    > [!tip]- Folded tip
    > Hidden until expanded.
```

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/Markdown/ WikiReaderTests/MarkdownParserTests.swift
git commit -m "feat: render Obsidian callouts"
```

---

### Task 4: Standalone image blocks

A line that is exactly `![alt](src)` becomes an image block. Remote (`http`/`https`) sources render via `AsyncImage`; relative paths load from the vault next to the note. Failures show a labeled placeholder.

**Files:**
- Modify: `WikiReader/Markdown/MarkdownBlock.swift`
- Modify: `WikiReader/Markdown/MarkdownParser.swift`
- Modify: `WikiReader/Markdown/MarkdownView.swift` (new `MarkdownImageView`, new `baseDirectory` parameter)
- Modify: `WikiReader/Views/MarkdownFileView.swift` (pass `baseDirectory`)
- Test: `WikiReaderTests/MarkdownParserTests.swift`

**Interfaces:**
- Produces: `MarkdownBlock.Kind.image(alt: String, source: String)` and `MarkdownView(blocks:baseDirectory:)` where `baseDirectory: URL? = nil` (existing call sites keep compiling; only `MarkdownFileView` passes it).

- [ ] **Step 1: Write the failing tests**

Add to `WikiReaderTests/MarkdownParserTests.swift`:

```swift
    @Test func parsesStandaloneImageBlock() throws {
        let blocks = MarkdownParser.parse("![diagram](media/pic.png)")
        let found = blocks.contains {
            if case .image(let alt, let source) = $0.kind {
                alt == "diagram" && source == "media/pic.png"
            } else { false }
        }
        #expect(found)
    }

    @Test func imageLineBreaksParagraph() {
        let blocks = MarkdownParser.parse("some text\n![p](a.png)\nmore text")
        let images = blocks.filter { if case .image = $0.kind { true } else { false } }
        let paragraphs = blocks.filter { if case .paragraph = $0.kind { true } else { false } }
        #expect(images.count == 1)
        #expect(paragraphs.count == 2)
    }

    @Test func inlineImageInSentenceStaysParagraph() {
        let blocks = MarkdownParser.parse("see ![icon](i.png) here")
        #expect(!blocks.contains { if case .image = $0.kind { true } else { false } })
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Same `-only-testing:WikiReaderTests/MarkdownParserTests` command.
Expected: compile FAILURE (`.image` does not exist).

- [ ] **Step 3: Implement the parser**

Add to `MarkdownBlock.Kind`:

```swift
        case image(alt: String, source: String)
```

In `MarkdownParser.parse`'s main loop, add a branch immediately before the `isTableStart` branch:

```swift
            } else if let image = parseImage(trimmed) {
                blocks.append(image)
                index += 1
            }
```

Add the helper:

```swift
    private static func parseImage(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("!"),
              let regex = try? NSRegularExpression(pattern: "^!\\[([^\\]]*)\\]\\(([^)]+)\\)$") else {
            return nil
        }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let alt = ns.substring(with: match.range(at: 1))
        let source = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock(kind: .image(alt: alt, source: source))
    }
```

In `parseParagraph`, add `|| parseImage(trimmed) != nil` to the break condition list (after `|| isTableStart(lines, index)`).

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Render images**

In `MarkdownView.swift`, add the stored property (defaulted so existing `MarkdownView(blocks:)` call sites compile):

```swift
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseDirectory: URL? = nil
```

Add the case to `view(for:)`:

```swift
        case .image(let alt, let source):
            MarkdownImageView(alt: alt, source: source, baseDirectory: baseDirectory)
```

Add the view (file-private):

```swift
private struct MarkdownImageView: View {
    let alt: String
    let source: String
    let baseDirectory: URL?

    var body: some View {
        Group {
            if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            } else if let image = localImage {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    private var remoteURL: URL? {
        let lower = source.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }

    private var localImage: UIImage? {
        guard let baseDirectory else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        let url = baseDirectory.appendingPathComponent(decoded)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var placeholder: some View {
        Label(alt.isEmpty ? "Image unavailable" : alt, systemImage: "photo")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.08))
    }
}
```

In `WikiReader/Views/MarkdownFileView.swift`, pass the note's folder:

```swift
                    MarkdownView(blocks: blocks, baseDirectory: file.url.deletingLastPathComponent())
```

Extend the `#Preview` sample in `MarkdownView.swift` with a remote image line:

```
    ![WikiReader](https://www.apple.com/favicon.ico)
```

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/Markdown/ WikiReader/Views/MarkdownFileView.swift WikiReaderTests/MarkdownParserTests.swift
git commit -m "feat: render standalone image blocks (remote and vault-relative)"
```

---

### Task 5: Minimal code syntax highlighting

One generic tokenizer (comments, strings, numbers, a shared keyword set) applied to every fenced code block regardless of language tag. Approximate by design — no per-language grammars.

**Files:**
- Create: `WikiReader/Markdown/CodeHighlighter.swift`
- Modify: `WikiReader/Markdown/MarkdownView.swift` (`.code` case)
- Test: `WikiReaderTests/CodeHighlighterTests.swift` (new file)

**Interfaces:**
- Produces: `CodeHighlighter.tokenize(_ code: String) -> [CodeHighlighter.Token]` (pure, tested) and `CodeHighlighter.attributed(_ code: String) -> AttributedString` (maps token kinds to colors; used by `MarkdownView`). `Token` is `(text: String, kind: TokenKind)`; `TokenKind` is `plain | keyword | string | comment | number`. Concatenating all token texts reproduces the input exactly.

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/CodeHighlighterTests.swift`:

```swift
import Testing
@testable import WikiReader

@MainActor
struct CodeHighlighterTests {
    @Test func classifiesKeywordsStringsNumbers() {
        let tokens = CodeHighlighter.tokenize("let x = \"hi\" + 42")
        #expect(tokens.contains { $0.text == "let" && $0.kind == .keyword })
        #expect(tokens.contains { $0.text == "\"hi\"" && $0.kind == .string })
        #expect(tokens.contains { $0.text == "42" && $0.kind == .number })
    }

    @Test func lineCommentRunsToEndOfLine() {
        let tokens = CodeHighlighter.tokenize("code // trailing comment\nnext")
        #expect(tokens.contains { $0.text == "// trailing comment" && $0.kind == .comment })
        #expect(tokens.contains { $0.text == "next" && $0.kind == .plain })
    }

    @Test func hashCommentDetected() {
        let tokens = CodeHighlighter.tokenize("# python comment")
        #expect(tokens.first?.kind == .comment)
    }

    @Test func identifiersContainingKeywordsStayPlain() {
        let tokens = CodeHighlighter.tokenize("letter iffy")
        #expect(tokens.allSatisfy { $0.kind != .keyword })
    }

    @Test func roundTripPreservesText() {
        let code = "func greet(name: String) -> String {\n    return \"hi \\(name)\" // 1\n}"
        let rebuilt = CodeHighlighter.tokenize(code).map(\.text).joined()
        #expect(rebuilt == code)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/CodeHighlighterTests
```
Expected: compile FAILURE (`CodeHighlighter` does not exist).

- [ ] **Step 3: Implement**

Create `WikiReader/Markdown/CodeHighlighter.swift`:

```swift
import SwiftUI

/// Minimal, language-agnostic code highlighting: line comments, quoted
/// strings, numbers, and a shared keyword set. Approximate by design — one
/// tokenizer for every fence, no per-language grammars.
nonisolated enum CodeHighlighter {
    enum TokenKind: Equatable {
        case plain, keyword, string, comment, number
    }

    struct Token: Equatable {
        let text: String
        let kind: TokenKind
    }

    private static let keywords: Set<String> = [
        "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
        "if", "else", "elif", "for", "while", "return", "import", "from",
        "def", "function", "const", "public", "private", "static", "final",
        "guard", "switch", "case", "break", "continue", "default",
        "try", "catch", "except", "throw", "throws", "async", "await",
        "in", "is", "as", "not", "and", "or",
        "true", "false", "nil", "null", "None", "True", "False",
        "self", "this", "new", "type", "interface", "impl", "fn", "match",
    ]

    static func tokenize(_ code: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(code)
        var i = 0

        func flushPlain(_ buffer: inout String) {
            guard !buffer.isEmpty else { return }
            tokens.append(Token(text: buffer, kind: .plain))
            buffer = ""
        }

        var plain = ""
        while i < chars.count {
            let c = chars[i]

            // Line comments: // or #
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" || c == "#" {
                flushPlain(&plain)
                var comment = ""
                while i < chars.count && chars[i] != "\n" {
                    comment.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: comment, kind: .comment))
                continue
            }

            // Strings: "..." or '...' (with backslash escapes, single line)
            if c == "\"" || c == "'" {
                flushPlain(&plain)
                let quote = c
                var literal = String(quote)
                i += 1
                while i < chars.count && chars[i] != "\n" {
                    literal.append(chars[i])
                    if chars[i] == quote && chars[i - 1] != "\\" {
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(Token(text: literal, kind: .string))
                continue
            }

            // Numbers
            if c.isNumber && !(plain.last?.isLetter ?? false) {
                flushPlain(&plain)
                var number = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    number.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: number, kind: .number))
                continue
            }

            // Words (identifiers / keywords)
            if c.isLetter || c == "_" {
                flushPlain(&plain)
                var word = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: word, kind: keywords.contains(word) ? .keyword : .plain))
                continue
            }

            plain.append(c)
            i += 1
        }
        flushPlain(&plain)
        return coalescePlain(tokens)
    }

    /// Merges adjacent plain tokens so round-tripping stays simple.
    private static func coalescePlain(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for token in tokens {
            if token.kind == .plain, let last = result.last, last.kind == .plain {
                result[result.count - 1] = Token(text: last.text + token.text, kind: .plain)
            } else {
                result.append(token)
            }
        }
        return result
    }

    static func attributed(_ code: String) -> AttributedString {
        var result = AttributedString()
        for token in tokenize(code) {
            var piece = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .keyword: piece.foregroundColor = .pink
            case .string: piece.foregroundColor = .orange
            case .comment: piece.foregroundColor = .secondary
            case .number: piece.foregroundColor = .blue
            }
            result += piece
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS. If `identifiersContainingKeywordsStayPlain` or `roundTripPreservesText` fails, fix the tokenizer — do not weaken the tests.

- [ ] **Step 5: Wire into `MarkdownView`**

In `MarkdownView.swift`, change the `.code` case body's `Text(code)` to:

```swift
                Text(CodeHighlighter.attributed(code))
```

(keep the surrounding `ScrollView`, font, padding, and background exactly as they are). Extend the `#Preview` fence to include highlights:

```
    ```swift
    // the answer
    let answer = 42
    print("hello")
    ```
```

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/Markdown/CodeHighlighter.swift WikiReader/Markdown/MarkdownView.swift WikiReaderTests/CodeHighlighterTests.swift
git commit -m "feat: minimal generic syntax highlighting for code blocks"
```

---

### Task 6: `VaultSearcher` — full-text search core

UI-free search index: crawl `.md` files once, hold lowercased contents in memory, answer queries with AND-token matching ranked title > headings > body, and produce a snippet around the first match.

**Files:**
- Create: `WikiReader/Vault/VaultSearcher.swift`
- Test: `WikiReaderTests/VaultSearcherTests.swift` (new file)

**Interfaces:**
- Produces:
  - `SearchResult` — `file: VaultFile`, `title: String`, `snippet: String`, `score: Int`; `Identifiable` by `file.url`.
  - `VaultSearcher.build(root: URL) -> VaultSearcher` — crawls and indexes; counts unreadable files in `skippedCount: Int` and triggers `startDownloadingUbiquitousItem` for any `.icloud` placeholders it encounters.
  - `searcher.search(_ query: String, limit: Int = 50) -> [SearchResult]`.
- Task 7's `VaultIndex` owns an instance; Task 8's UI calls `search`.

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/VaultSearcherTests.swift`:

```swift
import Foundation
import Testing
@testable import WikiReader

@MainActor
struct VaultSearcherTests {
    /// Builds a throwaway vault on disk and returns its root.
    private func makeVault(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("searcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, contents) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func titleMatchOutranksBodyMatch() throws {
        let root = try makeVault([
            "Swift Concurrency.md": "notes about actors",
            "Journal.md": "today I studied swift concurrency for hours swift swift",
        ])
        let results = VaultSearcher.build(root: root).search("swift")
        #expect(results.count == 2)
        #expect(results[0].title == "Swift Concurrency")
    }

    @Test func headingMatchOutranksBodyMatch() throws {
        let root = try makeVault([
            "A.md": "# Databases\nsome text",
            "B.md": "text mentioning databases once",
        ])
        let results = VaultSearcher.build(root: root).search("databases")
        #expect(results.first?.title == "A")
    }

    @Test func allTokensMustMatch() throws {
        let root = try makeVault([
            "Both.md": "alpha beta",
            "OnlyAlpha.md": "alpha gamma",
        ])
        let results = VaultSearcher.build(root: root).search("alpha beta")
        #expect(results.map(\.title) == ["Both"])
    }

    @Test func emptyQueryReturnsNothing() throws {
        let root = try makeVault(["A.md": "text"])
        #expect(VaultSearcher.build(root: root).search("   ").isEmpty)
    }

    @Test func searchIsCaseInsensitive() throws {
        let root = try makeVault(["Note.md": "Contains MixedCase Word"])
        #expect(VaultSearcher.build(root: root).search("mixedcase").count == 1)
    }

    @Test func snippetSurroundsMatchWithEllipses() {
        let text = String(repeating: "x", count: 200) + " needle " + String(repeating: "y", count: 200)
        let snippet = VaultSearcher.snippet(in: text, around: "needle")
        #expect(snippet.contains("needle"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.count < 200)
    }

    @Test func nonMarkdownFilesIgnored() throws {
        let root = try makeVault(["real.md": "findme", "skip.txt": "findme"])
        #expect(VaultSearcher.build(root: root).search("findme").count == 1)
    }

    @Test func subdirectoriesAreIndexed() throws {
        let root = try makeVault(["wiki/entities/Person.md": "findme deep"])
        #expect(VaultSearcher.build(root: root).search("findme").count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/VaultSearcherTests
```
Expected: compile FAILURE (`VaultSearcher` does not exist).

- [ ] **Step 3: Implement**

Create `WikiReader/Vault/VaultSearcher.swift`:

```swift
import Foundation

nonisolated struct SearchResult: Identifiable, Equatable {
    let file: VaultFile
    let title: String
    let snippet: String
    let score: Int

    var id: URL { file.url }
}

/// In-memory full-text index over the vault's markdown files. At current
/// vault scale (hundreds of notes, a few MB) a linear scan per query is
/// instant; revisit only past ~10k notes.
nonisolated struct VaultSearcher {
    struct Document: Equatable {
        let file: VaultFile
        let title: String
        let titleLower: String
        let headingsLower: String
        let bodyLower: String
        let rawBody: String
    }

    let documents: [Document]
    /// Files that couldn't be read (e.g. iCloud not downloaded yet).
    let skippedCount: Int

    static func build(root: URL) -> VaultSearcher {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return VaultSearcher(documents: [], skippedCount: 0)
        }

        var documents: [Document] = []
        var skipped = 0

        for case let url as URL in enumerator {
            if url.lastPathComponent.hasSuffix(".icloud") {
                skipped += 1
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                skipped += 1
                continue
            }
            let file = VaultFile(url: url, isDirectory: false)
            let headings = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .joined(separator: " ")
            documents.append(Document(
                file: file,
                title: file.displayName,
                titleLower: file.displayName.lowercased(),
                headingsLower: headings.lowercased(),
                bodyLower: text.lowercased(),
                rawBody: text
            ))
        }
        return VaultSearcher(documents: documents, skippedCount: skipped)
    }

    func search(_ query: String, limit: Int = 50) -> [SearchResult] {
        let tokens = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        var results: [SearchResult] = []
        for document in documents {
            var score = 0
            var matchedAll = true
            for token in tokens {
                var tokenScore = 0
                if document.titleLower.contains(token) { tokenScore += 100 }
                if document.headingsLower.contains(token) { tokenScore += 20 }
                if document.bodyLower.contains(token) { tokenScore += 1 }
                guard tokenScore > 0 else {
                    matchedAll = false
                    break
                }
                score += tokenScore
            }
            guard matchedAll else { continue }
            results.append(SearchResult(
                file: document.file,
                title: document.title,
                snippet: Self.snippet(in: document.rawBody, around: tokens[0]),
                score: score
            ))
        }

        return Array(
            results.sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    static func snippet(in text: String, around token: String, radius: Int = 60) -> String {
        guard let range = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(radius * 2)).replacingOccurrences(of: "\n", with: " ")
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WikiReader/Vault/VaultSearcher.swift WikiReaderTests/VaultSearcherTests.swift
git commit -m "feat: in-memory full-text vault search core"
```

---

### Task 7: `VaultIndex` — shared graph + search index

An `@Observable` session object that builds `VaultGraph` and `VaultSearcher` once, off-main, and is shared across tabs via the environment. `GraphScreen` switches to it (with a local-build fallback so previews keep working).

**Files:**
- Create: `WikiReader/Vault/VaultIndex.swift`
- Modify: `WikiReader/ContentView.swift` (create + inject)
- Modify: `WikiReader/Graph/GraphView.swift` (`GraphScreen` consumes it)

**Interfaces:**
- Consumes: `VaultGraph.build(root:)`, `VaultSearcher.build(root:)` (Task 6).
- Produces: `VaultIndex` — `init(root: URL)`, `var graph: VaultGraph?`, `var searcher: VaultSearcher?`, `var isBuilding: Bool`, `func ensureBuilt()`, `func rebuild()`. Injected with `.environment(index)`; consumers read it as `@Environment(VaultIndex.self) private var index: VaultIndex?` (optional, so previews without injection still work). Tasks 8 and 9 rely on this exact shape.

This is a thin session-state wrapper like `VaultStore` (which is also untested); the logic it orchestrates is tested in Tasks 6 and the existing `VaultGraph` tests. No new unit test.

- [ ] **Step 1: Create `WikiReader/Vault/VaultIndex.swift`**

```swift
import Foundation
import Observation

/// Vault-wide derived data — the wiki-link graph and the full-text search
/// index — built once per vault session, off the main thread, and shared
/// across tabs via the environment.
@MainActor
@Observable
final class VaultIndex {
    let root: URL

    private(set) var graph: VaultGraph?
    private(set) var searcher: VaultSearcher?
    private(set) var isBuilding = false

    private var buildTask: Task<Void, Never>?

    init(root: URL) {
        self.root = root
    }

    /// Builds the index if it hasn't been built yet. Safe to call repeatedly.
    func ensureBuilt() {
        guard graph == nil, buildTask == nil else { return }
        rebuild()
    }

    /// Discards and rebuilds (e.g. after pull-to-refresh).
    func rebuild() {
        buildTask?.cancel()
        isBuilding = true
        let url = root
        buildTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                (VaultGraph.build(root: url), VaultSearcher.build(root: url))
            }.value
            graph = built.0
            searcher = built.1
            isBuilding = false
            buildTask = nil
        }
    }
}
```

- [ ] **Step 2: Create and inject it in `ContentView.swift`**

Replace the `MainTabs` struct with a version that owns a `VaultIndex` (view-owned model → `@State`, initialized from `root`; `MainTabs` is already recreated per-vault by `.id(root)` in `ContentView`):

```swift
private struct MainTabs: View {
    let root: URL
    let store: VaultStore
    var onChangeVault: () -> Void

    @State private var index: VaultIndex

    init(root: URL, store: VaultStore, onChangeVault: @escaping () -> Void) {
        self.root = root
        self.store = store
        self.onChangeVault = onChangeVault
        _index = State(initialValue: VaultIndex(root: root))
    }

    var body: some View {
        TabView {
            NavigationStack {
                VaultBrowserView(directory: root, title: store.displayName ?? "Vault", root: root)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Change Vault", systemImage: "folder.badge.gearshape", action: onChangeVault)
                        }
                    }
            }
            .tabItem { Label("Files", systemImage: "folder") }

            NavigationStack {
                AskWikiView(root: root)
                    .navigationTitle("Ask")
            }
            .tabItem { Label("Ask", systemImage: "questionmark.bubble") }

            NavigationStack {
                GraphScreen(root: root)
                    .navigationTitle("Graph")
            }
            .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .environment(index)
    }
}
```

- [ ] **Step 3: Make `GraphScreen` consume the shared index**

In `WikiReader/Graph/GraphView.swift`, replace the `GraphScreen` struct (only this struct — leave `GraphExplorerView` and below untouched):

```swift
/// Loads the vault's wiki-link graph and hosts the interactive force layout.
struct GraphScreen: View {
    let root: URL

    @Environment(VaultIndex.self) private var index: VaultIndex?

    @State private var localGraph: VaultGraph?
    @State private var isLocalLoading = false
    @State private var selectedFile: VaultFile?

    private var graph: VaultGraph? { index?.graph ?? localGraph }
    private var isLoading: Bool { index.map(\.isBuilding) ?? isLocalLoading }

    var body: some View {
        Group {
            if let graph, !graph.isEmpty {
                GraphExplorerView(graph: graph) { node in
                    open(node)
                }
            } else if isLoading || graph == nil {
                ProgressView("Building graph…")
            } else {
                ContentUnavailableView(
                    "No links yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Add [[wiki-links]] between notes to grow the graph.")
                )
            }
        }
        .navigationDestination(item: $selectedFile) { file in
            MarkdownFileView(file: file, root: root)
        }
        .task {
            if let index {
                index.ensureBuilt()
            } else if localGraph == nil {
                isLocalLoading = true
                let url = root
                localGraph = await Task.detached(priority: .userInitiated) {
                    VaultGraph.build(root: url)
                }.value
                isLocalLoading = false
            }
        }
    }

    private func open(_ node: GraphNode) {
        guard let url = node.url else { return }
        selectedFile = VaultFile(url: url, isDirectory: false)
    }
}
```

Note the empty-but-done state: when a build finished and the graph is genuinely empty, the `ContentUnavailableView` shows; while nothing has been built yet, the spinner shows.

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run the full test suite (regression check)**

Run the test command (no `-only-testing`). Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add WikiReader/Vault/VaultIndex.swift WikiReader/ContentView.swift WikiReader/Graph/GraphView.swift
git commit -m "feat: shared VaultIndex builds graph and search index once per session"
```

---

### Task 8: Search UI on the Files tab + "Ask the wiki instead" escalation

A `FilesTabView` wraps the browser with `.searchable`; a non-empty query swaps in ranked results with snippets. Every results list ends with an "Ask the wiki instead" row that forwards the query text into the Ask tab (prefilled, not auto-submitted).

**Files:**
- Create: `WikiReader/Views/FilesTabView.swift`
- Modify: `WikiReader/ContentView.swift` (tab selection + pending question plumbing)
- Modify: `WikiReader/Views/AskWikiView.swift` (accept a prefilled question)

**Interfaces:**
- Consumes: `VaultIndex` (Task 7), `SearchResult` / `VaultSearcher.search` (Task 6), `VaultBrowserView(directory:title:root:)` (Task 1).
- Produces: `FilesTabView(root:title:onAskWiki:)` where `onAskWiki: (String) -> Void`; `AskWikiView(root:pendingQuestion:)` where `pendingQuestion: Binding<String?>` (defaulted to `.constant(nil)` so existing previews compile); `MainTab` enum (`home` case is added in Task 10).

- [ ] **Step 1: Create `WikiReader/Views/FilesTabView.swift`**

```swift
import SwiftUI

/// The Files tab root: the folder browser with vault-wide full-text search
/// layered on top. A non-empty search query replaces the browser with ranked
/// results; an "Ask the wiki" row escalates the query to the Ask tab.
struct FilesTabView: View {
    let root: URL
    let title: String
    var onAskWiki: (String) -> Void

    @Environment(VaultIndex.self) private var index: VaultIndex?
    @State private var searchText = ""

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                VaultBrowserView(directory: root, title: title, root: root)
            } else {
                SearchResultsList(
                    query: trimmedQuery,
                    root: root,
                    searcher: index?.searcher,
                    isBuilding: index?.isBuilding ?? false,
                    onAskWiki: onAskWiki
                )
                .navigationTitle(title)
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .onChange(of: trimmedQuery) { _, newValue in
            if !newValue.isEmpty {
                index?.ensureBuilt()
            }
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SearchResultsList: View {
    let query: String
    let root: URL
    let searcher: VaultSearcher?
    let isBuilding: Bool
    var onAskWiki: (String) -> Void

    private var results: [SearchResult] {
        searcher?.search(query) ?? []
    }

    var body: some View {
        List {
            if searcher == nil || isBuilding {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Indexing vault…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(results) { result in
                    NavigationLink {
                        MarkdownFileView(file: result.file, root: root)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                            Text(result.snippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                if results.isEmpty {
                    Text("No notes match \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(.secondary)
                }
                if let skipped = searcher?.skippedCount, skipped > 0 {
                    Text("\(skipped) file\(skipped == 1 ? "" : "s") not yet indexed (downloading from iCloud).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    onAskWiki(query)
                } label: {
                    Label("Ask the wiki instead", systemImage: "questionmark.bubble")
                }
            } footer: {
                Text("Sends this as a question to the wiki daemon.")
            }
        }
    }
}

#if DEBUG
private func previewSearchVault() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-search-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? "# Swift Actors\nNotes about actor isolation.".write(
        to: root.appendingPathComponent("Swift Actors.md"), atomically: true, encoding: .utf8)
    try? "Daily journal mentioning actors briefly.".write(
        to: root.appendingPathComponent("Journal.md"), atomically: true, encoding: .utf8)
    return root
}

#Preview {
    NavigationStack {
        FilesTabView(root: previewSearchVault(), title: "Vault") { _ in }
    }
    .environment(VaultIndex(root: previewSearchVault()))
}
#endif
```

- [ ] **Step 2: Add pending-question support to `AskWikiView`**

In `WikiReader/Views/AskWikiView.swift`, add a binding with a defaulted initializer (keeps the existing preview compiling):

```swift
struct AskWikiView: View {
    let root: URL
    @Binding var pendingQuestion: String?

    init(root: URL, pendingQuestion: Binding<String?> = .constant(nil)) {
        self.root = root
        self._pendingQuestion = pendingQuestion
    }
```

Consume it — extend the existing `.onAppear` and add an `.onChange` right after it:

```swift
        .onAppear {
            if !hasLoadedToken {
                token = WikiDaemonTokenStore.load()
                hasLoadedToken = true
            }
            consumePendingQuestion()
        }
        .onChange(of: pendingQuestion) { _, _ in
            consumePendingQuestion()
        }
```

And add the method next to `submit()`:

```swift
    @MainActor
    private func consumePendingQuestion() {
        guard let pending = pendingQuestion, !pending.isEmpty else { return }
        question = pending
        pendingQuestion = nil
    }
```

(Note the existing `.onAppear` currently guards on `hasLoadedToken` and returns early — restructure it as shown so the pending question is consumed regardless.)

- [ ] **Step 3: Wire tab selection in `ContentView.swift`**

In `MainTabs`, add a selection enum, selection state, and the pending question, and switch the Files tab to `FilesTabView`:

```swift
private enum MainTab: Hashable {
    case files, ask, graph
}
```

In the `MainTabs` struct add:

```swift
    @State private var selection: MainTab = .files
    @State private var pendingQuestion: String?
```

Replace the `TabView` body:

```swift
        TabView(selection: $selection) {
            NavigationStack {
                FilesTabView(root: root, title: store.displayName ?? "Vault") { question in
                    pendingQuestion = question
                    selection = .ask
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Change Vault", systemImage: "folder.badge.gearshape", action: onChangeVault)
                    }
                }
            }
            .tabItem { Label("Files", systemImage: "folder") }
            .tag(MainTab.files)

            NavigationStack {
                AskWikiView(root: root, pendingQuestion: $pendingQuestion)
                    .navigationTitle("Ask")
            }
            .tabItem { Label("Ask", systemImage: "questionmark.bubble") }
            .tag(MainTab.ask)

            NavigationStack {
                GraphScreen(root: root)
                    .navigationTitle("Graph")
            }
            .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(MainTab.graph)
        }
        .environment(index)
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WikiReader/Views/FilesTabView.swift WikiReader/Views/AskWikiView.swift WikiReader/ContentView.swift
git commit -m "feat: full-text search on Files tab with Ask-the-wiki escalation"
```

---

### Task 9: Backlinks panel in the note view

A "Linked from (N)" disclosure at the bottom of every note, fed by the shared graph's edges. Tapping a backlink resolves and opens the linking note.

**Files:**
- Modify: `WikiReader/Views/MarkdownFileView.swift`

**Interfaces:**
- Consumes: `VaultIndex.graph` (Task 7), `VaultGraph.edges` / `GraphEdge`, `WikiLinkResolver.resolve(_:in:)`.
- Produces: nothing new for later tasks.

Backlink extraction is one `Set`/`filter` expression over `VaultGraph.edges`, whose construction is already covered by the existing `VaultGraph` tests in `CoreUtilitiesTests` — no new Core logic to test.

- [ ] **Step 1: Add the backlinks section to `MarkdownFileView`**

Add the environment and computed property:

```swift
    @Environment(VaultIndex.self) private var index: VaultIndex?
```

```swift
    /// Titles of notes that link to this one, from the shared graph.
    private var backlinks: [String] {
        guard root != nil, let graph = index?.graph else { return [] }
        let name = file.displayName
        return Set(graph.edges.filter { $0.target == name }.map(\.source)).sorted()
    }
```

In `body`, insert the panel after the `MarkdownView` (inside the same `Group`'s success branch — wrap the existing `MarkdownView` and the new panel in a `VStack`):

```swift
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        MarkdownView(blocks: blocks, baseDirectory: file.url.deletingLastPathComponent())
                        if !backlinks.isEmpty {
                            BacklinksView(names: backlinks) { name in
                                openBacklink(name)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
```

Kick the index build in the existing `.task`:

```swift
        .task {
            index?.ensureBuilt()
            await load()
        }
```

Add the open method next to `load()`:

```swift
    private func openBacklink(_ name: String) {
        guard let root, let target = WikiLinkResolver.resolve(name, in: root) else { return }
        linkedFile = target
    }
```

- [ ] **Step 2: Add the `BacklinksView` (file-private, bottom of the file above the previews)**

```swift
private struct BacklinksView: View {
    let names: [String]
    var onOpen: (String) -> Void

    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Button {
                        onOpen(name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Linked from (\(names.count))", systemImage: "arrow.turn.up.left")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add WikiReader/Views/MarkdownFileView.swift
git commit -m "feat: backlinks panel in the note view"
```

---

### Task 10: Home tab

A landing dashboard: recently modified notes, a row into `wiki/index.md`, and the last few daemon `log.md` entries. Core pieces (`RecentNotes`, `WikiLog`) are UI-free and tested.

**Files:**
- Create: `WikiReader/Vault/RecentNotes.swift`
- Create: `WikiReader/Vault/WikiLog.swift`
- Create: `WikiReader/Views/HomeView.swift`
- Modify: `WikiReader/ContentView.swift` (insert the tab)
- Test: `WikiReaderTests/HomeCoreTests.swift` (new file)

**Interfaces:**
- Consumes: `VaultFile`, `MarkdownFileView(file:root:)`, `MainTab` (Task 8).
- Produces:
  - `RecentNote` — `file: VaultFile`, `modified: Date`; `Identifiable` by `file.url`.
  - `RecentNotes.scan(root: URL, limit: Int = 10) -> [RecentNote]` — newest first.
  - `WikiLogEntry` — `date: String`, `operation: String`, `summary: String`, `id: Int`.
  - `WikiLog.recentEntries(in text: String, limit: Int = 5) -> [WikiLogEntry]` — parses `## [YYYY-MM-DD] op | summary` lines, returns the last `limit` entries newest-first (the daemon appends, so later lines are newer).

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/HomeCoreTests.swift`:

```swift
import Foundation
import Testing
@testable import WikiReader

@MainActor
struct HomeCoreTests {
    @Test func recentNotesSortedNewestFirst() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("recents-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let old = root.appendingPathComponent("old.md")
        let new = root.appendingPathComponent("new.md")
        try "old".write(to: old, atomically: true, encoding: .utf8)
        try "new".write(to: new, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: new.path)

        let recents = RecentNotes.scan(root: root)
        #expect(recents.map { $0.file.displayName } == ["new", "old"])
    }

    @Test func recentNotesHonorsLimit() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("recents-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<5 {
            try "n".write(to: root.appendingPathComponent("note\(i).md"), atomically: true, encoding: .utf8)
        }
        #expect(RecentNotes.scan(root: root, limit: 3).count == 3)
    }

    @Test func parsesLogEntriesNewestFirst() {
        let log = """
        # Wiki Log

        ## [2026-07-01] ingest | Added swift actors source
        ## [2026-07-02] query | Answered question about actors
        ## [2026-07-03] lint | Fixed 2 dead links
        """
        let entries = WikiLog.recentEntries(in: log, limit: 2)
        #expect(entries.count == 2)
        #expect(entries[0].date == "2026-07-03")
        #expect(entries[0].operation == "lint")
        #expect(entries[0].summary == "Fixed 2 dead links")
        #expect(entries[1].date == "2026-07-02")
    }

    @Test func ignoresNonLogHeadings() {
        let log = "## Not a log line\n## [2026-07-01] ingest | real entry"
        let entries = WikiLog.recentEntries(in: log)
        #expect(entries.count == 1)
        #expect(entries[0].summary == "real entry")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/HomeCoreTests
```
Expected: compile FAILURE (`RecentNotes` / `WikiLog` do not exist).

- [ ] **Step 3: Implement the Core pieces**

Create `WikiReader/Vault/RecentNotes.swift`:

```swift
import Foundation

nonisolated struct RecentNote: Identifiable, Equatable {
    let file: VaultFile
    let modified: Date

    var id: URL { file.url }
}

/// Finds the most recently modified markdown notes in the vault.
nonisolated enum RecentNotes {
    static func scan(root: URL, limit: Int = 10) -> [RecentNote] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var notes: [RecentNote] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            notes.append(RecentNote(file: VaultFile(url: url, isDirectory: false), modified: modified))
        }
        return Array(notes.sorted { $0.modified > $1.modified }.prefix(limit))
    }
}
```

Create `WikiReader/Vault/WikiLog.swift`:

```swift
import Foundation

nonisolated struct WikiLogEntry: Identifiable, Equatable {
    let date: String
    let operation: String
    let summary: String
    let id: Int
}

/// Parses the daemon's append-only `wiki/log.md`. Entries look like
/// `## [2026-07-03] ingest | Added a source page`.
nonisolated enum WikiLog {
    static func recentEntries(in text: String, limit: Int = 5) -> [WikiLogEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: "^##\\s*\\[([^\\]]+)\\]\\s*([^|]+)\\|\\s*(.*)$"
        ) else {
            return []
        }

        var entries: [WikiLogEntry] = []
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                continue
            }
            entries.append(WikiLogEntry(
                date: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                operation: ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces),
                summary: ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces),
                id: offset
            ))
        }
        return Array(entries.reversed().prefix(limit))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Create `WikiReader/Views/HomeView.swift`**

```swift
import SwiftUI

/// Landing tab: recently modified notes, the daemon-maintained wiki index,
/// and recent daemon activity parsed from wiki/log.md.
struct HomeView: View {
    let root: URL

    @Environment(VaultIndex.self) private var index: VaultIndex?

    @State private var recents: [RecentNote] = []
    @State private var logEntries: [WikiLogEntry] = []
    @State private var indexFile: VaultFile?
    @State private var didLoad = false

    var body: some View {
        List {
            if let indexFile {
                Section {
                    NavigationLink {
                        MarkdownFileView(file: indexFile, root: root)
                    } label: {
                        Label("Wiki Index", systemImage: "books.vertical")
                    }
                }
            }

            if !recents.isEmpty {
                Section("Recent notes") {
                    ForEach(recents) { note in
                        NavigationLink {
                            MarkdownFileView(file: note.file, root: root)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.file.displayName)
                                Text(note.modified.formatted(.relative(presentation: .named)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !logEntries.isEmpty {
                Section("Wiki activity") {
                    ForEach(logEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.operation)
                                    .font(.footnote.smallCaps().weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.date)
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.summary)
                        }
                    }
                }
            }

            if didLoad && indexFile == nil && recents.isEmpty && logEntries.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "house",
                    description: Text("Clip some notes and they'll show up here.")
                )
            }
        }
        .navigationTitle("Home")
        .refreshable {
            index?.rebuild()
            await load()
        }
        .task {
            guard !didLoad else { return }
            await load()
        }
    }

    private func load() async {
        let url = root
        let loaded = await Task.detached(priority: .userInitiated) { () -> ([RecentNote], [WikiLogEntry], VaultFile?) in
            let recents = RecentNotes.scan(root: url)
            let logText = try? String(
                contentsOf: url.appendingPathComponent("wiki/log.md"), encoding: .utf8)
            let entries = logText.map { WikiLog.recentEntries(in: $0) } ?? []
            let indexURL = url.appendingPathComponent("wiki/index.md")
            let indexFile = FileManager.default.fileExists(atPath: indexURL.path)
                ? VaultFile(url: indexURL, isDirectory: false)
                : nil
            return (recents, entries, indexFile)
        }.value
        recents = loaded.0
        logEntries = loaded.1
        indexFile = loaded.2
        didLoad = true
    }
}

#if DEBUG
private func previewHomeVault() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("wr-home-preview", isDirectory: true)
    let wiki = root.appendingPathComponent("wiki", isDirectory: true)
    try? FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
    try? "# Recent Note\nBody.".write(
        to: root.appendingPathComponent("Recent Note.md"), atomically: true, encoding: .utf8)
    try? "# Index\n- [[Recent Note]]".write(
        to: wiki.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    try? "## [2026-07-09] ingest | Added a sample source".write(
        to: wiki.appendingPathComponent("log.md"), atomically: true, encoding: .utf8)
    return root
}

#Preview {
    NavigationStack {
        HomeView(root: previewHomeVault())
    }
}
#endif
```

- [ ] **Step 6: Insert the tab in `ContentView.swift`**

Add `home` as the first case of `MainTab` and make it the default selection:

```swift
private enum MainTab: Hashable {
    case home, files, ask, graph
}
```

```swift
    @State private var selection: MainTab = .home
```

Insert as the first tab inside the `TabView`:

```swift
            NavigationStack {
                HomeView(root: root)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(MainTab.home)
```

- [ ] **Step 7: Build and run the full test suite**

Run the build command, then the full test command. Expected: `** BUILD SUCCEEDED **`, all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add WikiReader/Vault/RecentNotes.swift WikiReader/Vault/WikiLog.swift WikiReader/Views/HomeView.swift WikiReader/ContentView.swift WikiReaderTests/HomeCoreTests.swift
git commit -m "feat: Home tab with recents, wiki index, and daemon activity"
```

---

### Task 11: Housekeeping — stale docs and dead code

**Files:**
- Modify: `README.md`
- Modify: `SETUP.md`
- Modify: `WikiReader/Core/ClipError.swift`
- Modify: `CLAUDE.md`

**Interfaces:** none.

- [ ] **Step 1: Delete the dead `ClipError.unsupported` case**

In `WikiReader/Core/ClipError.swift`, remove the `case unsupported(String)` line and its `errorDescription` branch:

```swift
        case .unsupported(let detail):
            return "Can't clip this yet: \(detail)."
```

Confirm nothing references it:

```bash
grep -rn "unsupported" WikiReader/ WikiReaderExtension/ WikiReaderTests/
```
Expected: no matches (or only unrelated words).

- [ ] **Step 2: Refresh README.md and SETUP.md**

Read both files first. Then:
- Anywhere they claim article clipping is "stubbed" / "not built yet": state that Twitter/X **and articles** are clipped fully, and video URLs write a `pending/` stub awaiting a home-machine transcription job.
- Add a short "Ask the wiki" section to README's feature list: the app connects to the companion `wiki-daemon` HTTP API (`/api/v1/health`, async `/api/v1/query` jobs) over LAN/Tailscale with a bearer token stored in the Keychain; answers cite `[[wiki-links]]` that open the local notes.
- Add this release's reader features to README's feature list: full-text search, backlinks panel, Home tab (recents + wiki index + daemon log), nested/task lists, callouts, images, minimal syntax highlighting.

- [ ] **Step 3: Update CLAUDE.md's Notes section**

Replace the last bullet ("Only the Twitter/X clip path is implemented; article/video return a clear 'not built yet' error in `ClipService`.") with:

```markdown
- Twitter/X and article clipping are fully implemented; video URLs write a
  `pending/` stub for a (future) home-machine transcription job.
- The Ask tab talks to the companion `wiki-daemon` HTTP API (health + async
  query jobs, bearer token in Keychain). See
  `docs/wiki-daemon-ios-api-requirements.md`.
```

- [ ] **Step 4: Build and run the full test suite**

Run the build command, then the full test command. Expected: `** BUILD SUCCEEDED **`, all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md SETUP.md CLAUDE.md WikiReader/Core/ClipError.swift
git commit -m "chore: refresh stale docs, drop dead ClipError.unsupported"
```

---

## Final verification

- [ ] Run the full test suite one last time (command in Global Constraints). Expected: all PASS.
- [ ] Manual smoke test in the simulator: open vault → Home shows recents/index/log → search finds a note by body text → open a note from Files and tap a `[[wikilink]]` (must navigate) → backlinks panel lists linking notes → Graph opens a note whose wikilinks navigate → search "zzz-no-match" → "Ask the wiki instead" lands on the Ask tab with the query prefilled.
- [ ] Use superpowers:verification-before-completion before claiming done, then superpowers:finishing-a-development-branch.
