import SwiftUI

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.heavy))
            .kerning(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .guideCard(padding: 14)
    }
}

/// Row of chips for choosing whose rules you're editing: All kids, or one kid.
/// "All kids" only appears with two or more kids. The + chip adds a kid profile.
struct KidSelectorBar: View {
    @EnvironmentObject private var store: FamilyStore
    var showsAll = true
    @State private var addingKid = false
    @State private var newName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsAll && store.kids.count > 1 {
                    chip("All kids", systemImage: "person.3.fill", selected: store.isAllKids) {
                        store.select(FamilyStore.allKidsID)
                    }
                }
                ForEach(store.kids) { kid in
                    chip(kid.name, systemImage: nil, selected: !store.isAllKids && store.selectedKid?.id == kid.id) {
                        store.select(kid.id)
                    }
                }
                Button {
                    newName = ""
                    addingKid = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 36, height: 36)
                        .background(GuideTheme.tertiaryFill, in: Circle())
                }
                .accessibilityLabel("Add a kid")
            }
            .padding(.horizontal, 2)
        }
        .alert("Add a kid", isPresented: $addingKid) {
            TextField("First name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { Task { await store.addKid(named: name) } }
            }
        } message: {
            Text("They'll get their own rules and a pairing code for their phone.")
        }
    }

    private func chip(_ title: String, systemImage: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? GuideTheme.brand : GuideTheme.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small "Mixed" caption for settings that differ between kids when editing All kids.
struct MixedCaption: View {
    var body: some View {
        Text("Mixed: kids have different settings. Choosing one sets it for all.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Allow / Guided / Block control. Guided is only offered where the extension can check prompts.
/// A nil state (kids differ) shows no segment selected.
struct CategoryStatePicker: View {
    let supportsGuided: Bool
    @Binding var state: CategoryState?

    var body: some View {
        Picker("Setting", selection: $state) {
            ForEach(options) { option in
                Text(option.label).tag(CategoryState?.some(option))
            }
        }
        .pickerStyle(.segmented)
    }

    private var options: [CategoryState] {
        supportsGuided ? CategoryState.allCases : [.allow, .block]
    }
}

struct StateBadge: View {
    let state: CategoryState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .allow: return GuideTheme.success
        case .guided: return GuideTheme.warmAccent
        case .block: return GuideTheme.brand
        }
    }
}

/// Text field + Save for the name kids see as "Guardian: <name>" in the extension.
struct GuardianNameField: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var name = ""
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        HStack(spacing: 10) {
            TextField("Your name, e.g. Maria or Mom", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .onSubmit(save)
            if saved && !changed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GuideTheme.success)
                    .accessibilityLabel("Saved")
            } else {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!changed || saving)
            }
        }
        .onAppear { name = store.parentName ?? "" }
        .onChange(of: store.parentName) { _, value in name = value ?? "" }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { !trimmed.isEmpty && trimmed != (store.parentName ?? "") }

    private func save() {
        guard changed else { return }
        saving = true
        Task {
            saved = await store.setParentName(trimmed)
            saving = false
        }
    }
}

enum TimeText {
    /// "21:00" → "9:00 PM" in the user's locale.
    static func display(_ hhmm: String) -> String {
        let minutes = PolicyResolver.minutes(hhmm)
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        guard let date = Calendar.current.date(from: comps) else { return hhmm }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.formatted(.relative(presentation: .named))
    }
}
