import SwiftUI
import SwiftData

struct TransactionsView: View {
    var onlyReview = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @State private var search = ""
    @State private var categoryFilter: CategoryStyle?
    @State private var showingAdd = false
    @State private var showingPaste = false
    @State private var editingSheet: Expense?

    private var filtered: [Expense] {
        expenses.filter { e in
            (!onlyReview || e.needsReview) &&
            (categoryFilter == nil || e.categoryRaw == categoryFilter?.rawValue) &&
            (search.isEmpty || e.merchant.localizedCaseInsensitiveContains(search)
                || (e.note ?? "").localizedCaseInsensitiveContains(search)
                || (e.bank ?? "").localizedCaseInsensitiveContains(search)
                || (e.rawText ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Expense]
        var id: Date { day }
    }

    private var grouped: [DayGroup] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// Categories that actually have transactions, most used first.
    private var usedCategories: [CategoryStyle] {
        Dictionary(grouping: expenses, by: \.categoryRaw)
            .sorted { $0.value.count > $1.value.count }
            .map { CategoryStyle.of($0.key) }
    }

    private var filteredSpend: Double {
        filtered.filter { !$0.isIncome && $0.currency == currency }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        let list = List {
            if !onlyReview && usedCategories.count > 1 {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if (search.isEmpty == false || categoryFilter != nil) && !filtered.isEmpty {
                HStack {
                    Text("\(filtered.count) results")
                    Spacer()
                    Text(Formatters.money(filteredSpend, currency)).fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }

            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(grouped) { group in
                Section {
                    ForEach(group.items) { e in
                        NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                            .listRowBackground(Theme.card)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
                            .swipeActions(edge: .leading) {
                                if e.needsReview {
                                    Button {
                                        withAnimation { e.needsReview = false }
                                    } label: { Label("Looks good", systemImage: "checkmark") }
                                        .tint(Theme.emerald)
                                }
                                Button { editingSheet = e } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(Color(light: 0x3B82F6, dark: 0x60A5FA))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { context.delete(e); try? context.save() }
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    withAnimation { _ = ExpenseStore.duplicate(e) }
                                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    .tint(Color(light: 0x8B5CF6, dark: 0xA78BFA))
                            }
                            .contextMenu {
                                Button { editingSheet = e } label: { Label("Edit", systemImage: "pencil") }
                                Button { withAnimation { _ = ExpenseStore.duplicate(e) } } label: {
                                    Label("Duplicate as today", systemImage: "plus.square.on.square")
                                }
                                if e.needsReview {
                                    Button { withAnimation { e.needsReview = false } } label: {
                                        Label("Mark as reviewed", systemImage: "checkmark.circle")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    withAnimation { context.delete(e); try? context.save() }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: {
                    dayHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .themedBackground()
        .animation(.snappy, value: categoryFilter)
        .searchable(text: $search, prompt: "Merchant, bank, note or SMS text")
        .navigationTitle(onlyReview ? "To review" : "Transactions")
        .toolbar {
            if !onlyReview {
                ToolbarItem(placement: .topBarTrailing) {
                    AddMenu(showingAdd: $showingAdd, showingPaste: $showingPaste)
                }
            }
        }
        .sheet(isPresented: $showingAdd) { ExpenseEditView(expense: nil) }
        .sheet(isPresented: $showingPaste) { ParseTestView(isSheet: true) }
        .sheet(item: $editingSheet) { e in ExpenseEditView(expense: e, presentedAsSheet: true) }
        .sensoryFeedback(.selection, trigger: categoryFilter)

        if onlyReview { list } else { NavigationStack { list } }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(title: "All", symbol: "square.grid.2x2", color: Theme.emerald,
                           selected: categoryFilter == nil) { categoryFilter = nil }
                ForEach(usedCategories) { c in
                    FilterChip(title: c.shortName, symbol: c.symbol, color: c.color,
                               selected: categoryFilter == c) {
                        categoryFilter = (categoryFilter == c) ? nil : c
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        let spent = group.items.filter { !$0.isIncome && $0.currency == currency }.reduce(0) { $0 + $1.amount }
        return HStack {
            Text(dayTitle(group.day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if spent > 0 {
                Text(Formatters.money(spent, currency))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        .textCase(nil)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if cal.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
        return day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if onlyReview {
            ContentUnavailableView("All caught up", systemImage: "checkmark.seal.fill",
                                   description: Text("Nothing needs reviewing."))
                .foregroundStyle(Theme.emerald)
        } else {
            ContentUnavailableView("No transactions", systemImage: "tray",
                                   description: Text("Bank SMS and Apple Pay payments will appear here automatically."))
        }
    }
}

/// "+" button offering manual entry or pasting a bank SMS.
struct AddMenu: View {
    @Binding var showingAdd: Bool
    @Binding var showingPaste: Bool
    @State private var showingVoice = false
    @State private var showingScan = false
    var body: some View {
        Menu {
            Button { showingAdd = true } label: { Label("Add expense manually", systemImage: "square.and.pencil") }
            Button { showingVoice = true } label: { Label("Speak an expense", systemImage: "mic.fill") }
            Button { showingScan = true } label: { Label("Scan a receipt", systemImage: "doc.viewfinder") }
            Button { showingPaste = true } label: { Label("Paste bank SMS", systemImage: "doc.on.clipboard") }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Theme.emeraldSoft, in: Circle())
        }
        .accessibilityLabel("Add expense")
        .sheet(isPresented: $showingVoice) { VoiceEntryView().presentationDetents([.medium, .large]) }
        .fullScreenCover(isPresented: $showingScan) { ReceiptScanView() }
    }
}

struct FilterChip: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : .primary)
            .background {
                Capsule().fill(selected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Theme.card))
            }
            .overlay(Capsule().strokeBorder(selected ? .clear : Theme.cardStroke))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
    }
}
