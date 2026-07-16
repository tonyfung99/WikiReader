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
