import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var store: FamilyStore
    let categoryID: String
    @State private var showingReport = false

    var body: some View {
        Group {
            if let kid = store.selectedKid, let category = store.catalog?.category(id: categoryID) {
                content(kid: kid, category: category)
                    .navigationTitle(category.name)
            } else {
                ContentUnavailableView("Category not found", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReport) {
            ReportSiteSheet(categoryID: categoryID)
        }
    }

    private func content(kid: Kid, category: AICategory) -> some View {
        let state = store.shared { $0.categories[category.id] ?? category.defaultState }

        return Form {
            Section {
                Text(category.description)
                    .foregroundStyle(.secondary)
                CategoryStatePicker(
                    supportsGuided: category.supportsGuided,
                    state: Binding(
                        get: { state },
                        set: { value in
                            guard let value else { return }
                            store.updatePolicies { $0.categories[category.id] = value }
                        }
                    )
                )
                .listRowSeparator(.hidden)
                if state == nil { MixedCaption() }
            } header: {
                if store.isAllKids { Text("All kids") }
            } footer: {
                if let state { Text(explanation(for: state)) }
            }

            Section {
                ForEach(category.domains, id: \.self) { domain in
                    SiteRow(domain: domain, categoryState: state)
                }
            } header: {
                Text("Sites in this category")
            } footer: {
                Text("Guidance keeps this list up to date. Tap a site to give it its own rule.")
            }

            Section {
                Button {
                    showingReport = true
                } label: {
                    Label("Report a missing AI site", systemImage: "plus.bubble")
                }
            }
        }
    }

    private func explanation(for state: CategoryState) -> String {
        switch state {
        case .allow:
            return "These sites work normally."
        case .guided:
            return "These sites work, but each prompt is checked against your homework rules first. Prompts that try to get the AI to do schoolwork are stopped and turned into a learning prompt."
        case .block:
            return "These sites show a simple \"blocked by your family's AI rules\" page in Safari, with a way to ask for permission."
        }
    }
}

private struct SiteRow: View {
    @EnvironmentObject private var store: FamilyStore
    let domain: String
    /// nil when kids have different category settings.
    let categoryState: CategoryState?

    var body: some View {
        // Outer nil: kids differ. Inner nil: no exception, the site follows its category.
        let shared = store.shared { $0.siteOverrides[domain] }
        let override = shared ?? nil

        Menu {
            Button {
                set(nil)
            } label: {
                CheckedLabel(title: "Follow category" + (categoryState.map { " (\($0.label))" } ?? ""), checked: shared != nil && override == nil)
            }
            ForEach(SiteOverride.allCases) { option in
                Button {
                    set(option)
                } label: {
                    CheckedLabel(title: option.label, checked: shared != nil && override == option)
                }
            }
        } label: {
            HStack {
                Text(domain)
                    .foregroundStyle(.primary)
                Spacer()
                if shared == nil {
                    Text("Mixed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let override {
                    StateBadge(state: override == .allow ? .allow : .block)
                    Text("exception")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let categoryState {
                    StateBadge(state: categoryState)
                }
            }
        }
    }

    private func set(_ value: SiteOverride?) {
        store.updatePolicies { $0.siteOverrides[domain] = value }
    }
}

private struct CheckedLabel: View {
    let title: String
    let checked: Bool

    var body: some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

struct ReportSiteSheet: View {
    @EnvironmentObject private var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    var categoryID: String?
    @State private var site = ""
    @State private var note = ""
    @State private var alsoBlock = true
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. newessaybot.com", text: $site)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("What does it do? (optional)", text: $note, axis: .vertical)
                } footer: {
                    Text("Reports help Guidance add new AI sites to the shared catalog for every family.")
                }
                Section {
                    Toggle("Block it for \(store.targetName) now", isOn: $alsoBlock)
                }
                if sent {
                    Label("Thanks, we got it.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(GuideTheme.success)
                }
            }
            .navigationTitle("Report a site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(DomainInput.normalize(site) == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        guard let domain = DomainInput.normalize(site) else { return }
        if alsoBlock {
            store.updatePolicies { $0.siteOverrides[domain] = .block }
        }
        Task {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.suggestSite(domain: domain, categoryID: categoryID, note: trimmedNote.isEmpty ? nil : trimmedNote) {
                sent = true
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
