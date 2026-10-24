import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var mode: Mode

    init(startsWithNewFamily: Bool = false) {
        _mode = State(initialValue: startsWithNewFamily ? .newFamily : .signIn)
    }
    @State private var email = ""
    @State private var password = ""
    @State private var parentName = ""
    @State private var kidName = ""
    @State private var serverAddress = UserDefaults.standard.string(forKey: AppConfig.serverURLKey) ?? ""
    @FocusState private var focused: Field?

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case newFamily = "New family"
        var id: String { rawValue }
    }

    private enum Field { case email, password, parent, kid }

    /// Made-up demo accounts (see UPDATE_README); they all use the demo password.
    private static let demoEmails = [
        "MarvesPaztanes@gmail.com",
        "JalenPaztanes@gmail.com",
        "MiguelPaztanes@gmail.com",
        "AlaniPaztanes@gmail.com",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: GuideTheme.sectionSpacing) {
                hero

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in store.errorMessage = nil }

                if mode == .signIn {
                    signInCard
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        point("square.grid.2x2.fill", "Control AI by category", "Block essay writers, math solvers and homework sites in one tap — new AI sites are added for you.")
                        point("graduationcap.fill", "Guide the big chatbots", "On ChatGPT, Claude and Gemini, prompts that try to offload homework are stopped and turned into learning.")
                        point("clock.fill", "Schedules and an off switch", "AI-free bedtime, stricter school nights, or turn all AI off right now.")
                    }
                    .guideCard()

                    newFamilyCard
                }

                DisclosureGroup("Server address") {
                    ServerAddressField(address: $serverAddress)
                        .padding(.top, 6)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                if let error = store.errorMessage {
                    ErrorBanner(message: error)
                }

                Button(action: mode == .signIn ? signIn : create) {
                    HStack {
                        if store.isLoading { ProgressView().tint(.white) }
                        Text(mode == .signIn ? "Sign in" : "Create family")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(GuideTheme.actionGradient, in: RoundedRectangle(cornerRadius: GuideTheme.compactCornerRadius, style: .continuous))
                }
                .disabled(!canSubmit || store.isLoading)
                .opacity(canSubmit ? 1 : 0.5)
            }
            .padding(16)
        }
        .background(GuideTheme.pageBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to your family")
                .font(.headline)
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .padding(12)
                .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(signIn)
                .padding(12)
                .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Menu {
                ForEach(Self.demoEmails, id: \.self) { demo in
                    Button(demo) { email = demo; focused = .password }
                }
            } label: {
                Label("Demo accounts", systemImage: "person.2.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .guideCard()
    }

    private var newFamilyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your name")
                .font(.headline)
            TextField("e.g. Maria or Mom", text: $parentName)
                .textContentType(.givenName)
                .focused($focused, equals: .parent)
                .submitLabel(.next)
                .onSubmit { focused = .kid }
                .padding(12)
                .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Your kid sees this as their guardian in Safari.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Who are you setting this up for?")
                .font(.headline)
                .padding(.top, 4)
            TextField("Kid's first name", text: $kidName)
                .textContentType(.givenName)
                .focused($focused, equals: .kid)
                .submitLabel(.go)
                .onSubmit(create)
                .padding(12)
                .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("You can add more kids later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .guideCard()
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn: return !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .newFamily: return canCreate
        }
    }

    private func signIn() {
        guard mode == .signIn, canSubmit else { return }
        focused = nil
        Task { _ = await store.signIn(email: email, password: password) }
    }

    private var trimmedName: String {
        kidName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedParentName: String {
        parentName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !trimmedParentName.isEmpty
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(GuideTheme.brand)
            Text(AppConfig.productDisplayName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(GuideTheme.heroText)
            Text("Not a ban. A better path. Set your family's rules for how AI helps your kid learn.")
                .font(.body)
                .foregroundStyle(GuideTheme.heroSecondaryText)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuideTheme.heroGradient, in: RoundedRectangle(cornerRadius: GuideTheme.cornerRadius, style: .continuous))
        .padding(.top, 8)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GuideTheme.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        focused = nil
        Task { _ = await store.createFamily(parentName: trimmedParentName, firstKidName: trimmedName) }
    }
}

/// Text field for the Guidance server address, shared by Welcome and Setup.
struct ServerAddressField: View {
    @Binding var address: String
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("http://192.168.1.10:8080", text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(GuideTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: address) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        UserDefaults.standard.removeObject(forKey: AppConfig.serverURLKey)
                    } else {
                        UserDefaults.standard.set(trimmed, forKey: AppConfig.serverURLKey)
                    }
                    status = nil
                }
            HStack {
                Button("Test connection") {
                    Task {
                        status = "Checking…"
                        status = await GuidanceAPI().health() ? "Connected" : "Not reachable"
                    }
                }
                .font(.subheadline.weight(.semibold))
                if let status {
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Leave empty to use this Mac in the Simulator. On an iPhone, use your Mac's address on Wi-Fi.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
