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

    static func postExpense(_ e: Expense, merged: Bool = false) {
        let content = UNMutableNotificationContent()
        let sign = e.isIncome ? "+" : "−"
        content.title = merged
            ? "Already recorded · \(e.merchant)"
            : "\(sign)\(Formatters.money(e.amount, e.currency)) · \(e.merchant)"

        var subtitle = [e.category.rawValue]
        if let acc = e.accountLabel { subtitle.append(acc) }
        content.subtitle = subtitle.joined(separator: "  ·  ")

        var lines: [String] = []
        if merged {
            lines.append("\(sign)\(Formatters.money(e.amount, e.currency)) matched an existing entry, so it wasn't counted twice.")
        } else {
            lines.append("\(e.isIncome ? "Income" : "Expense") via \(e.source.label) at \(e.date.formatted(date: .omitted, time: .shortened)).")
        }
        if !e.isIncome, let line = budgetLine(for: e) { lines.append(line) }
        if e.needsReview { lines.append("Some details weren't clear — tap to review.") }
        else if (e.bank ?? "").isEmpty && e.source != .manual { lines.append("Tap to add the bank or account.") }
        content.body = lines.joined(separator: "\n")

        content.sound = .default
        content.threadIdentifier = "expenses"
        content.categoryIdentifier = Category.expense
        content.userInfo = ["route": "expense", "expenseID": e.id.uuidString]
        content.relevanceScore = e.needsReview ? 0.8 : 0.5
        if let attachment = attachment(symbol: e.category.symbol, color: e.category.color, name: "cat") {
            content.attachments = [attachment]
        }
        post(content)
    }

    /// e.g. "Groceries budget: AED 420 of 600 used this month (70%)."
    private static func budgetLine(for e: Expense) -> String? {
        let budgets = (try? ExpenseStore.context.fetch(FetchDescriptor<Budget>())) ?? []
        let relevant = budgets.filter { $0.isEnabled && $0.limit > 0 && $0.applies(to: e) }
            .sorted { ($0.categoryRaw == nil ? 1 : 0) < ($1.categoryRaw == nil ? 1 : 0) }
        guard let b = relevant.first else { return nil }
        let s = BudgetService.status(of: b)
        return "\(b.title) budget: \(Formatters.compactMoney(s.spent, b.currency)) of \(Formatters.compactMoney(b.limit, b.currency)) used \(b.period.noun) (\(Int((s.ratio * 100).rounded()))%)."
    }

    // MARK: Budget alerts

    static func postBudgetAlert(_ b: Budget, status s: BudgetStatus) {
        guard BudgetService.alertsEnabled else { return }
        let content = UNMutableNotificationContent()
        let pct = Int((s.ratio * 100).rounded())
        if s.level == .exceeded {
            content.title = "\(b.title) budget exceeded"
            content.body = "Over by \(Formatters.money(-s.remaining, b.currency)). \(s.timeLeftText)."
        } else {
            content.title = "\(b.title) budget \(pct)% used"
            content.body = "\(Formatters.money(max(s.remaining, 0), b.currency)) left \(b.period.noun). \(s.timeLeftText)."
        }
        content.subtitle = "\(b.period.label) · \(Formatters.compactMoney(s.spent, b.currency)) of \(Formatters.compactMoney(b.limit, b.currency))"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "budgets"
        content.categoryIdentifier = Category.budget
        content.userInfo = ["route": "budgets", "budgetID": b.id.uuidString]
        if let attachment = ringAttachment(ratio: s.ratio, level: s.level, symbol: b.symbol) {
            content.attachments = [attachment]
        }
        post(content)
    }

    // MARK: Helpers

    private static func post(_ content: UNMutableNotificationContent) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Renders a small branded image (category tile) as a notification thumbnail.
    private static func attachment(symbol: String, color: Color, name: String) -> UNNotificationAttachment? {
        let view = NotificationTile(symbol: symbol, color: color)
        return render(view, name: name)
    }

    private static func ringAttachment(ratio: Double, level: BudgetStatus.Level, symbol: String) -> UNNotificationAttachment? {
        render(NotificationRing(ratio: ratio, color: level.color, symbol: symbol), name: "ring")
    }

    private static func render<V: View>(_ view: V, name: String) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: name, url: url,
                                                options: [UNNotificationAttachmentOptionsThumbnailClippingRectKey:
                                                            CGRect(x: 0, y: 0, width: 1, height: 1).dictionaryRepresentation])
        } catch {
            return nil
        }
    }
}

/// Category icon on a soft gradient tile with a tiny brand mark.
private struct NotificationTile: View {
    let symbol: String
    let color: Color
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .overlay(Image(systemName: symbol).font(.system(size: 52, weight: .semibold)).foregroundStyle(.white))
            Image("AppLogo")
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white, lineWidth: 3))
                .offset(x: 6, y: 6)
        }
        .padding(8)
    }
}

/// Progress ring used for budget alerts.
private struct NotificationRing: View {
    let ratio: Double
    let color: Color
    let symbol: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
            Circle().stroke(color.opacity(0.18), lineWidth: 12).padding(16)
            Circle().trim(from: 0, to: min(ratio, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(16)
            Image(systemName: symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(color)
        }
        .frame(width: 120, height: 120)
        .padding(8)
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
