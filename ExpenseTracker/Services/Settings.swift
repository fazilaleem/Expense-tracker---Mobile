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
        UserDefaults.standard.string(forKey: SettingsKey.defaultCurrency)
            ?? Locale.current.currency?.identifier ?? "USD"
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

    static let commonCurrencies = ["AED", "USD", "EUR", "GBP", "INR", "PKR", "SAR", "QAR", "OMR", "KWD",
                                   "BHD", "CAD", "AUD", "SGD", "MYR", "JPY", "NGN", "KES", "ZAR", "LKR",
                                   "BDT", "NPR", "EGP", "TRY", "PHP"]
}
