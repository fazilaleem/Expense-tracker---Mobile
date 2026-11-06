import SwiftUI

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food & Dining"
    case groceries = "Groceries"
    case transport = "Transport"
    case fuel = "Fuel"
    case shopping = "Shopping"
    case bills = "Bills & Utilities"
    case entertainment = "Entertainment"
    case health = "Health"
    case travel = "Travel"
    case education = "Education"
    case subscriptions = "Subscriptions"
    case transfer = "Transfers"
    case cash = "Cash Withdrawal"
    case income = "Income"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .groceries: return "cart.fill"
        case .transport: return "car.fill"
        case .fuel: return "fuelpump.fill"
        case .shopping: return "bag.fill"
        case .bills: return "bolt.fill"
        case .entertainment: return "film.fill"
        case .health: return "cross.case.fill"
        case .travel: return "airplane"
        case .education: return "book.fill"
        case .subscriptions: return "repeat"
        case .transfer: return "arrow.left.arrow.right"
        case .cash: return "banknote.fill"
        case .income: return "arrow.down.circle.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: return .orange
        case .groceries: return .green
        case .transport: return .blue
        case .fuel: return .brown
        case .shopping: return .pink
        case .bills: return .yellow
        case .entertainment: return .purple
        case .health: return .red
        case .travel: return .cyan
        case .education: return .indigo
        case .subscriptions: return .mint
        case .transfer: return .gray
        case .cash: return .teal
        case .income: return .green
        case .other: return .secondary
        }
    }
}
