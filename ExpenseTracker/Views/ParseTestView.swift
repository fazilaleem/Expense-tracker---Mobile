import SwiftUI

/// Paste any bank SMS / notification to record it manually or to test the parser.
struct ParseTestView: View {
    @State private var text = ""
    @State private var resultMessage: String?
    @FocusState private var focused: Bool

    private var preview: ParsedTransaction? {
        TransactionParser.parse(text, defaultCurrency: AppSettings.defaultCurrency)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste a bank SMS or notification…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                    HStack {
                        Button {
                            if let s = UIPasteboard.general.string { text = s }
                        } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        Spacer()
                        if !text.isEmpty {
                            Button("Clear", role: .destructive) { text = ""; resultMessage = nil }
                        }
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text("Useful for older messages, or to check how a new bank's format is read before you automate it.")
                }

                if !text.isEmpty {
                    Section("Detected") {
                        if let p = preview {
                            LabeledContent("Amount", value: Formatters.money(p.amount, p.currency))
                            LabeledContent("Type", value: p.isIncome ? "Income / credit" : "Expense / debit")
                            LabeledContent("Merchant", value: p.merchant ?? "—")
                            LabeledContent("Category", value: Categorizer.categorize(merchant: p.merchant, text: text, isIncome: p.isIncome).rawValue)
                            LabeledContent("Card / account", value: p.account.map { "••\($0)" } ?? "—")
                            LabeledContent("Confidence", value: "\(Int(p.confidence * 100))%")
                            Button {
                                let r = ExpenseStore.logMessage(text, sender: nil, source: .sms)
                                resultMessage = r.summary
                                if case .ignored = r {} else { text = "" }
                                focused = false
                            } label: {
                                Label("Record this transaction", systemImage: "plus.circle.fill")
                            }
                        } else {
                            Label("No transaction found (OTPs, promos and payment reminders are ignored).",
                                  systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let msg = resultMessage {
                    Section { Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Paste SMS")
        }
    }
}
