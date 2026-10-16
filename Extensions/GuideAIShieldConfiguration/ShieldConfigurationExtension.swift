import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Copy {
        static let title = "Learning-First Protection"
        static let subtitle = "This tool is restricted by your parent.\nOpen Guidance for hints, explanations, and guided help."
        static let primary = "Get Guided Help"
        static let secondary = "Not Now"
    }

    private func brandedConfiguration() -> ShieldConfiguration {
        let title = ShieldConfiguration.Label(text: Copy.title, color: .label)
        let subtitle = ShieldConfiguration.Label(text: Copy.subtitle, color: .secondaryLabel)
        let primary = ShieldConfiguration.Label(text: Copy.primary, color: .white)
        let secondary = ShieldConfiguration.Label(text: Copy.secondary, color: .label)
        let icon = UIImage(systemName: "shield.lefthalf.filled")
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor.systemBackground.withAlphaComponent(0.9),
            icon: icon,
            title: title,
            subtitle: subtitle,
            primaryButtonLabel: primary,
            primaryButtonBackgroundColor: UIColor(red: 0.96, green: 0.14, blue: 0.16, alpha: 1),
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
