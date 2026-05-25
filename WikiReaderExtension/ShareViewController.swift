import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the share extension. Pulls the shared URL out of the
/// extension context, hands it to the SwiftUI status flow, and completes the
/// request when the user is done.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await start() }
    }

    private func start() async {
        let url = await extractURL()
        let model = ShareModel(url: url)
        model.onDone = { [weak self] in self?.complete() }

        let host = UIHostingController(rootView: ShareRootView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func extractURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                   let url = loaded as? URL {
                    return url
                }
            }
        }

        // Fallback: some apps share the link as plain text.
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let text = loaded as? String,
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme != nil {
                    return url
                }
            }
        }

        return nil
    }
}
