import SwiftUI

struct SettingsView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.myName) private var myName = "Jason Smith"
    @AppStorage(Prefs.showWeekends) private var showWeekends = false

    @State private var tokenDraft = ""
    @State private var hasToken = KeychainStore.readToken() != nil
    @State private var savedFlash = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(hasToken ? Chalk.green : Chalk.pink)
                            .frame(width: 10, height: 10)
                            .shadow(color: hasToken ? Chalk.green : Chalk.pink, radius: 3)
                        Text(hasToken ? "Connected to monday.com" : "Not connected")
                            .font(Chalk.font(16, bold: true))
                            .chalk()
                    }
                    SecureField(hasToken ? "Replace API token" : "Paste monday API token", text: $tokenDraft)
                        .font(Chalk.font(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(savedFlash ? "Saved ✓" : "Save & sync") { saveToken() }
                            .buttonStyle(ChalkButtonStyle(color: Chalk.yellow))
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        if hasToken {
                            Button("Disconnect") {
                                KeychainStore.deleteToken()
                                hasToken = false
                                store.useSampleData()
                            }
                            .buttonStyle(ChalkButtonStyle(color: Chalk.pink))
                        }
                    }
                } header: {
                    header("monday.com")
                } footer: {
                    Text("In monday: avatar → Developers → My access tokens → copy. The token stays in this iPhone's Keychain and is only sent to api.monday.com.")
                        .font(Chalk.font(12)).chalk(Chalk.dim)
                }
                .listRowBackground(Chalk.boardDeep.opacity(0.6))

                Section {
                    TextField("Your instructor name", text: $myName)
                        .font(Chalk.font(16))
                    Toggle("Show weekends", isOn: $showWeekends)
                        .font(Chalk.font(15))
                        .tint(Chalk.green)
                } header: {
                    header("You")
                } footer: {
                    Text("Your name must match the Instructor label on the boards. It powers the \"Just me\" filter.")
                        .font(Chalk.font(12)).chalk(Chalk.dim)
                }
                .listRowBackground(Chalk.boardDeep.opacity(0.6))

                Section {
                    LabeledContent("Classes loaded") {
                        Text("\(store.trainings.count)").chalk()
                    }
                    LabeledContent("Last synced") {
                        Text(store.lastUpdated.map { $0.formatted(.relative(presentation: .named)) } ?? (store.isSampleData ? "Sample data" : "Never"))
                            .chalk()
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Text(store.isLoading ? "Syncing…" : "Sync now")
                            Spacer()
                            if store.isLoading { ProgressView().tint(Chalk.white) }
                        }
                    }
                    .disabled(!hasToken || store.isLoading)
                    if let error = store.lastError {
                        Text(error).font(Chalk.font(13)).chalk(Chalk.pink)
                    }
                } header: {
                    header("Data")
                }
                .font(Chalk.font(15))
                .listRowBackground(Chalk.boardDeep.opacity(0.6))

                Section {
                    ForEach(SourceBoard.allCases) { board in
                        Label {
                            VStack(alignment: .leading) {
                                Text(board.title).chalk()
                                Text("Board \(board.boardID)").font(Chalk.font(11)).chalk(Chalk.dim)
                            }
                        } icon: {
                            Image(systemName: board.symbol).chalk(Chalk.yellow)
                        }
                    }
                } header: {
                    header("Calendar boards")
                } footer: {
                    Text("The same three boards behind the monday Calendar dashboard. Bootcamp weeks come from each course's subitems.")
                        .font(Chalk.font(12)).chalk(Chalk.dim)
                }
                .font(Chalk.font(15))
                .listRowBackground(Chalk.boardDeep.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
            .background(ChalkboardBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Chalk.boardDeep)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(Chalk.font(13, bold: true, relativeTo: .footnote)).chalk(Chalk.dim)
    }

    private func saveToken() {
        guard KeychainStore.saveToken(tokenDraft) else { return }
        tokenDraft = ""
        hasToken = true
        withAnimation { savedFlash = true }
        Task {
            await store.refresh()
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { savedFlash = false }
        }
    }
}
