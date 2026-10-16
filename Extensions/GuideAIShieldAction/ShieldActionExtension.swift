import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    private enum SharedStore {
        static let suiteName = "group.com.cac.guideai.shared"
        static let openAssistantKey = "guideai.openAssistantFromShield"
    }

    private func handlePrimary(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if #available(iOS 26.5, *) {
            UserDefaults(suiteName: SharedStore.suiteName)?
                .set(true, forKey: SharedStore.openAssistantKey)
            completionHandler(.openParentalControlsApp)
        } else {
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            handlePrimary(completionHandler: completionHandler)
        case .secondaryButtonPressed:
            completionHandler(.close)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            handlePrimary(completionHandler: completionHandler)
        case .secondaryButtonPressed:
            completionHandler(.close)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            handlePrimary(completionHandler: completionHandler)
        case .secondaryButtonPressed:
            completionHandler(.close)
        default:
            completionHandler(.close)
        }
    }
}
