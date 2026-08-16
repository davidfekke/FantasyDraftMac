import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DraftBoardViewModel {
    private let playerLoader: PlayerLoading
    private var players: [FantasyPlayer] = []
    private var submittedSearchTerm = ""

    var searchText = ""
    var selectedPosition: String?
    var selectedPlayer: FantasyPlayer?
    var automaticallySelectsFirstPlayer = true
    var isLoading = false
    var errorMessage: String?

    let positionFilters = ["RB", "WR", "K", "QB", "TE"]

    init(playerLoader: PlayerLoading = BundledPlayerRepository()) {
        self.playerLoader = playerLoader
    }

    var visiblePlayers: [FantasyPlayer] {
        players.filter { player in
            let matchesSearch = submittedSearchTerm.isEmpty || player.fullName.localizedCaseInsensitiveContains(submittedSearchTerm)
            let matchesPosition = selectedPosition == nil || player.position == selectedPosition
            return matchesSearch && matchesPosition
        }
    }

    var totalPlayerCount: Int {
        players.count
    }

    func loadPlayers(modelContext: ModelContext) async {
        guard players.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            players = try await playerLoader.loadPlayers(modelContext: modelContext)
            selectedPlayer = automaticallySelectsFirstPlayer ? players.first : nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reloadPlayers(modelContext: ModelContext) async {
        players = []
        selectedPlayer = nil
        await loadPlayers(modelContext: modelContext)
    }

    func resetDraft(modelContext: ModelContext) throws {
        let persistedPlayers = try modelContext.fetch(FetchDescriptor<FantasyPlayer>())

        for player in persistedPlayers {
            player.clearDraftState()
        }

        try modelContext.save()
    }

    func submitSearch() {
        submittedSearchTerm = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSelectionAfterFiltering()
    }

    func clearSearch() {
        searchText = ""
        submittedSearchTerm = ""
        updateSelectionAfterFiltering()
    }

    func togglePosition(_ position: String) {
        selectedPosition = selectedPosition == position ? nil : position
        updateSelectionAfterFiltering()
    }

    func togglePicked(_ player: FantasyPlayer) {
        player.isPicked.toggle()
    }

    func select(_ player: FantasyPlayer) {
        selectedPlayer = player
    }

    private func updateSelectionAfterFiltering() {
        let visibleIDs = Set(visiblePlayers.map(\.id))

        if let selectedPlayer, visibleIDs.contains(selectedPlayer.id) {
            return
        }

        selectedPlayer = automaticallySelectsFirstPlayer ? visiblePlayers.first : nil
    }
}
