import Foundation

extension Database.Notification {
    /// A PostgreSQL notification payload that is guaranteed to be valid UTF-8.
    ///
    /// This type ensures that:
    /// 1. Payloads are validated as UTF-8 **once** at creation time
    /// 2. UTF-8 → Data conversion is cached and reused
    /// 3. Invalid UTF-8 is caught at the boundary (when receiving from PostgreSQL)
    ///
    /// ## Example
    ///
    /// ```swift
    /// // From PostgreSQL notification
    /// let payload = NotificationPayload(validated: notification.payload)
    ///
    /// // Decode as JSON
    /// let event = try payload.decode(as: ReminderEvent.self)
    ///
    /// // Access as string
    /// print(payload.string)
    /// ```
    ///
    /// ## Performance
    ///
    /// The UTF-8 encoding is cached, so repeated access to `.data` or `.decode()` doesn't
    /// re-encode the string. This is significantly faster than re-encoding on every access.
    @frozen
    public struct Payload: Sendable, Hashable {
        /// The validated UTF-8 data.
        ///
        /// This is cached at initialization to avoid repeated string → data conversion.
        @usableFromInline
        let utf8Data: Data

        /// The payload as a string.
        ///
        /// This is a cheap accessor since the data is already validated as UTF-8.
        @inlinable
        public var string: String {
            // Safe: utf8Data is guaranteed to be valid UTF-8
            String(data: utf8Data, encoding: .utf8)!
        }

        /// The payload as UTF-8 data.
        ///
        /// This returns the cached data without re-encoding.
        @inlinable
        public var data: Data {
            utf8Data
        }

        /// Creates a payload from a validated UTF-8 string.
        ///
        /// This is a safe initializer for strings that are already known to be valid UTF-8
        /// (e.g., from PostgreSQL).
        ///
        /// - Parameter validated: A string guaranteed to be valid UTF-8
        @usableFromInline
        init(validated: String) {
            // Safe: PostgreSQL text columns are always valid UTF-8
            self.utf8Data = validated.data(using: .utf8)!
        }

        /// Creates a payload by encoding a value to JSON.
        ///
        /// This is the primary way to create payloads for sending notifications.
        ///
        /// - Parameters:
        ///   - value: The encodable value to serialize as JSON
        ///   - encoder: The JSON encoder to use (default: JSONEncoder())
        /// - Throws: Encoding errors if the value cannot be serialized
        @inlinable
        public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONEncoder()) throws {
            self.utf8Data = try encoder.encode(value)
        }

        /// Decodes the payload as JSON.
        ///
        /// This method uses the cached UTF-8 data for efficient decoding.
        ///
        /// - Parameters:
        ///   - type: The type to decode (can be inferred)
        ///   - decoder: The JSON decoder to use (default: JSONDecoder())
        /// - Returns: The decoded value
        /// - Throws: Decoding errors if the payload is not valid JSON or doesn't match the type
        @inlinable
        public func decode<T: Decodable>(
            as type: T.Type = T.self,
            decoder: JSONDecoder = JSONDecoder()
        ) throws -> T {
            try decoder.decode(T.self, from: utf8Data)
        }
    }
}

// MARK: - String Conversion

extension Database.Notification.Payload: CustomStringConvertible {
    @inlinable
    public var description: String {
        string
    }
}

extension Database.Notification.Payload: CustomDebugStringConvertible {
    @inlinable
    public var debugDescription: String {
        "NotificationPayload(\(string))"
    }
}

// MARK: - ExpressibleByStringLiteral (for Testing)

extension Database.Notification.Payload: ExpressibleByStringLiteral {
    /// Creates a payload from a string literal.
    ///
    /// This is primarily for testing. In production code, use `init(encoding:)` for type safety.
    @inlinable
    public init(stringLiteral value: String) {
        self.init(validated: value)
    }
}
