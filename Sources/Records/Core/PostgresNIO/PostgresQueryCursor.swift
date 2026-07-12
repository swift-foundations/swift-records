import Foundation
import NIOCore
import PostgresNIO
import PostgreSQL_Standard

// extension Database {
//    /// A cursor for iterating over PostgreSQL query results
//    public struct QueryCursor<Element: QueryDecodable>: AsyncSequence {
//        public typealias Element = Element
//
//        private let rows: PostgresRowSequence
//
//        public init(rows: PostgresRowSequence) {
//            self.rows = rows
//        }
//
//        public func makeAsyncIterator() -> AsyncIterator {
//            AsyncIterator(rows: rows)
//        }
//
//        public struct AsyncIterator: AsyncIteratorProtocol {
//            private var rowIterator: PostgresRowSequence.AsyncIterator
//
//            init(rows: PostgresRowSequence) {
//                self.rowIterator = rows.makeAsyncIterator()
//            }
//
//            public mutating func next() async throws -> Element? {
//                guard let row = try await rowIterator.next() else {
//                    return nil
//                }
//
//                var decoder = PostgresQueryDecoder(row: row)
//                return try Element(decoder: &decoder)
//            }
//        }
//    }
// }
