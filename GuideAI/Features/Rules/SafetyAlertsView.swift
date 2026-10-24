import SwiftUI

struct SafetyAlertsView: View {
    var body: some View {
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
                Text("You get an alert in Activity. Nothing is blocked.")
            }
        }
        .navigationTitle("Safety alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
