import SwiftUI
import SwiftData

/// Add a new expense (expense == nil) or edit an existing one.
struct ExpenseEditView: View {
    let expense: Expense?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double?
    @State private var currency = AppSettings.defaultCurrency
    @State private var merchant = ""
    @State private var category: ExpenseCategory = .other
    @State private var userPickedCategory = false
    @State private var date = Date.now
    @State private var isIncome = false
    @State private var note = ""
    @State private var rememberCategory = true
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saved = false
    @FocusState private var amountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        if expense == nil {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                amountHeader.appearAnimation()
                detailsCard.appearAnimation(delay: 0.05)
                categoryCard.appearAnimation(delay: 0.1)
                if let e = expense { sourceCard(e).appearAnimation(delay: 0.15) }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .navigationTitle(expense == nil ? "New expense" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if expense == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled((amount ?? 0) <= 0)
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let e = expense {
                    context.delete(e)
                    try? context.save()
                }
                dismiss()
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.selection, trigger: category)
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var amountHeader: some View {
        VStack(spacing: 14) {
            Picker("Type", selection: $isIncome.animation(.snappy)) {
                Text("Expense").tag(false)
                Text("Income").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(currency)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                TextField("0", value: $amount, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(isIncome ? Theme.income : .primary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .card()
        .onTapGesture { amountFocused = true }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            fieldRow(symbol: "storefront", color: Theme.emerald) {
                TextField(isIncome ? "From" : "Merchant", text: $merchant)
                    .textInputAutocapitalization(.words)
                    .onChange(of: merchant) { _, new in
                        guard !userPickedCategory, expense == nil else { return }
                        let guess = Categorizer.categorize(merchant: new, text: nil, isIncome: isIncome)
                        if guess != category { withAnimation(.snappy) { category = guess } }
                    }
            }
            Divider().padding(.leading, 48)
            fieldRow(symbol: "calendar", color: Color(light: 0x3B82F6, dark: 0x60A5FA)) {
                DatePicker("Date", selection: $date).labelsHidden()
                Spacer()
            }
            Divider().padding(.leading, 48)
            fieldRow(symbol: "text.alignleft", color: Color(light: 0x8B5CF6, dark: 0xA78BFA)) {
                TextField("Add a note", text: $note, axis: .vertical)
            }
        }
        .card(padding: 6)
    }

    private func fieldRow<C: View>(symbol: String, color: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 32)
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Category")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ExpenseCategory.allCases.filter { $0 != .income || isIncome }) { c in
                    Button {
                        userPickedCategory = true
                        withAnimation(.snappy) { category = c }
                    } label: {
                        VStack(spacing: 6) {
                            IconTile(symbol: c.symbol, color: c.color, size: 44, filled: category == c)
                                .scaleEffect(category == c ? 1.06 : 1)
                            Text(c.shortName)
                                .font(.caption2.weight(category == c ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundStyle(category == c ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            let name = merchant.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !isIncome {
                Toggle(isOn: $rememberCategory) {
                    Text("Always use this category for “\(name)”").font(.footnote)
                }
                .tint(Theme.emerald)
            }
        }
        .card()
    }

    private func sourceCard(_ e: Expense) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Source")
            HStack(spacing: 8) {
                Pill(text: e.source.label, symbol: e.source.symbol)
                if let acc = e.account { Pill(text: "••\(acc)", symbol: "creditcard", color: .secondary) }
                if let sender = e.sender { Pill(text: sender, symbol: "person", color: .secondary) }
            }
            if let raw = e.rawText {
                Text(raw)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete transaction", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
        }
        .card()
    }

    // MARK: Logic

    private var currencies: [String] {
        var list = AppSettings.commonCurrencies
        if !list.contains(currency) { list.insert(currency, at: 0) }
        return list
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = expense else {
            amountFocused = true
            return
        }
        amount = e.amount
        currency = e.currency
        merchant = e.merchant
        category = e.category
        userPickedCategory = true
        date = e.date
        isIncome = e.isIncome
        note = e.note ?? ""
    }

    private func save() {
        guard let value = amount, value > 0 else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let finalCategory: ExpenseCategory = isIncome && !userPickedCategory ? .income : category
        if let e = expense {
            if rememberCategory && !name.isEmpty && !isIncome && e.category != finalCategory && finalCategory != .other {
                Categorizer.learn(merchant: name, category: finalCategory)
            }
            e.amount = value
            e.currency = currency
            e.merchant = name
            e.category = finalCategory
            e.date = date
            e.isIncome = isIncome
            e.note = note.isEmpty ? nil : note
            e.needsReview = false
        } else {
            ExpenseStore.save(Expense(amount: value, currency: currency, merchant: name.isEmpty ? "Cash" : name,
                                      category: finalCategory, date: date, source: .manual,
                                      isIncome: isIncome, note: note.isEmpty ? nil : note))
            if rememberCategory && userPickedCategory && !name.isEmpty && !isIncome && finalCategory != .other {
                Categorizer.learn(merchant: name, category: finalCategory)
            }
        }
        try? context.save()
        saved.toggle()
        dismiss()
    }
}
