import SwiftUI

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.emerald.opacity(0.3), radius: 10, y: 5)
                    Text("Automatic expense tracking").font(.title2.bold())
                    Text("Apple doesn't allow any app to read your SMS or notifications directly. Instead, the built-in **Shortcuts** app can hand each bank message or Apple Pay payment to Expenses automatically, with no tapping needed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                Step(1, "Open **Shortcuts** ▸ **Automation** tab ▸ **+** (New Automation).")
                Step(2, "Choose **Message**.")
                Step(3, "Set **Message Contains** to a word your bank always uses, e.g. `debited` or `spent`. Optionally set **Sender** to your bank. (Create one automation per keyword if your banks use different words.)")
                Step(4, "Select **Run Immediately** and turn **off** *Notify When Run*. Tap **Next**.")
                Step(5, "Tap **New Blank Automation** ▸ **Add Action**, search for **Log Expense from Message** (from Expenses).")
                Step(6, "Tap the **Message** field ▸ select **Shortcut Input**, then tap it again and choose **Content**. Optionally set **Sender** to *Shortcut Input ▸ Sender*.")
                Step(7, "Tap **Done**. Every matching SMS is now recorded and you'll get a small confirmation.")
            } header: {
                Label("1 · Bank SMS", systemImage: "message.fill")
            } footer: {
                Text("Tip: use **+ ▸ Paste bank SMS** (or Settings ▸ Paste & test) to check that your bank's message format is read correctly.")
            }

            Section {
                Step(1, "In **Shortcuts** ▸ **Automation** ▸ **+**, choose **Transaction** (Wallet).")
                Step(2, "Select the cards to track and tick **Tapped / used** ▸ **Run Immediately**. Tap **Next**.")
                Step(3, "**New Blank Automation** ▸ add **Log Wallet Transaction** (from Expenses).")
                Step(4, "Set **Amount** = *Shortcut Input ▸ Amount*, **Merchant** = *Shortcut Input ▸ Merchant*, **Card** = *Shortcut Input ▸ Card* (or *Name*).")
                Step(5, "Tap **Done**. Every Apple Pay tap is now recorded the moment you pay.")
            } header: {
                Label("2 · Apple Pay / Wallet", systemImage: "wallet.pass.fill")
            } footer: {
                Text("If your bank also sends an SMS for the same purchase, Expenses merges the two (same amount within 15 minutes), so nothing is counted twice.")
            }

            Section {
                Step(1, "Banking apps' **push notifications** can't be read by Shortcuts. Turn on **SMS alerts** in your bank's app or settings for the most reliable tracking.")
                Step(2, "Siri: *“Add an expense in Expenses”* or *“How much did I spend in Expenses”*.")
                Step(3, "For cash, tap **+** on the Overview screen.")
            } header: {
                Label("Other ways", systemImage: "lightbulb.fill")
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("Setup guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey
    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = LocalizedStringKey(text)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.emerald.gradient))
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
