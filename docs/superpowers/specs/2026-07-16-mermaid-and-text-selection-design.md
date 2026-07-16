# Mermaid Diagram Rendering & Text Selection — Design

**Date:** 2026-07-16
**Status:** Approved scope, pending implementation plan

## Context

Two enhancements to WikiReader's rendering, both touching the shared
`MarkdownView` used by note viewing (`MarkdownFileView`) and the Ask-answer
detail view (`AskEntryDetailView`):

1. Rendered content (notes, answers) can't currently be selected — no way to
   copy or share text out of the app.
2. The wiki daemon's LLM sometimes generates Mermaid diagrams in query
   answers (the daemon's `query_prompt` explicitly allows "tables, mermaid,
   code snippets"). Today a ` ```mermaid ` fence just renders as a plain
   code block — the diagram source, not a diagram.

Evaluating an approach for (2) led to a deliberate policy change: the
project's README/CLAUDE.md have stated "no third-party dependencies" since
inception, enforced by hand-rolling everything (Markdown parser, HTTP
client, graph force-layout). Rendering Mermaid diagrams natively and well is
a real engineering undertaking (six-plus diagram grammars, real layout
algorithms) that a purpose-built library already solves cleanly. Rather than
either hand-rolling a partial diagram renderer or reaching for a WebView +
bundled JS (which itself abandons the "native, no WebView" spirit), the
project takes its first external dependency.

Two candidate libraries were evaluated:
- **`beautiful-mermaid-swift`** (lukilabs, MIT, 348★, actively maintained) —
  pure Swift, no WebView/JavaScript, SwiftUI-native `MermaidDiagramView`,
  six diagram types (flowchart/state/sequence/class/ER/XY) via the ELK
  layout engine (`elk-swift`, EPL-2.0, pure Swift, no further transitive
  dependencies). **Adopted.**
- **`GMarkdown`** (GIKICoder, MIT, 69★) — a full UIKit Markdown renderer
  that itself pulls in four more dependencies (`swift-markdown`,
  `SwiftMath`, `MPITextKit`, `Highlightr`) to cover things this project's
  hand-rolled `MarkdownParser`/`MarkdownView` already does (tables, code
  highlighting) plus things nobody asked for (LaTeX, HTML preview).
  **Reviewed, not adopted** — replacing a working, well-tested parser and
  taking on a UIKit view plus four dependencies is disproportionate to the
  two features actually needed here.

## Scope

1. Amend the "no third-party dependencies" policy in README/CLAUDE.md to
   "prefer zero dependencies; take a well-maintained one when it's clearly
   the right tool," with each dependency's purpose documented explicitly.
2. Add `beautiful-mermaid-swift` (app target) and render ` ```mermaid `
   fenced blocks as real diagrams, with a graceful fallback to the raw
   source on parse failure or an unsupported diagram type.
3. Add `ViewInspector` (test target only) and cover the new fallback
   branching logic with structural SwiftUI tests.
4. Enable text selection broadly across the note-viewing and Ask-answer
   detail screens.

## Design

### Policy documentation

README and CLAUDE.md currently state the app is built with "no third-party
dependencies" as a headline architectural fact. Both get updated to state
the amended policy plus the two dependencies now in the project and their
purpose (`beautiful-mermaid-swift` for diagram rendering; `ViewInspector`,
test-only, for structural view tests) — honest about the exception rather
than silently contradicting a documented rule.

### Mermaid rendering

The parser already tags fenced code blocks with their language
(`MarkdownParser.parseCodeFence` → `MarkdownBlock.Kind.code(language:
code:)`), so ` ```mermaid ` already arrives as `.code(language: "mermaid",
code: "...")` — no parser change needed. This is purely a `MarkdownView`
rendering decision.

In `MarkdownView`'s `view(for:)` switch, the `.code` case branches: when
`language?.lowercased() == "mermaid"`, render a new `MermaidBlockView`
instead of the existing `CodeHighlighter`-based text view; every other
language keeps today's behavior unchanged.

**`MermaidBlockView`** (new private struct, kept in `MarkdownView.swift`
alongside the file's other private subviews, matching existing convention):
- Reads `@Environment(\.colorScheme)` and renders `MermaidDiagramView`
  (from `beautiful-mermaid-swift`) themed `.githubDark` in dark mode,
  `.githubLight` in light mode — the built-in theme closest to this app's
  minimal, native-feeling aesthetic (no custom hex-coded theme needed).
- Binds `parseError: Error?` and `diagramBounds: CGRect` (both provided by
  the library's view). Wraps the diagram in a horizontal `ScrollView` (the
  same overflow pattern already used for tables and code blocks) sized from
  `diagramBounds` once known, with a small placeholder size before the
  first layout pass completes.
- When `parseError` is non-nil (malformed Mermaid syntax, or a diagram type
  outside the library's six supported kinds — e.g. Gantt, pie, mindmap),
  renders `MermaidFallbackView` instead: a labeled
  (`"Diagram unavailable"`), monospaced block showing the raw Mermaid
  source — the same degrade-gracefully-never-blank-or-crash pattern already
  used for image load failures (`MarkdownImageView`'s placeholder).

### Text selection

`.textSelection(.enabled)` applied at:
- `MarkdownView`'s root (covers all rendered note/answer body content —
  headings, paragraphs, lists, tables, callouts, code, frontmatter).
- `AskEntryDetailView`'s question header and each citation row's title/link
  text.

Selection was already implicitly available nowhere in the app; this is a
pure addition with no interaction with existing wikilink-tap handling (link
taps and text selection are independent SwiftUI gesture systems and don't
conflict in practice for `Text`/`AttributedString` content).

### Testing

- **Core smoke test** (`WikiReaderTests`, no dependency on SwiftUI): a
  known-good Mermaid flowchart source is rendered via
  `MermaidRenderer.renderSVG(source:)` (the library's own pure-Swift entry
  point, independent of the SwiftUI wrapper) and asserted not to throw.
  Catches dependency/setup regressions (e.g. a broken package resolution)
  without re-testing the library's own parser, which is already tested
  upstream.
- **ViewInspector structural tests** on `MermaidBlockView`: given a state
  where `parseError` is set, the view tree contains the fallback's raw
  source text; given `parseError == nil`, the view tree contains a
  `MermaidDiagramView` node. This verifies *our* branching logic — it
  cannot and does not attempt to inspect pixels inside the
  `UIViewRepresentable`-wrapped diagram itself (a documented ViewInspector
  limitation), which is why the Core smoke test above exists as the
  complementary check that the underlying render path actually works.
- No tests for `.textSelection(.enabled)` placement (a one-line modifier,
  visually verified, matching the project's convention of not
  unit-testing view styling).

## Error handling

- Malformed or unsupported Mermaid syntax: falls back to
  `MermaidFallbackView`, never a crash, never blank space, never silently
  swallowed content — the raw source stays readable.
- Everything else (non-mermaid code fences, all other block types): fully
  unchanged.

## Out of scope (this release)

- Editing or copying Mermaid diagrams as images (view-only, matching the
  app's existing read-only note viewing).
- The three diagram types `beautiful-mermaid-swift` doesn't support (Gantt,
  pie, mindmap, journey, git graph) — these fall back to the raw-source
  view; not a rendering gap this release intends to close.
- XCUITest / end-to-end UI test infrastructure (evaluated and explicitly
  declined in favor of the lighter ViewInspector approach — see the
  brainstorming discussion; a real investment disproportionate to this
  feature).
- Snapshot/visual-regression testing (same reasoning — deferred, not
  rejected outright, should the project's testing needs grow).
- Retrofitting text selection or view tests onto other, pre-existing views
  not touched by this change.

## Implementation deviations & follow-ups (recorded 2026-07-16)

- Final whole-branch review (which built the app, ran `nm` on the linked
  binary to confirm zero `ViewInspector` symbols ship in it, and read
  `beautiful-mermaid-swift`'s actual source) found one real bug the
  controller fixed before merge: `MermaidLayer.prepareDiagram()` silently
  no-ops on empty/whitespace-only source (no `parseError`, no
  `diagramBounds`, nothing drawn) rather than failing — so an empty
  ` ```mermaid ``` ` fence rendered a blank colored box instead of the
  fallback, contradicting this design's own "never blank" guarantee. Fixed
  in `MermaidBlockContentView` with an explicit empty-source check routing
  to the fallback with the message "Empty diagram source." — covered by a
  new `showsFallbackWhenSourceIsEmpty` test.
- **Follow-up, not blocking:** the review noted `beautiful-mermaid-swift`
  ships a purpose-built `MermaidDiagram` value type (hold in `@State`, read
  `.parseError`/`.diagramBounds` synchronously) that would let
  `MermaidBlockView` drop its two separate `@State` vars, two `@Binding`s,
  and the `DispatchQueue.main.async` round-trip in favor of one simpler
  value. The current implementation is correct and tested as shipped; this
  is a legitimate simplification worth a follow-up, not a defect.
