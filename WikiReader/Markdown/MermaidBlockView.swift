import SwiftUI
import BeautifulMermaid

/// Renders a fenced ```mermaid``` code block as a native diagram, falling
/// back to the raw source (never a crash or blank space) when the syntax
/// is malformed or uses a diagram type the library doesn't support.
struct MermaidBlockView: View {
    let source: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var parseError: Error?
    @State private var diagramBounds: CGRect = .zero

    var body: some View {
        MermaidBlockContentView(
            source: source,
            errorMessage: parseError?.localizedDescription,
            diagramBounds: diagramBounds,
            theme: colorScheme == .dark ? .githubDark : .githubLight,
            parseErrorBinding: $parseError,
            diagramBoundsBinding: $diagramBounds
        )
    }
}

/// The rendering decision as a pure function of its inputs — testable and
/// previewable without a live MermaidDiagramView render pass. A non-nil
/// `errorMessage` selects the fallback branch; nil selects the diagram.
struct MermaidBlockContentView: View {
    let source: String
    let errorMessage: String?
    let diagramBounds: CGRect
    let theme: DiagramTheme
    @Binding var parseErrorBinding: Error?
    @Binding var diagramBoundsBinding: CGRect

    var body: some View {
        if let message = effectiveErrorMessage {
            MermaidFallbackView(source: source, message: message)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                MermaidDiagramView(
                    source: source,
                    theme: theme,
                    parseError: $parseErrorBinding,
                    diagramBounds: $diagramBoundsBinding
                )
                .frame(
                    width: diagramBounds.width > 0 ? diagramBounds.width : 300,
                    height: diagramBounds.height > 0 ? diagramBounds.height : 200
                )
            }
        }
    }

    /// `MermaidLayer` silently no-ops on empty source (no parseError, no
    /// diagramBounds, nothing drawn) rather than failing — without this,
    /// an empty ```mermaid``` fence renders a blank colored box instead of
    /// the fallback, contradicting the "never blank" guarantee.
    private var effectiveErrorMessage: String? {
        if let errorMessage { return errorMessage }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Empty diagram source."
        }
        return nil
    }
}

/// Raw-source fallback for a Mermaid block that failed to parse or uses an
/// unsupported diagram type.
struct MermaidFallbackView: View {
    let source: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagram unavailable", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview("Diagram") {
    ScrollView {
        MermaidBlockView(source: """
        graph TD
            A[Start] --> B{Decision}
            B -->|Yes| C[Do Something]
            B -->|No| D[Do Something Else]
            C --> E[End]
            D --> E
        """)
        .padding()
    }
}

#Preview("Fallback") {
    MermaidBlockContentView(
        source: "pie title Unsupported\n  \"A\" : 1",
        errorMessage: "Unsupported diagram type.",
        diagramBounds: .zero,
        theme: .githubLight,
        parseErrorBinding: .constant(nil),
        diagramBoundsBinding: .constant(.zero)
    )
    .padding()
}
