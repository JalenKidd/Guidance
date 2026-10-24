import SwiftUI

struct GuidedRulesView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var newInstruction = ""

    private let examples = [
        "Keep explanations at a middle school reading level.",
        "Always ask me a question back to check I understood.",
        "Don't write code for me; explain what each step should do.",
        "No graphic or violent content.",
    ]

    var body: some View {
        Group {
            if let kid = store.selectedKid {
                form(kid)
            }
        }
        .navigationTitle("Rules for LLMs (Chatbots)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Every instruction any target kid has, in first-seen order.
    private var instructions: [String] {
        var seen: [String] = []
        for kid in store.targetKids {
            for i in kid.policy.guidedRules.globalInstructions where !seen.contains(i) { seen.append(i) }
        }
        return seen
    }

    private func kidsMissing(_ instruction: String) -> [Kid] {
        store.targetKids.filter { !$0.policy.guidedRules.globalInstructions.contains(instruction) }
    }

    private func form(_ kid: Kid) -> some View {
        let instructions = instructions
        let full = store.targetKids.contains { $0.policy.guidedRules.globalInstructions.count >= 10 }

        return Form {
            Section {
                toggle("Stop homework offloading", \.blockHomeworkOffloading)
                toggle("Ask what they tried first", \.requireAttemptFirst)
                toggle("Hide finished answers", \.hideFinishedAnswers)
            } header: {
                if store.isAllKids { Text("All kids") }
            } footer: {
                Text("Applies on chatbots set to Guided (ChatGPT, Claude, Gemini and others). Prompts like \"write my essay\" or \"solve these for me\" are stopped, and your kid is offered a learning-style prompt instead. If an AI answers with a finished essay or worked-out homework anyway, the answer is blurred and replaced with hints.")
            }

            Section {
                ForEach(instructions, id: \.self) { instruction in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instruction)
                        let missing = kidsMissing(instruction)
                        if !missing.isEmpty {
                            Text("Not for \(missing.map(\.name).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { instructions[$0] }
                    store.updatePolicies { $0.guidedRules.globalInstructions.removeAll { removed.contains($0) } }
                }

                HStack {
                    TextField("Add an instruction", text: $newInstruction, axis: .vertical)
                        .onSubmit { add(newInstruction) }
                    Button {
                        add(newInstruction)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || full)
                }
            } header: {
                Text("Instructions for every chatbot")
            } footer: {
                Text("Added to every allowed prompt on Guided chatbots, so the AI follows your rules too.")
            }

            Section("Ideas") {
                ForEach(examples.filter { !kidsMissing($0).isEmpty }, id: \.self) { example in
                    Button {
                        add(example)
                    } label: {
                        Label(example, systemImage: "plus")
                            .foregroundStyle(.primary)
                    }
                    .disabled(full)
                }
            }
        }
    }

    @ViewBuilder
    private func toggle(_ title: String, _ keyPath: WritableKeyPath<GuidedRules, Bool>) -> some View {
        let value = store.shared { $0.guidedRules[keyPath: keyPath] }
        Toggle(isOn: Binding(
            get: { value ?? false },
            set: { newValue in store.updatePolicies { $0.guidedRules[keyPath: keyPath] = newValue } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if value == nil {
                    Text("Mixed: on for some kids")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func add(_ text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty else { return }
        store.updatePolicies { policy in
            guard policy.guidedRules.globalInstructions.count < 10,
                  !policy.guidedRules.globalInstructions.contains(trimmed) else { return }
            policy.guidedRules.globalInstructions.append(trimmed)
        }
        newInstruction = ""
    }
}
