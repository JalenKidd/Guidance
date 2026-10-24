import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: FamilyStore
    @AppStorage("guidance.appearance") private var appearance = GuidanceAppearance.system.rawValue
    @State private var serverAddress = UserDefaults.standard.string(forKey: AppConfig.serverURLKey) ?? ""
    @State private var newKidName = ""
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TabHeader("Setup")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(store.kids) { kid in
                        NavigationLink {
                            KidProfileView(kidID: kid.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(kid.paired ? GuideTheme.success : Color.secondary.opacity(0.4))
                                    .frame(width: 10, height: 10)
                                    .accessibilityLabel(kid.paired ? "Phone paired" : "No phone paired")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kid.name)
                                    Text(kid.paired ? "Phone paired" : "Code \(kid.pairingCode) · not paired yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("Add a kid", text: $newKidName)
                            .textContentType(.givenName)
                            .onSubmit(addKid)
                        Button("Add", action: addKid)
                            .disabled(newKidName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Kids")
                } footer: {
                    Text("Each kid has their own rules and a pairing code for their phone. Tap a kid to see their code and phone setup.")
                }

                Section {
                    PhoneSetupSteps()
                } header: {
                    Text("Set up a kid's phone")
                } footer: {
                    Text("Guidance works in Safari. Without Apple's paid Family Controls, the native AI apps are closed off with Screen Time instead.")
                }

                Section {
                    GuardianNameField()
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Your kids see this as \"Guardian: \(store.parentName ?? "your name")\" in the Guidance extension in Safari.")
                }

                Section("Server") {
                    ServerAddressField(address: $serverAddress)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(GuidanceAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Lock parent controls") { store.isUnlocked = false }
                    Button("Sign out of this family", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("Signing out removes the family from this phone only. Sign back in with your account email; rules stay on the server.")
                }
            }
            .navigationTitle("Setup")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .confirmationDialog("Sign out of this family?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { store.signOut() }
            }
        }
    }

    private func addKid() {
        let name = newKidName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newKidName = ""
        Task { await store.addKid(named: name) }
    }
}
