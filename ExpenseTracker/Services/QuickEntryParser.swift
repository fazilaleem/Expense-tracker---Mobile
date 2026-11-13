import Foundation

/// Values used to pre-fill the add-expense screen (from voice or a scanned receipt).
struct ExpensePrefill: Equatable {
    var amount: Double?
    var currency: String?
    var merchant: String?
    var category: ExpenseCategory?
    var note: String?
    var date: Date?
    var categoryRaw: String?
    var bank: String?
    var account: String?
    var rawText: String?
    var photo: Data?
}

/// Turns a spoken phrase into an expense, e.g.
/// "2.5 dinars coffee at Costa", "spent 45 on groceries", "taxi 3 BD", "fuel 12 dinar ENOC".
enum VoiceParser {
    private static let spokenCurrencies: [(String, String)] = [
        ("bahraini dinars", "BHD"), ("bahraini dinar", "BHD"), ("kuwaiti dinars", "KWD"), ("kuwaiti dinar", "KWD"),
        ("dirhams", "AED"), ("dirham", "AED"), ("riyals", "SAR"), ("riyal", "SAR"), ("rupees", "INR"), ("rupee", "INR"),
        ("dollars", "USD"), ("dollar", "USD"), ("euros", "EUR"), ("euro", "EUR"), ("pounds", "GBP"), ("pound", "GBP")
    ]
    private static let fillers: Set<String> = ["i", "spent", "spend", "paid", "pay", "for", "on", "at", "the", "a", "an",
                                               "to", "in", "from", "of", "and", "my", "add", "expense", "bought", "buy",
                                               "dinar", "dinars", "fils", "bd", "kd", "bhd", "kwd"]

    static func parse(_ phrase: String, defaultCurrency: String) -> ExpensePrefill {
        var text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        var lower = text.lowercased()
        var prefill = ExpensePrefill()

        // "dinars" alone → the user's own dinar currency if it is one, else BHD.
        var currency: String?
        for (word, code) in spokenCurrencies where lower.contains(word) { currency = code; break }
        if currency == nil, lower.range(of: #"\bdinars?\b"#, options: .regularExpression) != nil {
            currency = ["BHD", "KWD", "JOD", "IQD"].contains(defaultCurrency) ? defaultCurrency : "BHD"
        }

        // Amount: currency-tagged first, then the first number.
        if let money = TransactionParser.extractAmount(from: text, defaultCurrency: currency ?? defaultCurrency,
                                                        skipBalanceCheck: true), money.hadCurrency {
            prefill.amount = money.value
            prefill.currency = money.currency
        } else if let r = text.range(of: #"\d+(?:[.,]\d{1,3})?"#, options: .regularExpression),
                  let v = TransactionParser.number(from: String(text[r])) {
            prefill.amount = v
            prefill.currency = currency ?? defaultCurrency
            text.removeSubrange(r)
            lower = text.lowercased()
        }

        // Merchant: words after "at" / "from"; otherwise the remaining meaningful words.
        if let r = lower.range(of: #"\b(?:at|from)\s+(.+)$"#, options: .regularExpression) {
            let tail = String(text[r]).split(separator: " ").dropFirst().joined(separator: " ")
            prefill.merchant = clean(tail)
        }
        let words = text.split(whereSeparator: { !$0.isLetter && $0 != "&" && $0 != "'" })
            .map(String.init)
            .filter { word in
                let w = word.lowercased()
                return !fillers.contains(w) && !spokenCurrencies.contains(where: { pair in pair.0.contains(w) })
            }
        let description = words.joined(separator: " ")
        if prefill.merchant == nil, !description.isEmpty { prefill.merchant = clean(description) }

        let category = Categorizer.categorize(merchant: prefill.merchant, text: lower, isIncome: false)
        prefill.category = category == .other ? nil : category
        prefill.note = phrase
        return prefill
    }

    private static func clean(_ s: String) -> String? {
        let words = s.split(separator: " ").filter { !fillers.contains($0.lowercased()) }
        let out = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return out.isEmpty ? nil : out.prefix(1).uppercased() + out.dropFirst()
    }
}

/// Finds merchant, total and date in OCR'd receipt text lines.
enum ReceiptParser {
    private static let totalWords = ["grand total", "total amount", "amount due", "total due", "net total",
                                     "total payable", "balance due", "total", "net amount", "amount"]
    private static let skipWords = ["subtotal", "sub total", "sub-total", "vat", "tax", "discount", "change", "cash", "tendered",
                                    "card no", "tel", "phone", "invoice", "receipt no", "qty"]

    static func parse(lines rawLines: [String], defaultCurrency: String) -> ExpensePrefill {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var prefill = ExpensePrefill()

        // Currency mentioned anywhere on the receipt.
        let joined = lines.joined(separator: "\n")
        if let m = TransactionParser.extractAmount(from: joined, defaultCurrency: defaultCurrency, skipBalanceCheck: true),
           m.hadCurrency {
            prefill.currency = m.currency
        }

        // 1) A line with a "total" keyword (best-ranked keyword wins; amount may be on the next line).
        var best: (rank: Int, value: Double)?
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard let rank = totalWords.firstIndex(where: { lower.contains($0) }),
                  !skipWords.contains(where: { lower.contains($0) && !lower.contains("total") }) else { continue }
            if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("sub-total") { continue }
            let value = lastNumber(in: line) ?? (i + 1 < lines.count ? lastNumber(in: lines[i + 1]) : nil)
            if let value, value > 0, best == nil || rank < best!.rank || (rank == best!.rank && value > best!.value) {
                best = (rank, value)
            }
        }
        // 2) Otherwise the largest money-looking number.
        if let best {
            prefill.amount = best.value
        } else {
            prefill.amount = lines.compactMap { line -> Double? in
                guard line.range(of: #"\d+[.,]\d{2,3}\b"#, options: .regularExpression) != nil else { return nil }
                return lastNumber(in: line)
            }.max()
        }

        // Merchant: first line that is mostly letters (usually the store name at the top).
        prefill.merchant = lines.prefix(6).first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.6
                && !skipWords.contains(where: { line.lowercased().contains($0) })
                && !line.lowercased().contains("welcome")
        }.map { $0.count > 3 && $0 == $0.uppercased() ? $0.capitalized : $0 }

        // Date like 07/11/2026, 07-11-26, 2026-11-07.
        prefill.date = firstDate(in: joined)

        if let m = prefill.merchant {
            let c = Categorizer.categorize(merchant: m, text: joined.lowercased(), isIncome: false)
            prefill.category = c == .other ? nil : c
        }
        prefill.note = "Scanned receipt"
        return prefill
    }

    static func lastNumber(in line: String) -> Double? {
        let ns = line as NSString
        let regex = try! NSRegularExpression(pattern: #"\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?|\d+(?:[.,]\d{1,3})?"#)
        guard let m = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return TransactionParser.number(from: ns.substring(with: m.range))
    }

    private static func firstDate(in text: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"\b\d{4}-\d{2}-\d{2}\b"#, "yyyy-MM-dd"),
            (#"\b\d{2}/\d{2}/\d{4}\b"#, "dd/MM/yyyy"),
            (#"\b\d{2}-\d{2}-\d{4}\b"#, "dd-MM-yyyy"),
            (#"\b\d{2}/\d{2}/\d{2}\b"#, "dd/MM/yy")
        ]
        for (pattern, format) in patterns {
            if let r = text.range(of: pattern, options: .regularExpression) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = format
                if let d = f.date(from: String(text[r])), d <= .now { return d }
            }
        }
        return nil
    }
}
