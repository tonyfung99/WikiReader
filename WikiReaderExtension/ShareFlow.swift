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
        ShareStatusView(phase: model.phase) { model.onDone?() }
            .task { await model.run() }
    }
}

struct ShareStatusView: View {
    let phase: ShareModel.Phase
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
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

            if phase.isFinished {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }
}

#Preview("Loading") { ShareStatusView(phase: .loading, onDone: {}) }
#Preview("Success") { ShareStatusView(phase: .success(title: "jack: just setting up my twttr"), onDone: {}) }
#Preview("Failure") { ShareStatusView(phase: .failure(message: "No URL was shared."), onDone: {}) }
