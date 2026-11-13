import SwiftUI
import SwiftData
import Charts

/// Net / spending summaries for a month, a year or a custom range, filterable by category and bank.
struct InsightsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency

    enum Scope: String, CaseIterable, Identifiable {
        case month = "Month", year = "Year", custom = "Custom"
        var id: String { rawValue }
    }
    enum Breakdown: String, CaseIterable, Identifiable {
        case category = "Category", merchant = "Merchant", bank = "Bank", weekday = "Weekday"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .month
    @State private var anchor = Date.now
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now)!
    @State private var customEnd = Date.now
    @State private var categoryFilter: String?
    @State private var bankFilter: String?
    @State private var breakdown: Breakdown = .category
    @State private var selectedMonth: Date?

    private let cal = Calendar.current
    private let blue = Color(light: 0x3B82F6, dark: 0x60A5FA)

    // MARK: Period

    private var interval: DateInterval {
        switch scope {
        case .month: return cal.dateInterval(of: .month, for: anchor)!
        case .year: return cal.dateInterval(of: .year, for: anchor)!
        case .custom:
            let s = cal.startOfDay(for: min(customStart, customEnd))
            let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(customStart, customEnd)))!
            return DateInterval(start: s, end: e)
        }
    }

    private var previousInterval: DateInterval {
        switch scope {
        case .month: return cal.dateInterval(of: .month, for: interval.start.addingTimeInterval(-1))!
        case .year: return cal.dateInterval(of: .year, for: interval.start.addingTimeInterval(-1))!
        case .custom: return DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
        }
    }

    private var isCurrent: Bool { interval.contains(.now) }

    private var periodTitle: String {
        switch scope {
        case .month: return interval.start.formatted(.dateTime.month(.wide).year())
        case .year: return interval.start.formatted(.dateTime.year())
        case .custom:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    // MARK: Filtered data

    /// Everything matching the currency, category and bank filters (any date).
    private var base: [Expense] {
        all.filter { e in
            e.currency == currency
                && (categoryFilter == nil || e.categoryRaw == categoryFilter)
                && (bankFilter == nil || (e.bank ?? "") == bankFilter)
        }
    }
    private func items(in i: DateInterval) -> [Expense] { base.filter { $0.date >= i.start && $0.date < i.end } }

    private var current: [Expense] { items(in: interval) }
    private var spending: [Expense] { current.filter { !$0.isIncome } }
    private var spent: Double { spending.reduce(0) { $0 + $1.amount } }
    private var income: Double { current.filter(\.isIncome).reduce(0) { $0 + $1.amount } }
    private var net: Double { income - spent }

    /// Spending vs the same point of the previous period.
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

    private var categoriesInUse: [CategoryStyle] {
        Dictionary(grouping: all.filter { !$0.isIncome }, by: \.categoryRaw)
            .sorted { $0.value.count > $1.value.count }
            .map { CategoryStyle.of($0.key) }
    }
    private var banksInUse: [String] {
        Array(Set(all.compactMap { $0.bank }.filter { !$0.isEmpty })).sorted()
    }

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
                .animation(.snappy, value: categoryFilter)
                .animation(.snappy, value: bankFilter)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationTitle("Insights")
            .sensoryFeedback(.selection, trigger: anchor)
            .sensoryFeedback(.selection, trigger: breakdown)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Range", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if scope == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date).labelsHidden()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date).labelsHidden()
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
            } else {
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

            // Filters
            HStack(spacing: 8) {
                Menu {
                    Button("All categories") { categoryFilter = nil }
                    Divider()
                    ForEach(categoriesInUse) { c in
                        Button { categoryFilter = c.rawValue } label: { Label(c.rawValue, systemImage: c.symbol) }
                    }
                } label: {
                    filterChip(categoryFilter.map { CategoryStyle.of($0).shortName } ?? "All categories",
                               symbol: categoryFilter.map { CategoryStyle.of($0).symbol } ?? "square.grid.2x2",
                               active: categoryFilter != nil)
                }
                Menu {
                    Button("All banks") { bankFilter = nil }
                    if !banksInUse.isEmpty { Divider() }
                    ForEach(banksInUse, id: \.self) { b in Button(b) { bankFilter = b } }
                } label: {
                    filterChip(bankFilter ?? "All banks", symbol: "building.columns", active: bankFilter != nil)
                }
                Spacer(minLength: 0)
                if categoryFilter != nil || bankFilter != nil {
                    Button("Clear") { categoryFilter = nil; bankFilter = nil }
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func filterChip(_ title: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(active ? .white : .primary)
        .background(Capsule().fill(active ? AnyShapeStyle(Theme.emerald.gradient) : AnyShapeStyle(Theme.card)))
        .overlay(Capsule().strokeBorder(active ? .clear : Theme.cardStroke))
    }

    private func shift(_ by: Int) {
        anchor = cal.date(byAdding: scope == .year ? .year : .month, value: by, to: anchor)!
        selectedMonth = nil
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text((net >= 0 ? "+" : "−") + Formatters.money(abs(net), currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(net >= 0 ? Theme.income : Theme.danger)
                        .contentTransition(.numericText(value: net))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer()
                if let change {
                    Pill(text: "\(change >= 0 ? "+" : "−")\(min(Int((abs(change) * 100).rounded()), 999))% spend",
                         symbol: change >= 0 ? "arrow.up.right" : "arrow.down.right",
                         color: change > 0.05 ? Theme.danger : Theme.emerald)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MetricTile(title: "Income", value: Formatters.money(income, currency), color: Theme.income, symbol: "arrow.down.left")
                MetricTile(title: "Spent", value: Formatters.money(spent, currency), symbol: "arrow.up.right")
                MetricTile(title: "Per day", value: Formatters.money(spent / Double(daysElapsed), currency), symbol: "calendar")
                MetricTile(title: "Transactions", value: "\(current.count)", symbol: "list.bullet")
            }
            if let change {
                Text("Spending is \(change >= 0 ? "up" : "down") \(min(Int((abs(change) * 100).rounded()), 999))% vs the same point of the previous \(scope == .year ? "year" : scope == .month ? "month" : "period").")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Trend chart

    private struct Point: Identifiable {
        let x: Int
        let value: Double
        let series: String
        var id: String { "\(series)-\(x)" }
    }

    private struct MonthBar: Identifiable {
        let month: Date
        let spent: Double
        let income: Double
        var id: Date { month }
    }

    /// Running total by day of month: this period vs the previous one.
    private var cumulative: [Point] {
        func run(_ i: DateInterval, upTo lastDay: Int, series: String) -> [Point] {
            let byDay = Dictionary(grouping: items(in: i).filter { !$0.isIncome }) { cal.component(.day, from: $0.date) }
                .mapValues { $0.reduce(0) { $0 + $1.amount } }
            var total = 0.0
            return (1...max(1, lastDay)).map { d in
                total += byDay[d] ?? 0
                return Point(x: d, value: total, series: series)
            }
        }
        let daysThis = cal.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        let daysPrev = cal.range(of: .day, in: .month, for: previousInterval.start)?.count ?? 30
        let today = isCurrent ? cal.component(.day, from: .now) : daysThis
        return run(previousInterval, upTo: daysPrev, series: "Last month") + run(interval, upTo: today, series: "This month")
    }

    private var yearBars: [MonthBar] {
        (0..<12).compactMap { cal.date(byAdding: .month, value: $0, to: interval.start) }.map { m in
            let list = items(in: cal.dateInterval(of: .month, for: m)!)
            return MonthBar(month: m,
                            spent: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                            income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount })
        }
    }

    private var dailyBars: [Point] {
        let byDay = Dictionary(grouping: spending) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        var points: [Point] = []
        var d = interval.start
        var i = 0
        while d < interval.end && i < 400 {
            points.append(Point(x: i, value: byDay[d] ?? 0, series: d.formatted(.dateTime.day().month(.abbreviated))))
            d = cal.date(byAdding: .day, value: 1, to: d)!
            i += 1
        }
        return points
    }

    @ViewBuilder private var trendCard: some View {
        switch scope {
        case .month: cumulativeCard
        case .year: yearCard
        case .custom: dailyCard
        }
    }

    private var cumulativeCard: some View {
        let data = cumulative
        let thisTotal = data.last(where: { $0.series == "This month" })?.value ?? 0
        let day = data.last(where: { $0.series == "This month" })?.x ?? 1
        let lastAtSameDay = data.first(where: { $0.series == "Last month" && $0.x == day })?.value ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Spending pace")
            Text(lastAtSameDay > 0
                 ? "\(Formatters.money(thisTotal, currency)) by day \(day) — \(thisTotal <= lastAtSameDay ? "less" : "more") than \(Formatters.money(lastAtSameDay, currency)) at this point last month."
                 : "\(Formatters.money(thisTotal, currency)) spent by day \(day).")
                .font(.footnote).foregroundStyle(.secondary)
            Chart(data) { p in
                if p.series == "This month" {
                    AreaMark(x: .value("Day", p.x), y: .value("Total", p.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.emerald.opacity(0.35), Theme.emerald.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Day", p.x), y: .value("Total", p.value), series: .value("Series", p.series))
                    .foregroundStyle(p.series == "This month" ? Theme.emerald : Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: p.series == "This month" ? 3 : 2,
                                           dash: p.series == "This month" ? [] : [5, 4]))
                    .interpolationMethod(.monotone)
            }
            .chartXScale(domain: 1...31)
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, 29]) { v in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            HStack(spacing: 16) {
                legend("This month", Theme.emerald, dashed: false)
                legend("Last month", .secondary, dashed: true)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var yearCard: some View {
        let data = yearBars
        let selected = selectedMonth.flatMap { s in data.first { cal.isDate($0.month, equalTo: s, toGranularity: .month) } }
        let active = data.filter { $0.spent > 0 }
        let avg = active.isEmpty ? 0 : active.map(\.spent).reduce(0, +) / Double(active.count)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Month by month",
                         trailing: selected.map { "\($0.month.formatted(.dateTime.month(.abbreviated))): \(Formatters.money($0.spent, currency))" }
                            ?? "avg \(Formatters.money(avg, currency))")
            Chart {
                ForEach(data) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Spent", m.spent), width: .ratio(0.55))
                        .foregroundStyle(selected == nil || selected?.id == m.id
                                         ? AnyShapeStyle(Theme.emerald.gradient) : AnyShapeStyle(Theme.emerald.opacity(0.3)))
                        .cornerRadius(5)
                    if m.income > 0 {
                        PointMark(x: .value("Month", m.month, unit: .month), y: .value("Income", m.income))
                            .symbolSize(40)
                            .foregroundStyle(blue)
                    }
                }
                if avg > 0 {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selectedMonth)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            HStack(spacing: 16) {
                legend("Spent", Theme.emerald, dashed: false)
                legend("Income", blue, dashed: false)
                legend("Average", .secondary, dashed: true)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var dailyCard: some View {
        let data = dailyBars
        let stride = max(1, data.count / 5)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Daily spending", trailing: "\(data.count) days")
            Chart(data) { p in
                BarMark(x: .value("Day", p.x), y: .value("Spent", p.value))
                    .foregroundStyle(Theme.emerald.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: Array(Swift.stride(from: 0, to: data.count, by: stride))) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self), i < data.count { Text(data[i].series) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
        .card()
    }

    private func legend(_ title: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [3, 3] : []))
                .frame(width: 16, height: 3)
            Text(title)
        }
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
        case .merchant: groups = Dictionary(grouping: spending) { $0.hasMerchant ? $0.merchant : "Unknown" }
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
                return Slice(id: key, title: key, symbol: "calendar", color: blue, total: total, items: list)
            }
        }
        .sorted { $0.total > $1.total }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Breakdown")
            Picker("Breakdown", selection: $breakdown) {
                ForEach(Breakdown.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if breakdown == .category { donut }

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
        }
        .card()
    }

    private var donut: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("Spent", s.total), innerRadius: .ratio(0.64), angularInset: 2)
                .foregroundStyle(s.color)
                .cornerRadius(4)
        }
        .chartLegend(.hidden)
        .frame(height: 170)
        .overlay {
            VStack(spacing: 2) {
                Text("Spent").font(.caption).foregroundStyle(.secondary)
                Text(Formatters.money(spent, currency)).font(.headline.weight(.bold)).minimumScaleFactor(0.6)
            }
            .frame(width: 110)
        }
    }

    private var largest: [Expense] { Array(spending.sorted { $0.amount > $1.amount }.prefix(5)) }

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

    // MARK: Monthly summary

    private struct MonthTotal: Identifiable {
        let month: Date
        let spent: Double
        let income: Double
        let count: Int
        var id: Date { month }
    }

    private var allMonths: [MonthTotal] {
        Dictionary(grouping: base) { cal.startOfMonth(for: $0.date) }
            .map { m, list in
                MonthTotal(month: m,
                           spent: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                           income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                           count: list.count)
            }
            .sorted { $0.month > $1.month }
    }

    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "Monthly summary", trailing: "Net").padding(.bottom, 6)
            if allMonths.isEmpty {
                Text("Months appear here as transactions are recorded.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(allMonths.enumerated()), id: \.element.id) { i, m in
                Button {
                    scope = .month
                    anchor = m.month
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
                            Text("Spent \(Formatters.money(m.spent, currency)) · In \(Formatters.money(m.income, currency))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer()
                        let n = m.income - m.spent
                        Text((n >= 0 ? "+" : "−") + Formatters.money(abs(n), currency))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(n >= 0 ? Theme.income : Theme.danger)
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
                        Capsule().fill(slice.color.opacity(0.15))
                        Capsule().fill(slice.color.gradient).frame(width: max(5, geo.size.width * share))
                    }
                }
                .frame(height: 6)
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
