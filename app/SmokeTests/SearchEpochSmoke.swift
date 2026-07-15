import Foundation

enum SearchEpochSmoke {
    static func run() {
        var epoch = SearchEpoch()
        let oldToken = epoch.beginQuery()
        let refreshedToken = epoch.refreshLocalIndex()
        precondition(!epoch.accepts(oldToken))
        precondition(epoch.accepts(refreshedToken))
        precondition(epoch.acceptsQuery(oldToken.queryID))

        let nextQuery = epoch.beginQuery()
        precondition(!epoch.accepts(refreshedToken))
        precondition(!epoch.acceptsQuery(refreshedToken.queryID))
        precondition(epoch.accepts(nextQuery))

        epoch.invalidateAll()
        precondition(!epoch.accepts(nextQuery))
        precondition(!epoch.acceptsQuery(nextQuery.queryID))
        print("search-epoch: ok")
    }
}
