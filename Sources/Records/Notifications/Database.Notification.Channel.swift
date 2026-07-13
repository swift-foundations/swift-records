import Foundation
import StructuredQueriesPostgres

extension Database.Notification {
    /// A phantom-typed notification channel that couples a channel name with its payload type.
    ///
    /// This type provides compile-time type safety for notification payloads without runtime overhead.
    /// The payload type parameter `Payload` is phantom - it exists only at compile time to ensure
    /// type safety when sending and receiving notifications.
    ///
    /// The channel name is type-safe using `ChannelName` (a Tagged type), ensuring that only
    /// validated PostgreSQL identifiers can be used.
    ///
    /// You can create channels in three ways:
    ///
    /// 1. From a `Database.Notification.ChannelSchema`:
    /// ```swift
    /// let channel = UserEventsChannel.channel
    /// ```
    ///
    /// 2. Using a validated channel name:
    /// ```swift
    /// let channelName: ChannelName = "my_channel"
    /// let channel = Database.Notification.Channel<MyPayload>(channelName)
    /// ```
    ///
    /// 3. From a string literal (validated at compile time):
    /// ```swift
    /// let channel: Database.Notification.Channel<MyPayload> = "my_channel"
    /// ```
    public struct Channel<Payload: Codable & Sendable>: Sendable, Hashable {
        /// The type-safe PostgreSQL channel name.
        ///
        /// This is a `ChannelName` (Tagged type) that guarantees the identifier is valid.
        public let name: ChannelName

        /// Creates a type-safe notification channel with a validated channel name.
        ///
        /// - Parameter name: A validated PostgreSQL channel name
        @inlinable
        public init(_ name: ChannelName) {
            self.name = name
        }

        /// Creates a type-safe notification channel from a raw string.
        ///
        /// This method validates the string at runtime. For compile-time validated strings,
        /// use string literals instead.
        ///
        /// - Parameter rawName: The channel name to validate
        /// - Throws: `Database.Error.invalidNotificationChannels` if validation fails
        @inlinable
        public init(validating rawName: String) throws {
            self.name = try ChannelName(validating: rawName)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension Database.Notification.Channel: ExpressibleByStringLiteral {
    /// Creates a type-safe notification channel from a string literal.
    ///
    /// The string literal is validated at runtime. If invalid, this will crash.
    /// For runtime strings, use `init(validating:)` instead.
    ///
    /// This allows you to write:
    /// ```swift
    /// let channel: Database.Notification.Channel<MyPayload> = "my_channel"
    /// ```
    @inlinable
    public init(stringLiteral value: String) {
        self.name = ChannelName(stringLiteral: value)
    }
}
