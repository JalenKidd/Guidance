import SwiftUI

enum GuideTheme {
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 16

    /// A deeper rose in Light Mode and a brighter coral-red in Dark Mode.
    /// Large surfaces use the softer adaptive colors below so the interface
    /// stays airy instead of feeling permanently dark.
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.30, blue: 0.35, alpha: 1)
            : UIColor(red: 0.82, green: 0.10, blue: 0.18, alpha: 1)
    })
    static let brandDeep = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.78, green: 0.12, blue: 0.20, alpha: 1)
            : UIColor(red: 0.66, green: 0.04, blue: 0.12, alpha: 1)
    })
    static let brandSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.055, blue: 0.085, alpha: 1)
            : UIColor(red: 1.00, green: 0.88, blue: 0.90, alpha: 1)
    })
    static let brandSoftDeep = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.34, green: 0.07, blue: 0.11, alpha: 1)
            : UIColor(red: 0.98, green: 0.76, blue: 0.80, alpha: 1)
    })
    static let heroText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.25, green: 0.03, blue: 0.07, alpha: 1)
    })
    static let heroSecondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.76)
            : UIColor(red: 0.38, green: 0.12, blue: 0.16, alpha: 0.82)
    })
    static let warmAccent = Color(red: 1.00, green: 0.40, blue: 0.20)
    static let success = Color(red: 0.16, green: 0.73, blue: 0.39)

    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let tertiaryFill = Color(uiColor: .tertiarySystemFill)

    static let heroGradient = LinearGradient(
        colors: [brandSoft, brandSoftDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
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
