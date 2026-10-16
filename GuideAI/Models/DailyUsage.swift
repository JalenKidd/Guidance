import Foundation

struct DailyUsage: Codable, Equatable {
    var calendarDay: String
    var secondsUsed: Int
    var requestCount: Int

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    static func fresh(for date: Date, calendar: Calendar = .current) -> DailyUsage {
        DailyUsage(calendarDay: dayKey(for: date, calendar: calendar), secondsUsed: 0, requestCount: 0)
    }

    func isSameDay(as date: Date, calendar: Calendar = .current) -> Bool {
        calendarDay == Self.dayKey(for: date, calendar: calendar)
    }

    func isLimitReached(limitSeconds: Int) -> Bool {
        secondsUsed >= limitSeconds
    }

    var minutesUsed: Int { secondsUsed / 60 }
}
