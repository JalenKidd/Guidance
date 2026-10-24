import Foundation

/// Swift mirror of `Extensions/GuidanceSafari/Resources/shared/resolver.js`, used to
/// show parents what's in effect right now. The extension's copy is what enforces
/// the rules; keep the two in step (precedence: AI off → site override → schedule → category).
struct EffectiveRules: Equatable {
    var masterOff: Bool
    /// Name of the schedule that turned AI off, when it wasn't the master switch.
    var masterOffSchedule: String?
    var states: [String: CategoryState]
    /// Category id → schedule name, for categories a schedule is changing right now.
    var scheduledBy: [String: String]
    var activeScheduleNames: [String]
}

enum PolicyResolver {
    static func minutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// JavaScript-style weekday: 0 = Sunday.
    static func jsWeekday(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func isActive(_ schedule: AISchedule, at date: Date, calendar: Calendar = .current) -> Bool {
        guard schedule.enabled else { return false }
        let day = jsWeekday(date, calendar: calendar)
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = minutes(schedule.start)
        let end = minutes(schedule.end)

        if start == end { return schedule.days.contains(day) }
        if start < end { return schedule.days.contains(day) && minute >= start && minute < end }
        let yesterday = (day + 6) % 7
        return (schedule.days.contains(day) && minute >= start) || (schedule.days.contains(yesterday) && minute < end)
    }

    static func effective(_ policy: KidPolicy, catalog: AICatalog, at date: Date = Date(), calendar: Calendar = .current) -> EffectiveRules {
        var states: [String: CategoryState] = [:]
        for category in catalog.categories {
            states[category.id] = policy.categories[category.id] ?? category.defaultState
        }

        var masterOff = policy.masterAIOff
        var masterOffSchedule: String?
        var scheduled: [String: (CategoryState, String)] = [:]
        let active = policy.schedules.filter { isActive($0, at: date, calendar: calendar) }

        for schedule in active {
            if schedule.masterAIOff && !masterOff {
                masterOff = true
                masterOffSchedule = schedule.name
            }
            for (id, value) in schedule.categories {
                if let current = scheduled[id], current.0.strictness >= value.strictness { continue }
                scheduled[id] = (value, schedule.name)
            }
        }

        var scheduledBy: [String: String] = [:]
        for (id, entry) in scheduled {
            states[id] = entry.0
            scheduledBy[id] = entry.1
        }

        return EffectiveRules(
            masterOff: masterOff,
            masterOffSchedule: masterOffSchedule,
            states: states,
            scheduledBy: scheduledBy,
            activeScheduleNames: active.map(\.name)
        )
    }
}
