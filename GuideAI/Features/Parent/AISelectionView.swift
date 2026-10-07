import FamilyControls
import SwiftUI

struct AISelectionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FamilyActivitySelection

    init() {
        _selection = State(initialValue: FamilyActivitySelection())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select external AI apps and websites to restrict when blocking is enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FamilyActivityPicker(selection: $selection)

                if !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected")
                            .font(.headline)
                        ForEach(Array(selection.applicationTokens), id: \.self) { token in
                            Label(token)
                        }
                        ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                            Label(token)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("External AI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.familyControls.activitySelection = selection
                        env.familyControls.saveSelection()
                        env.syncShieldsFromPolicy()
                        dismiss()
                    }
                }
            }
            .onAppear {
                selection = env.familyControls.activitySelection
            }
        }
    }
}
