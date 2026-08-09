import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: DraftBoardViewModel
    @State private var presentedPlayer: FantasyPlayer?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Fantasy Draft")
        } detail: {
            detailPane
        }
        .task {
            await viewModel.loadPlayers(modelContext: modelContext)
        }
        .sheet(item: $presentedPlayer) { player in
            PlayerDetailSheet(player: player)
                .presentationSizing(.form)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterBar
                .padding()

            Divider()

            contentList
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit {
                        viewModel.submitSearch()
                    }

                Button("Search") {
                    viewModel.submitSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            HStack(spacing: 8) {
                Button("Clear") {
                    viewModel.clearSearch()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                ForEach(viewModel.positionFilters, id: \.self) { position in
                    Toggle(position, isOn: Binding(
                        get: { viewModel.selectedPosition == position },
                        set: { _ in viewModel.togglePosition(position) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }

            Text("\(viewModel.visiblePlayers.count) of \(viewModel.totalPlayerCount) players")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if viewModel.isLoading {
            ProgressView("Loading players...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView("Unable to Load Players", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if viewModel.visiblePlayers.isEmpty {
            ContentUnavailableView("No Players", systemImage: "magnifyingglass", description: Text("Try a different search or position filter."))
        } else {
            List(selection: Binding(
                get: { viewModel.selectedPlayer?.id },
                set: { playerID in
                    guard let playerID, let player = viewModel.visiblePlayers.first(where: { $0.id == playerID }) else { return }
                    viewModel.select(player)
                }
            )) {
                ForEach(viewModel.visiblePlayers) { player in
                    PlayerRow(
                        player: player,
                        isPicked: player.isPicked,
                        onTogglePicked: { togglePicked(player) },
                        onShowInfo: { presentedPlayer = player }
                    )
                    .tag(player.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let player = viewModel.selectedPlayer {
            PlayerDetailView(player: player, isPicked: player.isPicked) {
                togglePicked(player)
            }
            .padding(24)
        } else {
            ContentUnavailableView("Select a Player", systemImage: "person.crop.circle", description: Text("Choose a draft candidate from the list."))
        }
    }

    private func togglePicked(_ player: FantasyPlayer) {
        viewModel.togglePicked(player)

        do {
            try modelContext.save()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct PlayerRow: View {
    let player: FantasyPlayer
    let isPicked: Bool
    let onTogglePicked: () -> Void
    let onShowInfo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTogglePicked) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPicked ? .green : .secondary)
            .accessibilityLabel(isPicked ? "Mark \(player.fullName) available" : "Mark \(player.fullName) picked")

            VStack(alignment: .leading, spacing: 4) {
                Text(player.fullName)
                    .font(.headline)
                    .strikethrough(isPicked)

                Text(player.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough(isPicked)
            }

            Spacer(minLength: 12)

            Button("Info") {
                onShowInfo()
            }
            .controlSize(.small)
        }
        .contentShape(Rectangle())
        //.onTapGesture(perform: onTogglePicked)
        .padding(.vertical, 4)
    }
}

struct PlayerDetailView: View {
    let player: FantasyPlayer
    let isPicked: Bool
    let onTogglePicked: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    PlayerHeadshot(player: player, size: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(player.fullName)
                            .font(.largeTitle.weight(.bold))
                            .strikethrough(isPicked)

                        Text("\(display(player.position)) | \(display(player.displayTeam))")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Button(isPicked ? "Mark Available" : "Mark Picked") {
                            onTogglePicked()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isPicked ? .green : .blue)
                    }
                }

                DetailGrid(player: player)

                PlayerInformationSummaryView(player: player)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }
}

struct PlayerDetailSheet: View {
    let player: FantasyPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.fullName)
                            .font(.title.weight(.bold))
                        Text("\(display(player.position)) | \(display(player.displayTeam))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                }

                PlayerHeadshot(player: player, size: 180)
                DetailGrid(player: player)
                PlayerInformationSummaryView(player: player)
            }
            .padding(24)
            .frame(width: 560, alignment: .leading)
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }
}

struct PlayerHeadshot: View {
    let player: FantasyPlayer
    let size: CGFloat

    var body: some View {
        AsyncImage(url: player.headshotURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.rectangle")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .accessibilityLabel("\(player.fullName) headshot")
    }
}

struct PlayerInformationSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let player: FantasyPlayer
    @State private var loadState: LoadState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Player Summary")
                    .font(.headline)

                Spacer()

                Button("Refresh") {
                    loadSummary(refresh: true)
                }
                .controlSize(.small)
                .disabled(loadState.isLoading)
            }

            switch loadState {
            case .idle, .loading:
                ProgressView("Loading player information...")
                    .controlSize(.small)
            case .loaded(let summary):
                Text(summary.text)
                    .font(.body)
                    .textSelection(.enabled)

                if !summary.sourceURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.usedFoundationModel ? "Summarized with Apple Foundation Models" : "Foundation Models unavailable; showing source excerpt")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(summary.sourceURLs, id: \.self) { profileURL in
                            Link(profileURL.source, destination: profileURL.url)
                                .font(.caption)
                        }
                    }
                }
            case .failed(let message):
                ContentUnavailableView("Summary Unavailable", systemImage: "text.page.badge.magnifyingglass", description: Text(message))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .task(id: player.id) {
            loadSummary()
        }
    }

    private func loadSummary(refresh: Bool = false) {
        if !refresh, let storedSummary = player.storedSummary {
            loadState = .loaded(storedSummary)
            return
        }

        loadState = .loading

        Task {
            do {
                let summary = try await PlayerInformationService.shared.summary(for: player, refresh: refresh)
                await MainActor.run {
                    player.storeSummary(summary)

                    do {
                        try modelContext.save()
                        loadState = .loaded(summary)
                    } catch {
                        loadState = .failed(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    loadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private enum LoadState {
        case idle
        case loading
        case loaded(PlayerInformationSummary)
        case failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }
}

struct DetailGrid: View {
    let player: FantasyPlayer

    private var fields: [(String, String)] {
        [
            ("Rank", display(player.searchRank)),
            ("Number", display(player.number)),
            ("Age", display(player.age)),
            ("Experience", display(player.yearsExperience)),
            ("Height", display(player.height)),
            ("Weight", display(player.weight)),
            ("College", display(player.college)),
            ("Status", display(player.status)),
            ("Birth Date", display(player.birthDate)),
            ("Player ID", display(player.playerID)),
            ("ESPN ID", display(player.espnID)),
            ("Yahoo ID", display(player.yahooID)),
            ("FantasyData ID", display(player.fantasyDataID)),
            ("Rotowire ID", display(player.rotowireID))
        ]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
            ForEach(fields, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }

    private func display(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }
}

#Preview {
    ContentView(viewModel: DraftBoardViewModel())
}
