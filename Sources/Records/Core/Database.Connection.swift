import Foundation
import Logging
import PostgreSQL_Standard
import PostgresNIO

extension Database {
    /// Internal wrapper to bridge to PostgresConnection
    public struct Connection: Records.Database.Connection.`Protocol` {
        let postgres: PostgresConnection
        let logger: Logger

        package init(_ postgres: PostgresConnection, logger: Logger? = nil) {
            self.postgres = postgres
            self.logger = logger ?? Logger(label: "records.connection")
        }

        /// Runs a query on the underlying driver, mapping driver failures into
        /// ``Database/Error/queryFailed(underlying:)``.
        private func run(
            _ query: PostgresQuery
        ) async throws(Database.Error)
            -> PostgresRowSequence
        {
            do {
                return try await postgres.query(query, logger: logger)
            } catch {
                throw .queryFailed(underlying: error)
            }
        }

        public func execute(_ statement: some Statement<()>) async throws(Database.Error) {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else { return }

            let query = try queryFragment.toPostgresQuery()
            _ = try await run(query)
        }

        public func execute(_ sql: String) async throws(Database.Error) {
            let query = PostgresQuery(unsafeSQL: sql)
            _ = try await run(query)
        }

        public func executeFragment(_ fragment: QueryFragment) async throws(Database.Error) {
            let query = try fragment.toPostgresQuery()
            _ = try await run(query)
        }

        public func fetchAll<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws(Database.Error) -> [QueryValue.QueryOutput] {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else { return [] }

            let query = try queryFragment.toPostgresQuery()
            let rows = try await run(query)

            do {
                var results: [QueryValue.QueryOutput] = []
                for try await row in rows {
                    var decoder = PostgresQueryDecoder(row: row)
                    let value = try decoder.decodeColumns(QueryValue.self)
                    results.append(value)
                }
                return results
            } catch let error as Database.Error {
                throw error
            } catch {
                throw .rowDecodingFailed(underlying: error)
            }
        }

        /// Parameter pack overload for fetching tuples of QueryRepresentable types.
        ///
        /// This overload explicitly handles statements with parameter pack tuple types,
        /// allowing type-safe execution of multi-column SELECT queries.
        ///
        /// - Parameter statement: A statement with a tuple QueryValue type.
        /// - Returns: An array of tuples matching the statement's column types.
        public func fetchAll<each V: QueryRepresentable>(
            _ statement: some Statement<(repeat each V)>
        ) async throws(Database.Error) -> [(repeat (each V).QueryOutput)] {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else { return [] }

            let query = try queryFragment.toPostgresQuery()
            let rows = try await run(query)

            do {
                var results: [(repeat (each V).QueryOutput)] = []
                for try await row in rows {
                    var decoder = PostgresQueryDecoder(row: row)
                    let value = try decoder.decodeColumns((repeat (each V)).self)
                    results.append(value)
                }
                return results
            } catch let error as Database.Error {
                throw error
            } catch {
                throw .rowDecodingFailed(underlying: error)
            }
        }

        public func fetchOne<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws(Database.Error) -> QueryValue.QueryOutput? {
            let results = try await fetchAll(statement)
            return results.first
        }

        public func fetchCursor<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws(Database.Error) -> Database.Cursor<QueryValue.QueryOutput> {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else {
                // Return empty cursor for empty queries
                return Database.Cursor<QueryValue.QueryOutput> { nil }
            }

            let query = try queryFragment.toPostgresQuery()
            let rows = try await run(query)

            // We need to manually iterate and decode since PostgresQueryCursor
            // expects QueryDecodable types, but we have QueryRepresentable
            var rowIterator = rows.makeAsyncIterator()

            // Create an actor to safely manage the async iterator
            let iteratorManager = CursorIteratorManager<QueryValue.QueryOutput> {
                () async throws(Database.Error) in
                do {
                    guard let row = try await rowIterator.next() else {
                        return nil
                    }
                    var decoder = PostgresQueryDecoder(row: row)
                    return try decoder.decodeColumns(QueryValue.self)
                } catch let error as Database.Error {
                    throw error
                } catch {
                    throw .rowDecodingFailed(underlying: error)
                }
            }

            return Database.Cursor<QueryValue.QueryOutput> { () async throws(Database.Error) in
                try await iteratorManager.next()
            }
        }
    }
}

/// Actor to safely manage cursor iteration for streaming results
private actor CursorIteratorManager<Element: Sendable> {
    private let fetchNext: () async throws(Database.Error) -> Element?
    private var exhausted = false

    init(fetchNext: @escaping () async throws(Database.Error) -> Element?) {
        self.fetchNext = fetchNext
    }

    func next() async throws(Database.Error) -> Element? {
        guard !exhausted else { return nil }

        if let element = try await fetchNext() {
            return element
        } else {
            exhausted = true
            return nil
        }
    }
}
