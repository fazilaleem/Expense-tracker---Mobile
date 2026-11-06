import SwiftUI
import SwiftData

struct TransactionsView: View {
    var onlyReview = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var search = ""
    @State private var categoryFilter: ExpenseCategory?
    @State private var showingAdd = false

    private var filtered: [Expense] {
        expenses.filter { e in
            (!onlyReview || e.needsReview) &&
            (categoryFilter == nil || e.category == categoryFilter) &&
            (search.isEmpty || e.merchant.localizedCaseInsensitiveContains(search)
                || (e.note ?? "").localizedCaseInsensitiveContains(search)
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

    var body: some View {
        let list = List {
            if filtered.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView(onlyReview ? "All caught up" : "No transactions",
                                           systemImage: onlyReview ? "checkmark.seal" : "tray")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
            ForEach(grouped) { group in
                Section {
                    ForEach(group.items) { e in
                        NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                            .swipeActions(edge: .leading) {
                                if e.needsReview {
                                    Button { e.needsReview = false } label: { Label("Looks good", systemImage: "checkmark") }
                                        .tint(.green)
                                }
                            }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(group.items[i]) }
                        try? context.save()
                    }
                } header: {
                    HStack {
                        Text(group.day.formatted(.dateTime.weekday(.wide).day().month()))
                        Spacer()
                        let spent = group.items.filter { !$0.isIncome }
                        if let cur = spent.first?.currency {
                            Text(Formatters.money(spent.filter { $0.currency == cur }.reduce(0) { $0 + $1.amount }, cur))
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Merchant, note or SMS text")
        .navigationTitle(onlyReview ? "Needs review" : "Transactions")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("All categories") { categoryFilter = nil }
                    ForEach(ExpenseCategory.allCases) { c in
                        Button { categoryFilter = c } label: { Label(c.rawValue, systemImage: c.symbol) }
                    }
                } label: {
                    Image(systemName: categoryFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { ExpenseEditView(expense: nil) }

        if onlyReview { list } else { NavigationStack { list } }
    }
}
