import SwiftData
import SwiftUI

@main
struct Fantasy_DraftApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = DraftBoardViewModel()

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: FantasyPlayer.self)
        } catch {
            fatalError("Unable to create SwiftData container: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Fantasy Draft") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About Fantasy Draft", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        #if os(macOS)
        Settings {
            SettingsView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
        #endif
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isUpdating = false
    @State private var isResetting = false
    @State private var statusMessage: String?

    private let dataStore = PlayerDataStore()
    let viewModel: DraftBoardViewModel

    var body: some View {
        Form {
            Section {
                Button {
                    updatePlayerData()
                } label: {
                    if isUpdating {
                        ProgressView()
                    } else {
                        Text("Update NFL Player Data")
                    }
                }
                .disabled(isUpdating || isResetting)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Player Data")
            }

            Section {
                Button(role: .destructive) {
                    resetDraft()
                } label: {
                    if isResetting {
                        ProgressView()
                    } else {
                        Text("Reset Draft")
                    }
                }
                .disabled(isUpdating || isResetting)
            } header: {
                Text("Draft")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }

    private func updatePlayerData() {
        isUpdating = true
        statusMessage = nil

        Task {
            do {
                try await dataStore.downloadLatestPlayers()
                await viewModel.reloadPlayers(modelContext: modelContext)
                statusMessage = "NFL player data updated."
            } catch {
                statusMessage = error.localizedDescription
            }

            isUpdating = false
        }
    }

    private func resetDraft() {
        isResetting = true
        statusMessage = nil

        Task {
            do {
                try viewModel.resetDraft(modelContext: modelContext)
                await PlayerInformationService.shared.clearCache()
                statusMessage = "Draft reset."
            } catch {
                statusMessage = error.localizedDescription
            }

            isResetting = false
        }
    }
}
