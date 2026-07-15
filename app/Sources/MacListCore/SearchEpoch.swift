import Foundation

public struct SearchEpochToken: Equatable, Sendable {
    public let queryID: UUID
    public let localIndexID: UUID

    public init(queryID: UUID, localIndexID: UUID) {
        self.queryID = queryID
        self.localIndexID = localIndexID
    }
}

public struct SearchEpoch: Equatable, Sendable {
    private var queryID: UUID
    private var localIndexID: UUID

    public init(
        queryID: UUID = UUID(),
        localIndexID: UUID = UUID()
    ) {
        self.queryID = queryID
        self.localIndexID = localIndexID
    }

    public mutating func beginQuery() -> SearchEpochToken {
        queryID = UUID()
        localIndexID = UUID()
        return currentToken
    }

    public mutating func refreshLocalIndex() -> SearchEpochToken {
        localIndexID = UUID()
        return currentToken
    }

    public mutating func invalidateAll() {
        queryID = UUID()
        localIndexID = UUID()
    }

    public func accepts(_ token: SearchEpochToken) -> Bool {
        token == currentToken
    }

    public func acceptsQuery(_ candidate: UUID) -> Bool {
        candidate == queryID
    }

    private var currentToken: SearchEpochToken {
        SearchEpochToken(queryID: queryID, localIndexID: localIndexID)
    }
}
