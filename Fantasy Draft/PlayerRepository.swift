import Foundation
import SwiftData

protocol PlayerLoading {
    @MainActor func loadPlayers(modelContext: ModelContext) async throws -> [FantasyPlayer]
}

struct PlayerDataStore: Sendable {
    nonisolated private static let remoteURL = URL(string: "https://api.sleeper.app/v1/players/nfl")!
    nonisolated private static let fileName = "nfl.customization.json"

    nonisolated init() {}

    nonisolated var localURL: URL {
        get throws {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let appSupportURL = applicationSupportURL.appendingPathComponent("Fantasy Draft", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            return appSupportURL.appendingPathComponent(Self.fileName)
        }
    }

    func downloadLatestPlayers() async throws {
        let (data, response) = try await URLSession.shared.data(from: Self.remoteURL)
        let destinationURL = try localURL

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlayerRepositoryError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlayerRepositoryError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        try await Task.detached(priority: .userInitiated) {
            _ = try JSONDecoder().decode([String: DraftItem].self, from: data)
            try data.write(to: destinationURL, options: .atomic)
        }.value
    }
}

struct BundledPlayerRepository: PlayerLoading {
    let bundle: Bundle
    let dataStore: PlayerDataStore

    nonisolated init(bundle: Bundle = .main, dataStore: PlayerDataStore = PlayerDataStore()) {
        self.bundle = bundle
        self.dataStore = dataStore
    }

    @MainActor
    func loadPlayers(modelContext: ModelContext) async throws -> [FantasyPlayer] {
        guard let url = playerDataURL() else {
            throw PlayerRepositoryError.missingResource
        }

        let draftItems = try await loadDraftItems(from: url)
        return try upsertPlayers(from: draftItems, modelContext: modelContext)
    }

    private func loadDraftItems(from url: URL) async throws -> [(id: String, item: DraftItem, fullName: String)] {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let draftItems = try decoder.decode([String: DraftItem].self, from: data)

            return draftItems.compactMap { id, draftItem in
                guard let fullName = Self.eligibleFullName(for: draftItem) else { return nil }
                return (id: id, item: draftItem, fullName: fullName)
            }
        }.value
    }

    @MainActor
    private func upsertPlayers(from draftItems: [(id: String, item: DraftItem, fullName: String)], modelContext: ModelContext) throws -> [FantasyPlayer] {
        let existingPlayers = try modelContext.fetch(FetchDescriptor<FantasyPlayer>())
        var playersByID: [String: FantasyPlayer] = [:]

        for player in existingPlayers {
            if let existing = playersByID[player.id] {
                if player.isPicked && !existing.isPicked {
                    modelContext.delete(existing)
                    playersByID[player.id] = player
                } else {
                    modelContext.delete(player)
                }
            } else {
                playersByID[player.id] = player
            }
        }

        var activeIDs = Set<String>()

        for draftItem in draftItems {
            activeIDs.insert(draftItem.id)

            if let player = playersByID[draftItem.id] {
                player.update(from: draftItem.item, fullName: draftItem.fullName)
            } else {
                let player = FantasyPlayer(id: draftItem.id, fullName: draftItem.fullName, draftItem: draftItem.item)
                modelContext.insert(player)
                playersByID[draftItem.id] = player
            }
        }

        for stalePlayer in existingPlayers where !activeIDs.contains(stalePlayer.id) {
            modelContext.delete(stalePlayer)
        }

        try modelContext.save()

        return playersByID.values.sorted { lhs, rhs in
            guard let lhsRank = lhs.searchRank, let rhsRank = rhs.searchRank else {
                return lhs.searchRank != nil
            }

            if lhsRank == rhsRank {
                return lhs.fullName.localizedStandardCompare(rhs.fullName) == .orderedAscending
            }

            return lhsRank < rhsRank
        }
    }

    private func playerDataURL() -> URL? {
        if let localURL = try? dataStore.localURL, FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        return bundle.url(forResource: "nfl.customization", withExtension: "json")
    }

    private nonisolated static func eligibleFullName(for item: DraftItem) -> String? {
        guard let rank = item.searchRank, rank < 9_999_999 else { return nil }
        guard let fullName = item.fullName else { return nil }
        guard fullName != "Player Invalid", fullName != "Duplicate Player" else { return nil }
        guard !fullName.contains("DUPLICATE") else { return nil }
        return fullName
    }
}

enum PlayerRepositoryError: LocalizedError {
    case missingResource
    case invalidResponse
    case downloadFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "The NFL player list could not be found."
        case .invalidResponse:
            return "Sleeper returned an invalid response."
        case .downloadFailed(let statusCode):
            return "Sleeper returned HTTP \(statusCode)."
        }
    }
}
