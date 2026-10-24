import SwiftUI

/// Overlay on Home until at least one kid's phone is paired. Rules do nothing
/// until the Guidance extension on a kid's phone is connected.
struct PairKidView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var selectedKidID: String?
    @State private var newKidName = ""
    @State private var confirmingSignOut = false

    private var kid: Kid? {
        store.kids.first { $0.id == selectedKidID } ?? store.kids.first
    }

    var body: some View {
        ZStack {
            // Dark layer over Home that also blocks taps on it.
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            GeometryReader { proxy in
                ScrollView {
                    card
                        .frame(maxWidth: 380)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        // Check for the pairing every few seconds; Home opens as soon as it lands.
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .confirmationDialog("Sign out of this family?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { store.signOut() }
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pair your child's phone")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if store.kids.count > 1 { kidPicker }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .guideCard()

            if let kid {
                codeBlock(kid)
                VStack(alignment: .leading, spacing: 8) {
                    PhoneSetupSteps(kidName: kid.name, includesScreenTime: false)
                }
                .guideCard()
            } else {
                addKidField
            }

            if let error = store.errorMessage {
                ErrorBanner(message: error)
            }

            Button {
                confirmingSignOut = true
            } label: {
                Text("Sign out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .guideCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var kidPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.kids) { option in
                    let selected = option.id == kid?.id
                    Button(option.name) { selectedKidID = option.id }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? .white : .primary)
                        .background(selected ? GuideTheme.brand : GuideTheme.tertiaryFill, in: Capsule())
                }
            }
        }
    }

    private func codeBlock(_ kid: Kid) -> some View {
        VStack(spacing: 10) {
            Text("\(kid.name.uppercased())'S PAIRING CODE")
                .font(.caption2.weight(.heavy))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(kid.pairingCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .kerning(6)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for \(kid.name)'s phone…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .guideCard()
    }

    private var addKidField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who are you setting this up for?")
                .font(.headline)
            HStack {
                TextField("Kid's first name", text: $newKidName)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit(addKid)
                Button("Add", action: addKid)
                    .fontWeight(.semibold)
                    .disabled(newKidName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .guideCard()
    }

    private func addKid() {
        let name = newKidName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newKidName = ""
        Task { await store.addKid(named: name) }
    }
}
