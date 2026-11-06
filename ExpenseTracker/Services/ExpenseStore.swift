import Foundation
import SwiftData

/// Single shared SwiftData container used by both the UI and App Intents
/// (intents run inside the app process, so they see the same store).
@MainActor
enum ExpenseStore {

    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Expense.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    enum LogResult {
        case logged(Expense)
        case merged(Expense)        // matched an existing record (e.g. Wallet + bank SMS for the same purchase)
        case ignored(String)        // reason
    }

    /// Parse a raw SMS / notification and save it.
    @discardableResult
    static func logMessage(_ text: String, sender: String?, source: ExpenseSource, date: Date = .now) -> LogResult {
        let currency = AppSettings.defaultCurrency
        guard let parsed = TransactionParser.parse(text, defaultCurrency: currency) else {
            return .ignored("No transaction amount found in the message.")
        }
        if parsed.isIncome && AppSettings.ignoreIncome {
            return .ignored("Income messages are ignored (see Settings).")
        }
        let category = Categorizer.categorize(merchant: parsed.merchant, text: text, isIncome: parsed.isIncome)
        let expense = Expense(amount: parsed.amount,
                              currency: parsed.currency,
                              merchant: parsed.merchant ?? (sender ?? "Unknown"),
                              category: category,
                              date: date,
                              source: source,
                              isIncome: parsed.isIncome,
                              account: parsed.account,
                              rawText: text,
                              sender: sender,
                              needsReview: parsed.confidence < 0.6 || parsed.merchant == nil)
        return save(expense)
    }

    /// Save a transaction coming from the Shortcuts "Transaction" (Apple Wallet / Apple Pay) automation.
    @discardableResult
    static func logWallet(amountText: String, merchant: String?, card: String?, date: Date = .now) -> LogResult {
        guard let money = TransactionParser.parseAmountString(amountText, defaultCurrency: AppSettings.defaultCurrency),
              money.value > 0 else {
            return .ignored("Couldn't read the amount “\(amountText)”.")
        }
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = Categorizer.categorize(merchant: name, text: nil, isIncome: false)
        let expense = Expense(amount: money.value,
                              currency: money.currency,
                              merchant: (name?.isEmpty == false ? name! : "Apple Pay"),
                              category: category,
                              date: date,
                              source: .wallet,
                              account: card,
                              rawText: "Wallet: \(amountText) at \(name ?? "?") – \(card ?? "")",
                              needsReview: name?.isEmpty ?? true)
        return save(expense)
    }

    @discardableResult
    static func save(_ expense: Expense) -> LogResult {
        if AppSettings.mergeDuplicates, let existing = findDuplicate(of: expense) {
            // Enrich the existing record instead of double counting.
            if existing.needsReview && !expense.needsReview {
                existing.merchant = expense.merchant
                existing.category = expense.category
                existing.needsReview = false
            }
            if existing.account == nil { existing.account = expense.account }
            if let raw = expense.rawText {
                existing.rawText = [existing.rawText, raw].compactMap { $0 }.joined(separator: "\n—\n")
            }
            try? context.save()
            return .merged(existing)
        }
        context.insert(expense)
        try? context.save()
        return .logged(expense)
    }

    /// Same amount & currency & direction, from a *different* source or identical text, within 15 minutes.
    private static func findDuplicate(of e: Expense) -> Expense? {
        let lower = e.date.addingTimeInterval(-15 * 60)
        let upper = e.date.addingTimeInterval(15 * 60)
        let amount = e.amount
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate {
            $0.date >= lower && $0.date <= upper && $0.amount == amount
        })
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { c in
            c.currency == e.currency && c.isIncome == e.isIncome &&
            (c.sourceRaw != e.sourceRaw || (c.rawText != nil && c.rawText == e.rawText))
        }
    }

    // MARK: Queries used by intents

    static func spend(from start: Date, to end: Date) -> [String: Double] {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.isIncome == false
        })
        let items = (try? context.fetch(descriptor)) ?? []
        return Dictionary(grouping: items, by: \.currency).mapValues { $0.reduce(0) { $0 + $1.amount } }
    }
}
