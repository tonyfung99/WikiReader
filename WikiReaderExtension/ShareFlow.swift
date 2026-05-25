import SwiftUI

@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case loading
        case success(title: String)
        case failure(message: String)

        var isFinished: Bool {
            if case .loading = self { return false }
            return true
        }
    }

    private(set) var phase: Phase = .loading
    var onDone: (() -> Void)?

    private let url: URL?
    private let service = ClipService()

    init(url: URL?) {
        self.url = url
    }

    func run() async {
        guard let url else {
            phase = .failure(message: "No URL was shared.")
            return
        }
        do {
            let result = try await service.clip(url: url)
            phase = .success(title: result.title)
            try? await Task.sleep(for: .seconds(1.2))
            onDone?()
        } catch {
            phase = .failure(message: error.localizedDescription)
        }
    }
}

struct ShareRootView: View {
    @State var model: ShareModel

    var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .loading:
                ProgressView("Clipping…")
            case .success(let title):
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Saved to vault")
                    .font(.headline)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failure(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Couldn't clip")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.phase.isFinished {
                Button("Done") { model.onDone?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .task { await model.run() }
    }
}
