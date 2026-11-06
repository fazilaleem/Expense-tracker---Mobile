import Foundation

/// Result of parsing a bank SMS, push notification text or Wallet amount.
struct ParsedTransaction: Equatable {
    var amount: Double
    var currency: String
    var merchant: String?
    var account: String?
    var isIncome: Bool
    /// 0...1 – how sure the parser is. Below 0.6 the expense is flagged for review.
    var confidence: Double
}

/// Rule-based parser for bank / card / wallet transaction messages.
///
/// Works with the common formats used by banks in South Asia, the Gulf, the
/// UK/EU and the US, e.g.
///  - "Rs.1,250.00 debited from A/c XX1234 on 05-11-26 to VPA swiggy@icici. Ref 1234"
///  - "AED 45.50 spent on your Credit Card ending 4321 at CARREFOUR DUBAI on 06/11/2026."
///  - "You spent $12.40 at Starbucks with card ending 9876."
///  - "INR 500 credited to your a/c **1234 from JOHN DOE"
enum TransactionParser {

    // MARK: Public API

    static func parse(_ rawText: String, defaultCurrency: String = "USD") -> ParsedTransaction? {
        let text = rawText
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let lower = text.lowercased()

        if isNonTransactional(lower) { return nil }

        guard let money = extractAmount(from: text, defaultCurrency: defaultCurrency) else { return nil }

        let direction = detectDirection(lower)
        // Without a debit/credit keyword it's probably promotional ("Get 20% off on orders above Rs 500").
        guard direction != nil || money.hadCurrency else { return nil }
        if direction == nil && looksPromotional(lower) { return nil }

        let isIncome = direction == .credit
        let merchant = extractMerchant(from: text, isIncome: isIncome)
        let account = extractAccount(from: text)

        var confidence = 0.4
        if money.hadCurrency { confidence += 0.2 }
        if direction != nil { confidence += 0.2 }
        if merchant != nil { confidence += 0.2 }

        return ParsedTransaction(amount: money.value,
                                 currency: money.currency,
                                 merchant: merchant,
                                 account: account,
                                 isIncome: isIncome,
                                 confidence: min(confidence, 1))
    }

    /// Parses an amount string handed over by Shortcuts, e.g. "AED 45.00", "$12.50", "12,50 €", "1200".
    static func parseAmountString(_ s: String, defaultCurrency: String) -> (value: Double, currency: String)? {
        if let m = extractAmount(from: s, defaultCurrency: defaultCurrency, skipBalanceCheck: true) {
            return (m.value, m.currency)
        }
        // Bare number (possibly with European decimal comma).
        let cleaned = s.filter { "0123456789.,".contains($0) }
        guard let value = number(from: cleaned) else { return nil }
        return (value, defaultCurrency)
    }

    // MARK: Direction

    enum Direction { case debit, credit }

    private static let debitWords = [
        "debited", "debit", "spent", "purchase", "purchased", "paid", "payment of", "payment to",
        "withdrawn", "withdrawal", "charged", "sent", "transferred to", "trf to", "used at",
        "used for", "using your", "txn of", "transaction of", "pos ", "deducted", "dr."
    ]
    private static let creditWords = [
        "credited", "received", "refund", "refunded", "deposited", "cashback", "reversed",
        "reversal", "added to your", "cr."
    ]

    static func detectDirection(_ lower: String) -> Direction? {
        func firstIndex(_ words: [String]) -> String.Index? {
            words.compactMap { lower.range(of: $0)?.lowerBound }.min()
        }
        let d = firstIndex(debitWords)
        let c = firstIndex(creditWords)
        switch (d, c) {
        case let (d?, c?): return d <= c ? .debit : .credit
        case (_?, nil): return .debit
        case (nil, _?): return .credit
        default: return nil
        }
    }

    // MARK: Filters

    private static func isNonTransactional(_ lower: String) -> Bool {
        let blockers = [
            "otp", "one time password", "one-time password", "verification code", "do not share",
            "will be debited", "is due", "due date", "minimum amount due", "payment due",
            "request money", "has requested", "requested money", "e-mandate", "auto-pay scheduled",
            "statement is ready", "statement generated"
        ]
        return blockers.contains { lower.contains($0) }
    }

    private static func looksPromotional(_ lower: String) -> Bool {
        ["% off", "offer", "discount", "win ", "cashback upto", "shop now", "click", "http"].contains { lower.contains($0) }
    }

    // MARK: Amount

    struct Money { var value: Double; var currency: String; var hadCurrency: Bool }

    /// Ordered longest-first so "US$" wins over "$" and "Dhs" over "Dh".
    private static let currencyTokens: [(token: String, code: String?)] = [
        ("US$", "USD"), ("USD", "USD"), ("INR", "INR"), ("Rs.", "INR"), ("Rs", "INR"), ("₹", "INR"),
        ("AED", "AED"), ("Dhs.", "AED"), ("Dhs", "AED"), ("Dh.", "AED"), ("Dh", "AED"),
        ("PKR", "PKR"), ("SAR", "SAR"), ("QAR", "QAR"), ("OMR", "OMR"), ("KWD", "KWD"), ("BHD", "BHD"),
        ("EUR", "EUR"), ("€", "EUR"), ("GBP", "GBP"), ("£", "GBP"), ("CAD", "CAD"), ("AUD", "AUD"),
        ("SGD", "SGD"), ("MYR", "MYR"), ("RM", "MYR"), ("JPY", "JPY"), ("¥", "JPY"), ("NGN", "NGN"),
        ("₦", "NGN"), ("KES", "KES"), ("ZAR", "ZAR"), ("LKR", "LKR"), ("BDT", "BDT"), ("Tk", "BDT"),
        ("NPR", "NPR"), ("EGP", "EGP"), ("TRY", "TRY"), ("PHP", "PHP"), ("₱", "PHP"),
        ("$", nil) // ambiguous dollar → resolved against default currency
    ]

    private static let currencyAlternation: String = currencyTokens
        .map { NSRegularExpression.escapedPattern(for: $0.token) }
        .joined(separator: "|")

    private static let numberPattern = #"[0-9]{1,3}(?:[,][0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?"#

    private static let currencyFirst = try! NSRegularExpression(
        pattern: "(?<![A-Za-z])(\(currencyAlternation))\\s?(\(numberPattern))(?![0-9])",
        options: [.caseInsensitive])

    private static let amountFirst = try! NSRegularExpression(
        pattern: "(?<![0-9.,])(\(numberPattern))\\s?(\(currencyAlternation))(?![A-Za-z])",
        options: [.caseInsensitive])

    /// "debited by 500", "spent 23.10" – used only when no currency symbol exists.
    private static let keywordAmount = try! NSRegularExpression(
        pattern: "(?:debited|credited|spent|paid|charged|withdrawn|amount|amt)\\s*(?:by|with|of|for|:)?\\s*(\(numberPattern))(?![0-9])",
        options: [.caseInsensitive])

    static func extractAmount(from text: String, defaultCurrency: String, skipBalanceCheck: Bool = false) -> Money? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var candidates: [(location: Int, value: Double, token: String)] = []
        for m in currencyFirst.matches(in: text, range: full) {
            if let v = number(from: ns.substring(with: m.range(at: 2))) {
                candidates.append((m.range.location, v, ns.substring(with: m.range(at: 1))))
            }
        }
        for m in amountFirst.matches(in: text, range: full) {
            if let v = number(from: ns.substring(with: m.range(at: 1))) {
                candidates.append((m.range.location, v, ns.substring(with: m.range(at: 2))))
            }
        }
        candidates.sort { $0.location < $1.location }

        let lower = text.lowercased() as NSString
        for c in candidates where c.value > 0 {
            if !skipBalanceCheck {
                // Skip "Avl Bal: Rs 10,000" / "credit limit AED 5000" style numbers.
                let start = max(0, c.location - 28)
                let context = lower.substring(with: NSRange(location: start, length: c.location - start))
                if ["bal", "balance", "limit", "avl", "available", "outstanding"].contains(where: { context.contains($0) }) {
                    continue
                }
            }
            return Money(value: c.value, currency: resolve(token: c.token, defaultCurrency: defaultCurrency), hadCurrency: true)
        }

        if let m = keywordAmount.firstMatch(in: text, range: full),
           let v = number(from: ns.substring(with: m.range(at: 1))), v > 0 {
            return Money(value: v, currency: defaultCurrency, hadCurrency: false)
        }
        return nil
    }

    private static func resolve(token: String, defaultCurrency: String) -> String {
        let t = token.lowercased()
        if let match = currencyTokens.first(where: { $0.token.lowercased() == t }), let code = match.code {
            return code
        }
        // Plain "$": keep the user's currency if it is a dollar currency.
        return ["USD", "CAD", "AUD", "SGD", "NZD", "HKD"].contains(defaultCurrency) ? defaultCurrency : "USD"
    }

    /// "1,234.50" → 1234.5, "12,50" → 12.5, "1,00,000" → 100000
    static func number(from raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("."), let comma = s.lastIndex(of: ","),
           s.distance(from: comma, to: s.endIndex) == 3, s.filter({ $0 == "," }).count == 1,
           s.distance(from: s.startIndex, to: comma) <= 3, Int(s[s.index(after: comma)...]) != nil,
           s[s.index(after: comma)...].count == 2 {
            // European decimal comma, e.g. "12,50"
            s = s.replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        return Double(s)
    }

    // MARK: Merchant

    private static let stopWords = #"(?=\s+(?:on|via|using|with|ref|refno|ref no|for|from|dated|date|avl|avail|available|bal|balance|txn|transaction|card|a/c|upi|by|is|has|at)\b|\s+\d{1,2}[-/.]\d{1,2}|[.,;:!()\n]\s|[;!()\n]|\.$|,|$)"#
    private static let nameChars = #"([A-Za-z0-9][A-Za-z0-9&'*@._\-/ ]{1,45}?)"#

    private static let debitMerchantPatterns: [NSRegularExpression] = ([String]([
        #"\b(?:at|@)\s+"# + nameChars + stopWords,
        #"\b(?:to\s+vpa|vpa|paid\s+to|payment\s+to|transfer(?:red)?\s+to|trf\s+to|sent\s+to|towards|to)\s+"# + nameChars + stopWords,
        #"\binfo[:\-\s]+"# + nameChars + stopWords,
        #"\bon\s+"# + nameChars + #"(?=\s+(?:on|using|with|via)\b)"#
    ])).map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let creditMerchantPatterns: [NSRegularExpression] = ([String]([
        #"\b(?:from|by)\s+(?:vpa\s+)?"# + nameChars + stopWords,
        #"\binfo[:\-\s]+"# + nameChars + stopWords
    ])).map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func extractMerchant(from text: String, isIncome: Bool) -> String? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for regex in (isIncome ? creditMerchantPatterns : debitMerchantPatterns) {
            for m in regex.matches(in: text, range: full) {
                let candidate = clean(ns.substring(with: m.range(at: 1)))
                if isPlausibleMerchant(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func clean(_ s: String) -> String {
        var out = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-*:/"))
        // UPI handle "swiggy@icici" → "swiggy"
        if out.contains("@"), !out.contains(" "), let handle = out.split(separator: "@").first {
            out = String(handle)
        }
        // Collapse whitespace.
        out = out.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        // Title-case shouty merchant names: "CARREFOUR DUBAI" → "Carrefour Dubai"
        if out == out.uppercased(), out.count > 3 {
            out = out.capitalized
        }
        return out
    }

    private static func isPlausibleMerchant(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard s.count >= 2, s.rangeOfCharacter(from: .letters) != nil else { return false }
        let banned = ["your", "you", "a/c", "ac ", "acct", "account", "card", "the", "be", "us", "avoid",
                      "call", "sms", "block", "report", "dispute", "customer", "bank", "self"]
        if banned.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return false }
        // Pure account mask like "XX1234"
        if lower.range(of: #"^[x*]+\d+$"#, options: .regularExpression) != nil { return false }
        return true
    }

    // MARK: Account

    private static let accountPatterns: [NSRegularExpression] = ([String]([
        #"(?:card|a/c|acct|account|ac)\s*(?:no\.?|number|ending|ending\s+(?:with|in)|ending:)?\s*[:#]?\s*[xX*•.]*\s*(\d{3,4})\b"#,
        #"[xX*•]{2,}\s?(\d{3,4})\b"#
    ])).map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func extractAccount(from text: String) -> String? {
        let ns = text as NSString
        for regex in accountPatterns {
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }
}
