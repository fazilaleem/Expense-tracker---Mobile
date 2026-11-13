import SwiftUI

/// A user-created expense category, stored in UserDefaults as JSON.
struct CustomCategory: Codable, Identifiable, Hashable {
    var name: String
    var symbol: String
    var colorHex: UInt32
    var id: String { name }
}

/// Display info for any category – built-in (`ExpenseCategory`) or custom.
/// Exposes the same fields the views already use: rawValue, shortName, symbol, color.
struct CategoryStyle: Identifiable, Hashable {
    let rawValue: String
    let shortName: String
    let symbol: String
    let color: Color
    let isCustom: Bool

    var id: String { rawValue }
    static func == (a: Self, b: Self) -> Bool { a.rawValue == b.rawValue }
    func hash(into h: inout Hasher) { h.combine(rawValue) }

    static func of(_ raw: String) -> CategoryStyle {
        if let c = ExpenseCategory(rawValue: raw) {
            return CategoryStyle(rawValue: c.rawValue, shortName: c.shortName, symbol: c.symbol, color: c.color, isCustom: false)
        }
        if let c = CategoryStore.all.first(where: { $0.name == raw }) {
            return CategoryStyle(rawValue: c.name, shortName: c.name, symbol: c.symbol,
                                 color: Color(hex: c.colorHex), isCustom: true)
        }
        // Unknown raw value (e.g. a deleted custom category) – show its name with the "Other" look.
        let o = ExpenseCategory.other
        return CategoryStyle(rawValue: raw, shortName: raw, symbol: o.symbol, color: o.color, isCustom: true)
    }

    /// Every category available for expenses: built-ins (except Income) followed by custom ones.
    static var allExpense: [CategoryStyle] {
        ExpenseCategory.allCases.filter { $0 != .income }.map { of($0.rawValue) }
            + CategoryStore.all.map { of($0.name) }
    }
}

/// Persists custom categories.
enum CategoryStore {
    static let key = "customCategories"

    static var all: [CustomCategory] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([CustomCategory].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [CustomCategory]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    @discardableResult
    static func add(name: String, symbol: String, colorHex: UInt32) -> CustomCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              ExpenseCategory(rawValue: trimmed) == nil,
              !all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        let c = CustomCategory(name: trimmed, symbol: symbol, colorHex: colorHex)
        save(all + [c])
        return c
    }

    static func remove(_ name: String) {
        save(all.filter { $0.name != name })
    }

    static let symbols = ["tag.fill", "gift.fill", "house.fill", "pawprint.fill", "figure.child", "dumbbell.fill",
                          "scissors", "tshirt.fill", "wrench.and.screwdriver.fill", "car.2.fill", "graduationcap.fill",
                          "heart.fill", "leaf.fill", "cup.and.saucer.fill", "gamecontroller.fill", "paintbrush.fill",
                          "laptopcomputer", "iphone", "creditcard.fill", "building.2.fill", "hands.sparkles.fill",
                          "stethoscope", "airplane.departure", "fork.knife.circle.fill"]
    static let colors: [UInt32] = [0x10B981, 0x3B82F6, 0x8B5CF6, 0xEC4899, 0xF97316, 0xEAB308,
                                   0xEF4444, 0x06B6D4, 0x6366F1, 0x84CC16, 0x14B8A6, 0x78716C]
}
