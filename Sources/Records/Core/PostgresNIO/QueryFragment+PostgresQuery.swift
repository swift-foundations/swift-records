import Byte_Primitives
import Foundation
import NIOCore
import PostgreSQL_Standard
import PostgresNIO
import Structured_Queries_Primitives_Foundation_Integration

extension PostgresQuery {
    package init(from fragment: QueryFragment) {
        var parameterIndex = 0
        var bindings = PostgresBindings()
        var sqlParts: [String] = []

        // Process segments to build SQL and bindings
        for segment in fragment.segments {
            switch segment {
            case .sql(let sql):
                sqlParts.append(sql)
            case .binding(let binding):
                parameterIndex += 1
                sqlParts.append("$\(parameterIndex)")
                fragment.appendBinding(binding, to: &bindings)
            }
        }

        // Join the SQL parts and normalize whitespace
        let sql = sqlParts.joined()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        self = PostgresQuery(unsafeSQL: sql, binds: bindings)
    }
}

extension QueryFragment {
    /// Converts a QueryFragment to a PostgresQuery for execution
    package func toPostgresQuery() -> PostgresQuery { .init(from: self) }

    func appendBinding(_ binding: QueryBinding, to bindings: inout PostgresBindings) {
        switch binding {
        case .null:
            bindings.appendNull()
        case .int(let value):
            bindings.append(Int(value), context: .default)
        case .double(let value):
            bindings.append(value, context: .default)
        case .text(let value):
            bindings.append(value, context: .default)
        case .blob(let bytes):
            // Convert [Byte] to ByteBuffer for PostgreSQL bytea type
            var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
            buffer.writeBytes(bytes.map(\.underlying))
            bindings.append(buffer, context: .default)
        case .date(let instant):
            // PostgresNIO's timestamp codec is Foundation's Date; the core carries
            // the Foundation-free Instant, so it is lowered here.
            bindings.append(Foundation.Date(instant), context: .default)
        case .uuid(let identifier):
            // Likewise: the core carries 16 raw bytes, PostgresNIO wants a UUID.
            guard let uuid = Foundation.UUID(identifier) else {
                // A payload that is not exactly 16 bytes cannot be a UUID; fall back
                // to null rather than trapping, as the .invalid case does.
                print("Warning: uuid binding is not 16 bytes; binding NULL")
                bindings.appendNull()
                break
            }
            bindings.append(uuid, context: .default)
        case .invalid(let error):
            // Log error and append null as fallback
            print("Warning: Invalid binding with error: \(error)")
            bindings.appendNull()
        case .bool(let value):
            // Use native PostgreSQL boolean type
            bindings.append(value, context: .default)
        case .jsonb(let bytes):
            // Use PostgresNIO's JSONB support
            let postgresData = PostgresData(jsonb: Data(bytes.map(\.underlying)))
            bindings.append(postgresData)
        case .decimal(let digits):
            // The core carries the value's exact digit string; PostgresNIO's NUMERIC
            // codec is Decimal, which is exactly what those digits were produced from
            // (`Decimal.description` in the Foundation Integration target).
            guard let value = Decimal(string: digits) else {
                print("Warning: decimal binding is not a decimal literal: \(digits)")
                bindings.appendNull()
                break
            }
            do {
                try bindings.append(value, context: .default)
            } catch {
                // Decimal encoding should never fail in practice, but handle the error
                // by appending null as a fallback (similar to .invalid case)
                print("Warning: Failed to encode Decimal value: \(error)")
                bindings.appendNull()
            }
        case .boolArray(let values):
            bindings.append(values, context: .default)
        case .stringArray(let values):
            bindings.append(values, context: .default)
        case .intArray(let values):
            bindings.append(values, context: .default)
        case .int16Array(let values):
            bindings.append(values, context: .default)
        case .int32Array(let values):
            bindings.append(values, context: .default)
        case .int64Array(let values):
            bindings.append(values, context: .default)
        case .floatArray(let values):
            bindings.append(values, context: .default)
        case .doubleArray(let values):
            bindings.append(values, context: .default)
        case .uuidArray(let identifiers):
            let uuids = identifiers.compactMap { Foundation.UUID($0) }
            guard uuids.count == identifiers.count else {
                print("Warning: uuidArray binding has a non-16-byte element; binding NULL")
                bindings.appendNull()
                break
            }
            bindings.append(uuids, context: .default)
        case .dateArray(let instants):
            bindings.append(instants.map { Foundation.Date($0) }, context: .default)
        case .genericArray:
            // For generic arrays, we need to recursively append each binding
            // However, PostgreSQL doesn't support heterogeneous arrays, so we need to
            // convert all elements to a compatible type. This is complex and requires
            // determining the common type at runtime.
            // For now, we'll throw an error if this case is hit
            print("Warning: genericArray case not yet implemented for PostgreSQL binding")
            bindings.appendNull()
        }
    }
}
