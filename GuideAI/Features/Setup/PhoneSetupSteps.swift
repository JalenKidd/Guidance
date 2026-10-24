import SwiftUI

/// The numbered steps for setting up a kid's phone. `kidName` is nil on the Setup
/// screen, where the steps apply to every kid.
struct PhoneSetupSteps: View {
    var kidName: String?

    var body: some View {
        let phone = kidName.map { "\($0)'s phone" } ?? "your kid's phone"
        step(1, "Turn on the Guidance extension",
             "On \(phone): Settings → Apps → Safari → Extensions → Guidance. Turn it on and set All Websites to Allow.")
        step(2, "Pair it",
             "In Safari, tap the page menu (left of the address), choose Guidance, and enter " +
             (kidName == nil ? "the kid's pairing code (tap their name above to see it)." : "the code above."))
        step(3, "Close the gaps with Screen Time",
             "Settings → Screen Time: set a Screen Time passcode, add 1-minute App Limits for the ChatGPT, Gemini and Claude apps and any other browsers, and turn off deleting apps. That keeps AI in Safari, where Guidance applies your rules.")
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            Label("Open Settings", systemImage: "gear")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(GuideTheme.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
