import AppIntents
import Foundation

// MARK: - Log from SMS / notification text
//
// Use in a Shortcuts Personal Automation:
//   Automation ▸ Message ▸ "Message Contains: debited" (and/or Sender: your bank) ▸ Run Immediately
//   Action: "Log Expense from Message"  ▸ Message = Shortcut Input › Content, Sender = Shortcut Input › Sender

struct LogMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense from Message"
    static var description = IntentDescription(
        "Reads a bank / card SMS or notification text, extracts the amount, merchant and card, and records it.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message", description: "Full text of the SMS or notification",
               inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    @Parameter(title: "Sender", description: "Optional – who sent the message (e.g. your bank)")
    var sender: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log expense from \(\.$message)") {
            \.$sender
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = ExpenseStore.logMessage(message, sender: sender, source: .sms)
        NotificationService.confirm(result)
        return .result(dialog: IntentDialog(stringLiteral: result.summary))
    }
}

// MARK: - Log from Apple Wallet / Apple Pay
//
// Use in a Shortcuts Personal Automation:
//   Automation ▸ Transaction ▸ choose your cards ▸ Run Immediately
//   Action: "Log Wallet Transaction" ▸ Amount = Shortcut Input › Amount,
//           Merchant = Shortcut Input › Merchant, Card = Shortcut Input › Card (or Name)

struct LogWalletTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Wallet Transaction"
    static var description = IntentDescription(
        "Records an Apple Pay / Wallet transaction. Connect it to the Shortcuts ‘Transaction’ automation.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "e.g. “AED 45.00” or “$12.40”")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = ExpenseStore.logWallet(amountText: amount, merchant: merchant, card: card)
        NotificationService.confirm(result)
        return .result(dialog: IntentDialog(stringLiteral: result.summary))
    }
}

// MARK: - Quick manual add (Siri: "Add expense in Expenses")

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Quickly add a cash or manual expense.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Merchant / Description")
    var merchant: String

    @Parameter(title: "Category", default: .other)
    var category: ExpenseCategory

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let currency = AppSettings.defaultCurrency
        var cat = category
        if cat == .other { cat = Categorizer.categorize(merchant: merchant, text: nil, isIncome: false) }
        let result = ExpenseStore.save(Expense(amount: amount, currency: currency, merchant: merchant,
                                               category: cat, source: .manual))
        NotificationService.confirm(result)
        return .result(dialog: IntentDialog(stringLiteral: result.summary))
    }
}

// MARK: - "How much did I spend this month?"

struct MonthlySpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Spending This Month"
    static var description = IntentDescription("Tells you how much you've spent so far this month.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        let totals = ExpenseStore.spend(from: start, to: end)
        let main = AppSettings.defaultCurrency
        guard !totals.isEmpty else {
            return .result(value: 0, dialog: "You haven't recorded any spending this month.")
        }
        let text = totals.sorted { $0.key == main || ($1.key != main && $0.value > $1.value) }
            .map { Formatters.money($0.value, $0.key) }
            .joined(separator: " + ")
        return .result(value: totals[main] ?? 0, dialog: IntentDialog(stringLiteral: "You've spent \(text) this month."))
    }
}

// MARK: - Category as an App Enum

extension ExpenseCategory: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] = [
        .food: "Food & Dining",
        .groceries: "Groceries",
        .transport: "Transport",
        .fuel: "Fuel",
        .shopping: "Shopping",
        .bills: "Bills & Utilities",
        .entertainment: "Entertainment",
        .health: "Health",
        .travel: "Travel",
        .education: "Education",
        .subscriptions: "Subscriptions",
        .transfer: "Transfers",
        .cash: "Cash Withdrawal",
        .income: "Income",
        .other: "Other"
    ]
}

extension ExpenseStore.LogResult {
    var summary: String {
        switch self {
        case .logged(let e):
            let review = e.needsReview ? " (flagged for review)" : ""
            return "Recorded \(Formatters.money(e.amount, e.currency)) at \(e.merchant) in \(e.category.rawValue)\(review)."
        case .merged(let e):
            return "\(Formatters.money(e.amount, e.currency)) at \(e.merchant) was already recorded – merged."
        case .ignored(let reason):
            return "Not recorded: \(reason)"
        }
    }
}

// MARK: - Siri / Spotlight phrases

struct ExpenseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add an expense in \(.applicationName)",
                              "Log expense in \(.applicationName)"],
                    shortTitle: "Add Expense",
                    systemImageName: "plus.circle")
        AppShortcut(intent: MonthlySpendIntent(),
                    phrases: ["How much did I spend in \(.applicationName)",
                              "Monthly spending in \(.applicationName)"],
                    shortTitle: "This Month",
                    systemImageName: "chart.pie")
        AppShortcut(intent: LogMessageIntent(),
                    phrases: ["Log bank message in \(.applicationName)"],
                    shortTitle: "Log from Message",
                    systemImageName: "message")
        AppShortcut(intent: LogWalletTransactionIntent(),
                    phrases: ["Log wallet transaction in \(.applicationName)"],
                    shortTitle: "Log Wallet Payment",
                    systemImageName: "wallet.pass")
    }
}
