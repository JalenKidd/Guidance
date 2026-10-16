import FamilyControls
import SwiftUI

struct AISelectionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FamilyActivitySelection
    @State private var demoSelectedToolIDs: Set<String> = []

    init() {
        _selection = State(initialValue: FamilyActivitySelection())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideTheme.pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(GuideTheme.brand.opacity(0.12))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "lock.shield.fill")
                                    .font(.headline)
                                    .foregroundStyle(GuideTheme.brand)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("You decide what is restricted")
                                    .font(.headline)
                                Text("Select answer-generating tools and leave approved learning tools unselected.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Label(selectionPrivacyMessage, systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .guideCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                    #if GUIDEAI_DEMO
                    demoSelectionList
                    #else
                    FamilyActivityPicker(selection: $selection)
                    #endif
                }
            }
            .navigationTitle("Restricted AI Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        #if GUIDEAI_DEMO
                        env.familyControls.updateDemoSelection(demoSelectedToolIDs)
                        #else
                        env.familyControls.activitySelection = selection
                        env.familyControls.saveSelection()
                        #endif
                        env.syncShieldsFromPolicy()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 7) {
                    HStack {
                        Label(selectionSummary, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectionCount == 0 ? Color.secondary : GuideTheme.success)
                        Spacer()
                    }

                    if !selection.categoryTokens.isEmpty {
                        Label(
                            "Categories are broad and may include non-AI apps. Specific apps and sites give you the most precise control.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .onAppear {
                selection = env.familyControls.activitySelection
                #if GUIDEAI_DEMO
                demoSelectedToolIDs = env.familyControls.demoSelectedToolIDs
                #endif
            }
        }
    }

    private var selectionCount: Int {
        #if GUIDEAI_DEMO
        return demoSelectedToolIDs.count
        #else
        selection.applicationTokens.count + selection.webDomainTokens.count + selection.categoryTokens.count
        #endif
    }

    private var selectionSummary: String {
        selectionCount == 0
            ? "No restricted tools selected"
            : "\(selectionCount) restricted selection\(selectionCount == 1 ? "" : "s")"
    }

    private var selectionPrivacyMessage: String {
        if AppConfig.isVideoDemo {
            return "Only the tools you select are included in this family policy. Tap a row to change it."
        }
        return "\(AppConfig.productDisplayName) uses Apple's private picker. It never reads a list of your installed apps."
    }

    #if GUIDEAI_DEMO
    private var demoSelectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI APPS & WEBSITES")
                    .font(.caption2.weight(.heavy))
                    .kerning(0.9)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    demoToolRow("ChatGPT", id: "chatgpt", subtitle: "Answer-generating AI app", symbol: "bubble.left.and.bubble.right.fill")
                    Divider().padding(.leading, 58)
                    demoToolRow("Gemini", id: "gemini", subtitle: "Answer-generating AI app", symbol: "sparkles")
                    Divider().padding(.leading, 58)
                    demoToolRow("claude.ai", id: "claude", subtitle: "AI website", symbol: "globe")
                }
                .guideCard(padding: 0)

                Label(
                    "Choose answer-generating tools to restrict while leaving approved learning tools available.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func demoToolRow(_ title: String, id: String, subtitle: String, symbol: String) -> some View {
        let isSelected = demoSelectedToolIDs.contains(id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isSelected {
                    demoSelectedToolIDs.remove(id)
                } else {
                    demoSelectedToolIDs.insert(id)
                }
            }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(GuideTheme.brand.opacity(0.11))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .foregroundStyle(GuideTheme.brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? GuideTheme.success : Color.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif
}
