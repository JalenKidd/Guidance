import DeviceActivity
import Foundation

/// Scaffold for future AI-free schedules (e.g. 10 PM – 7 AM).
/// MVP daily limits are enforced in-app; interval hooks can apply extra shields later.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
