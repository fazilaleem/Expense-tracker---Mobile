import SwiftUI
import SwiftData
import UserNotifications

/// Rich local notifications for recorded expenses and budget alerts.
/// The app icon shows automatically; each notification also carries a category
/// image, a clear header, details, and tap / action handling.
@MainActor
enum NotificationService {

    enum Category {
        static let expense = "EXPENSE"
        static let budget = "BUDGET"
    }
    enum Action {
        static let edit = "EDIT"
        static let markReviewed = "MARK_REVIEWED"
        static let delete = "DELETE"
        static let viewBudgets = "VIEW_BUDGETS"
    }

    static func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        let edit = UNNotificationAction(identifier: Action.edit, title: "Edit",
                                        options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "pencil"))
        let reviewed = UNNotificationAction(identifier: Action.markReviewed, title: "Looks right",
                                            options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let delete = UNNotificationAction(identifier: Action.delete, title: "Delete",
                                          options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "trash"))
        let viewBudgets = UNNotificationAction(identifier: Action.viewBudgets, title: "View budgets",
                                               options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "target"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.expense, actions: [edit, reviewed, delete], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.budget, actions: [viewBudgets], intentIdentifiers: [])
        ])
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Expense recorded

    static func confirm(_ result: ExpenseStore.LogResult) {
        guard AppSettings.notifyOnLog else { return }
        switch result {
        case .logged(let e): postExpense(e, merged: false)
        case .merged(let e): postExpense(e, merged: true)
        case .ignored: return
        }
    }

    /// Minimal two-line notification:
    ///   −BHD 1.000 · Carrefour
    ///   Groceries · KFH ••1234
    static func postExpense(_ e: Expense, merged: Bool = false) {
        let content = UNMutableNotificationContent()
        let sign = e.isIncome ? "+" : "−"
        content.title = "\(sign)\(Formatters.money(e.amount, e.currency)) · \(e.merchant)"

        var details = [e.category.rawValue]
        if let acc = e.accountLabel { details.append(acc) }
        if merged {
            details = ["Already recorded"]
        } else if e.needsReview {
            details.append("Tap to add details")
        }
        content.body = details.joined(separator: " · ")

        content.sound = .default
        content.threadIdentifier = "expenses"
        content.categoryIdentifier = Category.expense
        content.userInfo = ["route": "expense", "expenseID": e.id.uuidString]
        content.relevanceScore = e.needsReview ? 0.8 : 0.5
        post(content)
    }

    /// Tells the user an automation is wired wrongly (e.g. the Message field holds "KFH" instead of the SMS).
    static func postSetupHint(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "setup"
        post(content)
    }

    // MARK: Budget alerts

    /// Minimal two-line budget alert:
    ///   Food budget 85% used
    ///   BHD 23.000 left this week
    static func postBudgetAlert(_ b: Budget, status s: BudgetStatus) {
        guard BudgetService.alertsEnabled else { return }
        let content = UNMutableNotificationContent()
        if s.level == .exceeded {
            content.title = "\(b.title) budget exceeded"
            content.body = "Over by \(Formatters.money(-s.remaining, b.currency)) \(b.period.noun)"
        } else {
            content.title = "\(b.title) budget \(Int((s.ratio * 100).rounded()))% used"
            content.body = "\(Formatters.money(max(s.remaining, 0), b.currency)) left \(b.period.noun)"
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "budgets"
        content.categoryIdentifier = Category.budget
        content.userInfo = ["route": "budgets", "budgetID": b.id.uuidString]
        post(content)
    }

    // MARK: Helpers

    private static func post(_ content: UNMutableNotificationContent) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

}

// MARK: - Delegate & routing

/// Where a notification tap should take the user.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var openExpenseID: UUID?
    var selectedTab: Int = UserDefaults.standard.integer(forKey: "startTab")
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let id = (info["expenseID"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        Task { @MainActor in
            switch (route, action) {
            case ("expense", NotificationService.Action.delete):
                if let id, let e = ExpenseStore.find(id) {
                    ExpenseStore.context.delete(e)
                    try? ExpenseStore.context.save()
                }
            case ("expense", NotificationService.Action.markReviewed):
                if let id, let e = ExpenseStore.find(id) {
                    e.needsReview = false
                    try? ExpenseStore.context.save()
                }
            case ("expense", _):
                AppRouter.shared.selectedTab = 1
                AppRouter.shared.openExpenseID = id
            case ("budgets", _):
                AppRouter.shared.selectedTab = 3
            default:
                break
            }
            completionHandler()
        }
    }
}
