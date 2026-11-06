import Foundation

enum Formatters {
    static func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(currency == "JPY" ? 0 : 2)))
    }

    static func compactMoney(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

enum CSVExporter {
    static func export(_ expenses: [Expense]) -> URL {
        var rows = ["Date,Merchant,Category,Amount,Currency,Type,Source,Bank,Account,Note,Raw Text"]
        let df = ISO8601DateFormatter()
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            rows.append([
                df.string(from: e.date),
                e.merchant,
                e.category.rawValue,
                String(format: "%.2f", e.amount),
                e.currency,
                e.isIncome ? "Income" : "Expense",
                e.source.label,
                e.bank ?? "",
                e.account ?? "",
                e.note ?? "",
                e.rawText ?? ""
            ].map(escape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expenses-\(Int(Date().timeIntervalSince1970)).csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ field: String) -> String {
        let f = field.replacingOccurrences(of: "\"", with: "\"\"")
        return f.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(f)\"" : f
    }
}
