# Expenses: automatic expense tracker for iPhone

A personal SwiftUI app that records your spending **automatically** from bank SMS
alerts and Apple Pay / Wallet transactions. It categorises each one, flags anything
it isn't sure about, and shows monthly totals, a budget bar and category charts.
All data stays on your iPhone (SwiftData).

## How the automation works (and why)

iOS does **not** let any app read your SMS or other apps' notifications. The only
supported way to react to them is **Shortcuts Personal Automations**, which can run
an action without any tap when:

| Trigger | What gets passed | App action |
|---|---|---|
| **Message** (SMS containing "debited", "spent", …) | Full SMS text + sender | **Log Expense from Message** |
| **Transaction** (Apple Pay / Wallet card tapped) | Amount, merchant, card | **Log Wallet Transaction** |

The app adds these actions to Shortcuts through App Intents. The in-app
**Settings ▸ Automation setup guide** walks you through the 3-minute setup.

> Push notifications from banking apps cannot be read by Shortcuts. Turn on SMS
> alerts in your bank for the best coverage. You can always paste an older
> message with **+ ▸ Paste bank SMS**.

## Features
- Parser for bank / card SMS in many formats: INR, AED, PKR, SAR, USD, GBP, EUR and 20+ more,
  including Indian lakh grouping, European decimal commas, UPI handles, and masked card numbers (`XX1234`)
- Ignores OTPs, promos, payment-due reminders and "available balance" / "credit limit" figures
- Detects income (credits/refunds) separately; optional ignore
- Auto-categorisation (≈300 merchant keywords, including Gulf and South Asian brands) that **learns** when you re-categorise a merchant
- **Duplicate merging**: an Apple Pay tap plus the bank SMS for the same purchase are counted once
- Low-confidence entries are flagged "needs review"
- Overview: month switcher, budget progress, donut chart by category, daily bar chart
- Search and filter transactions, swipe to delete or approve, full edit screen with the original SMS
- Siri: *"Add an expense in Expenses"*, *"How much did I spend in Expenses"*
- **Budgets** — overall or per category, resetting daily, weekly or monthly; notifications at your
  warning level (default 80%) and when fully used, once per period
- Overview: "vs last month" comparison, budget alerts, quick stats (today / this week / daily average)
- Edit any recorded transaction (tap, swipe or long-press), duplicate, delete; add manually or paste an SMS
- **Face ID / passcode lock**
- CSV export

## Install from Windows (no Mac needed)

GitHub builds the app on its macOS machines on every push to `main`
(`.github/workflows/build-ipa.yml`). You then install the resulting `.ipa` from Windows.

1. **Download the build:** GitHub repo ▸ **Actions** ▸ latest green *Build IPA* run ▸
   **Artifacts** ▸ `ExpenseTracker-ipa` (a zip containing `ExpenseTracker.ipa`). Unzip it.
2. **On Windows**, install **iTunes** and **iCloud** from apple.com (the web installers,
   *not* the Microsoft Store versions), then install **Sideloadly** (sideloadly.io).
3. Connect your iPhone by USB, unlock it, and tap **Trust**.
4. Open Sideloadly, drag in `ExpenseTracker.ipa`, enter your Apple ID, and click **Start**.
   Sideloadly signs the app with your Apple ID and installs it.
5. On the iPhone:
   - **Settings ▸ General ▸ VPN & Device Management** ▸ trust your Apple ID.
   - **Settings ▸ Privacy & Security ▸ Developer Mode** ▸ On (the phone restarts).
6. Open **Expenses** and follow the setup guide.

**Free Apple ID limit:** the app stops opening after **7 days** and must be
re-signed. Your data is kept when you re-sign. To re-sign, run Sideloadly again with
the same `.ipa`, or turn on Sideloadly's *Automatic refresh* (needs the PC and iPhone on the same Wi‑Fi).
**AltStore** (altstore.io) with AltServer on Windows is an alternative that refreshes automatically over Wi‑Fi.

To avoid the 7-day expiry, a paid Apple Developer account ($99/year) gives you 1-year
signing, or TestFlight distribution.

## Build & install on your iPhone with a Mac

Requirements: a Mac with **Xcode 15+**, an iPhone on **iOS 17+**, and a free Apple ID.

```bash
brew install xcodegen          # one-time
git clone <this repo> && cd Expense-tracker---Mobile
xcodegen generate              # creates ExpenseTracker.xcodeproj from project.yml
open ExpenseTracker.xcodeproj
```

1. In Xcode select the **ExpenseTracker** target ▸ *Signing & Capabilities* ▸ choose your
   **Team** (your Apple ID). If the bundle ID is taken, change `com.personal.expensetracker`
   to something unique.
2. Plug in your iPhone, select it as the run destination, and press **⌘R**.
3. On the iPhone: *Settings ▸ General ▸ VPN & Device Management* ▸ trust your developer certificate.
   On iOS 16+ also enable *Settings ▸ Privacy & Security ▸ Developer Mode*.
4. Open the app, allow notifications, then follow the setup guide to create the two automations.

With a free Apple ID the app must be re-installed from Xcode every 7 days. A paid developer
account ($99/yr) extends that to a year.

Run the parser unit tests with **⌘U**.

## Project layout
```
project.yml                     XcodeGen spec
ExpenseTracker/
  App/          app entry + tab view
  Models/       Expense (SwiftData), ExpenseCategory
  Services/     TransactionParser, Categorizer, ExpenseStore (save + dedupe), notifications, CSV
  Intents/      App Intents used by Shortcuts and Siri
  Views/        Overview, Transactions, Budgets, Edit, Paste SMS, Settings, Setup guide, App lock
ExpenseTrackerTests/            parser + categoriser tests
```

## Adding your bank's format
If a message isn't read correctly, paste it via **+ ▸ Paste bank SMS** to see what was detected.
Then add a test case to `TransactionParserTests.swift` and adjust the keyword lists or
merchant patterns in `TransactionParser.swift`.
