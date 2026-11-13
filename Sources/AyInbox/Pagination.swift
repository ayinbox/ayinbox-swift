import Foundation

/// One page of a list: the rows and the cursor for the next page.
public struct Page<Element: Decodable & Sendable>: Decodable, Sendable {
    public let data: [Element]
    /// Pass back as `cursor` for the next page. `nil` on the last page.
    public let nextCursor: String?
    public let hasMore: Bool
    /// Present on some lists only. Do not rely on it.
    public let total: Int?

    enum CodingKeys: String, CodingKey { case data, pagination }
    enum PaginationKeys: String, CodingKey {
        case nextCursor = "next_cursor", hasMore = "has_more", total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([Element].self, forKey: .data) ?? []
        if container.contains(.pagination), (try? container.decodeNil(forKey: .pagination)) == false {
            let pagination = try container.nestedContainer(keyedBy: PaginationKeys.self, forKey: .pagination)
            nextCursor = try pagination.decodeIfPresent(String.self, forKey: .nextCursor)
            hasMore = try pagination.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
            total = try? pagination.decodeIfPresent(Int.self, forKey: .total)
        } else {
            nextCursor = nil
            hasMore = false
            total = nil
        }
    }
}

/// An `AsyncSequence` that yields every row of a paginated list, fetching pages as it goes.
public struct PageSequence<Element: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Fetch = @Sendable (_ cursor: String?) async throws -> Page<Element>
    let fetch: Fetch

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(fetch: fetch)
    }

    public struct Iterator: AsyncIteratorProtocol {
        let fetch: Fetch
        var buffer: [Element] = []
        var index = 0
        var cursor: String?
        var started = false
        var finished = false

        public mutating func next() async throws -> Element? {
            while index >= buffer.count {
                if finished || (started && cursor == nil) { return nil }
                let page = try await fetch(cursor)
                started = true
                buffer = page.data
                index = 0
                if page.hasMore, let next = page.nextCursor, !next.isEmpty {
                    cursor = next
                } else {
                    cursor = nil
                    finished = true
                }
            }
            defer { index += 1 }
            return buffer[index]
        }
    }
}
