import Byte_Primitives
import Foundation
import NIOCore
import PostgreSQL_Standard
import PostgresNIO
import Structured_Queries_Primitives_Foundation_Integration
import Time_Primitives

public struct PostgresQueryDecoder: QueryDecoder {
    internal let row: PostgresRandomAccessRow
    private var currentIndex: Int = 0

    public init(row: PostgresRow) {
        self.row = row.makeRandomAccess()
        self.currentIndex = 0
    }

    public mutating func next() {
        currentIndex = 0
    }

    public mutating func decode(_ columnType: [Byte].Type) throws(Database.Error) -> [Byte]? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        // Check for NULL
        if column.bytes == nil {
            return nil
        }

        // Try to decode as JSONB first (PostgreSQL's JSON binary format)
        // PostgreSQL can return JSONB as a text string in JSON format
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let jsonString = try? column.decode(String.self) {
            // If we got a valid JSON string, convert to UTF-8 bytes
            return jsonString.utf8.map(Byte.init)
        }

        // Fall back to ByteA (PostgreSQL's binary data type)
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let buffer = try? column.decode(ByteBuffer.self) {
            return buffer.readableBytesView.map(Byte.init)
        }

        return nil
    }

    public mutating func decode(_ columnType: Double.Type) throws(Database.Error) -> Double? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        do {
            return try column.decode(Double.self)
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    public mutating func decode(_ columnType: Int64.Type) throws(Database.Error) -> Int64? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        // Try direct Int64 decoding first (for INTEGER/BIGINT types)
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let value = try? column.decode(Int64.self) {
            return value
        }

        // Fall back to Decimal for NUMERIC types (from SUM operations)
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let decimal = try? column.decode(Decimal.self) {
            return NSDecimalNumber(decimal: decimal).int64Value
        }

        // If neither works, throw the original error
        do {
            return try column.decode(Int64.self)
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    public mutating func decode(_ columnType: String.Type) throws(Database.Error) -> String? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        do {
            return try column.decode(String.self)
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    public mutating func decode(_ columnType: Bool.Type) throws(Database.Error) -> Bool? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        // Use native PostgreSQL boolean decoding
        do {
            return try column.decode(Bool.self)
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    public mutating func decode(_ columnType: Int.Type) throws(Database.Error) -> Int? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        // Try direct Int decoding first (for INTEGER/BIGINT types)
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let value = try? column.decode(Int.self) {
            return value
        }

        // Fall back to Decimal for NUMERIC types (from SUM operations)
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let decimal = try? column.decode(Decimal.self) {
            return NSDecimalNumber(decimal: decimal).intValue
        }

        // If neither works, throw the original error
        do {
            return try column.decode(Int.self)
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    // The requirement is stated in `Instant` since the L1 Foundation drain.
    // PostgresNIO decodes timestamps as `Foundation.Date`, so the wire value is
    // still read as a `Date` and lifted at the boundary — including the ISO8601
    // string fallback, which is unchanged apart from that lift.
    public mutating func decode(_ columnType: Instant.Type) throws(Database.Error) -> Instant? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        // PostgreSQL can store dates as timestamps
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let date = try? column.decode(Foundation.Date.self) {
            return date.instant
        }

        // Fallback to ISO8601 string parsing
        // Deliberate: representation probe; failure selects the fallback decoding path.
        // swiftlint:disable:next no_try_optional
        if let dateString = try? column.decode(String.self) {
            return ISO8601DateFormatter().date(from: dateString)?.instant
        }

        return nil
    }

    // Likewise stated in the core's byte-based `QueryBinding.UUID`; PostgresNIO's
    // codec is `Foundation.UUID`, so the value is lifted at the boundary.
    public mutating func decode(
        _ columnType: QueryBinding.UUID.Type
    ) throws(Database.Error) -> QueryBinding.UUID? {
        defer { currentIndex += 1 }
        let column = row[currentIndex]

        if column.bytes == nil {
            return nil
        }

        do {
            return QueryBinding.UUID(try column.decode(Foundation.UUID.self))
        } catch {
            throw .rowDecodingFailed(underlying: error)
        }
    }

    // `decode(_: Decimal.Type)` is deliberately absent: the L1 Foundation drain
    // removed that `QueryDecoder` requirement, and `Decimal` now decodes through
    // the Foundation Integration target's `Decimal.init(decoder:)`, which reads
    // the value's exact digits as a `String`.
}
