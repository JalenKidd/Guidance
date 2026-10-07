import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role != .user { Spacer(minLength: 40) }
        }
        .accessibilityLabel(message.role == .user ? "You said" : "Assistant said")
    }

    private var bubbleColor: Color {
        message.role == .user ? .accentColor : Color(.secondarySystemBackground)
    }
}
