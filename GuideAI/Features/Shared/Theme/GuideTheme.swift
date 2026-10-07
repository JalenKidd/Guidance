import SwiftUI

enum GuideTheme {
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 16

    static let brand = Color(red: 0.96, green: 0.14, blue: 0.16)
    static let brandDeep = Color(red: 0.80, green: 0.06, blue: 0.12)
    static let warmAccent = Color(red: 1.00, green: 0.40, blue: 0.20)
    static let success = Color(red: 0.16, green: 0.73, blue: 0.39)

    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let tertiaryFill = Color(uiColor: .tertiarySystemFill)

    static let heroGradient = LinearGradient(
        colors: [brand, brandDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let titleFont = Font.title2.weight(.semibold)
    static let headlineFont = Font.headline
    static let metricFont = Font.system(.title2, design: .rounded).weight(.bold)

    struct Card: ViewModifier {
        let padding: CGFloat

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: GuideTheme.cornerRadius, style: .continuous)
                        .fill(GuideTheme.cardBackground)
                        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
                }
        }
    }
}

extension View {
    func guideCard(padding: CGFloat = GuideTheme.cardPadding) -> some View {
        modifier(GuideTheme.Card(padding: padding))
    }
}
