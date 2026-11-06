import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    init() {
        if DemoData.isEnabled {
            DemoData.seedIfNeeded()
        } else {
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
            ParseTestView()
                .tabItem { Label("Paste SMS", systemImage: "doc.on.clipboard") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.emerald)
        .fontDesign(.rounded)
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
