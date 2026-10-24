import SwiftUI

struct SiteOverridesView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var newSite = ""
    @State private var newRule: SiteOverride = .block
    @State private var showingReport = false

    var body: some View {
        Group {
            if let kid = store.selectedKid {
                form(kid)
            }
        }
        .navigationTitle("Site exceptions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReport) { ReportSiteSheet() }
    }

    private func form(_ kid: Kid) -> some View {
        // Every site any target kid has an exception for.
        let domains = Set(store.targetKids.flatMap { $0.policy.siteOverrides.keys }).sorted()

        return Form {
            Section {
                TextField("Site, e.g. claude.ai", text: $newSite)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Rule", selection: $newRule) {
                    ForEach(SiteOverride.allCases) { Text($0.label).tag($0) }
                }
                Button(store.isAllKids ? "Add exception for all kids" : "Add exception") { add() }
                    .disabled(DomainInput.normalize(newSite) == nil)
            } footer: {
                Text("Exceptions beat category settings and schedules. \"Turn off all AI\" still blocks every AI site.")
            }

            if !domains.isEmpty {
                Section("Exceptions") {
                    ForEach(domains, id: \.self) { domain in
                        let rule = store.shared { $0.siteOverrides[domain] }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domain)
                                if let category = store.catalog?.category(forDomain: domain) {
                                    Text(category.name).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Not in the catalog").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let rule = rule ?? nil {
                                StateBadge(state: rule == .allow ? .allow : .block)
                            } else {
                                Text("Some kids").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { domains[$0] }
                        store.updatePolicies { policy in
                            for domain in removed { policy.siteOverrides[domain] = nil }
                        }
                    }
                }
            }

            Section {
                Button {
                    showingReport = true
                } label: {
                    Label("Report a new AI site to Guidance", systemImage: "plus.bubble")
                }
            }
        }
    }

    private func add() {
        guard let domain = DomainInput.normalize(newSite) else { return }
        let rule = newRule
        store.updatePolicies { $0.siteOverrides[domain] = rule }
        newSite = ""
    }
}
