import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var editing: AISchedule?

    var body: some View {
        NavigationStack {
            Group {
                if let kid = store.selectedKid {
                    list(kid)
                } else {
                    ContentUnavailableView("No kid selected", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(item: $editing) { schedule in
                ScheduleEditorView(schedule: schedule)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("School nights (stricter homework hours)") { editing = .schoolNightsPreset.withFreshID() }
            Button("Bedtime (all AI off)") { editing = .bedtimePreset.withFreshID() }
            Button("Custom schedule") { editing = .new(name: "New schedule") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add schedule")
    }

    /// Schedules of the target kids, once each (matched by id), with the kids that have them.
    private var entries: [(schedule: AISchedule, owners: [Kid])] {
        var result: [(schedule: AISchedule, owners: [Kid])] = []
        for kid in store.targetKids {
            for schedule in kid.policy.schedules {
                if let i = result.firstIndex(where: { $0.schedule.id == schedule.id }) {
                    result[i].owners.append(kid)
                } else {
                    result.append((schedule, [kid]))
                }
            }
        }
        return result
    }

    private func list(_ kid: Kid) -> some View {
        let entries = entries

        return List {
            Section {
                KidSelectorBar()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No schedules yet")
                            .font(.headline)
                        Text("Schedules change AI rules at set times, like stricter homework hours on school nights or no AI at bedtime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Add School nights") { editing = .schoolNightsPreset.withFreshID() }
                            Button("Add Bedtime") { editing = .bedtimePreset.withFreshID() }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    ForEach(entries, id: \.schedule.id) { entry in
                        ScheduleRow(
                            schedule: entry.schedule,
                            onlyFor: entry.owners.count < store.targetKids.count ? entry.owners.map(\.name) : nil
                        ) { editing = entry.schedule }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { entries[$0].schedule.id }
                        store.updatePolicies { $0.schedules.removeAll { removed.contains($0.id) } }
                    }
                } header: {
                    if store.isAllKids { Text("All kids") }
                } footer: {
                    Text("Times use this phone's clock. When schedules overlap, the stricter setting wins.")
                }
            }
        }
        .refreshable { await store.refresh() }
    }
}

private struct ScheduleRow: View {
    @EnvironmentObject private var store: FamilyStore
    let schedule: AISchedule
    /// Names of the kids who have this schedule, when it isn't every selected kid.
    let onlyFor: [String]?
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(schedule.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if PolicyResolver.isActive(schedule, at: Date()) {
                            Text("ON NOW")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GuideTheme.brand, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text("\(DayText.summary(schedule.days)) · \(TimeText.display(schedule.start))–\(TimeText.display(schedule.end))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(effectSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let onlyFor {
                        Text("Only \(onlyFor.joined(separator: ", "))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GuideTheme.brand)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: Binding(
                get: { schedule.enabled },
                set: { value in
                    store.updatePolicies { policy in
                        if let i = policy.schedules.firstIndex(where: { $0.id == schedule.id }) {
                            policy.schedules[i].enabled = value
                        }
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var effectSummary: String {
        if schedule.masterAIOff { return "Turns off all AI" }
        guard let catalog = store.catalog, !schedule.categories.isEmpty else { return "No changes yet" }
        return schedule.categories
            .sorted { $0.key < $1.key }
            .map { "\(catalog.category(id: $0.key)?.name ?? $0.key): \($0.value.label)" }
            .joined(separator: ", ")
    }
}

enum DayText {
    static let short = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func summary(_ days: [Int]) -> String {
        let set = Set(days)
        if set.count == 7 { return "Every day" }
        if set == [0, 1, 2, 3, 4] { return "School nights (Sun–Thu)" }
        if set == [1, 2, 3, 4, 5] { return "Weekdays" }
        if set == [0, 6] { return "Weekends" }
        return days.sorted().map { short[$0] }.joined(separator: ", ")
    }
}

extension AISchedule {
    func withFreshID() -> AISchedule {
        var copy = self
        copy.id = UUID().uuidString
        return copy
    }
}
