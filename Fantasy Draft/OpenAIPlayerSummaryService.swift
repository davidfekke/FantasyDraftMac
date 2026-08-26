import Foundation
import Security

enum PlayerSummaryProvider: String, CaseIterable, Identifiable, Sendable {
    nonisolated static let defaultsKey = "playerSummaryProvider"

    case appleFoundationModels
    case openAI

    var id: Self { self }

    var title: String {
        switch self {
        case .appleFoundationModels:
            return "Apple Foundation Models"
        case .openAI:
            return "OpenAI"
        }
    }

    nonisolated static var selected: Self {
        guard let value = UserDefaults.standard.string(forKey: defaultsKey) else {
            return .appleFoundationModels
        }

        return Self(rawValue: value) ?? .appleFoundationModels
    }
}

enum OpenAICredentialStore {
    nonisolated private static let account = "openai-api-key"
    nonisolated private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "Fantasy-Draft").openai"
    }

    nonisolated static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        return key
    }

    nonisolated static func save(apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            try deleteAPIKey()
            return
        }

        let keyData = Data(trimmedKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: keyData
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = keyData
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAICredentialError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw OpenAICredentialError.keychainStatus(updateStatus)
        }
    }

    nonisolated static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAICredentialError.keychainStatus(status)
        }
    }
}

enum OpenAICredentialError: LocalizedError {
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "The API key could not be saved."
        }
    }
}

protocol OpenAIPlayerSummarizing: Sendable {
    nonisolated func summarize(prompt: String, apiKey: String) async throws -> String
    nonisolated func streamSummarize(
        prompt: String,
        apiKey: String,
        onPartialSummary: @Sendable @escaping (String) async -> Void
    ) async throws -> String
}

struct OpenAIPlayerSummaryService: OpenAIPlayerSummarizing {
    nonisolated private static let endpointString = "https://api.openai.com/v1/responses"
    nonisolated private static let instructions = """
    You summarize NFL fantasy football player research. Use only the supplied excerpts.
    Write one short paragraph followed by three concise bullets. Mention uncertainty when the source text is thin or stale.
    """

    let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func summarize(prompt: String, apiKey: String) async throws -> String {
        let request = try makeRequest(prompt: prompt, apiKey: apiKey, stream: false)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIPlayerSummaryError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
            throw OpenAIPlayerSummaryError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }

        let responseBody = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        let summary = responseBody.output
            .flatMap(\.content)
            .filter { $0.type == "output_text" }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty else {
            throw OpenAIPlayerSummaryError.emptyResponse
        }

        return summary
    }

    nonisolated func streamSummarize(
        prompt: String,
        apiKey: String,
        onPartialSummary: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        let request = try makeRequest(prompt: prompt, apiKey: apiKey, stream: true)
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIPlayerSummaryError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: errorData)
            throw OpenAIPlayerSummaryError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }

        var summary = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else { continue }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(OpenAIStreamEvent.self, from: data) else {
                continue
            }

            switch event.type {
            case "response.output_text.delta":
                guard let delta = event.delta, !delta.isEmpty else { continue }
                summary += delta

                let partialSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !partialSummary.isEmpty {
                    await onPartialSummary(partialSummary)
                }
            case "response.failed", "error":
                throw OpenAIPlayerSummaryError.streamingFailed(
                    message: event.response?.error?.message ?? event.error?.message
                )
            default:
                continue
            }
        }

        let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalSummary.isEmpty else {
            throw OpenAIPlayerSummaryError.emptyResponse
        }

        return finalSummary
    }

    nonisolated private func makeRequest(prompt: String, apiKey: String, stream: Bool) throws -> URLRequest {
        guard let endpoint = URL(string: Self.endpointString) else {
            throw OpenAIPlayerSummaryError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: "gpt-5.6-luna",
                instructions: Self.instructions,
                input: prompt,
                maxOutputTokens: 500,
                reasoning: .init(effort: "none"),
                text: .init(verbosity: "low"),
                stream: stream
            )
        )
        return request
    }
}

nonisolated private struct OpenAIResponseRequest: Encodable {
    struct Reasoning: Encodable {
        let effort: String
    }

    struct TextConfiguration: Encodable {
        let verbosity: String
    }

    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let reasoning: Reasoning
    let text: TextConfiguration
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case reasoning
        case text
        case stream
    }
}

nonisolated private struct OpenAIResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        let content: [OutputContent]
    }

    struct OutputContent: Decodable {
        let type: String
        let text: String
    }

    let output: [OutputItem]
}

nonisolated private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

nonisolated private struct OpenAIStreamEvent: Decodable {
    struct ResponseFailure: Decodable {
        let error: OpenAIErrorEnvelope.APIError?
    }

    let type: String
    let delta: String?
    let response: ResponseFailure?
    let error: OpenAIErrorEnvelope.APIError?
}

enum OpenAIPlayerSummaryError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case streamingFailed(message: String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .requestFailed(let statusCode, let message):
            return message ?? "OpenAI returned HTTP status \(statusCode)."
        case .streamingFailed(let message):
            return message ?? "OpenAI could not complete the streamed summary."
        case .emptyResponse:
            return "OpenAI returned an empty summary."
        }
    }
}
