import Testing
import BeautifulMermaid
@testable import WikiReader

@MainActor
struct MermaidRendererSmokeTests {
    @Test func rendersKnownGoodFlowchartWithoutThrowing() throws {
        let source = """
        graph TD
            A[Start] --> B{Decision}
            B -->|Yes| C[Do Something]
            B -->|No| D[Do Something Else]
            C --> E[End]
            D --> E
        """
        let svg = try MermaidRenderer.renderSVG(source: source, theme: .githubLight)
        #expect(!svg.isEmpty)
        #expect(svg.contains("<svg"))
    }
}
