import SwiftUI

struct ScheduleEditorView: View {
    @EnvironmentObject private var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AISchedule

    init(schedule: AISchedule) {
        _draft = State(initialValue: schedule)
    }

    private var isExisting: Bool {
        store.targetKids.contains { kid in kid.policy.schedules.contains { $0.id == draft.id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }

                Section("When") {
                    dayPicker
                    DatePicker("Starts", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                    if PolicyResolver.minutes(draft.end) < PolicyResolver.minutes(draft.start) {
                        Text("Ends the next morning.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Turn off all AI", isOn: $draft.masterAIOff)
                } footer: {
                    Text("Blocks every AI site in the catalog during this time, like the switch on the Rules tab.")
                }

                if !draft.masterAIOff, let catalog = store.catalog {
                    Section {
                        ForEach(catalog.categories) { category in
                            Picker(selection: categoryBinding(category.id)) {
                                Text("No change").tag(CategoryState?.none)
                                ForEach(category.supportsGuided ? CategoryState.allCases : [.allow, .block]) { state in
                                    Text(state.label).tag(CategoryState?.some(state))
                                }
                            } label: {
                                Label(category.name, systemImage: category.icon)
                            }
                        }
                    } header: {
                        Text("During this time")
                    } footer: {
                        Text("Categories set to \"No change\" keep their usual setting.")
                    }
                }

                if isExisting {
                    Section {
                        Button("Delete schedule", role: .destructive) {
                            store.updatePolicies { $0.schedules.removeAll { $0.id == draft.id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isExisting ? "Edit schedule" : "New schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.days.isEmpty)
                }
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let selected = draft.days.contains(day)
                Button {
                    if selected { draft.days.removeAll { $0 == day } } else { draft.days.append(day) }
                    draft.days.sort()
                } label: {
                    Text(String(DayText.short[day].prefix(1)))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selected ? GuideTheme.brand : GuideTheme.tertiaryFill, in: Circle())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DayText.short[day])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<AISchedule, String>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = PolicyResolver.minutes(draft[keyPath: keyPath])
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft[keyPath: keyPath] = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    private func categoryBinding(_ id: String) -> Binding<CategoryState?> {
        Binding(
            get: { draft.categories[id] },
            set: { draft.categories[id] = $0 }
        )
    }

    private func save() {
        var schedule = draft
        schedule.name = schedule.name.trimmingCharacters(in: .whitespaces)
        if schedule.masterAIOff { schedule.categories = [:] }
        // Editing changes the kids that already have this schedule; a new one goes to every selected kid.
        let existing = isExisting
        store.updatePolicies { policy in
            if let i = policy.schedules.firstIndex(where: { $0.id == schedule.id }) {
                policy.schedules[i] = schedule
            } else if !existing {
                policy.schedules.append(schedule)
            }
        }
        dismiss()
    }
}
