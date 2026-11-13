import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    init() {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !DemoData.isEnabled { AppSettings.applyLocalCurrencyOnce() }
        NotificationService.configure()
        BudgetService.migrateLegacyMonthlyBudget()
        if DemoData.isEnabled {
            DemoData.seedIfNeeded()
        } else if !underTest {
            NotificationService.requestAuthorization()
        }
        ExpenseShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ExpenseStore.container)
    }
}

struct ContentView: View {
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
    @Bindable private var router = AppRouter.shared
    @State private var openedExpense: Expense?

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                .tag(0)
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(1)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(2)
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "target") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(Theme.emerald)
        .fontDesign(.rounded)
        .overlay {
            if appLock && locked {
                AppLockView { withAnimation(.easeOut(duration: 0.25)) { locked = false } }
                    .transition(.opacity)
            }
        }
        // Notification tap → open that expense.
        .onChange(of: router.openExpenseID) { _, id in
            guard let id else { return }
            openedExpense = ExpenseStore.find(id)
            router.openExpenseID = nil
        }
        .sheet(item: $openedExpense) { e in
            ExpenseEditView(expense: e, presentedAsSheet: true)
        }
        .onChange(of: scenePhase) { _, phase in
            // Lock again whenever the app goes to the background.
            if phase == .background && appLock { locked = true }
        }
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            NavigationStack {
                SetupGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { hasOnboarded = true }
                        }
                    }
            }
        }
    }
}
