import SwiftUI

struct ModeConfigurationView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AIMode
    @State private var customInstructions: String

    init() {
        _mode = State(initialValue: .learning)
        _customInstructions = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(AIMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    Text(mode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Custom Instructions") {
                    TextField("Optional guidance for the assistant", text: $customInstructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.updatePolicy {
                            $0.mode = mode
                            $0.customInstructions = customInstructions
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                mode = env.policyStore.policy.mode
                customInstructions = env.policyStore.policy.customInstructions
            }
        }
    }
}
