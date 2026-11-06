import SwiftUI
import AppIntents

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
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

    /// Harmonised palette, tuned separately for light and dark mode.
    var color: Color {
        switch self {
        case .food: return Color(light: 0xF97316, dark: 0xFB923C)
        case .groceries: return Color(light: 0x16A34A, dark: 0x4ADE80)
        case .transport: return Color(light: 0x2563EB, dark: 0x60A5FA)
        case .fuel: return Color(light: 0xB45309, dark: 0xF59E0B)
        case .shopping: return Color(light: 0xDB2777, dark: 0xF472B6)
        case .bills: return Color(light: 0xCA8A04, dark: 0xFACC15)
        case .entertainment: return Color(light: 0x7C3AED, dark: 0xA78BFA)
        case .health: return Color(light: 0xDC2626, dark: 0xF87171)
        case .travel: return Color(light: 0x0891B2, dark: 0x22D3EE)
        case .education: return Color(light: 0x4F46E5, dark: 0x818CF8)
        case .subscriptions: return Color(light: 0x0D9488, dark: 0x2DD4BF)
        case .transfer: return Color(light: 0x64748B, dark: 0x94A3B8)
        case .cash: return Color(light: 0x65A30D, dark: 0xA3E635)
        case .income: return Color(light: 0x059669, dark: 0x34D399)
        case .other: return Color(light: 0x78716C, dark: 0xA8A29E)
        }
    }

    /// Short label for chips.
    var shortName: String {
        switch self {
        case .food: return "Food"
        case .bills: return "Bills"
        case .entertainment: return "Fun"
        case .subscriptions: return "Subs"
        case .cash: return "Cash"
        default: return rawValue
        }
    }
}
