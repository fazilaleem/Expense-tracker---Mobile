import Foundation
import SwiftData

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }

    var shortLabel: String {
        switch self {
        case .daily: return "Day"
        case .weekly: return "Week"
        case .monthly: return "Month"
        case .yearly: return "Year"
        case .custom: return "Custom"
        }
    }

    var noun: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "this week"
        case .monthly: return "this month"
        case .yearly: return "this year"
        case .custom: return "in this period"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily, .custom: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }

    /// The period window containing `date`.
    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// Stable identifier for the window, used so each alert fires once per period.
    func key(for date: Date, calendar: Calendar = .current) -> String {
        let start = interval(containing: date, calendar: calendar).start
        return "\(rawValue)-\(Int(start.timeIntervalSince1970))"
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    /// nil = overall budget across all categories.
    var categoryRaw: String?
    var periodRaw: String = BudgetPeriod.monthly.rawValue
    var limit: Double = 0
    var currency: String = "USD"
    /// Fraction (0.5–0.95) at which the "almost used" alert fires.
    var warnAt: Double = 0.8
    var isEnabled: Bool = true
    var lastWarnedKey: String?
    var lastExceededKey: String?
    var createdAt: Date = Date()
    /// Only for `.custom` budgets: the date range they cover (inclusive).
    var customStart: Date?
    var customEnd: Date?

    init(category: ExpenseCategory?, period: BudgetPeriod, limit: Double, currency: String, warnAt: Double = 0.8) {
        self.id = UUID()
        self.categoryRaw = category?.rawValue
        self.periodRaw = period.rawValue
        self.limit = limit
        self.currency = currency
        self.warnAt = warnAt
        self.createdAt = .now
    }

    var category: ExpenseCategory? {
        get { categoryRaw.flatMap(ExpenseCategory.init(rawValue:)) }
        set { categoryRaw = newValue?.rawValue }
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    /// nil for the overall budget.
    var style: CategoryStyle? { categoryRaw.map(CategoryStyle.of) }
    var title: String { categoryRaw ?? "Overall" }
    var shortTitle: String { style?.shortName ?? "Overall" }
    var symbol: String { style?.symbol ?? "chart.pie.fill" }

    /// The budget window containing `date` (custom budgets have one fixed window).
    func interval(at date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        if period == .custom, let s = customStart, let e = customEnd {
            let start = calendar.startOfDay(for: min(s, e))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(s, e)))!
            return DateInterval(start: start, end: end)
        }
        return period.interval(containing: date, calendar: calendar)
    }

    /// The window before the current one (same length for custom budgets).
    func previousInterval(calendar: Calendar = .current) -> DateInterval {
        let current = interval(calendar: calendar)
        if period == .custom {
            return DateInterval(start: current.start.addingTimeInterval(-current.duration), end: current.start)
        }
        return period.interval(containing: current.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// Identifies the current window so each alert fires once per period.
    func alertKey(at date: Date = .now) -> String {
        "\(periodRaw)-\(Int(interval(at: date).start.timeIntervalSince1970))"
    }

    /// "Monthly", or "1 Nov – 15 Dec" for custom budgets.
    var periodLabel: String {
        guard period == .custom else { return period.label }
        let i = interval()
        let end = i.end.addingTimeInterval(-1)
        return "\(i.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    func applies(to e: Expense) -> Bool {
        !e.isIncome && e.currency == currency && (categoryRaw == nil || e.categoryRaw == categoryRaw)
    }
}

/// Spending status of a budget for one period.
struct BudgetStatus {
    let spent: Double
    let limit: Double
    let warnAt: Double
    let interval: DateInterval

    var ratio: Double { limit > 0 ? spent / limit : 0 }
    var remaining: Double { limit - spent }

    enum Level { case ok, warning, exceeded }
    var level: Level {
        if ratio >= 1 { return .exceeded }
        if ratio >= warnAt { return .warning }
        return .ok
    }

    /// e.g. "Resets tomorrow", "5 days left"
    var timeLeftText: String {
        let cal = Calendar.current
        if interval.end <= .now { return "Ended" }
        if interval.start > .now {
            return "Starts \(interval.start.formatted(.dateTime.day().month(.abbreviated)))"
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: interval.end).day ?? 0
        switch days {
        case ...1: return "Resets tomorrow"
        default: return "\(days) days left"
        }
    }
}
