import os
import SafariServices

/// Required entry point for the Safari Web Extension. All Guidance logic lives in
/// the JavaScript under Resources/; this only answers native messages so Safari
/// can confirm the extension is installed.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "com.cac.guideai", category: "SafariExtension")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey]
        logger.debug("Received native message: \(String(describing: message), privacy: .public)")

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
