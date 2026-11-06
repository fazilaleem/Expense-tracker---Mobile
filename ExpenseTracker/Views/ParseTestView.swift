import SwiftUI

/// Paste any bank SMS / notification to record it manually or to test the parser.
struct ParseTestView: View {
    var isSheet = false
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var resultMessage: String?
    @State private var recorded = false
    @FocusState private var focused: Bool

    private var preview: ParsedTransaction? {
        TransactionParser.parse(text, defaultCurrency: AppSettings.defaultCurrency)
    }

    var body: some View {
        if isSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
            ScrollView {
                VStack(spacing: 16) {
                    inputCard.appearAnimation()
                    if !text.isEmpty {
                        resultCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let msg = resultMessage {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.emerald)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 14)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .padding(16)
                .animation(.snappy, value: text.isEmpty)
                .animation(.snappy, value: resultMessage)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedBackground()
            .navigationTitle("Paste bank SMS")
            .navigationBarTitleDisplayMode(isSheet ? .inline : .large)
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
            }
            .sensoryFeedback(.success, trigger: recorded)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Paste a bank SMS or notification…", text: $text, axis: .vertical)
                .lineLimit(4...10)
                .focused($focused)
                .padding(12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { text = s; resultMessage = nil }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.emerald)
                Spacer()
                if !text.isEmpty {
                    Button("Clear") { text = ""; resultMessage = nil }
                        .buttonStyle(.bordered)
                }
            }
            Text("Use this for older messages, or to check that a new bank's format is read correctly before you automate it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder private var resultCard: some View {
        if let p = preview {
            let category = Categorizer.categorize(merchant: p.merchant, text: text, isIncome: p.isIncome)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "Detected")
                    Pill(text: "\(Int(p.confidence * 100))% sure",
                         symbol: p.confidence >= 0.8 ? "checkmark.seal.fill" : "questionmark.circle",
                         color: p.confidence >= 0.8 ? Theme.emerald : Theme.warning)
                }
                HStack(spacing: 14) {
                    IconTile(symbol: category.symbol, color: category.color, size: 52, filled: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.merchant ?? "Unknown merchant").font(.headline)
                        Text(category.rawValue).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((p.isIncome ? "+" : "−") + Formatters.money(p.amount, p.currency))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(p.isIncome ? Theme.income : .primary)
                }
                HStack(spacing: 8) {
                    Pill(text: p.isIncome ? "Income" : "Expense",
                         symbol: p.isIncome ? "arrow.down.left" : "arrow.up.right",
                         color: p.isIncome ? Theme.income : .secondary)
                    if let acc = p.account { Pill(text: "••\(acc)", symbol: "creditcard", color: .secondary) }
                }
                Button {
                    let r = ExpenseStore.logMessage(text, sender: nil, source: .sms)
                    resultMessage = r.summary
                    if case .ignored = r {} else { text = ""; recorded.toggle() }
                    focused = false
                } label: {
                    Label("Record transaction", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.emerald)
            }
            .card()
        } else {
            HStack(spacing: 12) {
                IconTile(symbol: "text.magnifyingglass", color: .secondary, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No transaction found").font(.subheadline.weight(.semibold))
                    Text("OTPs, promotions and payment reminders are ignored on purpose.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }
}
