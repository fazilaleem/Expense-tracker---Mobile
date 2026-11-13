import SwiftUI
import SwiftData
import Charts

/// Monthly / yearly summaries with several ways to slice spending.
struct InsightsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency

    enum Scope: String, CaseIterable, Identifiable {
        case month = "Month", year = "Year"
        var id: String { rawValue }
        var component: Calendar.Component { self == .month ? .month : .year }
    }
    enum Breakdown: String, CaseIterable, Identifiable {
        case category = "Category", merchant = "Merchant", bank = "Bank", weekday = "Weekday"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .month
    @State private var anchor = Date.now
    @State private var breakdown: Breakdown = .category
    @State private var selectedBar: Date?

    private let cal = Calendar.current

    // MARK: Periods

    private var interval: DateInterval {
        cal.dateInterval(of: scope.component, for: anchor) ?? DateInterval(start: anchor, duration: 1)
    }
    private var previousInterval: DateInterval {
        let prev = cal.date(byAdding: scope.component, value: -1, to: anchor)!
        return cal.dateInterval(of: scope.component, for: prev)!
    }
    private var isCurrent: Bool { interval.contains(.now) }

    private var periodTitle: String {
        scope == .month
            ? interval.start.formatted(.dateTime.month(.wide).year())
            : interval.start.formatted(.dateTime.year())
    }

    private func items(in i: DateInterval) -> [Expense] {
        all.filter { $0.currency == currency && $0.date >= i.start && $0.date < i.end }
    }
    private var current: [Expense] { items(in: interval) }
    private var spending: [Expense] { current.filter { !$0.isIncome } }
    private var spent: Double { spending.reduce(0) { $0 + $1.amount } }
    private var income: Double { current.filter(\.isIncome).reduce(0) { $0 + $1.amount } }

    /// Previous period up to the same point, so a half-finished month is compared fairly.
    private var change: Double? {
        let elapsed = isCurrent ? Date.now.timeIntervalSince(interval.start) : interval.duration
        let p = DateInterval(start: previousInterval.start, duration: min(elapsed, previousInterval.duration))
        let prev = items(in: p).filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
        guard prev > 0 else { return nil }
        return (spent - prev) / prev
    }

    private var daysElapsed: Int {
        let end = isCurrent ? Date.now : interval.end
        return max(1, (cal.dateComponents([.day], from: interval.start, to: end).day ?? 0) + (isCurrent ? 1 : 0))
    }

    // MARK: Trend

    private struct MonthTotal: Identifiable {
        let month: Date
        let spent: Double
        let income: Double
        let count: Int
        var id: Date { month }
    }

    /// 6 months ending at the selected month, or the 12 months of the selected year.
    private var trend: [MonthTotal] {
        let months: [Date]
        if scope == .month {
            let start = cal.startOfMonth(for: interval.start)
            months = (0..<6).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: start) }
        } else {
            months = (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: interval.start) }
        }
        return months.map { m in
            let i = cal.dateInterval(of: .month, for: m)!
            let list = items(in: i)
            return MonthTotal(month: m,
                              spent: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                              income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                              count: list.count)
        }
    }

    /// Every month that has data, newest first (the "monthly summary" list).
    private var allMonths: [MonthTotal] {
        let grouped = Dictionary(grouping: all.filter { $0.currency == currency }) { cal.startOfMonth(for: $0.date) }
        return grouped.map { m, list in
            MonthTotal(month: m,
                       spent: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                       income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                       count: list.count)
        }
        .sorted { $0.month > $1.month }
    }

    // MARK: Breakdown

    struct Slice: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let color: Color
        let total: Double
        let items: [Expense]
    }

    private var slices: [Slice] {
        let groups: [String: [Expense]]
        switch breakdown {
        case .category: groups = Dictionary(grouping: spending) { $0.categoryRaw }
        case .merchant: groups = Dictionary(grouping: spending) { $0.merchant }
        case .bank: groups = Dictionary(grouping: spending) { ($0.bank?.isEmpty == false ? $0.bank! : "Not set") }
        case .weekday: groups = Dictionary(grouping: spending) { $0.date.formatted(.dateTime.weekday(.wide)) }
        }
        return groups.map { key, list in
            let total = list.reduce(0) { $0 + $1.amount }
            switch breakdown {
            case .category:
                let c = CategoryStyle.of(key)
                return Slice(id: key, title: key, symbol: c.symbol, color: c.color, total: total, items: list)
            case .merchant:
                let c = list.first?.style ?? CategoryStyle.of(ExpenseCategory.other.rawValue)
                return Slice(id: key, title: key, symbol: c.symbol, color: c.color, total: total, items: list)
            case .bank:
                return Slice(id: key, title: key, symbol: key == "Not set" ? "questionmark.circle" : "building.columns.fill",
                             color: key == "Not set" ? .secondary : Color(light: 0x0F766E, dark: 0x2DD4BF),
                             total: total, items: list)
            case .weekday:
                return Slice(id: key, title: key, symbol: "calendar", color: Color(light: 0x3B82F6, dark: 0x60A5FA),
                             total: total, items: list)
            }
        }
        .sorted { $0.total > $1.total }
    }

    private var largest: [Expense] { Array(spending.sorted { $0.amount > $1.amount }.prefix(5)) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controls.appearAnimation()
                    summaryCard.appearAnimation(delay: 0.05)
                    trendCard.appearAnimation(delay: 0.1)
                    if !spending.isEmpty {
                        breakdownCard.appearAnimation(delay: 0.15)
                        largestCard.appearAnimation(delay: 0.2)
                    }
                    monthsCard.appearAnimation(delay: 0.25)
                }
                .padding(16)
                .animation(.snappy, value: anchor)
                .animation(.snappy, value: scope)
                .animation(.snappy, value: breakdown)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationTitle("Insights")
            .sensoryFeedback(.selection, trigger: anchor)
            .sensoryFeedback(.selection, trigger: breakdown)
        }
    }

    // MARK: Sections

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                Spacer()
                Text(periodTitle).font(.headline).contentTransition(.numericText())
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .disabled(isCurrent)
            }
            .font(.body.weight(.semibold))
            .padding(4)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardStroke))
        }
    }

    private func shift(_ by: Int) {
        anchor = cal.date(byAdding: scope.component, value: by, to: anchor)!
        selectedBar = nil
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spent").font(.subheadline).foregroundStyle(.secondary)
                    Text(Formatters.money(spent, currency))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: spent))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer()
                if let change {
                    Pill(text: "\(change >= 0 ? "+" : "−")\(Int((abs(change) * 100).rounded()))%",
                         symbol: change >= 0 ? "arrow.up.right" : "arrow.down.right",
                         color: change > 0.05 ? Theme.danger : Theme.emerald)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metric("Income", Formatters.compactMoney(income, currency), Theme.income)
                metric("Net", (income - spent >= 0 ? "+" : "−") + Formatters.compactMoney(abs(income - spent), currency),
                       income - spent >= 0 ? Theme.income : Theme.danger)
                metric("Per day", Formatters.compactMoney(spent / Double(daysElapsed), currency), .primary)
                metric("Count", "\(spending.count)", .primary)
            }
            if let change {
                Text("\(change >= 0 ? "Up" : "Down") \(Int((abs(change) * 100).rounded()))% compared with the same point last \(scope == .month ? "month" : "year").")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trendCard: some View {
        let data = trend
        let avg = data.isEmpty ? 0 : data.map(\.spent).reduce(0, +) / Double(max(data.filter { $0.spent > 0 }.count, 1))
        let selected = selectedBar.flatMap { d in data.first { cal.isDate($0.month, equalTo: d, toGranularity: .month) } }
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: scope == .month ? "Last 6 months" : "Month by month",
                         trailing: selected.map { "\($0.month.formatted(.dateTime.month(.abbreviated))): \(Formatters.compactMoney($0.spent, currency))" }
                            ?? "avg \(Formatters.compactMoney(avg, currency))")
            Chart(data) { m in
                BarMark(x: .value("Month", m.month, unit: .month), y: .value("Spent", m.spent), width: .ratio(0.6))
                    .foregroundStyle(highlight(m) ? AnyShapeStyle(Theme.emerald.gradient) : AnyShapeStyle(Theme.emerald.opacity(0.3)))
                    .cornerRadius(5)
                if m.income > 0 {
                    PointMark(x: .value("Month", m.month, unit: .month), y: .value("Income", m.income))
                        .symbol(.circle)
                        .symbolSize(30)
                        .foregroundStyle(Color(light: 0x3B82F6, dark: 0x60A5FA))
                }
            }
            .chartXSelection(value: $selectedBar)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
            HStack(spacing: 14) {
                legend("Spent", Theme.emerald)
                legend("Income", Color(light: 0x3B82F6, dark: 0x60A5FA))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func highlight(_ m: MonthTotal) -> Bool {
        if let s = selectedBar { return cal.isDate(m.month, equalTo: s, toGranularity: .month) }
        return scope == .month ? cal.isDate(m.month, equalTo: interval.start, toGranularity: .month) : true
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Breakdown")
            Picker("Breakdown", selection: $breakdown) {
                ForEach(Breakdown.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if breakdown == .weekday {
                weekdayChart
            }

            let list = breakdown == .merchant ? Array(slices.prefix(10)) : slices
            VStack(spacing: 2) {
                ForEach(list) { slice in
                    NavigationLink {
                        FilteredExpensesView(title: slice.title, subtitle: periodTitle, expenses: slice.items)
                    } label: {
                        SliceRow(slice: slice, share: slice.total / max(spent, 0.01), currency: currency)
                    }
                    .buttonStyle(.plain)
                }
            }
            if breakdown == .bank && slices.contains(where: { $0.id == "Not set" }) {
                Text("Tip: open a transaction to fill in its bank or account. Recognised banks are filled in automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var weekdayChart: some View {
        let symbols = cal.shortWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 }
        let totals = order.map { idx in
            (symbols[idx], spending.filter { cal.component(.weekday, from: $0.date) == idx + 1 }.reduce(0) { $0 + $1.amount })
        }
        let maxTotal = totals.map(\.1).max() ?? 0
        return Chart(totals, id: \.0) { item in
            BarMark(x: .value("Day", item.0), y: .value("Spent", item.1), width: .ratio(0.55))
                .foregroundStyle(item.1 == maxTotal && maxTotal > 0
                                 ? AnyShapeStyle(Color(light: 0x3B82F6, dark: 0x60A5FA).gradient)
                                 : AnyShapeStyle(Color(light: 0x3B82F6, dark: 0x60A5FA).opacity(0.3)))
                .cornerRadius(4)
        }
        .chartYAxis(.hidden)
        .frame(height: 130)
    }

    private var largestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Largest expenses").padding(.bottom, 4)
            ForEach(Array(largest.enumerated()), id: \.element.id) { i, e in
                NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                    .buttonStyle(.plain)
                if i < largest.count - 1 { Divider().padding(.leading, 56) }
            }
        }
        .card()
    }

    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "Monthly summary", trailing: "\(allMonths.count) months").padding(.bottom, 6)
            if allMonths.isEmpty {
                Text("Months appear here as transactions are recorded.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(allMonths.enumerated()), id: \.element.id) { i, m in
                Button {
                    scope = .month
                    anchor = m.month
                    selectedBar = nil
                } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(m.month.formatted(.dateTime.month(.abbreviated)).uppercased())
                                .font(.caption2.weight(.bold)).foregroundStyle(Theme.emerald)
                            Text(m.month.formatted(.dateTime.year(.twoDigits)))
                                .font(.caption.weight(.semibold))
                        }
                        .frame(width: 44, height: 44)
                        .background(Theme.emeraldSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.month.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                            Text("\(m.count) transactions" + (m.income > 0 ? " · +\(Formatters.compactMoney(m.income, currency)) in" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formatters.money(m.spent, currency))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < allMonths.count - 1 { Divider().padding(.leading, 56) }
            }
        }
        .card()
    }
}

private struct SliceRow: View {
    let slice: InsightsView.Slice
    let share: Double
    let currency: String
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: slice.symbol, color: slice.color, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(slice.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(Formatters.money(slice.total, currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(slice.color.opacity(0.12))
                        Capsule().fill(slice.color.gradient).frame(width: max(5, geo.size.width * share))
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("\(slice.items.count) transaction\(slice.items.count == 1 ? "" : "s")")
                    Spacer()
                    Text("\(Int((share * 100).rounded()))%")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Drill-down list for one category / merchant / bank / weekday.
struct FilteredExpensesView: View {
    let title: String
    let subtitle: String
    let expenses: [Expense]

    var body: some View {
        let sorted = expenses.sorted { $0.date > $1.date }
        let currency = sorted.first?.currency ?? AppSettings.defaultCurrency
        let total = sorted.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.money(total, currency)).font(.title2.weight(.bold))
                    }
                    Spacer()
                    Pill(text: "\(sorted.count) items", color: .secondary)
                }
            }
            .listRowBackground(Theme.card)
            Section {
                ForEach(sorted) { e in
                    NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
