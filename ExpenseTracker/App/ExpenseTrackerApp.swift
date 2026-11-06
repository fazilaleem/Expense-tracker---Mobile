import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    init() {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
    /// `-startTab N` launch argument picks the initial tab (used for screenshots).
    @State private var tab = UserDefaults.standard.integer(forKey: "startTab")

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                .tag(0)
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(1)
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "target") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.emerald)
        .fontDesign(.rounded)
        .overlay {
            if appLock && locked {
                AppLockView { withAnimation(.easeOut(duration: 0.25)) { locked = false } }
                    .transition(.opacity)
            }
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
