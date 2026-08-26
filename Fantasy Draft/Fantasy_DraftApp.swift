import SwiftData
import SwiftUI

@main
struct Fantasy_DraftApp: App {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var viewModel = DraftBoardViewModel()

    private let modelContainer: ModelContainer = {
        let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.fekke.Fantasy-Draft"))

        do {
            return try ModelContainer(for: FantasyPlayer.self, configurations: configuration)
        } catch {
            fatalError("Unable to create SwiftData container: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        #if os(macOS)
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

        Settings {
            SettingsView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
        #else
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
        #endif
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PlayerSummaryProvider.defaultsKey) private var summaryProvider = PlayerSummaryProvider.appleFoundationModels.rawValue
    @State private var isUpdating = false
    @State private var isResetting = false
    @State private var statusMessage: String?
    @State private var openAIAPIKey = ""
    @State private var openAIStatusMessage: String?

    private let dataStore = PlayerDataStore()
    let viewModel: DraftBoardViewModel

    var body: some View {
        Form {
            Section {
                Picker("Summary provider", selection: $summaryProvider) {
                    ForEach(PlayerSummaryProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }

                SecureField("OpenAI API key", text: $openAIAPIKey)
                    .textContentType(.password)

                HStack {
                    Button("Save Key") {
                        saveOpenAIAPIKey()
                    }
                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove Key", role: .destructive) {
                        removeOpenAIAPIKey()
                    }
                    .disabled(OpenAICredentialStore.apiKey() == nil)
                }

                Text("The key is stored in this Mac's Keychain. Player source excerpts are sent to OpenAI when this provider is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let openAIStatusMessage {
                    Text(openAIStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Player Summaries")
            }

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
        .frame(minWidth: 520, minHeight: 460)
        .onAppear {
            openAIAPIKey = OpenAICredentialStore.apiKey() ?? ""
        }
        .onChange(of: summaryProvider) { _, _ in
            Task {
                await PlayerInformationService.shared.clearCache()
            }
        }
        .onDisappear {
            openAIAPIKey = ""
        }
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

    private func saveOpenAIAPIKey() {
        do {
            try OpenAICredentialStore.save(apiKey: openAIAPIKey)
            openAIStatusMessage = "OpenAI API key saved."
            Task {
                await PlayerInformationService.shared.clearCache()
            }
        } catch {
            openAIStatusMessage = error.localizedDescription
        }
    }

    private func removeOpenAIAPIKey() {
        do {
            try OpenAICredentialStore.deleteAPIKey()
            openAIAPIKey = ""
            openAIStatusMessage = "OpenAI API key removed."
            Task {
                await PlayerInformationService.shared.clearCache()
            }
        } catch {
            openAIStatusMessage = error.localizedDescription
        }
    }
}
