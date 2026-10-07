import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    private func handlePrimary(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if #available(iOS 26.5, *) {
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
