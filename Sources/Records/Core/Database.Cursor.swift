import Foundation

// MARK: - Database.Cursor

extension Database {
    /// A cursor for iterating over query results.
    ///
    /// Query cursors allow you to iterate over database results without loading
    /// all rows into memory at once.
    public struct Cursor<Element: Sendable>: AsyncSequence, Sendable {
        public typealias Element = Element

        private let fetchNext: @Sendable () async throws(Database.Error) -> Element?

        init(fetchNext: @escaping @Sendable () async throws(Database.Error) -> Element?) {
            self.fetchNext = fetchNext
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(fetchNext: fetchNext)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private let fetchNext: @Sendable () async throws(Database.Error) -> Element?
            private var exhausted = false

            init(fetchNext: @escaping @Sendable () async throws(Database.Error) -> Element?) {
                self.fetchNext = fetchNext
            }

            public mutating func next() async throws(Database.Error) -> Element? {
                guard !exhausted else { return nil }

                if let element = try await fetchNext() {
                    return element
                } else {
                    exhausted = true
                    return nil
                }
            }
        }

        /// Returns the next element from the cursor.
        public func next() async throws(Database.Error) -> Element? {
            try await fetchNext()
        }

        /// Collects all remaining elements into an array.
        ///
        /// - Warning: This loads all remaining rows into memory.
        public func fetchAll() async throws(Database.Error) -> [Element] {
            var results: [Element] = []
            while let element = try await next() {
                results.append(element)
            }
            return results
        }
    }
}
