import SwiftUI

/// One kid's profile: name, the pairing code for their phone, and phone setup steps.
struct KidProfileView: View {
    @EnvironmentObject private var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    let kidID: String
    @State private var name = ""
    @State private var confirmingRemove = false

    private var kid: Kid? { store.kids.first { $0.id == kidID } }

    var body: some View {
        Group {
            if let kid {
                form(kid)
            } else {
                ContentUnavailableView("Kid removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(kid?.name ?? "Kid")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = kid?.name ?? "" }
    }

    private func form(_ kid: Kid) -> some View {
        Form {
            Section("Name") {
                HStack {
                    TextField("First name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit(rename)
                    if trimmedName != kid.name && !trimmedName.isEmpty {
                        Button("Save", action: rename).fontWeight(.semibold)
                    }
                }
            }

            Section {
                VStack(spacing: 8) {
                    Text("PAIRING CODE")
                        .font(.caption2.weight(.heavy))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)
                    Text(kid.pairingCode)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .kerning(6)
                        .textSelection(.enabled)
                    Label(kid.paired ? "Phone paired · last check-in \(TimeText.relative(kid.lastHeartbeat))" : "No phone paired yet",
                          systemImage: kid.paired ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.subheadline)
                        .foregroundStyle(kid.paired ? GuideTheme.success : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("Enter this code in the Guidance extension in Safari on \(kid.name)'s phone. Pairing again with the code moves Guidance to a new phone.")
            }

            Section {
                PhoneSetupSteps(kidName: kid.name)
            } header: {
                Text("Set up \(kid.name)'s phone")
            }

            Section {
                Button("Remove \(kid.name)", role: .destructive) { confirmingRemove = true }
            } footer: {
                Text("Removes their rules and activity. Their phone stops getting rule updates.")
            }
        }
        .confirmationDialog("Remove \(kid.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove kid and their rules", role: .destructive) {
                Task {
                    await store.removeKid(kid.id)
                    dismiss()
                }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func rename() {
        guard !trimmedName.isEmpty else { return }
        Task { await store.renameKid(kidID, to: trimmedName) }
    }
}
