import Foundation
import StructuredQueriesPostgres

extension Database {
    /// A notification event with full metadata (channel, payload, backend PID).
    ///
    /// This type wraps a decoded notification payload with its metadata from PostgreSQL.
    /// Use this when you need access to both the payload data and notification context.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = try await db.notificationEvents(on: channel, expecting: MyPayload.self)
    ///
    /// for try await event in stream {
    ///     print("Payload: \(event.payload)")
    ///     print("Channel: \(event.channel)")
    ///     print("Backend PID: \(event.backendPID)")
    /// }
    /// ```
    public struct NotificationEvent<Payload: Decodable & Sendable>: Sendable {
        /// The decoded notification payload
        public let payload: Payload

        /// The channel on which this notification was received
        public let channel: ChannelName

        /// The backend process ID that sent the notification
        public let backendPID: Int32

        /// Creates a notification event
        public init(payload: Payload, channel: ChannelName, backendPID: Int32) {
            self.payload = payload
            self.channel = channel
            self.backendPID = backendPID
        }
    }

    /// A notification message received from PostgreSQL LISTEN/NOTIFY.
    ///
    /// Notifications are sent by PostgreSQL when a NOTIFY command is executed
    /// on a channel that this connection is listening to.
    ///
    /// This type uses type-safe `ChannelName` (Tagged) to ensure channel names are validated,
    /// preventing SQL injection and typos.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Receive notifications with type-safe channel names
    /// for try await notification in db.notifications(channel: "updates") {
    ///     print("Channel: \(notification.channel.rawValue)")
    ///     print("Payload: \(notification.payload)")
    /// }
    /// ```
    public struct Notification: Sendable, Hashable {
        /// The type-safe channel name on which the notification was sent.
        ///
        /// This is a `ChannelName` (Tagged type) that guarantees the identifier is valid.
        public let channel: ChannelName

        /// The notification payload as a string.
        ///
        /// For typed payloads, use the `notifications(channel:as:)` API which automatically
        /// decodes JSON payloads into your Codable types.
        public let payload: String

        /// The backend process ID that sent the notification.
        ///
        /// This can be useful for debugging or filtering notifications from specific processes.
        public let backendPID: Int32

        /// Creates a notification with a type-safe channel name.
        ///
        /// - Parameters:
        ///   - channel: The validated channel name
        ///   - payload: The notification payload as a string
        ///   - backendPID: The PostgreSQL backend process ID
        public init(channel: ChannelName, payload: String, backendPID: Int32) {
            self.channel = channel
            self.payload = payload
            self.backendPID = backendPID
        }

        /// Creates a notification from raw strings (for internal use).
        ///
        /// This initializer validates the channel name at runtime.
        ///
        /// - Parameters:
        ///   - rawChannel: The channel name to validate
        ///   - payload: The notification payload
        ///   - backendPID: The PostgreSQL backend process ID
        /// - Throws: `Database.Error.invalidNotificationChannels` if channel name is invalid
        internal init(rawChannel: String, payload: String, backendPID: Int32) throws {
            self.channel = try ChannelName(validating: rawChannel)
            self.payload = payload
            self.backendPID = backendPID
        }
    }
}
