# Selectable Text & Dynamic Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give notes and Ask answers real drag-to-select text (like Safari/Books/Notes) instead of SwiftUI's whole-block-only `.textSelection`, and verify Dynamic Type is honored throughout.

**Architecture:** `MarkdownView`'s block list is grouped into runs — consecutive heading/paragraph/quote/list blocks merge into one `NSAttributedString` rendered by a new `UITextView`-backed `SelectableTextView`; everything else (tables, images, code, Mermaid, callouts' container, frontmatter, rules) renders exactly as today. This is the single biggest rendering change in the project so far — it introduces the app's first `UIViewRepresentable` text renderer and a hand-built `NSAttributedString` composer.

**Tech Stack:** Swift / SwiftUI + UIKit interop (iOS 26, Xcode 26), Swift Testing. Spec: `docs/superpowers/specs/2026-07-16-selectable-text-and-dynamic-type-design.md`.

## Global Constraints

- **No third-party dependencies for this feature** — `UITextView`/`NSAttributedString`/`UIFont` are all system frameworks.
- **Apple-native "MV" pattern, never MVVM.** No inline `Binding(get:set:)` in a view body.
- **Every new SwiftUI view gets a `#Preview`.**
- **Tests are Swift Testing** (`import Testing`, `@testable import WikiReader`, `@MainActor struct XxxTests`, `@Test`, `#expect`/`#require`) — never XCTest.
- **The app target (`WikiReader/`) is a filesystem-synchronized Xcode group** — new app source files need no project registration.
- **`WikiReaderTests` is a PLAIN group, NOT synchronized** — any new test file must be registered in the `WikiReaderTests` target via the `xcodeproj` Ruby gem. Confirm the RED run's failure is a genuine compile error naming the missing type — a silent "0 new tests ran" pass means the file wasn't actually linked into the target.
- **Genuine, flagged technical uncertainty in Task 2**: exactly how `AttributedString`'s `Runs.Run` exposes `inlinePresentationIntent`/`link` for manual translation into `NSAttributedString` attributes hasn't been verified by actually compiling it (this plan was written by reading Foundation's documented attribute-scope model, not by running Xcode). If the exact property names/types in the plan's code don't compile, investigate `AttributedString`'s actual API (Xcode Quick Help / jump-to-definition) and adjust — preserving the same translation logic (bold trait for `.stronglyEmphasized`, italic for `.emphasized`, monospace for `.code`, forward `.link`) — rather than guessing blindly or abandoning the approach. If genuinely stuck after investigating, report BLOCKED with specifics.
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
- **Known flake:** if the simulator reports "Busy / failed preflight checks", run `xcrun simctl shutdown all` and retry.
- Run all commands from the repo root: `/Users/tonyfung/workspace/WikiReader`.

---

### Task 1: `MarkdownRun` — block-run grouping

Pure Core logic: partitions a flat `[MarkdownBlock]` into a sequence where consecutive flowing-text blocks (heading/paragraph/quote/list) collapse into one `.text` run, and every other block kind becomes its own `.structural` run.

**Files:**
- Create: `WikiReader/Markdown/MarkdownRun.swift`
- Test: `WikiReaderTests/MarkdownRunTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock`, `MarkdownBlock.Kind` (existing, `WikiReader/Markdown/MarkdownBlock.swift`).
- Produces: `MarkdownRun` (`nonisolated enum, Identifiable`) — `case text(id: UUID, blocks: [MarkdownBlock])`, `case structural(MarkdownBlock)`, `var id: UUID`. `MarkdownRunGrouper.group(_ blocks: [MarkdownBlock]) -> [MarkdownRun]`. Tasks 3–4 consume this exact shape.

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/MarkdownRunTests.swift`:

```swift
import Testing
@testable import WikiReader

@MainActor
struct MarkdownRunTests {
    private func blocks(_ kinds: [MarkdownBlock.Kind]) -> [MarkdownBlock] {
        kinds.map { MarkdownBlock(kind: $0) }
    }

    @Test func consecutiveFlowingBlocksMergeIntoOneRun() {
        let input = blocks([
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Body"),
            .list(items: [MarkdownListItem(text: "item", depth: 0, number: nil, checked: nil)]),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 1)
        guard case .text(_, let runBlocks) = runs[0] else {
            Issue.record("expected a text run")
            return
        }
        #expect(runBlocks.count == 3)
    }

    @Test func tableBetweenParagraphsProducesThreeRuns() {
        let input = blocks([
            .paragraph(text: "Before"),
            .table(headers: ["A"], alignments: [.leading], rows: [["1"]]),
            .paragraph(text: "After"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 3)
        guard case .text = runs[0] else { Issue.record("expected text run first"); return }
        guard case .structural(let middle) = runs[1] else { Issue.record("expected structural run second"); return }
        if case .table = middle.kind {} else { Issue.record("expected table block") }
        guard case .text = runs[2] else { Issue.record("expected text run third"); return }
    }

    @Test func calloutBetweenParagraphsProducesThreeRuns() {
        let input = blocks([
            .paragraph(text: "Before"),
            .callout(type: "note", title: "Note", lines: ["callout body"], foldable: false),
            .paragraph(text: "After"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 3)
    }

    @Test func emptyBlockListProducesNoRuns() {
        #expect(MarkdownRunGrouper.group([]).isEmpty)
    }

    @Test func onlyStructuralBlocksProduceOneRunEach() {
        let input = blocks([
            .rule,
            .image(alt: "a", source: "b.png"),
        ])
        let runs = MarkdownRunGrouper.group(input)
        #expect(runs.count == 2)
    }
}
```

- [ ] **Step 2: Register the test file in the Xcode project**

`WikiReaderTests` is a plain (non-synchronized) group. Use the `xcodeproj` Ruby gem to add `WikiReaderTests/MarkdownRunTests.swift` as a file reference in the `WikiReaderTests` group and to the `WikiReaderTests` target's Sources build phase.

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/MarkdownRunTests
```
Expected: compile FAILURE naming `MarkdownRun`/`MarkdownRunGrouper`.

- [ ] **Step 4: Implement**

Create `WikiReader/Markdown/MarkdownRun.swift`:

```swift
import Foundation

/// One renderable unit of a parsed document: either a merged run of
/// flowing-text blocks (heading/paragraph/quote/list) rendered as one
/// continuous, drag-selectable text view, or a single structural block
/// (table/image/code/callout/frontmatter/rule) rendered exactly as before.
nonisolated enum MarkdownRun: Identifiable {
    case text(id: UUID, blocks: [MarkdownBlock])
    case structural(MarkdownBlock)

    var id: UUID {
        switch self {
        case .text(let id, _): id
        case .structural(let block): block.id
        }
    }
}

nonisolated enum MarkdownRunGrouper {
    /// Groups consecutive heading/paragraph/quote/list blocks into one
    /// `.text` run each; every other block kind becomes its own
    /// `.structural` run, breaking any run in progress.
    static func group(_ blocks: [MarkdownBlock]) -> [MarkdownRun] {
        var runs: [MarkdownRun] = []
        var pending: [MarkdownBlock] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            runs.append(.text(id: UUID(), blocks: pending))
            pending = []
        }

        for block in blocks {
            if isFlowingText(block.kind) {
                pending.append(block)
            } else {
                flushPending()
                runs.append(.structural(block))
            }
        }
        flushPending()
        return runs
    }

    private static func isFlowingText(_ kind: MarkdownBlock.Kind) -> Bool {
        switch kind {
        case .heading, .paragraph, .quote, .list: true
        case .frontmatter, .code, .callout, .image, .table, .rule: false
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Same command as Step 3. Expected: PASS, 5/5.

- [ ] **Step 6: Build**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/Markdown/MarkdownRun.swift WikiReaderTests/MarkdownRunTests.swift WikiReader.xcodeproj/project.pbxproj
git commit -m "feat: add MarkdownRun block-grouping for the selectable-text renderer"
```

---

### Task 2: `MarkdownAttributedComposer`

The riskiest task in this plan: builds one Dynamic-Type-correct `NSAttributedString` from a run of flowing-text blocks, preserving inline formatting and `[[wikilinks]]` by walking `MarkdownInline.attributed(_:)`'s `AttributedString` runs and translating each into concrete `NSAttributedString` attributes (rather than relying on default bridging, which does not reliably turn markdown's semantic bold/italic markers into an actual bold/italic `UIFont`).

**Files:**
- Create: `WikiReader/Markdown/MarkdownAttributedComposer.swift`
- Test: `WikiReaderTests/MarkdownAttributedComposerTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock`, `MarkdownBlock.Kind`, `MarkdownListItem` (existing); `MarkdownInline.attributed(_:) -> AttributedString`, `MarkdownInline.wikiLinkTarget(from:)` (existing, `WikiReader/Markdown/MarkdownInline.swift`).
- Produces: `MarkdownAttributedComposer.compose(_ blocks: [MarkdownBlock]) -> NSAttributedString`. Tasks 3–4 consume this exact signature.

- [ ] **Step 1: Write the failing tests**

Create `WikiReaderTests/MarkdownAttributedComposerTests.swift`:

```swift
import Testing
import UIKit
@testable import WikiReader

@MainActor
struct MarkdownAttributedComposerTests {
    @Test func headingUsesBoldPreferredFont() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .heading(level: 1, text: "Title"))
        ])
        #expect(result.string == "Title")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test func paragraphUsesBodyFont() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "Hello"))
        ])
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let expected = UIFont.preferredFont(forTextStyle: .body)
        #expect(font?.pointSize == expected.pointSize)
    }

    @Test func wikilinkProducesLinkAttribute() throws {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "see [[Some Note]]"))
        ])
        var foundLink: URL?
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let url = value as? URL { foundLink = url }
        }
        let link = try #require(foundLink)
        #expect(link.scheme == "wikilink")
        #expect(MarkdownInline.wikiLinkTarget(from: link) == "Some Note")
    }

    @Test func bulletListItemHasMarkerPrefix() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "first", depth: 0, number: nil, checked: nil)
            ]))
        ])
        #expect(result.string.hasPrefix("•"))
        #expect(result.string.contains("first"))
    }

    @Test func orderedListItemHasNumberPrefix() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "step", depth: 0, number: 1, checked: nil)
            ]))
        ])
        #expect(result.string.hasPrefix("1."))
    }

    @Test func nestedListItemIndentsMoreThanTopLevel() throws {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .list(items: [
                MarkdownListItem(text: "top", depth: 0, number: nil, checked: nil),
                MarkdownListItem(text: "nested", depth: 1, number: nil, checked: nil),
            ]))
        ])
        let topStyle = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let nestedRange = try #require(result.string.range(of: "nested"))
        let nestedIndex = result.string.distance(from: result.string.startIndex, to: nestedRange.lowerBound)
        let nestedStyle = result.attribute(.paragraphStyle, at: nestedIndex, effectiveRange: nil) as? NSParagraphStyle
        #expect((nestedStyle?.headIndent ?? 0) > (topStyle?.headIndent ?? 0))
    }

    @Test func multipleBlocksAreSeparatedByNewline() {
        let result = MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .paragraph(text: "First")),
            MarkdownBlock(kind: .paragraph(text: "Second")),
        ])
        #expect(result.string == "First\nSecond")
    }
}
```

- [ ] **Step 2: Register the test file in the Xcode project**

Same procedure as Task 1 Step 2 — add `WikiReaderTests/MarkdownAttributedComposerTests.swift` via the `xcodeproj` gem.

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WikiReaderTests/MarkdownAttributedComposerTests
```
Expected: compile FAILURE naming `MarkdownAttributedComposer`.

- [ ] **Step 4: Implement**

Create `WikiReader/Markdown/MarkdownAttributedComposer.swift`:

```swift
import UIKit

/// Builds a single Dynamic-Type-correct NSAttributedString from a run of
/// flowing-text blocks (heading/paragraph/quote/list), preserving inline
/// formatting and [[wikilinks]] via the existing MarkdownInline pipeline.
/// Uses UIFont.preferredFont(forTextStyle:) throughout — not a bridged
/// SwiftUI Font — because that's what actually responds live to the
/// system text-size setting (including Control Center's slider).
nonisolated enum MarkdownAttributedComposer {
    static func compose(_ blocks: [MarkdownBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(attributedString(for: block.kind))
        }
        return result
    }

    private static func attributedString(for kind: MarkdownBlock.Kind) -> NSAttributedString {
        switch kind {
        case .heading(let level, let text):
            return styled(text, style: headingStyle(level), bold: true, paragraphSpacing: 8)

        case .paragraph(let text):
            return styled(text, style: .body, paragraphSpacing: 14)

        case .quote(let lines):
            return styled(
                lines.joined(separator: "\n"), style: .body,
                color: .secondaryLabel, indent: 14, paragraphSpacing: 14
            )

        case .list(let items):
            let list = NSMutableAttributedString()
            for (index, item) in items.enumerated() {
                if index > 0 { list.append(NSAttributedString(string: "\n")) }
                list.append(listItemAttributedString(item))
            }
            return list

        case .frontmatter, .code, .callout, .image, .table, .rule:
            return NSAttributedString(string: "")
        }
    }

    private static func headingStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title1
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }

    private static func styled(
        _ text: String,
        style: UIFont.TextStyle,
        bold: Bool = false,
        color: UIColor = .label,
        indent: CGFloat = 0,
        paragraphSpacing: CGFloat = 0
    ) -> NSAttributedString {
        let baseFont = bold
            ? boldVariant(of: UIFont.preferredFont(forTextStyle: style))
            : UIFont.preferredFont(forTextStyle: style)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = paragraphSpacing

        let attributed = NSMutableAttributedString(inline(text, baseFont: baseFont))
        attributed.addAttribute(
            .foregroundColor, value: color,
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            .paragraphStyle, value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
    }

    private static func listItemAttributedString(_ item: MarkdownListItem) -> NSAttributedString {
        let indent: CGFloat = 20 + CGFloat(item.depth) * 20
        let markerWidth: CGFloat = 20

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = indent - markerWidth
        paragraphStyle.headIndent = indent
        paragraphStyle.paragraphSpacing = 6
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
        paragraphStyle.defaultTabInterval = indent

        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString()
        result.append(marker(for: item))
        result.append(NSAttributedString(string: "\t"))
        result.append(inline(item.text, baseFont: baseFont))
        result.addAttribute(
            .paragraphStyle, value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func marker(for item: MarkdownListItem) -> NSAttributedString {
        if let checked = item.checked {
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: checked ? "checkmark.square.fill" : "square")?
                .withTintColor(checked ? .tintColor : .secondaryLabel, renderingMode: .alwaysOriginal)
            return NSAttributedString(attachment: attachment)
        } else if let number = item.number {
            return NSAttributedString(string: "\(number).")
        } else {
            return NSAttributedString(string: "•")
        }
    }

    /// Walks MarkdownInline.attributed(_:)'s runs and translates its
    /// semantic markdown attributes (bold/italic/code emphasis, links)
    /// into concrete NSAttributedString attributes layered on `baseFont` —
    /// deliberately not a blind NSAttributedString(attributedString)
    /// bridge, since that does not reliably turn emphasis markers into an
    /// actual bold/italic UIFont.
    private static func inline(_ text: String, baseFont: UIFont) -> NSAttributedString {
        let source = MarkdownInline.attributed(text)
        let result = NSMutableAttributedString()

        for run in source.runs {
            let substring = String(source[run.range].characters)
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    font = boldVariant(of: font)
                }
                if intent.contains(.emphasized) {
                    font = italicVariant(of: font)
                }
                if intent.contains(.code) {
                    font = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let link = run.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: substring, attributes: attributes))
        }
        return result
    }

    private static func boldVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func italicVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Same command as Step 3. Expected: PASS, 7/7. If `run.inlinePresentationIntent` or `run.link` don't compile, see the Global Constraints note on this task's flagged uncertainty — investigate `AttributedString`'s actual API rather than guessing, preserving the same translation logic.

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WikiReader/Markdown/MarkdownAttributedComposer.swift WikiReaderTests/MarkdownAttributedComposerTests.swift WikiReader.xcodeproj/project.pbxproj
git commit -m "feat: add MarkdownAttributedComposer, a Dynamic-Type-correct NSAttributedString builder"
```

---

### Task 3: `SelectableTextView`

A `UIViewRepresentable` wrapping a non-editable, selectable `UITextView` — this is what actually gives real drag-to-select. Not unit-tested (thin view wrapper, matching this project's convention); verified by build and, in Task 4's final manual pass, by actually dragging to select and tapping a wikilink.

**Files:**
- Create: `WikiReader/Markdown/SelectableTextView.swift`

**Interfaces:**
- Consumes: nothing new (`UIKit`, `SwiftUI` only).
- Produces: `SelectableTextView(attributedString: NSAttributedString)`. Task 4 uses this in `MarkdownView` and `CalloutView`.

- [ ] **Step 1: Implement**

Create `WikiReader/Markdown/SelectableTextView.swift`:

```swift
import SwiftUI
import UIKit

/// A non-editable, natively-selectable text view — gives real drag-to-
/// select (word/sentence granularity, magnifier, native menu) that
/// SwiftUI's `.textSelection(.enabled)` cannot provide on its own. Sized
/// via `sizeThatFits` so it fits naturally inside the existing
/// ScrollView-based layout; link taps forward to the ambient `\.openURL`
/// environment action — the same mechanism every wikilink call site
/// already uses, so no call site outside MarkdownView needs to change.
struct SelectableTextView: UIViewRepresentable {
    let attributedString: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.attributedText = attributedString
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
        if uiView.attributedText != attributedString {
            uiView.attributedText = attributedString
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction?

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard interaction == .invokeDefaultAction else { return false }
            openURL?(URL)
            return false
        }
    }
}

#Preview {
    ScrollView {
        SelectableTextView(attributedString: MarkdownAttributedComposer.compose([
            MarkdownBlock(kind: .heading(level: 1, text: "Selectable Text")),
            MarkdownBlock(kind: .paragraph(
                text: "Try long-pressing and dragging to select part of this sentence, then copy it."
            )),
        ]))
        .padding()
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WikiReader/Markdown/SelectableTextView.swift
git commit -m "feat: add SelectableTextView, a UITextView-backed drag-selectable renderer"
```

---

### Task 4: Wire into `MarkdownView` and `CalloutView`

Replaces `MarkdownView`'s block-by-block rendering with run-based rendering, and swaps `CalloutView`'s body text to `SelectableTextView`. This is the task that makes the whole feature visible — it's also the final integration point, so it runs the full regression suite.

**Files:**
- Modify: `WikiReader/Markdown/MarkdownView.swift`

**Interfaces:**
- Consumes: `MarkdownRun`, `MarkdownRunGrouper.group(_:)` (Task 1); `MarkdownAttributedComposer.compose(_:)` (Task 2); `SelectableTextView` (Task 3).

- [ ] **Step 1: Replace `MarkdownView`'s `body` and `view(for:)`**

Read the current file first (previous tasks in this plan didn't touch it, but confirm). Replace from the top of the file through the end of `headingFont(_:)` (i.e. everything in the `MarkdownView` struct itself) with:

```swift
import SwiftUI

/// Renders parsed markdown blocks as SwiftUI views. Flowing-text blocks
/// (heading/paragraph/quote/list) are grouped into runs and rendered as one
/// continuous, drag-selectable SelectableTextView each; everything else
/// (tables, images, code, Mermaid, callouts, frontmatter, rules) renders as
/// its own structural view, exactly as before.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseDirectory: URL? = nil

    private var runs: [MarkdownRun] {
        MarkdownRunGrouper.group(blocks)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(runs) { run in
                view(for: run)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for run: MarkdownRun) -> some View {
        switch run {
        case .text(_, let runBlocks):
            SelectableTextView(attributedString: MarkdownAttributedComposer.compose(runBlocks))
        case .structural(let block):
            structuralView(for: block.kind)
        }
    }

    @ViewBuilder
    private func structuralView(for kind: MarkdownBlock.Kind) -> some View {
        switch kind {
        case .frontmatter(let lines):
            FrontmatterView(lines: lines)

        case .code(let language, let code):
            if language?.lowercased() == "mermaid" {
                MermaidBlockView(source: code)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(CodeHighlighter.attributed(code))
                        .font(.system(.callout, design: .monospaced))
                        .padding(12)
                }
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

        case .callout(let type, let title, let lines, let foldable):
            CalloutView(type: type, title: title, lines: lines, foldable: foldable)

        case .image(let alt, let source):
            MarkdownImageView(alt: alt, source: source, baseDirectory: baseDirectory)

        case .table(let headers, let alignments, let rows):
            MarkdownTableView(headers: headers, alignments: alignments, rows: rows)

        case .rule:
            Divider()

        case .heading, .paragraph, .quote, .list:
            EmptyView() // unreachable: MarkdownRunGrouper only emits these inside .text runs
        }
    }
}
```

Note this removes the now-unused `listMarker(for:)` and `headingFont(_:)` helper functions — their logic moved into `MarkdownAttributedComposer` in Task 2.

- [ ] **Step 2: Swap `CalloutView`'s body text to `SelectableTextView`**

In the same file, find `CalloutView`'s `bodyText` computed property:

```swift
    private var bodyText: some View {
        Text(MarkdownInline.attributed(lines.joined(separator: "\n")))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
```

Replace with:

```swift
    private var bodyText: some View {
        SelectableTextView(
            attributedString: MarkdownAttributedComposer.compose([
                MarkdownBlock(kind: .paragraph(text: lines.joined(separator: "\n")))
            ])
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run the full test suite (regression check)**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all tests PASS (the count from before this plan, plus 5 `MarkdownRunTests` + 7 `MarkdownAttributedComposerTests` — report the actual total you see rather than trusting a specific number, since this plan may not have a perfectly current baseline).

- [ ] **Step 5: Commit**

```bash
git add WikiReader/Markdown/MarkdownView.swift
git commit -m "feat: render flowing text through SelectableTextView for real drag-to-select"
```

---

### Task 5: Dynamic Type verification

A manual verification pass, not a code-writing task by default — fix only what's actually found broken.

**Files:**
- Modify (only if a fixed-size font is found): `WikiReader/Markdown/MarkdownView.swift`, `WikiReader/Markdown/MermaidBlockView.swift`, or any other file a fixed-size font turns up in.

**Interfaces:** none.

- [ ] **Step 1: Grep for fixed-point font usage across the touched area**

```bash
grep -n "\.system(size:\|UIFont(name:\|UIFont.systemFont(ofSize:" \
  WikiReader/Markdown/*.swift
```

Expected: no matches. If any turn up, they need converting to a semantic style (`Font.system(.body, design:)` / `UIFont.preferredFont(forTextStyle:)`) as part of this step — show the before/after in your report.

- [ ] **Step 2: Manual test — system Dynamic Type**

In the iOS Simulator: Settings app → Accessibility → Display & Text Size → Larger Text → drag the slider to a noticeably larger size. Reopen WikiReader, open a note with headings/paragraphs/lists/a table/a code block/a callout. Confirm every piece of text visibly grew — the new `SelectableTextView`-rendered content (headings/paragraphs/lists/callout body) and the still-SwiftUI-rendered content (table cells, code, Mermaid fallback) alike.

- [ ] **Step 3: Manual test — live Control Center resize**

With the same note open, open Control Center (or add the Text Size control if not already present) and drag its slider while WikiReader is visible in the background/split view if possible, or switch back to WikiReader immediately after adjusting it. Confirm the already-open note's text updates without needing to close and reopen it (this is the behavior `UIFont.preferredFont(forTextStyle:)` should give "for free" — if it doesn't update live, note this in your report as a finding rather than silently accepting it).

- [ ] **Step 4: If any fix was needed, run the full test suite and commit**

```bash
xcodebuild test -project WikiReader.xcodeproj -scheme WikiReader \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all tests PASS.

```bash
git add <whatever files were changed>
git commit -m "fix: convert fixed-size fonts to Dynamic-Type-scalable styles"
```

If no fix was needed, skip the commit — report what you verified instead.

---

## Final verification

- [ ] Run the full test suite one more time (command in Global Constraints). Expected: all PASS.
- [ ] Manual smoke test in the simulator, covering the specific behaviors this plan set out to deliver:
  1. Open a note with a heading, a few paragraphs, a nested list, and a blockquote. Long-press inside a paragraph and drag — confirm you get real word/sentence-granularity selection with drag handles (not just "select the whole paragraph"), and that dragging continues smoothly from the heading through the paragraph into the list (one continuous run).
  2. Tap a `[[wikilink]]` inside the newly-selectable text — confirm it still navigates to the target note (or shows "Note not found" for a broken one), exactly as before.
  3. Open a note with a callout — confirm its text is now drag-selectable too, and its tinted/bordered/foldable container still looks and behaves exactly as before.
  4. Confirm selection does NOT drag across a table or image into the text after it — expected, documented limitation, not a bug.
  5. Confirm a table, a code block, and the Mermaid fallback view still show correctly (unchanged rendering path).
  6. Re-run the Dynamic Type check from Task 5 once more end-to-end on a note that has all of the above.
- [ ] Use superpowers:verification-before-completion before claiming done, then superpowers:finishing-a-development-branch.
