# Selectable Text & Dynamic Type — Design

**Date:** 2026-07-16
**Status:** Approved scope, pending implementation plan

## Context

Text selection was added to `MarkdownView` via `.textSelection(.enabled)`
(the Mermaid/text-selection release). In practice this only gives
long-press-to-select-the-whole-block-then-copy — SwiftUI's native text
selection has no drag handles, no word/sentence granularity, nothing like
Safari, Books, or Notes. That's a genuine platform ceiling, not a bug:
those apps all get their selection behavior from `UITextView`/WebKit's text
layer, not from SwiftUI `Text`.

Getting real drag-to-select requires rendering the affected content through
`UITextView` instead. This is a real rendering-architecture change — the
scope decided is "everything including lists and callout text": headings,
paragraphs, quotes, and list items merge into continuous `UITextView`-backed
runs; callout body text also becomes selectable, but stays inside its
existing tinted/bordered SwiftUI container rather than merging into the
surrounding document flow (a callout is a visually bounded region, not part
of continuous prose). Tables, images, Mermaid diagrams, code blocks,
frontmatter, and rules are unaffected — they keep rendering exactly as
today.

Separately: "should the reader be zoomable" was resolved to Dynamic Type
(the standard iOS mechanism — Settings > Display & Brightness > Text Size,
or Control Center's Text Size quick action), not pinch-to-zoom, since
pinch-zoom doesn't map coherently onto reflowable text (Safari Reader,
Books, and Kindle all use a font-size control instead, for the same
reason). The codebase already uses semantic `Font` styles (`.headline`,
`.footnote`, `.system(.callout, design:)`) almost everywhere rather than
fixed point sizes, so this is folded into the same release as a
verification pass plus whatever the new `UITextView` path needs to get
right from scratch.

## Scope

1. A block-run grouping pass over `[MarkdownBlock]`: consecutive
   `heading`/`paragraph`/`quote`/`list` blocks become one run; every other
   block kind breaks a run and renders unchanged.
2. `MarkdownAttributedComposer` (Core, UI-free): converts a run of blocks
   into one Dynamic-Type-correct `NSAttributedString`, preserving inline
   formatting and `[[wikilinks]]`.
3. `SelectableTextView`: a `UIViewRepresentable` wrapping a non-editable,
   selectable `UITextView`, sized via `sizeThatFits`, forwarding link taps
   to the ambient `\.openURL` environment action.
4. Callouts: body text rendered via `SelectableTextView` instead of `Text`,
   inside the unchanged tinted/bordered container.
5. Dynamic Type verification across the remaining SwiftUI-rendered block
   types (tables, code, Mermaid fallback), with any fixed-size fonts found
   converted to semantic styles.

## Design

### Block-run grouping

A new Core function partitions `[MarkdownBlock]` into a sequence of
`MarkdownRun`:

```swift
enum MarkdownRun {
    case text(NSAttributedString)
    case structural(MarkdownBlock)
}
```

Consecutive `.heading`, `.paragraph`, `.quote`, `.list` blocks fold into one
`.text` run (composed by `MarkdownAttributedComposer`, below); every other
kind (`.frontmatter`, `.code`, `.callout`, `.image`, `.table`, `.rule`)
becomes its own `.structural` run, rendered by `MarkdownView` exactly as it
is today — `.callout` included, since its container stays SwiftUI even
though its *inner* text becomes a `SelectableTextView` (a rendering detail
inside the existing `CalloutView`, not a run-grouping concern).

`MarkdownView`'s `LazyVStack` iterates `[MarkdownRun]` instead of
`[MarkdownBlock]` directly; laziness is preserved at the run level (each run
is one `LazyVStack` child), matching today's granularity for anything with
periodic structural blocks. A note that's pure prose with zero tables,
images, or code becomes one large run rendered non-lazily — an accepted,
noted tradeoff at this app's typical note sizes (clipped posts, articles,
LLM answers), not something this release optimizes further.

### `MarkdownAttributedComposer`

Pure Core logic (no UIKit dependency in its own tests — only the final
`NSAttributedString` construction touches `UIFont`): takes a run's blocks
and produces one `NSAttributedString`.

- Each block's inline content still goes through the existing
  `MarkdownInline.attributed(_:) -> AttributedString` (unchanged — this
  already handles bold/italic/inline-code/links/wikilinks correctly), then
  bridges to `NSAttributedString` and has block-level styling layered on:
  - **Headings**: `UIFont.preferredFont(forTextStyle:)` mapped from level
    (1→`.title1`, 2→`.title2`, 3→`.title3`, 4–6→`.headline`), bold trait.
  - **Paragraphs**: `.body`.
  - **Quotes**: `.body`, `.secondaryLabel` color, left indent via
    `NSParagraphStyle.headIndent`/`firstLineHeadIndent` (visually
    approximating today's colored-rule-plus-indent look without a rule
    glyph — a rule requires drawing, out of scope for text-only
    composition).
  - **List items**: marker text prepended per item — `"•  "` for bullets,
    `"\(n).  "` for ordered, an `NSTextAttachment` wrapping
    `UIImage(systemName: "checkmark.square.fill"/"square")` for task items
    (matching the current `listMarker(for:)` glyph choice) — with a hanging
    indent (`firstLineHeadIndent` at the marker, `headIndent` past it) so
    wrapped lines align under the text, and `headIndent`/`firstLineHeadIndent`
    scaled by `item.depth` for nesting, mirroring today's
    `.padding(.leading: CGFloat(item.depth) * 20)`.
  - Blocks within a run are joined with paragraph spacing
    (`NSParagraphStyle.paragraphSpacing`), approximating the `LazyVStack`'s
    current `spacing: 14`.
- **Dynamic Type correctness is the reason this is composed by hand rather
  than relying on automatic `AttributedString`→`NSAttributedString`
  font bridging**: `UIFont.preferredFont(forTextStyle:)` is what actually
  responds live to the system text-size setting (including Control
  Center's live slider, no relaunch needed) — a bridged SwiftUI `Font`
  value doesn't reliably carry that through. Inline emphasis (bold/italic
  from `MarkdownInline.attributed`) is applied as a trait toggle
  (`UIFontDescriptor.withSymbolicTraits`) on top of the preferred-style
  base font, so it stays Dynamic-Type-correct rather than becoming a fixed
  point size once bold/italic is applied.

### `SelectableTextView`

```swift
struct SelectableTextView: UIViewRepresentable {
    let attributedString: NSAttributedString

    func makeUIView(context: Context) -> UITextView { ... }
    func updateUIView(_ uiView: UITextView, context: Context) { ... }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? { ... }
    func makeCoordinator() -> Coordinator { ... }
}
```

- `isEditable = false`, `isSelectable = true`, `isScrollEnabled = false`
  (the existing outer `ScrollView` handles scrolling), zero text-container
  insets so it sits flush like a `Text` would.
- Sized via the `sizeThatFits(_:uiView:context:)` `UIViewRepresentable`
  method (iOS 16+, well under this project's iOS 26 floor) — SwiftUI asks
  the view for its natural height at a proposed width, avoiding a manual
  height-reporting `Binding` round-trip.
- Link taps: the `Coordinator` implements
  `UITextViewDelegate.textView(_:shouldInteractWith:in:interaction:)`,
  reads `context.environment.openURL` (available inside
  `UIViewRepresentableContext`) and invokes it directly — the exact same
  `OpenURLAction` every existing call site (`MarkdownFileView`,
  `AskEntryDetailView`, `AnswerResultView`, etc.) already sets via
  `.environment(\.openURL, OpenURLAction { ... })` for wikilink navigation.
  No call site outside `MarkdownView` needs to change.

### Callout integration

`CalloutView`'s body text (`bodyText`, currently
`Text(MarkdownInline.attributed(...))`) becomes a `SelectableTextView` built
from the same composer path (a single-block "run" of just that callout's
lines). The tinted background, icon, left border, and fold behavior are
unchanged — this only swaps what renders the text inside.

### Dynamic Type verification

A manual pass (Settings > Display & Brightness > Text Size, and the
Control Center Text Size slider for live-update behavior) across every
remaining SwiftUI-rendered block: tables (`MarkdownTableView`), code
(`CodeHighlighter`'s output), Mermaid fallback (`MermaidFallbackView`), and
the callout header/label (icon + title, which stays `Text`/`Label`, not
`SelectableTextView`). Any fixed-point font found gets converted to a
semantic style; based on a read of the current code, none are expected —
this task is verification-first, fix-if-needed.

### Testing

- `MarkdownAttributedComposer`: pure Core tests — given a run of blocks,
  assert the produced `NSAttributedString`'s text content, and spot-check
  key attributes at specific ranges (a heading's font trait, a bullet
  marker's literal prefix, a wikilink's `.link` attribute value, a nested
  list item's indent scaling with depth).
- Block-run grouping: pure Core tests — given a `[MarkdownBlock]` mix,
  assert the resulting `[MarkdownRun]` sequence groups/breaks correctly
  (a table between two paragraphs produces three runs; a callout between
  two paragraphs produces three runs; consecutive heading+paragraph+list
  produce one run).
- `SelectableTextView` itself: not unit-tested (a thin `UIViewRepresentable`
  wrapper, consistent with this project's convention of not testing view
  plumbing) — verified by manual testing (drag-select across a
  heading→paragraph→list run; tap a wikilink inside the new rendering path;
  confirm text still can't be dragged across a table/image boundary, the
  accepted limitation).

## Error handling

- Empty run (shouldn't occur — `MarkdownParser` never emits a block with no
  content) — if it did, `SelectableTextView` renders a zero-height view,
  no crash.
- A wikilink target that doesn't resolve: unchanged — the existing
  "Note not found" alert path in each call site still fires, since
  `SelectableTextView` forwards to the same `\.openURL` action those call
  sites already handle this through.

## Out of scope (this release)

- Tables, images, Mermaid diagrams, code blocks, frontmatter, and
  horizontal rules staying non-selectable beyond today's whole-block
  `.textSelection(.enabled)` — genuinely selectable table cells or code
  text is a future enhancement, not required here.
- Selection spanning across a structural block boundary (e.g. dragging
  from text before a table into text after it) — an accepted platform/
  design limitation, not something this release attempts to solve.
- An in-app font-size control independent of system Dynamic Type (decided
  against — Dynamic Type is the standard mechanism and was explicitly
  preferred).
- Note editing (still read-only, `UITextView.isEditable = false`
  throughout).
