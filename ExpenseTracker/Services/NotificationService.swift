import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Small confirmation banner after an automatic log, e.g. "AED 45.50 · Carrefour → Groceries".
    static func confirm(_ result: ExpenseStore.LogResult) {
        guard AppSettings.notifyOnLog else { return }
        let content = UNMutableNotificationContent()
        switch result {
        case .logged(let e):
            content.title = e.isIncome ? "Income recorded" : "Expense recorded"
            content.body = "\(Formatters.money(e.amount, e.currency)) · \(e.merchant) → \(e.category.rawValue)"
                + (e.needsReview ? "  (tap to review)" : "")
        case .merged(let e):
            content.title = "Already recorded"
            content.body = "\(Formatters.money(e.amount, e.currency)) · \(e.merchant) matched an existing entry."
        case .ignored:
            return
        }
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
