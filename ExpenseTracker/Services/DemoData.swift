import Foundation
import SwiftData

/// Sample data used only when the app is launched with `-seedDemo YES`
/// (for screenshots / trying the UI). Never runs in normal use.
@MainActor
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "seedDemo") }

    static func seedIfNeeded() {
        guard isEnabled else { return }
        let ctx = ExpenseStore.context
        let existing = (try? ctx.fetchCount(FetchDescriptor<Expense>())) ?? 0
        guard existing == 0 else { return }

        let cal = Calendar.current
        let now = Date.now
        let cur = AppSettings.defaultCurrency
        let samples: [(String, ExpenseCategory, Double, ExpenseSource)] = [
            ("Carrefour", .groceries, 186.40, .sms), ("Starbucks", .food, 24.50, .wallet),
            ("Careem", .transport, 38.00, .wallet), ("ENOC", .fuel, 120.00, .sms),
            ("Talabat", .food, 64.75, .sms), ("Netflix", .subscriptions, 56.00, .sms),
            ("Amazon", .shopping, 249.00, .sms), ("DEWA", .bills, 412.30, .sms),
            ("Lulu Hypermarket", .groceries, 143.20, .wallet), ("Vox Cinemas", .entertainment, 95.00, .wallet),
            ("Life Pharmacy", .health, 47.80, .wallet), ("Salik", .transport, 20.00, .sms),
            ("Costa Coffee", .food, 19.00, .wallet), ("Noon", .shopping, 89.00, .sms),
            ("Spotify", .subscriptions, 21.99, .sms), ("Shake Shack", .food, 72.00, .wallet),
            ("Spinneys", .groceries, 98.60, .wallet), ("Uber", .transport, 31.50, .wallet),
        ]
        let today = cal.component(.day, from: now)
        for (i, s) in samples.enumerated() {
            let dayOffset = (i * 7) % max(today, 1)
            let date = cal.date(byAdding: .day, value: -dayOffset, to: now)!
                .addingTimeInterval(-Double(i % 5) * 3600 * 2)
            ctx.insert(Expense(amount: s.2, currency: cur, merchant: s.0, category: s.1, date: date,
                               source: s.3, account: ["4321", "9876"][i % 2],
                               bank: i % 5 == 3 ? nil : ["Emirates NBD", "ADCB"][i % 2],
                               rawText: "\(cur) \(s.2) spent at \(s.0.uppercased())",
                               needsReview: i == 4))
        }
        ctx.insert(Expense(amount: 15000, currency: cur, merchant: "Salary", category: .income,
                           date: cal.startOfMonth(for: now), source: .sms, isIncome: true))
        // A couple from last month so the month switcher has history.
        for (j, s) in samples.prefix(6).enumerated() {
            let date = cal.date(byAdding: .day, value: -(today + 3 + j * 4), to: now)!
            ctx.insert(Expense(amount: s.2 * 1.1, currency: cur, merchant: s.0, category: s.1, date: date, source: s.3))
        }
        ctx.insert(Budget(category: nil, period: .monthly, limit: 3000, currency: cur))
        ctx.insert(Budget(category: .food, period: .weekly, limit: 150, currency: cur))
        ctx.insert(Budget(category: .groceries, period: .monthly, limit: 600, currency: cur))
        ctx.insert(Budget(category: .transport, period: .daily, limit: 60, currency: cur))
        ctx.insert(Budget(category: .bills, period: .monthly, limit: 450, currency: cur))
        try? ctx.save()
    }
}
