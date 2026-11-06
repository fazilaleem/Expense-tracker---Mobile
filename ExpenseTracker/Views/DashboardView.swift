import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @AppStorage(SettingsKey.monthlyBudget) private var budget: Double = 0
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var showingAdd = false

    private var monthExpenses: [Expense] {
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month)!
        return allExpenses.filter { $0.date >= month && $0.date < end }
    }
    private var spending: [Expense] { monthExpenses.filter { !$0.isIncome && $0.currency == currency } }
    private var total: Double { spending.reduce(0) { $0 + $1.amount } }
    private var income: Double { monthExpenses.filter { $0.isIncome && $0.currency == currency }.reduce(0) { $0 + $1.amount } }

    private var otherCurrencyTotals: [(key: String, value: Double)] {
        Dictionary(grouping: monthExpenses.filter { !$0.isIncome && $0.currency != currency }, by: \.currency)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
            .sorted { $0.value > $1.value }
    }

    private var byCategory: [CategoryTotal] {
        Dictionary(grouping: spending, by: \.category)
            .map { CategoryTotal(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var byDay: [DayTotal] {
        Dictionary(grouping: spending) { Calendar.current.startOfDay(for: $0.date) }
            .map { DayTotal(day: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.day < $1.day }
    }

    private var reviewCount: Int { allExpenses.filter(\.needsReview).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthPicker
                    summaryCard
                    if reviewCount > 0 { reviewBanner }
                    if !byCategory.isEmpty { categoryCard }
                    if byDay.count > 1 { dailyCard }
                    recentCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Expenses")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill") }
            }
            .sheet(isPresented: $showingAdd) { ExpenseEditView(expense: nil) }
        }
    }

    private var monthPicker: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .padding(.horizontal, 4)
    }

    private func shift(_ by: Int) {
        month = Calendar.current.date(byAdding: .month, value: by, to: month)!
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spent").font(.subheadline).foregroundStyle(.secondary)
                Text(Formatters.money(total, currency))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                if !otherCurrencyTotals.isEmpty {
                    Text("+ " + otherCurrencyTotals.map { Formatters.money($0.value, $0.key) }.joined(separator: " + "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if budget > 0 {
                    let ratio = total / budget
                    ProgressView(value: min(ratio, 1))
                        .tint(ratio > 1 ? .red : ratio > 0.8 ? .orange : .accentColor)
                    Text(ratio > 1
                         ? "Over budget by \(Formatters.money(total - budget, currency))"
                         : "\(Formatters.money(budget - total, currency)) left of \(Formatters.compactMoney(budget, currency)) budget")
                        .font(.footnote).foregroundStyle(ratio > 1 ? .red : .secondary)
                }
                if income > 0 {
                    Label("Income \(Formatters.money(income, currency))", systemImage: "arrow.down.circle")
                        .font(.footnote).foregroundStyle(.green)
                }
                Text("\(spending.count) transactions").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewBanner: some View {
        NavigationLink {
            TransactionsView(onlyReview: true)
        } label: {
            Card {
                HStack {
                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange)
                    Text("\(reviewCount) transaction\(reviewCount == 1 ? "" : "s") need a quick review")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var categoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("By category").font(.headline)
                Chart(byCategory) { item in
                    SectorMark(angle: .value("Amount", item.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(item.category.color)
                        .cornerRadius(3)
                }
                .frame(height: 190)
                ForEach(byCategory) { item in
                    HStack {
                        Image(systemName: item.category.symbol)
                            .foregroundStyle(item.category.color).frame(width: 24)
                        Text(item.category.rawValue)
                        Spacer()
                        Text(Formatters.money(item.total, currency)).monospacedDigit()
                        Text("\(Int((item.total / max(total, 0.01) * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var dailyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily spending").font(.headline)
                Chart(byDay) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Amount", item.total))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(3)
                }
                .frame(height: 160)
            }
        }
    }

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent").font(.headline).padding(.bottom, 4)
                if monthExpenses.isEmpty {
                    ContentUnavailableView("No transactions yet",
                                           systemImage: "tray",
                                           description: Text("Set up the Shortcuts automations in Settings ▸ Setup guide, or tap + to add one."))
                } else {
                    ForEach(monthExpenses.prefix(6)) { e in
                        NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}

struct CategoryTotal: Identifiable {
    let category: ExpenseCategory
    let total: Double
    var id: ExpenseCategory { category }
}

struct DayTotal: Identifiable {
    let day: Date
    let total: Double
    var id: Date { day }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ExpenseRow: View {
    let expense: Expense
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.symbol)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(expense.category.color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(expense.merchant).font(.body.weight(.medium)).lineLimit(1)
                    if expense.needsReview {
                        Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: expense.source.symbol)
                    Text(expense.date.formatted(date: .abbreviated, time: .shortened))
                    if let acc = expense.account { Text("· ••\(acc)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((expense.isIncome ? "+" : "") + Formatters.money(expense.amount, expense.currency))
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(expense.isIncome ? .green : .primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
