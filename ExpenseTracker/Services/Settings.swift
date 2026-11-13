import Foundation

/// Keys for @AppStorage / UserDefaults.
enum SettingsKey {
    static let defaultCurrency = "defaultCurrency"
    static let monthlyBudget = "monthlyBudget"
    static let notifyOnLog = "notifyOnLog"
    static let mergeDuplicates = "mergeDuplicates"
    static let ignoreIncome = "ignoreIncome"
    static let hasOnboarded = "hasOnboarded"
    static let budgetAlerts = "budgetAlerts"
    static let appLock = "appLock"
}

enum AppSettings {
    static var defaultCurrency: String {
        UserDefaults.standard.string(forKey: SettingsKey.defaultCurrency) ?? "BHD"
    }
    static var notifyOnLog: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.notifyOnLog) as? Bool ?? true
    }
    static var mergeDuplicates: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.mergeDuplicates) as? Bool ?? true
    }
    /// When true, incoming credits (salary, refunds) from SMS are not recorded at all.
    static var ignoreIncome: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.ignoreIncome) as? Bool ?? false
    }

    /// One-time switch of the main currency to BHD (the owner's local currency).
    static func applyLocalCurrencyOnce() {
        let key = "didSetLocalCurrencyBHD"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set("BHD", forKey: SettingsKey.defaultCurrency)
        UserDefaults.standard.set(true, forKey: key)
    }

    static let commonCurrencies = ["BHD", "KWD", "SAR", "AED", "QAR", "OMR", "USD", "EUR", "GBP", "INR", "PKR", "CAD", "AUD", "SGD", "MYR", "JPY", "NGN", "KES", "ZAR", "LKR", "BDT", "NPR", "EGP", "TRY", "PHP"]
}
