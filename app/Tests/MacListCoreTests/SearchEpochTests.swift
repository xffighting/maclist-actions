import XCTest
@testable import MacListCore

final class SearchEpochTests: XCTestCase {
    func testRefreshingLocalIndexRejectsOlderLocalResultButKeepsCurrentQuery() {
        var epoch = SearchEpoch()
        let oldToken = epoch.beginQuery()
        let refreshedToken = epoch.refreshLocalIndex()

        XCTAssertFalse(epoch.accepts(oldToken))
        XCTAssertTrue(epoch.accepts(refreshedToken))
        XCTAssertTrue(epoch.acceptsQuery(oldToken.queryID))
    }

    func testBeginningNewQueryRejectsEveryOlderResult() {
        var epoch = SearchEpoch()
        let oldToken = epoch.beginQuery()
        let currentToken = epoch.beginQuery()

        XCTAssertFalse(epoch.accepts(oldToken))
        XCTAssertFalse(epoch.acceptsQuery(oldToken.queryID))
        XCTAssertTrue(epoch.accepts(currentToken))
        XCTAssertTrue(epoch.acceptsQuery(currentToken.queryID))
    }

    func testInvalidationRejectsOutstandingLocalAndSpotlightResults() {
        var epoch = SearchEpoch()
        let token = epoch.beginQuery()
        epoch.invalidateAll()

        XCTAssertFalse(epoch.accepts(token))
        XCTAssertFalse(epoch.acceptsQuery(token.queryID))
    }
}
