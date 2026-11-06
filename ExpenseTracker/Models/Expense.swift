import Foundation
import SwiftData

/// Where a transaction record came from.
enum ExpenseSource: String, Codable, CaseIterable, Identifiable {
    case sms
    case wallet
    case manual
    case notification

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sms: return "SMS"
        case .wallet: return "Apple Wallet"
        case .manual: return "Manual"
        case .notification: return "Notification"
        }
    }

    var symbol: String {
        switch self {
        case .sms: return "message.fill"
        case .wallet: return "wallet.pass.fill"
        case .manual: return "pencil"
        case .notification: return "bell.fill"
        }
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Double = 0
    var currency: String = "USD"
    var merchant: String = ""
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var date: Date = Date()
    var sourceRaw: String = ExpenseSource.manual.rawValue
    /// true = money in (refund / credit / salary). Excluded from spend totals.
    var isIncome: Bool = false
    /// Card / account suffix such as "1234", if found.
    var account: String?
    /// Original SMS / notification text, kept for auditing and re-parsing.
    var rawText: String?
    var sender: String?
    var note: String?
    /// Set when the parser was unsure (e.g. no merchant found) so you can review it.
    var needsReview: Bool = false
    var createdAt: Date = Date()

    init(amount: Double,
         currency: String,
         merchant: String,
         category: ExpenseCategory,
         date: Date = .now,
         source: ExpenseSource,
         isIncome: Bool = false,
         account: String? = nil,
         rawText: String? = nil,
         sender: String? = nil,
         note: String? = nil,
         needsReview: Bool = false) {
        self.id = UUID()
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.categoryRaw = category.rawValue
        self.date = date
        self.sourceRaw = source.rawValue
        self.isIncome = isIncome
        self.account = account
        self.rawText = rawText
        self.sender = sender
        self.note = note
        self.needsReview = needsReview
        self.createdAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: ExpenseSource {
        get { ExpenseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Amount signed from the point of view of spending (expenses positive).
    var signedSpend: Double { isIncome ? -amount : amount }
}
