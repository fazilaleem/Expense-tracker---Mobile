import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var showingAdd = UserDefaults.standard.bool(forKey: "demoShowAdd")
    @State private var showingSetup = false
    @State private var showingPaste = false
    @State private var selectedAngle: Double?

    private let cal = Calendar.current

    // MARK: Derived data

    private var monthEnd: Date { cal.date(byAdding: .month, value: 1, to: month)! }
    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: .now, toGranularity: .month) }

    private var monthExpenses: [Expense] {
        allExpenses.filter { $0.date >= month && $0.date < monthEnd }
    }
    private var spending: [Expense] { monthExpenses.filter { !$0.isIncome && $0.currency == currency } }
    private var total: Double { spending.reduce(0) { $0 + $1.amount } }
    private var income: Double {
        monthExpenses.filter { $0.isIncome && $0.currency == currency }.reduce(0) { $0 + $1.amount }
    }

    private var otherCurrencyTotals: [(key: String, value: Double)] {
        Dictionary(grouping: monthExpenses.filter { !$0.isIncome && $0.currency != currency }, by: \.currency)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
            .sorted { $0.value > $1.value }
    }

    private var byCategory: [CategoryTotal] {
        Dictionary(grouping: spending, by: \.category)
            .map { CategoryTotal(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    private var byDay: [DayTotal] {
        let grouped = Dictionary(grouping: spending) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        // Fill every day so the chart has a continuous axis.
        let lastDay = isCurrentMonth ? cal.startOfDay(for: .now) : cal.date(byAdding: .day, value: -1, to: monthEnd)!
        var days: [DayTotal] = []
        var d = month
        while d <= lastDay {
            days.append(DayTotal(day: d, total: grouped[d] ?? 0))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return days
    }

    private var todayTotal: Double {
        spending.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }
    private var weekTotal: Double {
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return spending.filter { week.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }
    private var dailyAverage: Double {
        let days = max(byDay.count, 1)
        return total / Double(days)
    }

    private var selectedCategory: CategoryTotal? {
        guard let angle = selectedAngle else { return nil }
        var running = 0.0
        for item in byCategory {
            running += item.total
            if angle <= running { return item }
        }
        return nil
    }

    private var reviewCount: Int { allExpenses.filter(\.needsReview).count }

    /// Overall monthly budget drives the hero progress bar.
    private var budget: Double {
        budgets.first { $0.categoryRaw == nil && $0.period == .monthly && $0.isEnabled && $0.currency == currency }?.limit ?? 0
    }

    /// Remaining monthly budget spread over the days left (including today).
    private var safePerDay: Double {
        let today = cal.component(.day, from: .now)
        let daysInMonth = cal.range(of: .day, in: .month, for: .now)?.count ?? 30
        let daysLeft = max(1, daysInMonth - today + 1)
        return max(budget - total, 0) / Double(daysLeft)
    }

    /// Budgets at or above their warning level right now.
    private var atRisk: [(budget: Budget, status: BudgetStatus)] {
        budgets.filter(\.isEnabled)
            .map { (budget: $0, status: BudgetService.status(of: $0, in: allExpenses)) }
            .filter { $0.status.level != .ok }
            .sorted { $0.status.ratio > $1.status.ratio }
    }

    /// Change vs the same number of days last month (e.g. 1–6 Oct vs 1–6 Nov).
    private var vsLastMonth: Double? {
        guard let prevStart = cal.date(byAdding: .month, value: -1, to: month) else { return nil }
        let elapsed = isCurrentMonth ? Date.now.timeIntervalSince(month) : monthEnd.timeIntervalSince(month)
        let prevEnd = min(prevStart.addingTimeInterval(elapsed), month)
        let prev = allExpenses.filter { !$0.isIncome && $0.currency == currency && $0.date >= prevStart && $0.date < prevEnd }
            .reduce(0) { $0 + $1.amount }
        guard prev > 0 else { return nil }
        return (total - prev) / prev
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    monthSwitcher.appearAnimation()
                    heroCard.appearAnimation(delay: 0.05)
                    if isCurrentMonth { quickStats.appearAnimation(delay: 0.1) }
                    if isCurrentMonth && !atRisk.isEmpty { budgetAlertCard.appearAnimation(delay: 0.11) }
                    if reviewCount > 0 { reviewBanner.appearAnimation(delay: 0.12) }

                    if spending.isEmpty {
                        emptyState.appearAnimation(delay: 0.15)
                    } else {
                        categoryCard.appearAnimation(delay: 0.15).id("categories")
                        if byDay.count > 1 { trendCard.appearAnimation(delay: 0.2) }
                        recentCard.appearAnimation(delay: 0.25)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: month)
            }
            .scrollIndicators(.hidden)
            .task {
                // Screenshot helper: `-demoScrollTo categories|bottom`.
                guard let target = UserDefaults.standard.string(forKey: "demoScrollTo") else { return }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation { proxy.scrollTo(target, anchor: target == "bottom" ? .bottom : .top) }
            }
            }
            .themedBackground()
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddMenu(showingAdd: $showingAdd, showingPaste: $showingPaste)
                }
            }
            .sheet(isPresented: $showingAdd) { ExpenseEditView(expense: nil) }
            .sheet(isPresented: $showingPaste) { ParseTestView(isSheet: true) }
            .sheet(isPresented: $showingSetup) {
                NavigationStack { SetupGuideView() }
            }
            .sensoryFeedback(.selection, trigger: month)
        }
    }

    // MARK: Sections

    private var monthSwitcher: some View {
        HStack(spacing: 12) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            Spacer()
            VStack(spacing: 0) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(month.formatted(.dateTime.year()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(isCurrentMonth)
        }
        .font(.body.weight(.semibold))
        .padding(4)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardStroke))
    }

    private func shift(_ by: Int) {
        selectedAngle = nil
        month = cal.date(byAdding: .month, value: by, to: month)!
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isCurrentMonth ? "Spent this month" : "Spent in \(month.formatted(.dateTime.month(.wide)))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Image(systemName: "wallet.pass.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(Formatters.money(total, currency))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: total))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if !otherCurrencyTotals.isEmpty {
                Text("+ " + otherCurrencyTotals.map { Formatters.money($0.value, $0.key) }.joined(separator: "  + "))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if budget > 0 { budgetBar }
            if budget > 0 && isCurrentMonth {
                Label {
                    Text("Safe to spend: **\(Formatters.money(safePerDay, currency))** / day")
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
            }

            HStack(spacing: 8) {
                heroChip("\(spending.count)", symbol: "list.bullet")
                if let change = vsLastMonth {
                    heroChip("\(change >= 0 ? "+" : "−")\(min(Int((abs(change) * 100).rounded()), 999))% vs \(cal.date(byAdding: .month, value: -1, to: month)!.formatted(.dateTime.month(.abbreviated)))",
                             symbol: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                }
                if income > 0 {
                    heroChip("+\(Formatters.compactMoney(income, currency))", symbol: "arrow.down.left")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                Theme.heroGradient
                Circle().fill(.white.opacity(0.08)).frame(width: 220, height: 220).offset(x: 70, y: -90)
                Circle().fill(.white.opacity(0.06)).frame(width: 140, height: 140).offset(x: -10, y: 120)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x047857).opacity(0.3), radius: 18, y: 10)
    }

    private var budgetBar: some View {
        let ratio = budget > 0 ? total / budget : 0
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(ratio > 1 ? Color(hex: 0xFCA5A5) : .white)
                        .frame(width: geo.size.width * min(ratio, 1))
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: ratio)
                }
            }
            .frame(height: 8)
            HStack {
                Text(ratio > 1
                     ? "Over by \(Formatters.money(total - budget, currency))"
                     : "\(Formatters.money(budget - total, currency)) left")
                Spacer()
                Text("\(Int((ratio * 100).rounded()))% of \(Formatters.compactMoney(budget, currency))")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func heroChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            StatTile(title: "Today", value: Formatters.compactMoney(todayTotal, currency),
                     symbol: "sun.max.fill", color: Color(light: 0xF59E0B, dark: 0xFBBF24))
            StatTile(title: "This week", value: Formatters.compactMoney(weekTotal, currency),
                     symbol: "calendar", color: Color(light: 0x3B82F6, dark: 0x60A5FA))
            StatTile(title: "Daily avg", value: Formatters.compactMoney(dailyAverage, currency),
                     symbol: "chart.line.uptrend.xyaxis", color: Theme.emerald)
        }
    }

    private var budgetAlertCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Budget alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(atRisk.contains { $0.status.level == .exceeded } ? Theme.danger : Theme.warning)
                Spacer()
            }
            ForEach(atRisk.prefix(3), id: \.budget.id) { item in
                HStack(spacing: 10) {
                    IconTile(symbol: item.budget.symbol, color: item.budget.category?.color ?? Theme.emerald, size: 28)
                    Text("\(item.budget.category?.shortName ?? "Overall") · \(item.budget.period.label)")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int((item.status.ratio * 100).rounded()))%")
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(item.status.level.color)
                }
            }
        }
        .card(padding: 14)
    }

    private var reviewBanner: some View {
        NavigationLink {
            TransactionsView(onlyReview: true)
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "sparkle.magnifyingglass", color: Theme.warning, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reviewCount) to review").font(.subheadline.weight(.semibold))
                    Text("Auto-recorded entries the parser wasn't sure about")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Where it went", trailing: "\(byCategory.count) categories")

            ZStack {
                Chart(byCategory) { item in
                    SectorMark(angle: .value("Amount", item.total),
                               innerRadius: .ratio(0.66),
                               outerRadius: .ratio(selectedCategory?.id == item.id ? 1.0 : 0.92),
                               angularInset: 2)
                        .foregroundStyle(item.category.color)
                        .cornerRadius(5)
                        .opacity(selectedCategory == nil || selectedCategory?.id == item.id ? 1 : 0.35)
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(.hidden)
                .frame(height: 210)
                .animation(.snappy, value: selectedCategory?.id)

                VStack(spacing: 2) {
                    if let sel = selectedCategory {
                        Image(systemName: sel.category.symbol).foregroundStyle(sel.category.color)
                        Text(sel.category.shortName).font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.compactMoney(sel.total, currency))
                            .font(.title3.weight(.bold)).contentTransition(.numericText(value: sel.total))
                    } else {
                        Text("Total").font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.compactMoney(total, currency)).font(.title3.weight(.bold))
                    }
                }
                .allowsHitTesting(false)
            }
            .sensoryFeedback(.selection, trigger: selectedCategory?.id)

            VStack(spacing: 14) {
                ForEach(byCategory) { item in
                    CategoryBarRow(item: item, share: item.total / max(total, 0.01), currency: currency)
                }
            }
        }
        .card()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Daily spending", trailing: "avg \(Formatters.compactMoney(dailyAverage, currency))")
            Chart {
                ForEach(byDay) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Amount", item.total), width: .ratio(0.6))
                        .foregroundStyle(cal.isDateInToday(item.day)
                                         ? AnyShapeStyle(Theme.emerald)
                                         : AnyShapeStyle(Theme.emerald.opacity(0.35)))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Average", dailyAverage))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, byDay.count / 6))) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 170)
        }
        .card()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Recent")
                .padding(.bottom, 4)
            ForEach(Array(monthExpenses.prefix(5).enumerated()), id: \.element.id) { index, e in
                NavigationLink { ExpenseEditView(expense: e) } label: { ExpenseRow(expense: e) }
                    .buttonStyle(.plain)
                if index < min(monthExpenses.count, 5) - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.emerald.opacity(0.3), radius: 12, y: 6)
            Text(isCurrentMonth ? "No spending yet this month" : "Nothing recorded this month")
                .font(.headline)
            Text("Connect your bank SMS and Apple Pay once, and every purchase is recorded automatically.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { showingSetup = true } label: {
                    Label("Set up automation", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                Button { showingAdd = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .card(padding: 22)
    }
}

// MARK: - Supporting views & models

struct CategoryTotal: Identifiable {
    let category: ExpenseCategory
    let total: Double
    let count: Int
    var id: ExpenseCategory { category }
}

struct DayTotal: Identifiable {
    let day: Date
    let total: Double
    var id: Date { day }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
    }
}

private struct CategoryBarRow: View {
    let item: CategoryTotal
    let share: Double
    let currency: String
    @State private var animatedShare: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: item.category.symbol, color: item.category.color, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.category.rawValue).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(Formatters.money(item.total, currency))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(item.category.color.opacity(0.12))
                        Capsule().fill(item.category.color.gradient)
                            .frame(width: max(6, geo.size.width * animatedShare))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("\(item.count) transaction\(item.count == 1 ? "" : "s")")
                    Spacer()
                    Text("\(Int((share * 100).rounded()))%")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) { animatedShare = share }
        }
        .onChange(of: share) { _, new in
            withAnimation(.snappy) { animatedShare = new }
        }
    }
}

/// Shared transaction row used on the dashboard and in the list.
struct ExpenseRow: View {
    let expense: Expense
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                IconTile(symbol: expense.category.symbol, color: expense.category.color, size: 44)
                if expense.needsReview {
                    Circle().fill(Theme.warning)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            // Category is the headline; merchant / bank / time are supporting detail.
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.category.rawValue)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: expense.source.symbol).font(.caption2)
                    Text(expense.detailLine)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            Text((expense.isIncome ? "+" : "−") + Formatters.money(expense.amount, expense.currency))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(expense.isIncome ? Theme.income : .primary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}
