import XCTest
@testable import ExpenseTracker

final class TransactionParserTests: XCTestCase {

    private func parse(_ s: String, _ cur: String = "USD") -> ParsedTransaction? {
        TransactionParser.parse(s, defaultCurrency: cur)
    }

    func testIndianUPIDebit() throws {
        let p = try XCTUnwrap(parse("Rs.1,250.00 debited from A/c XX1234 on 05-11-26 to VPA swiggy@icici. Ref 1234567."))
        XCTAssertEqual(p.amount, 1250)
        XCTAssertEqual(p.currency, "INR")
        XCTAssertEqual(p.merchant, "swiggy")
        XCTAssertEqual(p.account, "1234")
        XCTAssertFalse(p.isIncome)
    }

    func testUAECreditCardIgnoresLimit() throws {
        let p = try XCTUnwrap(parse("AED 45.50 spent on your Credit Card ending 4321 at CARREFOUR DUBAI on 06/11/2026. Avl Cr. limit AED 12,000.00"))
        XCTAssertEqual(p.amount, 45.5)
        XCTAssertEqual(p.currency, "AED")
        XCTAssertEqual(p.merchant, "Carrefour Dubai")
        XCTAssertEqual(p.account, "4321")
    }

    func testDollarUsesDefaultDollarCurrency() throws {
        let p = try XCTUnwrap(parse("You spent $12.40 at Starbucks with card ending 9876.", "CAD"))
        XCTAssertEqual(p.amount, 12.4)
        XCTAssertEqual(p.currency, "CAD")
        XCTAssertEqual(p.merchant, "Starbucks")
    }

    func testCreditIsIncome() throws {
        let p = try XCTUnwrap(parse("INR 500.00 credited to your a/c **1234 from JOHN DOE on 05-Nov. Avl Bal INR 10,000"))
        XCTAssertTrue(p.isIncome)
        XCTAssertEqual(p.amount, 500)
        XCTAssertEqual(p.merchant, "John Doe")
    }

    func testBalanceBeforeAmountIsSkipped() throws {
        let p = try XCTUnwrap(parse("Your A/c XX5678 is debited with PKR 3,500.00 for purchase at KFC Gulberg on 06-Nov-26. Bal PKR 45,000"))
        XCTAssertEqual(p.amount, 3500)
        XCTAssertEqual(p.currency, "PKR")
        XCTAssertEqual(p.merchant, "KFC Gulberg")
    }

    func testThankYouForUsingCard() throws {
        let p = try XCTUnwrap(parse("Thank you for using your card ending 3333 for GBP 23.10 at TESCO STORES 2134 on 06 Nov"))
        XCTAssertEqual(p.amount, 23.1)
        XCTAssertEqual(p.currency, "GBP")
        XCTAssertFalse(p.isIncome)
    }

    func testEuropeanDecimalComma() throws {
        let p = try XCTUnwrap(parse("12,50 € paid at Lidl Berlin"))
        XCTAssertEqual(p.amount, 12.5)
        XCTAssertEqual(p.currency, "EUR")
    }

    func testIndianLakhGrouping() {
        XCTAssertEqual(TransactionParser.number(from: "1,00,000.50"), 100000.5)
    }

    func testOTPIgnored() {
        XCTAssertNil(parse("Your OTP for txn of Rs 500 is 123456. Do not share"))
    }

    func testPromoIgnored() {
        XCTAssertNil(parse("Get 20% off on orders above Rs 500! Shop now"))
    }

    func testDueReminderIgnored() {
        XCTAssertNil(parse("Your credit card bill of AED 1,200 is due on 15-Nov."))
    }

    func testWalletAmountString() throws {
        let a = try XCTUnwrap(TransactionParser.parseAmountString("AED 45.00", defaultCurrency: "USD"))
        XCTAssertEqual(a.value, 45); XCTAssertEqual(a.currency, "AED")
        let b = try XCTUnwrap(TransactionParser.parseAmountString("18.75", defaultCurrency: "GBP"))
        XCTAssertEqual(b.value, 18.75); XCTAssertEqual(b.currency, "GBP")
    }

    func testCategorizer() {
        XCTAssertEqual(Categorizer.categorize(merchant: "Carrefour Dubai", text: nil, isIncome: false), .groceries)
        XCTAssertEqual(Categorizer.categorize(merchant: "swiggy", text: nil, isIncome: false), .food)
        XCTAssertEqual(Categorizer.categorize(merchant: "Netflix.Com", text: nil, isIncome: false), .subscriptions)
        XCTAssertEqual(Categorizer.categorize(merchant: "Coca-Cola Arena", text: nil, isIncome: false), .other)
    }

    func testBudgetPeriodIntervals() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        let date = ISO8601DateFormatter().date(from: "2026-11-06T15:30:00Z")!
        let day = BudgetPeriod.daily.interval(containing: date, calendar: cal)
        XCTAssertEqual(day.duration, 86_400)
        let month = BudgetPeriod.monthly.interval(containing: date, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: month.start), 1)
        XCTAssertEqual(month.duration, 30 * 86_400)
        let week = BudgetPeriod.weekly.interval(containing: date, calendar: cal)
        XCTAssertEqual(week.duration, 7 * 86_400)
        XCTAssertTrue(week.contains(date))
        // Same key inside a period, different key in the next one.
        let later = date.addingTimeInterval(3600)
        XCTAssertEqual(BudgetPeriod.daily.key(for: date, calendar: cal), BudgetPeriod.daily.key(for: later, calendar: cal))
        XCTAssertNotEqual(BudgetPeriod.daily.key(for: date, calendar: cal),
                          BudgetPeriod.daily.key(for: date.addingTimeInterval(86_400), calendar: cal))
    }

    func testBudgetStatusLevels() {
        let i = DateInterval(start: .now, duration: 86_400)
        XCTAssertEqual(BudgetStatus(spent: 50, limit: 100, warnAt: 0.8, interval: i).level, .ok)
        XCTAssertEqual(BudgetStatus(spent: 85, limit: 100, warnAt: 0.8, interval: i).level, .warning)
        XCTAssertEqual(BudgetStatus(spent: 100, limit: 100, warnAt: 0.8, interval: i).level, .exceeded)
    }

    func testBankDetection() {
        XCTAssertEqual(BankDetector.detect(text: "Rs 500 debited", sender: "AD-HDFCBK"), "HDFC Bank")
        XCTAssertEqual(BankDetector.detect(text: "Rs 500 debited", sender: "VM-SBIINB-S"), "SBI")
        XCTAssertEqual(BankDetector.detect(text: "AED 45 spent", sender: "EmiratesNBD"), "Emirates NBD")
        XCTAssertEqual(BankDetector.detect(text: "Your ADCB card ending 1234 was used for AED 20", sender: nil), "ADCB")
        XCTAssertEqual(BankDetector.detect(text: "PKR 900 paid from your Meezan Bank account", sender: "8079"), "Meezan Bank")
        XCTAssertNil(BankDetector.detect(text: "AED 45 spent at Carrefour", sender: "+971501234567"))
        XCTAssertEqual(BankDetector.fromWalletCard("Emirates NBD Visa Infinite"), "Emirates NBD")
        XCTAssertEqual(BankDetector.fromWalletCard("My Travel Card"), "My Travel Card")
        XCTAssertNil(BankDetector.fromWalletCard("1234"))
        XCTAssertEqual(ExpenseStore.lastDigits("Visa ••1234"), "1234")
    }

    // MARK: Gulf formats (3-decimal currencies)

    func testBahrainDebitWithFils() throws {
        let p = try XCTUnwrap(parse("BD 12.345 has been debited from your account XXXX81150000 at LULU HYPERMARKET on 07/11/2026", "BHD"))
        XCTAssertEqual(p.amount, 12.345, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertEqual(p.merchant, "Lulu Hypermarket")
        XCTAssertFalse(p.isIncome)
    }

    func testKuwaitCardTrx() throws {
        let p = try XCTUnwrap(parse("Trx on your card XXXX1234 for KWD 7.500 at TALABAT on 07-11-2026. Avl limit KWD 990.000", "KWD"))
        XCTAssertEqual(p.amount, 7.5, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "KWD")
        XCTAssertEqual(p.merchant, "Talabat")
        XCTAssertEqual(p.account, "1234")
        XCTAssertFalse(p.isIncome)
    }

    func testAccountHasBeenDebited() throws {
        let p = try XCTUnwrap(parse("Your A/C 0020-XXXX71-300 has been debited with BHD 25.000 on 07/11/2026", "BHD"))
        XCTAssertEqual(p.amount, 25, accuracy: 0.0001)
        XCTAssertFalse(p.isIncome)
    }

    func testGulfBanks() {
        XCTAssertEqual(BankDetector.detect(text: "Trx on your KFH card", sender: nil), "KFH")
        XCTAssertEqual(BankDetector.detect(text: "BD 5.000 debited", sender: "ALSALAM"), "Al Salam Bank")
        XCTAssertEqual(BankDetector.detect(text: "BD 5.000 debited", sender: "BBK"), "BBK")
    }

    // "Credited to beneficiary IBAN" = money sent from your account.
    func testCreditedToBeneficiaryIBANIsExpense() throws {
        let sms = "BHD 50.000 credited to beneficiary IBAN BH12XXXXXXXX0001 from your account XXXX8115 on 07/11/2026"
        let p = try XCTUnwrap(parse(sms, "BHD"))
        XCTAssertFalse(p.isIncome)
        XCTAssertEqual(p.amount, 50, accuracy: 0.0001)
        XCTAssertNil(p.merchant)   // not recognised → shown as Unknown
        XCTAssertEqual(Categorizer.categorize(merchant: p.merchant, text: sms, isIncome: false), .transfer)
    }

    func testRealIncomeStillIncome() throws {
        let p = try XCTUnwrap(parse("BHD 500.000 has been credited to your account XXXX8115", "BHD"))
        XCTAssertTrue(p.isIncome)
    }

    // MARK: Voice & receipt

    func testVoiceDinarsAtMerchant() throws {
        let p = VoiceParser.parse("2.5 dinars coffee at Costa", defaultCurrency: "BHD")
        XCTAssertEqual(try XCTUnwrap(p.amount), 2.5, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertEqual(p.merchant, "Costa")
        XCTAssertEqual(p.category, .food)
    }

    func testVoiceShortForm() throws {
        let p = VoiceParser.parse("taxi 3 BD", defaultCurrency: "BHD")
        XCTAssertEqual(try XCTUnwrap(p.amount), 3, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertEqual(p.category, .transport)
    }

    func testVoiceGroceries() throws {
        let p = VoiceParser.parse("spent 45 on groceries", defaultCurrency: "BHD")
        XCTAssertEqual(try XCTUnwrap(p.amount), 45, accuracy: 0.0001)
        XCTAssertEqual(p.category, .groceries)
    }

    func testReceiptTotal() throws {
        let lines = ["CARREFOUR CITY CENTRE", "Tel 17000000", "Milk 1.200", "Bread 0.450", "Subtotal 1.650",
                     "VAT 10% 0.165", "TOTAL BHD 1.815", "Cash 2.000", "Change 0.185", "07/11/2026"]
        let p = ReceiptParser.parse(lines: lines, defaultCurrency: "BHD")
        XCTAssertEqual(try XCTUnwrap(p.amount), 1.815, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertEqual(p.merchant, "Carrefour City Centre")
        XCTAssertEqual(p.category, .groceries)
        XCTAssertNotNil(p.date)
    }

    // Real KFH-style card SMS (double space before the amount, merchant after "from").
    func testTrxFromMerchantDoubleSpace() throws {
        let sms = "You have a Trx on your Card no. XXXX2021 from ANWAR ALBAHRAIN PHONES for BHD  2.600 on 13-Nov at 7:16 PM  GMT+3 Available Bal"
        let p = try XCTUnwrap(parse(sms, "BHD"))
        XCTAssertEqual(p.amount, 2.6, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertFalse(p.isIncome)
        XCTAssertEqual(p.merchant, "Anwar Albahrain Phones")
        XCTAssertEqual(p.account, "2021")
        XCTAssertEqual(Categorizer.categorize(merchant: p.merchant, text: sms, isIncome: false), .shopping)
    }

    func testYearlyAndCustomBudgetWindows() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = ISO8601DateFormatter().date(from: "2026-11-06T15:30:00Z")!
        let year = BudgetPeriod.yearly.interval(containing: date, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: year.start), 1)
        XCTAssertEqual(cal.component(.day, from: year.start), 1)

        let b = Budget(category: nil, period: .custom, limit: 100, currency: "BHD")
        b.customStart = ISO8601DateFormatter().date(from: "2026-11-01T10:00:00Z")!
        b.customEnd = ISO8601DateFormatter().date(from: "2026-11-10T10:00:00Z")!
        let i = b.interval(calendar: cal)
        XCTAssertEqual(i.duration, 10 * 86_400)            // 1–10 Nov inclusive
        XCTAssertEqual(b.previousInterval(calendar: cal).duration, 10 * 86_400)
        XCTAssertEqual(b.previousInterval(calendar: cal).end, i.start)
    }

    // Al Salam-style debit: no space after BHD, billing descriptor merchant.
    func testAppleBillingDebit() throws {
        let sms = "Dear Client,  BHD2.132 has been debited from your account XXXX81150000 at APPLE.COM/BILL ITUNES.COM IE on 14/11 at 10:00."
        let p = try XCTUnwrap(parse(sms, "BHD"))
        XCTAssertEqual(p.amount, 2.132, accuracy: 0.0001)
        XCTAssertEqual(p.currency, "BHD")
        XCTAssertFalse(p.isIncome)
        XCTAssertEqual(p.merchant, "Apple")
        XCTAssertEqual(Categorizer.categorize(merchant: p.merchant, text: sms, isIncome: false), .subscriptions)
    }

    func testCountryCodeStripped() throws {
        let p = try XCTUnwrap(parse("BHD 5.000 has been debited from your account XXXX1111 at CITY CENTRE CAFE BH on 14/11", "BHD"))
        XCTAssertEqual(p.merchant, "City Centre Cafe")
    }
}
