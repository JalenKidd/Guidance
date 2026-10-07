import SwiftUI

struct ParentSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var blockExternal: Bool = true
    @State private var dailyLimit: Double = 45
    @State private var requireAttempt: Bool = true
    @State private var allowFullAssignments: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("External AI") {
                    Toggle("Block External AI", isOn: $blockExternal)
                    if blockExternal && env.familyControls.applicationTokenCount == 0 && env.familyControls.webDomainTokenCount == 0 {
                        Text("Choose apps and websites first so blocking has effect.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Daily Limit") {
                    Stepper(value: $dailyLimit, in: 5...180, step: 5) {
                        Text("\(Int(dailyLimit)) minutes per day")
                    }
                }
                Section("Learning Behavior") {
                    Toggle("Encourage attempt before full answers", isOn: $requireAttempt)
                    Toggle("Allow full assignment generation", isOn: $allowFullAssignments)
                }
                Section {
                    Button("Reset Today's Usage") {
                        env.usageTracker.resetToday()
                    }
                    Button("Temporarily Allow External AI") {
                        blockExternal = false
                        save()
                    }
                }
            }
            .navigationTitle("Parent Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
            }
            .onAppear { loadFromPolicy() }
        }
    }

    private func loadFromPolicy() {
        let p = env.policyStore.policy
        blockExternal = p.blockExternalAI
        dailyLimit = Double(p.dailyLimitMinutes)
        requireAttempt = p.requireAttemptFirst
        allowFullAssignments = p.allowFullAssignmentGeneration
    }

    private func save() {
        env.updatePolicy {
            $0.blockExternalAI = blockExternal
            $0.dailyLimitMinutes = Int(dailyLimit)
            $0.requireAttemptFirst = requireAttempt
            $0.allowFullAssignmentGeneration = allowFullAssignments
        }
    }
}
