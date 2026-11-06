import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @AppStorage(SettingsKey.defaultCurrency) private var currency = AppSettings.defaultCurrency
    @AppStorage(SettingsKey.monthlyBudget) private var budget: Double = 0
    @AppStorage(SettingsKey.notifyOnLog) private var notifyOnLog = true
    @AppStorage(SettingsKey.mergeDuplicates) private var mergeDuplicates = true
    @AppStorage(SettingsKey.ignoreIncome) private var ignoreIncome = false
    @State private var exportURL: URL?
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SetupGuideView()
                    } label: {
                        Label("Automation setup guide", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("iOS doesn't let apps read SMS or other apps' notifications, so recording works through Shortcuts automations. It takes about 3 minutes to set up.")
                }

                Section("Preferences") {
                    Picker("Main currency", selection: $currency) {
                        ForEach(AppSettings.commonCurrencies, id: \.self) { Text($0) }
                    }
                    HStack {
                        Text("Monthly budget")
                        Spacer()
                        TextField("None", value: $budget, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    Toggle("Confirm each auto-recorded expense", isOn: $notifyOnLog)
                    Toggle("Merge Wallet + SMS duplicates", isOn: $mergeDuplicates)
                    Toggle("Ignore income / credit messages", isOn: $ignoreIncome)
                }

                Section("Data") {
                    Button {
                        exportURL = CSVExporter.export(expenses)
                    } label: {
                        Label("Export CSV (\(expenses.count) records)", systemImage: "square.and.arrow.up")
                    }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Share exported file", systemImage: "doc.text") }
                    }
                    let rules = Categorizer.learnedRules().count
                    Button("Forget learned categories (\(rules))") { Categorizer.clearLearnedRules() }
                        .disabled(rules == 0)
                    Button("Delete all transactions", role: .destructive) { confirmWipe = true }
                }

                Section {
                    LabeledContent("Storage", value: "On this iPhone only")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all \(expenses.count) transactions?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    for e in expenses { context.delete(e) }
                    try? context.save()
                }
            }
        }
    }
}
