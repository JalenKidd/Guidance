import SwiftUI

/// One AI app: who it's for, what to know, its own rule, and instructions just for it.
struct AppDetailView: View {
    @EnvironmentObject private var store: FamilyStore
    let appID: String
    @State private var newInstruction = ""

    private static let instructionLimit = 5

    var body: some View {
        Group {
            if let found = store.catalog?.app(id: appID) {
                form(found.app, category: found.category)
                    .navigationTitle(found.app.name)
            } else {
                ContentUnavailableView("App not found", systemImage: "questionmark.app")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func form(_ app: AIApp, category: AICategory) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppIconView(app: app, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title2.weight(.bold))
                        Text(category.name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !app.audience.isEmpty {
                Section("Who it's for") {
                    Text(app.audience)
                }
            }

            if !app.quirks.isEmpty {
                Section("Good to know") {
                    ForEach(app.quirks, id: \.self) { quirk in
                        Label(quirk, systemImage: "info.circle")
                    }
                }
            }

            ruleSection(app, category: category)

            if category.supportsGuided {
                instructionsSection(app)
            }
        }
    }

    // MARK: - Rule

    private func ruleSection(_ app: AIApp, category: AICategory) -> some View {
        // Outer nil: kids differ. Inner nil: follows the category.
        let shared = store.shared { policy in app.domains.lazy.compactMap { policy.siteOverrides[$0] }.first }
        let override = shared ?? nil
        let categoryState = store.shared { $0.categories[category.id] ?? category.defaultState }

        return Section {
            Button {
                setRule(nil, for: app)
            } label: {
                ruleRow(
                    "Same as category" + (categoryState.map { " · \($0.label)" } ?? ""),
                    checked: shared != nil && override == nil
                )
            }
            ForEach(SiteOverride.options(supportsGuided: category.supportsGuided)) { option in
                Button {
                    setRule(option, for: app)
                } label: {
                    ruleRow(option.categoryState.label, checked: shared != nil && override == option)
                }
            }
        } header: {
            Text(store.isAllKids ? "Rule for all kids" : "Rule")
        } footer: {
            if shared == nil {
                Text("Kids have different rules for \(app.name). Choosing one sets it for all.")
            } else {
                Text("\"Turn off all AI\" still blocks \(app.name).")
            }
        }
        .tint(.primary)
    }

    private func ruleRow(_ title: String, checked: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if checked {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GuideTheme.brand)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func setRule(_ rule: SiteOverride?, for app: AIApp) {
        store.updatePolicies { policy in
            for domain in app.domains { policy.siteOverrides[domain] = rule }
        }
    }

    // MARK: - Instructions

    /// Every instruction any target kid has for this app, in first-seen order.
    private func instructions(_ app: AIApp) -> [String] {
        var seen: [String] = []
        for kid in store.targetKids {
            for i in kid.policy.appInstructions[app.id] ?? [] where !seen.contains(i) { seen.append(i) }
        }
        return seen
    }

    private func instructionsSection(_ app: AIApp) -> some View {
        let list = instructions(app)
        let full = store.targetKids.contains { ($0.policy.appInstructions[app.id] ?? []).count >= Self.instructionLimit }

        return Section {
            ForEach(list, id: \.self) { instruction in
                VStack(alignment: .leading, spacing: 2) {
                    Text(instruction)
                    let missing = store.targetKids.filter { !($0.policy.appInstructions[app.id] ?? []).contains(instruction) }
                    if !missing.isEmpty {
                        Text("Not for \(missing.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { list[$0] }
                store.updatePolicies { policy in
                    let kept = (policy.appInstructions[app.id] ?? []).filter { !removed.contains($0) }
                    policy.appInstructions[app.id] = kept.isEmpty ? nil : kept
                }
            }

            HStack {
                TextField("e.g. Only help with coding", text: $newInstruction, axis: .vertical)
                    .onSubmit { add(newInstruction, to: app) }
                Button {
                    add(newInstruction, to: app)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || full)
            }
        } header: {
            Text("Custom instructions")
        } footer: {
            Text("Used only while \(app.name) is Guided, on top of your rules for every chatbot. Up to \(Self.instructionLimit).")
        }
    }

    private func add(_ text: String, to app: AIApp) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty else { return }
        store.updatePolicies { policy in
            var list = policy.appInstructions[app.id] ?? []
            guard list.count < Self.instructionLimit, !list.contains(trimmed) else { return }
            list.append(trimmed)
            policy.appInstructions[app.id] = list
        }
        newInstruction = ""
    }
}
