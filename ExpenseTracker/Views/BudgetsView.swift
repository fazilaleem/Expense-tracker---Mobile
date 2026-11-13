import SwiftUI
import SwiftData
import Charts

struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @State private var editing: Budget?
    @State private var showingNew = false
    @State private var newPreset: (ExpenseCategory?, BudgetPeriod)?
    @State private var window: Window = .current
    @State private var periodFilter: BudgetPeriod?
    @State private var statusFilter: BudgetStatus.Level?

    enum Window: String, CaseIterable, Identifiable {
        case current = "This period", previous = "Previous period"
        var id: String { rawValue }
    }

    private func status(_ b: Budget) -> BudgetStatus {
        BudgetService.status(of: b, interval: window == .current ? b.interval() : b.previousInterval(), in: expenses)
    }
    private func previousStatus(_ b: Budget) -> BudgetStatus {
        BudgetService.status(of: b, interval: b.previousInterval(), in: expenses)
    }

    private var filtered: [Budget] {
        budgets.filter { b in
            (periodFilter == nil || b.period == periodFilter)
                && (statusFilter == nil || status(b).level == statusFilter)
        }
        .sorted { status($0).ratio > status($1).ratio }
    }
    private var overall: [Budget] { filtered.filter { $0.categoryRaw == nil } }
    private var perCategory: [Budget] { filtered.filter { $0.categoryRaw != nil } }
    private var periodsInUse: [BudgetPeriod] { BudgetPeriod.allCases.filter { p in budgets.contains { $0.period == p } } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if budgets.isEmpty {
                        emptyState.appearAnimation()
                    } else {
                        filters.appearAnimation()
                        summaryCard.appearAnimation(delay: 0.05)
                        if filtered.count > 0 { comparisonChart.appearAnimation(delay: 0.1) }
                        ForEach(Array(overall.enumerated()), id: \.element.id) { i, b in
                            OverallBudgetCard(budget: b, status: status(b))
                                .onTapGesture { editing = b }
                                .appearAnimation(delay: 0.12 + Double(i) * 0.04)
                        }
                        if !perCategory.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionTitle(title: "By category", trailing: "\(perCategory.count)")
                                    .padding(.bottom, 8)
                                ForEach(Array(perCategory.enumerated()), id: \.element.id) { i, b in
                                    Button { editing = b } label: {
                                        BudgetRow(budget: b, status: status(b),
                                                  previous: window == .current ? previousStatus(b) : nil)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { editing = b } label: { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            withAnimation { context.delete(b); try? context.save() }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    if i < perCategory.count - 1 { Divider().padding(.leading, 52) }
                                }
                            }
                            .card()
                            .appearAnimation(delay: 0.15)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView("No budgets match", systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text("Change or clear the filters."))
                        }
                        alertInfo.appearAnimation(delay: 0.2)
                    }
                }
                .padding(16)
                .animation(.snappy, value: budgets.count)
                .animation(.snappy, value: window)
                .animation(.snappy, value: periodFilter)
                .animation(.snappy, value: statusFilter)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newPreset = nil; showingNew = true } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(Theme.emeraldSoft, in: Circle())
                    }
                    .accessibilityLabel("Add budget")
                }
            }
            .sheet(isPresented: $showingNew) {
                BudgetEditView(budget: nil, presetCategory: newPreset?.0, presetPeriod: newPreset?.1 ?? .monthly)
            }
            .sheet(item: $editing) { b in
                BudgetEditView(budget: b)
            }
            .sensoryFeedback(.selection, trigger: window)
        }
    }

    // MARK: Filters

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Window", selection: $window) {
                ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", symbol: "square.grid.2x2", color: Theme.emerald,
                               selected: periodFilter == nil) { periodFilter = nil }
                    ForEach(periodsInUse) { p in
                        FilterChip(title: p.label, symbol: "calendar", color: Theme.emerald,
                                   selected: periodFilter == p) { periodFilter = periodFilter == p ? nil : p }
                    }
                    Divider().frame(height: 22)
                    FilterChip(title: "Over", symbol: "exclamationmark.triangle.fill", color: Theme.danger,
                               selected: statusFilter == .exceeded) { statusFilter = statusFilter == .exceeded ? nil : .exceeded }
                    FilterChip(title: "Near limit", symbol: "exclamationmark.circle.fill", color: Theme.warning,
                               selected: statusFilter == .warning) { statusFilter = statusFilter == .warning ? nil : .warning }
                    FilterChip(title: "On track", symbol: "checkmark.circle.fill", color: Theme.emerald,
                               selected: statusFilter == .ok) { statusFilter = statusFilter == .ok ? nil : .ok }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let list = filtered.filter { $0.isEnabled }
        // Avoid double counting: if an overall budget is shown, compare against it; otherwise sum categories.
        let basis = list.contains { $0.categoryRaw == nil } ? list.filter { $0.categoryRaw == nil } : list
        let budgeted = basis.reduce(0) { $0 + $1.limit }
        let spent = basis.reduce(0) { $0 + status($1).spent }
        let ratio = budgeted > 0 ? spent / budgeted : 0
        let over = list.filter { status($0).level == .exceeded }.count
        let near = list.filter { status($0).level == .warning }.count
        let color: Color = ratio >= 1 ? Theme.danger : ratio >= 0.8 ? Theme.warning : Theme.emerald
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(color.opacity(0.15), lineWidth: 11)
                    Circle().trim(from: 0, to: min(ratio, 1))
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((ratio * 100).rounded()))%")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }
                .frame(width: 78, height: 78)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: ratio)
                VStack(alignment: .leading, spacing: 4) {
                    Text(window == .current ? "Budget vs actual" : "Previous period")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(Formatters.money(spent, currency))")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .contentTransition(.numericText(value: spent))
                    Text("of \(Formatters.money(budgeted, currency)) budgeted")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MetricTile(title: budgeted - spent >= 0 ? "Remaining" : "Over by",
                           value: Formatters.money(abs(budgeted - spent), currency),
                           color: budgeted - spent >= 0 ? Theme.income : Theme.danger, symbol: "wallet.pass")
                MetricTile(title: "Budgets", value: "\(list.count)", symbol: "target")
                MetricTile(title: "Near limit", value: "\(near)", color: near > 0 ? Theme.warning : .primary,
                           symbol: "exclamationmark.circle")
                MetricTile(title: "Over", value: "\(over)", color: over > 0 ? Theme.danger : .primary,
                           symbol: "exclamationmark.triangle")
            }
        }
        .card()
    }

    // MARK: Chart

    private struct Bar: Identifiable {
        let name: String
        let series: String
        let value: Double
        var id: String { name + series }
    }

    private var comparisonChart: some View {
        // Categories only – the overall budget is in the ring above and would dwarf the bars.
        let categories = filtered.filter { $0.categoryRaw != nil }
        let shown = Array((categories.isEmpty ? filtered : categories).prefix(8))
        let bars = shown.flatMap { b -> [Bar] in
            let name = b.shortTitle
            return [Bar(name: name, series: "Budget", value: b.limit),
                    Bar(name: name, series: "Actual", value: status(b).spent)]
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Budget vs actual", trailing: window == .current ? "This period" : "Previous")
            Chart(bars) { bar in
                BarMark(x: .value("Budget", bar.name), y: .value("Amount", bar.value), width: .ratio(0.8))
                    .foregroundStyle(by: .value("Series", bar.series))
                    .position(by: .value("Series", bar.series))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["Budget": Color.secondary.opacity(0.3), "Actual": Theme.emerald])
            .chartLegend(position: .top, alignment: .leading)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardStroke)
                    AxisValueLabel()
                }
            }
            .frame(height: 200)
        }
        .card()
    }

    private var alertInfo: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "bell.badge.fill", color: Theme.warning, size: 34)
            Text("You'll get a notification when a budget reaches its warning level (80% by default) and again when it's fully used — once per day, week or month.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card(padding: 14)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconTile(symbol: "target", color: Theme.emerald, size: 64, filled: true)
            Text("Set your first budget").font(.title3.weight(.bold))
            Text("Budgets can cover everything or a single category, and reset every day, week or month. You're alerted before you go over.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(spacing: 10) {
                presetButton("Overall monthly budget", symbol: "chart.pie.fill", color: Theme.emerald, nil, .monthly)
                presetButton("Food & Dining · weekly", symbol: ExpenseCategory.food.symbol, color: ExpenseCategory.food.color, .food, .weekly)
                presetButton("Groceries · monthly", symbol: ExpenseCategory.groceries.symbol, color: ExpenseCategory.groceries.color, .groceries, .monthly)
                presetButton("Transport · daily", symbol: ExpenseCategory.transport.symbol, color: ExpenseCategory.transport.color, .transport, .daily)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 22)
    }

    private func presetButton(_ title: String, symbol: String, color: Color,
                              _ category: ExpenseCategory?, _ period: BudgetPeriod) -> some View {
        Button {
            newPreset = (category, period)
            showingNew = true
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 32)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.emerald)
            }
            .padding(10)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cards & rows

extension BudgetStatus.Level {
    var color: Color {
        switch self {
        case .ok: return Theme.emerald
        case .warning: return Theme.warning
        case .exceeded: return Theme.danger
        }
    }
}

struct OverallBudgetCard: View {
    let budget: Budget
    let status: BudgetStatus
    @State private var animated: Double = 0

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(status.level.color.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(animated, 1))
                    .stroke(status.level.color.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((status.ratio * 100).rounded()))%")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .contentTransition(.numericText(value: status.ratio))
                    Text("used").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Overall").font(.headline)
                    Pill(text: budget.periodLabel, color: .secondary)
                    if !budget.isEnabled { Pill(text: "Paused", color: .secondary) }
                }
                Text(Formatters.money(status.spent, budget.currency))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText(value: status.spent))
                Text("of \(Formatters.money(budget.limit, budget.currency))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(status.remaining >= 0
                     ? "\(Formatters.money(status.remaining, budget.currency)) left · \(status.timeLeftText)"
                     : "Over by \(Formatters.money(-status.remaining, budget.currency))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.level == .ok ? Color.secondary : status.level.color)
            }
            Spacer(minLength: 0)
        }
        .card()
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) { animated = status.ratio }
        }
        .onChange(of: status.ratio) { _, new in withAnimation(.snappy) { animated = new } }
    }
}

struct BudgetRow: View {
    let budget: Budget
    let status: BudgetStatus
    /// Previous period, for the "vs last period" comparison.
    var previous: BudgetStatus? = nil
    @State private var animated: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: budget.symbol, color: budget.style?.color ?? Theme.emerald, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(budget.shortTitle).font(.subheadline.weight(.semibold))
                    Text(budget.periodLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.elevated, in: Capsule())
                    Spacer()
                    Text("\(Formatters.compactMoney(status.spent, budget.currency)) / \(budget.limit.formatted(.number.precision(.fractionLength(0))))")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(status.level.color.opacity(0.14))
                        Capsule().fill(status.level.color.gradient)
                            .frame(width: max(6, geo.size.width * min(animated, 1)))
                    }
                }
                .frame(height: 8)
                HStack {
                    if status.level == .exceeded {
                        Label("Over by \(Formatters.compactMoney(-status.remaining, budget.currency))",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    } else if status.level == .warning {
                        Label("\(Formatters.compactMoney(status.remaining, budget.currency)) left",
                              systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.warning)
                    } else {
                        Text("\(Formatters.compactMoney(status.remaining, budget.currency)) left")
                    }
                    Spacer()
                    if let previous, previous.spent > 0 {
                        let d = (status.spent - previous.spent) / previous.spent
                        Text("\(d >= 0 ? "▲" : "▼") \(min(Int((abs(d) * 100).rounded()), 999))% vs last")
                            .foregroundStyle(d > 0.05 ? Theme.danger : Theme.emerald)
                    }
                    Text(budget.isEnabled ? status.timeLeftText : "Paused")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(budget.isEnabled ? 1 : 0.55)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) { animated = status.ratio }
        }
        .onChange(of: status.ratio) { _, new in withAnimation(.snappy) { animated = new } }
    }
}

// MARK: - Editor

struct BudgetEditView: View {
    let budget: Budget?
    var presetCategory: ExpenseCategory? = nil
    var presetPeriod: BudgetPeriod = .monthly

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBudgets: [Budget]

    /// nil = overall; otherwise a built-in or custom category name.
    @State private var category: String?
    @State private var period: BudgetPeriod = .monthly
    @State private var customStart = Calendar.current.startOfDay(for: .now)
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 29, to: Calendar.current.startOfDay(for: .now))!
    @State private var limit: Double?
    @State private var currency = AppSettings.defaultCurrency
    @State private var warnAt: Double = 0.8
    @State private var isEnabled = true
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private var duplicate: Budget? {
        allBudgets.first { $0.id != budget?.id && $0.categoryRaw == category && $0.period == period && period != .custom }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currency).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Limit", value: $limit, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    .padding(.vertical, 6)
                    Picker("Period", selection: $period.animation(.snappy)) {
                        ForEach(BudgetPeriod.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if period == .custom {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    }
                } header: {
                    Text("Limit")
                } footer: {
                    Text(period == .custom
                         ? "Counts \(category?.lowercased() ?? "all") spending in \(currency) between the two dates."
                         : "Counts \(category?.lowercased() ?? "all") spending in \(currency) \(period.noun), resetting every \(period.shortLabel.lowercased()).")
                }

                Section("Applies to") {
                    Picker("Category", selection: $category) {
                        Label("Overall (all spending)", systemImage: "chart.pie.fill").tag(String?.none)
                        ForEach(CategoryStyle.allExpense) { c in
                            Label(c.rawValue, systemImage: c.symbol).tag(String?.some(c.rawValue))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if let dup = duplicate {
                        Label("You already have a \(dup.period.label.lowercased()) \(dup.title) budget.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Warn me at")
                            Spacer()
                            Text("\(Int((warnAt * 100).rounded()))%")
                                .font(.body.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.warning)
                        }
                        Slider(value: $warnAt, in: 0.5...0.95, step: 0.05)
                            .tint(Theme.warning)
                    }
                    Toggle("Budget active", isOn: $isEnabled).tint(Theme.emerald)
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("A notification is sent when spending reaches \(Int(warnAt * 100))% and again at 100%.")
                }

                if budget != nil {
                    Section {
                        Button("Delete budget", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle(budget == nil ? "New budget" : "Edit budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled((limit ?? 0) <= 0 || duplicate != nil)
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let b = budget { context.delete(b); try? context.save() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let b = budget {
            category = b.categoryRaw
            period = b.period
            if let s = b.customStart { customStart = s }
            if let e = b.customEnd { customEnd = e }
            limit = b.limit
            currency = b.currency
            warnAt = b.warnAt
            isEnabled = b.isEnabled
        } else {
            category = presetCategory?.rawValue
            period = presetPeriod
            amountFocused = true
        }
    }

    private func save() {
        guard let value = limit, value > 0 else { return }
        let target: Budget
        if let b = budget {
            target = b
            // Changing the limit, period or threshold re-arms alerts for the current period.
            if b.limit != value || b.period != period || b.warnAt != warnAt {
                b.lastWarnedKey = nil
                b.lastExceededKey = nil
            }
        } else {
            target = Budget(category: nil, period: period, limit: value, currency: currency, warnAt: warnAt)
            context.insert(target)
        }
        target.categoryRaw = category
        target.period = period
        target.customStart = period == .custom ? customStart : nil
        target.customEnd = period == .custom ? customEnd : nil
        target.limit = value
        target.warnAt = warnAt
        target.isEnabled = isEnabled
        try? context.save()
        dismiss()
    }
}
