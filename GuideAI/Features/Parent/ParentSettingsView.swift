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
                Section("Learning-First Protection") {
                    Toggle("Restrict selected AI tools", isOn: $blockExternal)
                    Text("Only the apps, websites, and categories selected by the parent are restricted. \(AppConfig.productDisplayName) remains available for guided help.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if blockExternal && !env.familyControls.hasSelection {
                        Text("Choose at least one AI tool from the Parent Dashboard so protection has an effect.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Daily Limit") {
                    Stepper(value: $dailyLimit, in: 5...180, step: 5) {
                        Text("\(Int(dailyLimit)) minutes per day")
                    }
                }
                Section("Learning Rules") {
                    Toggle("Ask for the student's attempt first", isOn: $requireAttempt)
                    Toggle("Allow complete assignment drafts", isOn: $allowFullAssignments)
                    if !allowFullAssignments {
                        Label("Recommended: \(AppConfig.productDisplayName) provides outlines, hints, explanations, and feedback—not ready-to-submit work.", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(GuideTheme.success)
                    }
                }
                Section {
                    Button("Reset Today's Usage") {
                        env.usageTracker.resetToday()
                    }
                    Button("Pause Learning-First Protection") {
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
