import XCTest
@testable import BasirConvert

/// The app's view of plans must match the server's (basir/billing/plans.py):
/// the same products, the same allowances, the same way of counting pages.
final class BillingTests: XCTestCase {
    func testEveryPaidPlanHasAMonthlyAndAYearlyProductThatMapsBack() {
        XCTAssertEqual(BillingPlanID.allProductIDs.count, 8)
        for plan in BillingPlanID.paid {
            for yearly in [false, true] {
                let product = try! XCTUnwrap(plan.productID(yearly: yearly))
                XCTAssertTrue(product.hasPrefix("com.basir.convert.ios."))
                XCTAssertEqual(BillingPlanID.plan(forProduct: product), plan)
            }
        }
        XCTAssertNil(BillingPlanID.free.productID(yearly: false))
        XCTAssertNil(BillingPlanID.plan(forProduct: "com.example.coins"))
    }

    func testAllowancesMatchTheServerAndGrowWithThePlan() {
        XCTAssertEqual(BillingPlanID.allCases.map(\.pagesPerMonth), [20, 55, 150, 320, 650])
    }

    func testMostAccurateCountsEveryPageTwice() {
        XCTAssertEqual(BillingEstimate.pages(documentPages: 12, preferredModel: "accurate"), 24)
        XCTAssertEqual(BillingEstimate.pages(documentPages: 12, preferredModel: "auto"), 12)
        XCTAssertEqual(BillingEstimate.pages(documentPages: 12, preferredModel: nil), 12)
        XCTAssertEqual(BillingEstimate.pages(documentPages: -3, preferredModel: "fast"), 0)
    }

    func testTheServersStatusIsReadWithItsDates() throws {
        let json = """
        {"mode":"enforce","plan":"reader","plan_name":"قارئ","pages_per_month":150,"pages_used":40,
         "pages_remaining":110,"period_start":"2026-10-15T09:00:00+00:00",
         "period_end":"2026-11-15T09:00:00.123000+00:00","product_id":"com.basir.convert.ios.reader.monthly",
         "expires_at":"2026-11-15T09:00:00+00:00","will_renew":true,"environment":"Sandbox","plans":[]}
        """
        let status = try BillingStatus.decode(Data(json.utf8))
        XCTAssertEqual(status.planID, .reader)
        XCTAssertEqual(status.pagesRemaining, 110)
        XCTAssertNotNil(status.periodEnd)
        XCTAssertTrue(status.fits(110))
        XCTAssertFalse(status.fits(111))
    }

    func testNothingIsRefusedUntilTheServerEnforcesPlans() throws {
        let json = """
        {"mode":"meter","plan":"free","plan_name":"Free","pages_per_month":20,"pages_used":20,
         "pages_remaining":0,"period_end":null,"product_id":null,"expires_at":null,"will_renew":null}
        """
        let status = try BillingStatus.decode(Data(json.utf8))
        XCTAssertTrue(status.fits(500))
        XCTAssertTrue(status.isActive)
        XCTAssertFalse(status.isEnforced)
    }

    func testTheAccountIdentifierIsStableAndShapedForTheServer() {
        let first = BillingAccount.header
        XCTAssertEqual(first, BillingAccount.header)
        XCTAssertEqual(first, first.lowercased())
        XCTAssertNotNil(UUID(uuidString: first))
    }
}
