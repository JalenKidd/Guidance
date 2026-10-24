import SwiftUI

struct SafetyAlertsView: View {
    @EnvironmentObject private var store: FamilyStore

    var body: some View {
        let name = store.selectedKid?.name ?? "your kid"

        Form {
            Section {
                ForEach(SafetyTopic.all) { topic in
                    HStack {
                        Label(topic.name, systemImage: topic.symbol)
                        Spacer()
                        if topic.urgent {
                            Text("URGENT")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
            } header: {
                Text("Always on")
            } footer: {
                Text("When \(name) asks an AI about one of these, you get an alert in Activity with their message. Guidance never blocks these questions, and \(name) won't see anything different.")
            }

            Section {
                Text("Alerts work on every AI site \(name) can use in Safari, whether it's Guided, Allowed or approved for a while. They're based on the words used, so they can miss things or flag harmless questions. Treat an alert as a reason to talk, not proof.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Safety alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
