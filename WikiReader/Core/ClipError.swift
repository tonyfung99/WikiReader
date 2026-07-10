import Foundation

enum ClipError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case noContent
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The shared item was not a valid URL."
        case .badResponse(let code):
            return "Server returned an error (HTTP \(code))."
        case .noContent:
            return "No content could be extracted from the link."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
