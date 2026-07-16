import Testing
import SwiftUI
import BeautifulMermaid
import ViewInspector
@testable import WikiReader

@MainActor
struct MermaidBlockViewTests {
    @Test func showsFallbackWhenErrorMessageIsSet() throws {
        let view = MermaidBlockContentView(
            source: "graph TD\nA-->B",
            errorMessage: "Parse failed",
            diagramBounds: .zero,
            theme: .githubLight,
            parseErrorBinding: .constant(nil),
            diagramBoundsBinding: .constant(.zero)
        )
        let fallback = try view.inspect().find(MermaidFallbackView.self)
        #expect(try fallback.actualView().source == "graph TD\nA-->B")
        #expect(try fallback.actualView().message == "Parse failed")
    }

    @Test func showsDiagramWhenErrorMessageIsNil() throws {
        let view = MermaidBlockContentView(
            source: "graph TD\nA-->B",
            errorMessage: nil,
            diagramBounds: .zero,
            theme: .githubLight,
            parseErrorBinding: .constant(nil),
            diagramBoundsBinding: .constant(.zero)
        )
        #expect(throws: Never.self) {
            _ = try view.inspect().find(MermaidDiagramView.self)
        }
    }

    @Test func fallbackViewExposesRawSource() throws {
        let view = MermaidFallbackView(source: "pie title X\n\"A\" : 1", message: "Unsupported diagram type.")
        let text = try view.inspect().find(text: "pie title X\n\"A\" : 1")
        #expect(try text.string() == "pie title X\n\"A\" : 1")
    }
}
