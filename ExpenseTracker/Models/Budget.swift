import Foundation
import SwiftData

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var noun: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "this week"
        case .monthly: return "this month"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
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
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: interval.end).day ?? 0
        switch days {
        case ...1: return "Resets tomorrow"
        default: return "\(days) days left"
        }
    }
}
