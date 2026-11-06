import SwiftUI
import SwiftData

/// Add a new expense (expense == nil) or edit an existing one.
struct ExpenseEditView: View {
    let expense: Expense?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 0
    @State private var currency = AppSettings.defaultCurrency
    @State private var merchant = ""
    @State private var category: ExpenseCategory = .other
    @State private var date = Date.now
    @State private var isIncome = false
    @State private var note = ""
    @State private var rememberCategory = true
    @State private var loaded = false

    var body: some View {
        if expense == nil {
            NavigationStack { form }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack {
                    Picker("", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                }
                Picker("Type", selection: $isIncome) {
                    Text("Expense").tag(false)
                    Text("Income").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Details") {
                TextField("Merchant", text: $merchant)
                    .onSubmit {
                        if expense == nil && category == .other {
                            category = Categorizer.categorize(merchant: merchant, text: nil, isIncome: isIncome)
                        }
                    }
                Picker("Category", selection: $category) {
                    ForEach(ExpenseCategory.allCases) { c in
                        Label(c.rawValue, systemImage: c.symbol).tag(c)
                    }
                }
                if !merchant.isEmpty {
                    Toggle("Always use this category for “\(merchant)”", isOn: $rememberCategory)
                        .font(.subheadline)
                }
                DatePicker("Date", selection: $date)
                TextField("Note", text: $note, axis: .vertical)
            }

            if let e = expense {
                Section("Source") {
                    LabeledContent("Recorded via", value: e.source.label)
                    if let acc = e.account { LabeledContent("Card / account", value: "••\(acc)") }
                    if let sender = e.sender { LabeledContent("Sender", value: sender) }
                    if let raw = e.rawText {
                        Text(raw).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Section {
                    Button("Delete transaction", role: .destructive) {
                        context.delete(e)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(expense == nil ? "New expense" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if expense == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(amount <= 0)
            }
        }
        .onAppear(perform: load)
    }

    private var currencies: [String] {
        var list = AppSettings.commonCurrencies
        if !list.contains(currency) { list.insert(currency, at: 0) }
        return list
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = expense else { return }
        amount = e.amount
        currency = e.currency
        merchant = e.merchant
        category = e.category
        date = e.date
        isIncome = e.isIncome
        note = e.note ?? ""
    }

    private func save() {
        let name = merchant.trimmingCharacters(in: .whitespaces)
        if let e = expense {
            e.amount = amount
            e.currency = currency
            e.merchant = name
            e.category = category
            e.date = date
            e.isIncome = isIncome
            e.note = note.isEmpty ? nil : note
            e.needsReview = false
        } else {
            ExpenseStore.save(Expense(amount: amount, currency: currency, merchant: name.isEmpty ? "Cash" : name,
                                      category: category, date: date, source: .manual,
                                      isIncome: isIncome, note: note.isEmpty ? nil : note))
        }
        if rememberCategory && !name.isEmpty && !isIncome && category != .other {
            Categorizer.learn(merchant: name, category: category)
        }
        try? context.save()
        dismiss()
    }
}
