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
}
