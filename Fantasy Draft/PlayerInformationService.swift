import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct PlayerInformationSummary: Sendable {
    let text: String
    let sourceURLs: [PlayerProfileURL]
    let usedFoundationModel: Bool
}

actor PlayerInformationService {
    static let shared = PlayerInformationService()

    private let session: URLSession
    private var cache: [FantasyPlayer.ID: PlayerInformationSummary] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func clearCache() {
        cache.removeAll()
    }

    func summary(for player: FantasyPlayer, refresh: Bool = false) async throws -> PlayerInformationSummary {
        if !refresh, let cached = cache[player.id] {
            return cached
        }

        let urls = player.profileURLs
        guard !urls.isEmpty else {
            throw PlayerInformationError.noSources
        }

        let excerpts = await fetchExcerpts(from: urls, playerName: player.fullName)
        guard !excerpts.isEmpty else {
            throw PlayerInformationError.noReadableSourceText
        }

        let prompt = Self.makePrompt(player: player, excerpts: excerpts)
        let modelSummary = await summarizeWithFoundationModel(prompt: prompt)
        let summary = PlayerInformationSummary(
            text: modelSummary ?? Self.makeExtractiveSummary(player: player, excerpts: excerpts),
            sourceURLs: excerpts.map(\.profileURL),
            usedFoundationModel: modelSummary != nil
        )

        cache[player.id] = summary
        return summary
    }

    private func fetchExcerpts(from urls: [PlayerProfileURL], playerName: String) async -> [PlayerSourceExcerpt] {
        await withTaskGroup(of: PlayerSourceExcerpt?.self) { group in
            for profileURL in urls {
                group.addTask { [session] in
                    await Self.fetchExcerpt(profileURL: profileURL, playerName: playerName, session: session)
                }
            }

            var excerpts: [PlayerSourceExcerpt] = []
            for await excerpt in group {
                if let excerpt {
                    excerpts.append(excerpt)
                }
            }

            return excerpts.sorted { $0.profileURL.source < $1.profileURL.source }
        }
    }

    private static func fetchExcerpt(profileURL: PlayerProfileURL, playerName: String, session: URLSession) async -> PlayerSourceExcerpt? {
        var request = URLRequest(url: profileURL.url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 Fantasy Draft macOS app", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }

            let text = readableText(from: html, playerName: playerName)
            guard text.count > 80 else { return nil }
            return PlayerSourceExcerpt(profileURL: profileURL, text: text)
        } catch {
            return nil
        }
    }

    private static func readableText(from html: String, playerName: String) -> String {
        let withoutScripts = html
            .replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<noscript[^>]*>.*?</noscript>", with: " ", options: .regularExpression)
        let plainText = withoutScripts
            .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
            .decodingBasicHTMLEntities
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = plainText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sentence in
                sentence.count > 35 && sentence.localizedCaseInsensitiveContains(playerName)
            }

        let selectedText = sentences.isEmpty ? plainText : sentences.joined(separator: ". ")
        return String(selectedText.prefix(2_800))
    }

    private static func makePrompt(player: FantasyPlayer, excerpts: [PlayerSourceExcerpt]) -> String {
        let sourceText = excerpts.map { excerpt in
            "Source: \(excerpt.profileURL.source)\nURL: \(excerpt.profileURL.url.absoluteString)\nExcerpt: \(excerpt.text)"
        }.joined(separator: "\n\n")

        return """
        Player: \(player.fullName)
        Position: \(player.position ?? "Unknown")
        Team: \(player.displayTeam ?? "Unknown")
        Rank: \(player.searchRank.map(String.init) ?? "Unknown")

        Summarize this NFL player information for a fantasy draft manager. Use only the source excerpts below. Focus on role, team context, injury/status notes, upside/risk, and draft relevance. Keep it concise.

        \(sourceText)
        """
    }

    private static func makeExtractiveSummary(player: FantasyPlayer, excerpts: [PlayerSourceExcerpt]) -> String {
        let sourceList = excerpts.map { $0.profileURL.source }.joined(separator: ", ")
        let combinedText = excerpts.map(\.text).joined(separator: " ")
        let clipped = String(combinedText.prefix(700))

        return "\(player.fullName) profile information was found from \(sourceList), but Apple Foundation Models was not available to generate a summary. Source excerpt: \(clipped)"
    }

    private func summarizeWithFoundationModel(prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelPlayerSummaryGenerator.summarize(prompt: prompt)
        }
        #endif

        return nil
    }
}

private struct PlayerSourceExcerpt: Sendable {
    let profileURL: PlayerProfileURL
    let text: String
}

enum PlayerInformationError: LocalizedError {
    case noSources
    case noReadableSourceText

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "This player does not have any supported profile URLs."
        case .noReadableSourceText:
            return "No readable player information could be loaded from the profile sources."
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelPlayerSummaryGenerator {
    static func summarize(prompt: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: """
            You summarize NFL fantasy football player research. Use only the supplied excerpts.
            Write one short paragraph followed by three concise bullets. Mention uncertainty when the source text is thin or stale.
            """)
            let response = try await session.respond(to: prompt)
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        } catch {
            return nil
        }
    }
}
#endif

private extension String {
    nonisolated var decodingBasicHTMLEntities: String {
        replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
