import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {
    init() {
        NotificationService.requestAuthorization()
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

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            ParseTestView()
                .tabItem { Label("Paste SMS", systemImage: "doc.on.clipboard") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
