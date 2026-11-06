import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @AppStorage(SettingsKey.budgetAlerts) private var budgetAlerts = true
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.notifyOnLog) private var notifyOnLog = true
    @AppStorage(SettingsKey.mergeDuplicates) private var mergeDuplicates = true
    @AppStorage(SettingsKey.ignoreIncome) private var ignoreIncome = false
    @State private var exportURL: URL?
    @State private var confirmWipe = false
    @State private var learnedCount = Categorizer.learnedRules().count

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("AppLogo")
                            .resizable()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Expenses").font(.title3.weight(.bold))
                            Text("\(expenses.count) transactions · stored on this iPhone")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    NavigationLink {
                        SetupGuideView()
                    } label: {
                        row("Automation setup", symbol: "wand.and.stars", color: Theme.emerald)
                    }
                    NavigationLink {
                        ParseTestView()
                    } label: {
                        row("Paste & test a bank SMS", symbol: "doc.on.clipboard.fill", color: Color(light: 0x6366F1, dark: 0x818CF8))
                    }
                } footer: {
                    Text("iOS doesn't let apps read SMS or notifications directly, so recording runs through Shortcuts automations. Setup takes about 3 minutes.")
                }
                .listRowBackground(Theme.card)

                Section("Preferences") {
                    Picker(selection: $currency) {
                        ForEach(AppSettings.commonCurrencies, id: \.self) { Text($0) }
                    } label: {
                        row("Main currency", symbol: "coloncurrencysign.circle.fill", color: Color(light: 0x3B82F6, dark: 0x60A5FA))
                    }
                    Toggle(isOn: $budgetAlerts) {
                        row("Budget alerts", symbol: "target", color: Color(light: 0xF97316, dark: 0xFB923C))
                    }
                    Toggle(isOn: $appLock) {
                        row("Lock with Face ID", symbol: "faceid", color: Color(light: 0x0F766E, dark: 0x2DD4BF))
                    }
                    Toggle(isOn: $notifyOnLog) {
                        row("Confirm auto-recorded", symbol: "bell.badge.fill", color: Color(light: 0xEF4444, dark: 0xF87171))
                    }
                    Toggle(isOn: $mergeDuplicates) {
                        row("Merge Wallet + SMS duplicates", symbol: "square.on.square", color: Color(light: 0x8B5CF6, dark: 0xA78BFA))
                    }
                    Toggle(isOn: $ignoreIncome) {
                        row("Ignore income messages", symbol: "arrow.down.left.circle.fill", color: Color(light: 0x64748B, dark: 0x94A3B8))
                    }
                }
                .tint(Theme.emerald)
                .listRowBackground(Theme.card)

                Section("Data") {
                    Button {
                        exportURL = CSVExporter.export(expenses)
                    } label: {
                        row("Export CSV", symbol: "tablecells.fill", color: Color(light: 0x16A34A, dark: 0x4ADE80))
                    }
                    .foregroundStyle(.primary)
                    if let url = exportURL {
                        ShareLink(item: url) {
                            row("Share exported file", symbol: "square.and.arrow.up.fill", color: Color(light: 0x0EA5E9, dark: 0x38BDF8))
                        }
                        .foregroundStyle(.primary)
                    }
                    Button {
                        Categorizer.clearLearnedRules()
                        learnedCount = 0
                    } label: {
                        row("Forget learned categories (\(learnedCount))", symbol: "brain", color: Color(light: 0xD946EF, dark: 0xE879F9))
                    }
                    .foregroundStyle(.primary)
                    .disabled(learnedCount == 0)
                    Button { confirmWipe = true } label: {
                        row("Delete all transactions", symbol: "trash.fill", color: Theme.danger)
                    }
                    .foregroundStyle(Theme.danger)
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Settings")
            .onAppear { learnedCount = Categorizer.learnedRules().count }
            .confirmationDialog("Delete all \(expenses.count) transactions?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    for e in expenses { context.delete(e) }
                    try? context.save()
                }
            }
        }
    }

    private func row(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 30, filled: true)
            Text(title)
        }
    }
}
