import Foundation

/// Assigns a category from the merchant name / message text.
/// Learns: when you change a merchant's category in the app it's remembered for next time.
enum Categorizer {

    private static let rulesKey = "merchantCategoryRules"

    private static let keywordMap: [(ExpenseCategory, [String])] = [
        (.subscriptions, ["netflix", "spotify", "apple.com", "itunes", "icloud", "youtube", "prime video",
                          "disney", "hulu", "osn", "shahid", "anghami", "chatgpt", "openai", "claude", "adobe",
                          "microsoft", "google storage", "patreon"]),
        (.food, ["restaurant", "cafe", "coffee", "starbucks", "costa", "tim hortons", "mcdonald", "kfc",
                 "burger", "pizza", "domino", "subway", "swiggy", "zomato", "talabat", "deliveroo", "uber eats",
                 "ubereats", "foodpanda", "careem food", "doordash", "grubhub", "dunkin", "shawarma", "biryani",
                 "bakery", "eatery", "kitchen", "grill", "diner", "noon food", "hardee", "popeyes", "chipotle"]),
        (.groceries, ["groceries", "carrefour", "lulu", "spinneys", "waitrose", "tesco", "sainsbury", "asda", "aldi", "lidl",
                      "walmart", "costco", "kroger", "safeway", "whole foods", "trader joe", "bigbasket", "blinkit",
                      "zepto", "instamart", "dmart", "grocery", "supermarket", "hypermarket", "choithrams",
                      "union coop", "imtiaz", "metro cash", "al meera", "panda", "danube", "othaim", "instashop"]),
        (.fuel, ["petrol", "fuel", "adnoc", "enoc", "eppco", "shell", "bp ", "chevron", "exxon", "texaco",
                 "indian oil", "iocl", "hpcl", "bpcl", "pso", "total energies", "caltex", "aramco", "gas station"]),
        (.transport, ["uber", "careem", "lyft", "ola", "rapido", "bolt", "taxi", "cab", "metro", "rta", "salik",
                      "nol", "parking", "toll", "fastag", "transit", "railway", "irctc", "bykea", "indrive"]),
        (.travel, ["airline", "airways", "emirates", "etihad", "flydubai", "air arabia", "qatar airways",
                   "indigo", "vistara", "air india", "pia", "booking.com", "agoda", "expedia", "airbnb",
                   "hotel", "marriott", "hilton", "makemytrip", "skyscanner", "trip.com", "saudia"]),
        (.shopping, ["amazon", "noon", "flipkart", "myntra", "ajio", "shein", "namshi", "ikea", "zara", "h&m",
                     "uniqlo", "nike", "adidas", "apple store", "sharaf dg", "jumbo", "croma", "reliance digital",
                     "daraz", "ebay", "etsy", "aliexpress", "temu", "mall", "centrepoint", "max fashion", "target",
                     "best buy", "decathlon", "home centre", "ace hardware"]),
        (.bills, ["dewa", "sewa", "fewa", "addc", "etisalat", "e&", "du ", "airtel", "jio", "vodafone", "vi ",
                  "bsnl", "ptcl", "jazz", "zong", "telenor", "ufone", "stc", "mobily", "zain", "ooredoo",
                  "electricity", "water", "gas bill", "internet", "broadband", "wifi", "utility", "bill pay",
                  "billdesk", "recharge", "postpaid", "prepaid", "insurance", "rent payment", "house rent", "k-electric", "lesco"]),
        (.entertainment, ["cinema", "vox", "reel cinemas", "pvr", "inox", "bookmyshow", "ticketmaster", "steam",
                          "playstation", "xbox", "nintendo", "game", "concert", "theme park", "bowling"]),
        (.health, ["pharmacy", "chemist", "hospital", "clinic", "medical", "doctor", "dental", "aster", "boots",
                   "life pharmacy", "apollo", "1mg", "pharmeasy", "netmeds", "lab", "diagnostic", "gym", "fitness"]),
        (.education, ["school", "college", "university", "udemy", "coursera", "tuition", "academy", "books",
                      "kindle", "bookstore", "magrudy", "library"]),
        (.cash, ["atm", "cash withdrawal", "withdrawn at", "cash wdl", "cwdl"]),
        (.transfer, ["iban", "beneficiary", "transfer", "trf", "neft", "imps", "rtgs", "upi", "sent to", "remittance", "western union",
                     "wise", "remitly", "al ansari", "lulu exchange", "raast", "ibft"])
    ]

    static func categorize(merchant: String?, text: String?, isIncome: Bool) -> ExpenseCategory {
        if isIncome { return .income }
        let merchantLower = (merchant ?? "").lowercased()

        if !merchantLower.isEmpty, let learned = learnedRules()[merchantLower],
           let cat = ExpenseCategory(rawValue: learned) {
            return cat
        }

        // Check merchant first, then the full message.
        for haystack in [merchantLower, (text ?? "").lowercased()] where !haystack.isEmpty {
            for (category, words) in keywordMap where words.contains(where: { matches($0, in: haystack) }) {
                return category
            }
        }
        return .other
    }

    /// Keyword match that respects word boundaries, so "ola" doesn't match "coca-cola"
    /// and "rent" doesn't match "current".
    static func matches(_ keyword: String, in haystack: String) -> Bool {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard haystack.contains(kw) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: kw)
        let pattern = "(?<![a-z0-9])" + escaped + (kw.count < 6 ? "(?![a-z])" : "")
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: Learned rules

    static func learn(merchant: String, category: ExpenseCategory) {
        let key = merchant.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        var rules = learnedRules()
        rules[key] = category.rawValue
        UserDefaults.standard.set(rules, forKey: rulesKey)
    }

    static func learnedRules() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: rulesKey) as? [String: String] ?? [:]
    }

    static func clearLearnedRules() {
        UserDefaults.standard.removeObject(forKey: rulesKey)
    }
}
