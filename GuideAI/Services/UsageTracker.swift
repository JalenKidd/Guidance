import Combine
import Foundation

protocol DateProviding {
    func now() -> Date
}

struct SystemDateProvider: DateProviding {
    func now() -> Date { Date() }
}

@MainActor
final class UsageTracker: ObservableObject {
    @Published private(set) var dailyUsage: DailyUsage

    private let defaults: UserDefaults
    private let dateProvider: DateProviding
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var tickTask: Task<Void, Never>?
    private var isTracking = false

    init(defaults: UserDefaults = AppGroupStore.sharedDefaults, dateProvider: DateProviding = SystemDateProvider()) {
        self.defaults = defaults
        self.dateProvider = dateProvider
        self.dailyUsage = .fresh(for: dateProvider.now())
        load()
        rolloverIfNeeded()
        #if GUIDEAI_DEMO
        loadVideoDemoUsage()
        #endif
    }

    func load() {
        guard let data = defaults.data(forKey: AppGroupStore.Key.dailyUsage),
              let usage = try? decoder.decode(DailyUsage.self, from: data) else {
            dailyUsage = .fresh(for: dateProvider.now())
            persist()
            return
        }
        dailyUsage = usage
        rolloverIfNeeded()
    }

    func rolloverIfNeeded() {
        let now = dateProvider.now()
        if !dailyUsage.isSameDay(as: now) {
            dailyUsage = .fresh(for: now)
            persist()
        }
    }

    func startTracking(limitSeconds: Int) {
        guard !dailyUsage.isLimitReached(limitSeconds: limitSeconds) else { return }
        isTracking = true
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick(limitSeconds: limitSeconds)
            }
        }
    }

    func pauseTracking() {
        isTracking = false
        tickTask?.cancel()
        tickTask = nil
    }

    func recordRequest(limitSeconds: Int) {
        rolloverIfNeeded()
        guard !dailyUsage.isLimitReached(limitSeconds: limitSeconds) else { return }
        dailyUsage.requestCount += 1
        persist()
    }

    func resetToday() {
        dailyUsage = .fresh(for: dateProvider.now())
        persist()
    }

    func isLimitReached(limitSeconds: Int) -> Bool {
        rolloverIfNeeded()
        return dailyUsage.isLimitReached(limitSeconds: limitSeconds)
    }

    func remainingSeconds(limitSeconds: Int) -> Int {
        max(0, limitSeconds - dailyUsage.secondsUsed)
    }

    private func tick(limitSeconds: Int) {
        guard isTracking else { return }
        rolloverIfNeeded()
        guard !dailyUsage.isLimitReached(limitSeconds: limitSeconds) else {
            pauseTracking()
            return
        }
        dailyUsage.secondsUsed += 1
        persist()
    }

    private func persist() {
        if let data = try? encoder.encode(dailyUsage) {
            defaults.set(data, forKey: AppGroupStore.Key.dailyUsage)
        }
    }

    #if GUIDEAI_DEMO
    private func loadVideoDemoUsage() {
        dailyUsage = DailyUsage(
            calendarDay: DailyUsage.dayKey(for: dateProvider.now()),
            secondsUsed: 18 * 60,
            requestCount: 7
        )
        persist()
    }
    #endif
}
