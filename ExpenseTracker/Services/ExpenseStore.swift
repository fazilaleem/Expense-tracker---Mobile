import Foundation
import SwiftData

/// Single shared SwiftData container used by both the UI and App Intents
/// (intents run inside the app process, so they see the same store).
@MainActor
enum ExpenseStore {

    static let container: ModelContainer = {
        // SwiftData doesn't create Application Support on first launch; make sure it exists.
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            return try ModelContainer(for: Expense.self, Budget.self)
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
    /// `bank` (optional) names the bank / account explicitly, e.g. "KFH Credit Card" set in the automation;
    /// otherwise it is detected from the sender or message text.
    static func logMessage(_ text: String, sender: String?, bank: String? = nil, source: ExpenseSource,
                           date: Date = .now) -> LogResult {
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
                              bank: (bank?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
                                    ?? BankDetector.detect(text: text, sender: sender),
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
                              account: card.flatMap(Self.lastDigits),
                              bank: BankDetector.fromWalletCard(card),
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
            if (existing.bank ?? "").isEmpty { existing.bank = expense.bank }
            if let raw = expense.rawText {
                existing.rawText = [existing.rawText, raw].compactMap { $0 }.joined(separator: "\n—\n")
            }
            try? context.save()
            return .merged(existing)
        }
        context.insert(expense)
        try? context.save()
        BudgetService.evaluate(after: expense)
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

    static func find(_ id: UUID) -> Expense? {
        var d = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// "Visa ••1234" → "1234"
    nonisolated static func lastDigits(_ s: String) -> String? {
        guard let r = s.range(of: #"\d{4}(?!.*\d)"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    /// Copy an expense as a new manual entry dated now (e.g. a repeat purchase).
    @discardableResult
    static func duplicate(_ e: Expense) -> Expense {
        let copy = Expense(amount: e.amount, currency: e.currency, merchant: e.merchant, category: e.category,
                           date: .now, source: .manual, isIncome: e.isIncome, account: e.account, bank: e.bank,
                           note: e.note)
        context.insert(copy)
        try? context.save()
        BudgetService.evaluate(after: copy)
        return copy
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
