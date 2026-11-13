import Foundation
import SwiftData

@MainActor
enum BudgetService {

    static var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.budgetAlerts) as? Bool ?? true
    }

    static func status(of budget: Budget, at date: Date = .now, in expenses: [Expense]) -> BudgetStatus {
        status(of: budget, interval: budget.interval(at: date), in: expenses)
    }

    /// Spending against a budget for any window (e.g. the previous period).
    static func status(of budget: Budget, interval: DateInterval, in expenses: [Expense]) -> BudgetStatus {
        let spent = expenses
            .filter { budget.applies(to: $0) && interval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
        return BudgetStatus(spent: spent, limit: budget.limit, warnAt: budget.warnAt, interval: interval)
    }

    static func status(of budget: Budget, at date: Date = .now) -> BudgetStatus {
        let interval = budget.interval(at: date)
        let start = interval.start, end = interval.end
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.isIncome == false
        })
        let items = (try? ExpenseStore.context.fetch(descriptor)) ?? []
        return status(of: budget, at: date, in: items)
    }

    /// Call after an expense is added or edited. Fires at most one "almost used"
    /// and one "exceeded" notification per budget per period.
    static func evaluate(after expense: Expense) {
        guard !expense.isIncome else { return }
        let ctx = ExpenseStore.context
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        for budget in budgets where budget.isEnabled && budget.limit > 0 && budget.applies(to: expense) {
            let interval = budget.interval(at: .now)
            // Only alert for spending in the current period.
            guard interval.contains(expense.date) else { continue }
            let s = status(of: budget)
            let key = budget.alertKey(at: .now)

            if s.ratio >= 1, budget.lastExceededKey != key {
                budget.lastExceededKey = key
                budget.lastWarnedKey = key
                NotificationService.postBudgetAlert(budget, status: s)
            } else if s.ratio >= budget.warnAt, s.ratio < 1, budget.lastWarnedKey != key {
                budget.lastWarnedKey = key
                NotificationService.postBudgetAlert(budget, status: s)
            }
        }
        try? ctx.save()
    }

    /// One-time migration of the old single "monthly budget" setting into a Budget record.
    static func migrateLegacyMonthlyBudget() {
        let legacy = UserDefaults.standard.double(forKey: SettingsKey.monthlyBudget)
        guard legacy > 0, !UserDefaults.standard.bool(forKey: "migratedLegacyBudget") else { return }
        let ctx = ExpenseStore.context
        let hasOverall = ((try? ctx.fetch(FetchDescriptor<Budget>())) ?? []).contains { $0.categoryRaw == nil && $0.period == .monthly }
        if !hasOverall {
            ctx.insert(Budget(category: nil, period: .monthly, limit: legacy, currency: AppSettings.defaultCurrency))
            try? ctx.save()
        }
        UserDefaults.standard.set(true, forKey: "migratedLegacyBudget")
    }
}
