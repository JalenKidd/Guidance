import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Copy {
        static let title = "External AI Restricted"
        static let subtitle = "This AI service is outside your approved settings.\nUse your approved AI assistant instead."
        static let primary = "Open GuideAI"
        static let secondary = "Close"
    }

    private func brandedConfiguration() -> ShieldConfiguration {
        let title = ShieldConfiguration.Label(text: Copy.title, color: .label)
        let subtitle = ShieldConfiguration.Label(text: Copy.subtitle, color: .secondaryLabel)
        let primary = ShieldConfiguration.Label(text: Copy.primary, color: .white)
        let secondary = ShieldConfiguration.Label(text: Copy.secondary, color: .label)
        let icon = UIImage(systemName: "hand.raised.fill")
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor.systemBackground.withAlphaComponent(0.9),
            icon: icon,
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: primary,
            primaryButtonBackgroundColor: UIColor.systemBlue,
            secondaryButtonLabel: secondary
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        brandedConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        brandedConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        brandedConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        brandedConfiguration()
    }
}
