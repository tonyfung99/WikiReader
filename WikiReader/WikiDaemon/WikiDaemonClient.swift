import Foundation

nonisolated enum WikiDaemonQueryStatus: String, Codable, Equatable {
    case queued
    case running
    case done
    case failed
}

nonisolated struct WikiDaemonCitation: Codable, Equatable, Hashable, Identifiable {
    let wikiLink: String
    let title: String

    var id: String { wikiLink }
}

nonisolated struct WikiDaemonHealthResponse: Decodable, Equatable {
    let schemaVersion: Int
    let status: String
    let daemonVersion: String?
    let vaultName: String?
    let queryAvailable: Bool
    let provider: String?
}

nonisolated struct WikiDaemonQueryStartResponse: Decodable, Equatable {
    let schemaVersion: Int
    let jobID: String
    let status: WikiDaemonQueryStatus

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case jobID = "jobId"
        case status
    }
}

nonisolated struct WikiDaemonQueryStatusResponse: Decodable, Equatable {
    let schemaVersion: Int
    let jobID: String
    let status: WikiDaemonQueryStatus
    let ok: Bool?
    let answerMarkdown: String?
    let saved: Bool?
    let saveError: String?
    let citations: [WikiDaemonCitation]
    let provider: String?
    let startedAt: String?
    let completedAt: String?
    let error: WikiDaemonErrorDetail?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case jobID = "jobId"
        case status
        case ok
        case answerMarkdown
        case saved
        case saveError
        case citations
        case provider
        case startedAt
        case completedAt
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        jobID = try container.decode(String.self, forKey: .jobID)
        status = try container.decode(WikiDaemonQueryStatus.self, forKey: .status)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        answerMarkdown = try container.decodeIfPresent(String.self, forKey: .answerMarkdown)
        saved = try container.decodeIfPresent(Bool.self, forKey: .saved)
        saveError = try container.decodeIfPresent(String.self, forKey: .saveError)
        citations = try container.decodeIfPresent([WikiDaemonCitation].self, forKey: .citations) ?? []
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        error = try container.decodeIfPresent(WikiDaemonErrorDetail.self, forKey: .error)
    }
}

nonisolated struct WikiDaemonErrorDetail: Decodable, Equatable {
    let code: String
    let message: String
    let retryable: Bool
}

nonisolated enum WikiDaemonClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case api(statusCode: Int, detail: WikiDaemonErrorDetail?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The daemon URL is invalid."
        case .invalidResponse:
            return "The daemon returned an invalid response."
        case .api(_, let detail):
            return detail?.message ?? "The daemon request failed."
        }
    }
}

nonisolated struct WikiDaemonClient {
    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func health() async throws -> WikiDaemonHealthResponse {
        let request = Self.makeHealthRequest(baseURL: baseURL)
        return try await send(request)
    }

    func startQuery(question: String, save: Bool) async throws -> WikiDaemonQueryStartResponse {
        let request = try Self.makeStartQueryRequest(
            baseURL: baseURL,
            token: token,
            question: question,
            save: save
        )
        return try await send(request)
    }

    func queryStatus(jobID: String) async throws -> WikiDaemonQueryStatusResponse {
        let request = Self.makeQueryStatusRequest(baseURL: baseURL, token: token, jobID: jobID)
        return try await send(request)
    }

    static func makeHealthRequest(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: "api/v1/health"))
        request.httpMethod = "GET"
        return request
    }

    static func makeStartQueryRequest(
        baseURL: URL,
        token: String,
        question: String,
        save: Bool
    ) throws -> URLRequest {
        var request = authenticatedRequest(
            baseURL: baseURL,
            path: "api/v1/query",
            token: token
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "question": question,
            "save": save,
        ])
        return request
    }

    static func makeQueryStatusRequest(baseURL: URL, token: String, jobID: String) -> URLRequest {
        var request = authenticatedRequest(
            baseURL: baseURL,
            path: "api/v1/query/\(jobID)",
            token: token
        )
        request.httpMethod = "GET"
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WikiDaemonClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(WikiDaemonErrorEnvelope.self, from: data)
            throw WikiDaemonClientError.api(statusCode: http.statusCode, detail: envelope?.error)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func authenticatedRequest(baseURL: URL, path: String, token: String) -> URLRequest {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func endpoint(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joined = [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = "/" + joined
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL
    }
}

nonisolated private struct WikiDaemonErrorEnvelope: Decodable {
    let error: WikiDaemonErrorDetail
}
