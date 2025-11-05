import Foundation
import StructuredQueriesPostgres

extension Database.Notification {
    /// A protocol that couples a notification channel with its table and payload type.
    ///
    /// Implement this protocol to create type-safe notification channels with compile-time guarantees
    /// about the table, payload structure, and channel name. The channel name is automatically derived
    /// from the table name by default, eliminating error-prone string literals.
    ///
    /// ## Automatic Channel Naming
    ///
    /// By default, the channel name is derived from the table name with "_notifications" suffix.
    /// This ensures consistency and eliminates typos:
    ///
    /// ```swift
    /// struct ReminderNotifications: Database.Notification.ChannelSchema {
    ///     typealias TableType = Reminder
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let operation: String
    ///         let new: Reminder?
    ///     }
    ///     // channelName automatically becomes "reminders_notifications"
    /// }
    /// ```
    ///
    /// ## Custom Channel Names
    ///
    /// Override `channelName` for custom naming (use sparingly):
    ///
    /// ```swift
    /// struct ReminderNotifications: Database.Notification.ChannelSchema {
    ///     typealias TableType = Reminder
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let operation: String
    ///         let new: Reminder?
    ///     }
    ///
    ///     static let channelName: ChannelName = "reminder_events"  // Custom name
    /// }
    /// ```
    ///
    /// ## Type-Safe Usage
    ///
    /// The schema enforces that the channel is always used with its correct table:
    ///
    /// ```swift
    /// // Setup - table type is derived from schema!
    /// try await db.setupNotificationChannel(
    ///     schema: ReminderNotifications.self,
    ///     on: .insert, .update, .delete
    /// )
    ///
    /// // Listen - payload type is guaranteed
    /// for try await event in try await db.notifications(schema: ReminderNotifications.self) {
    ///     // event is ReminderNotifications.Payload
    ///     print(event.new?.title ?? "deleted")
    /// }
    ///
    /// // Send - impossible to use wrong table or payload
    /// try await db.notify(
    ///     schema: ReminderNotifications.self,
    ///     payload: ReminderNotifications.Payload(operation: "INSERT", new: reminder)
    /// )
    /// ```
    public protocol ChannelSchema {
        /// The table this notification channel is associated with.
        /// This creates an unbreakable compile-time link between the channel and its table.
        associatedtype TableType: Table

        /// The payload type that will be sent and received on this channel.
        /// Must be Codable for automatic JSON encoding/decoding and Sendable for Swift concurrency.
        associatedtype Payload: Codable & Sendable

        /// The type-safe PostgreSQL channel name.
        ///
        /// This is a `ChannelName` (Tagged type) that guarantees the identifier is valid.
        /// Defaults to "{tableName}_notifications" - override only when necessary.
        static var channelName: ChannelName { get }
    }
}

extension Database.Notification.ChannelSchema {
    /// Default channel name: derived from table name with "_notifications" suffix.
    ///
    /// This eliminates the need for manual string literals in most cases:
    /// - `Reminder` table → `"reminders_notifications"`
    /// - `User` table → `"users_notifications"`
    /// - `BlogPost` table → `"blogPosts_notifications"`
    ///
    /// Override this property only when you need a custom channel name.
    ///
    /// The returned `ChannelName` is type-safe and validated, preventing SQL injection.
    @inlinable
    public static var channelName: ChannelName {
        // Safe: @Table macro ensures tableName is a valid PostgreSQL identifier
        // We construct the channel name by appending "_notifications" suffix
        ChannelName(stringLiteral: "\(TableType.tableName)_notifications")
    }

    /// A type-safe channel instance for this schema.
    ///
    /// Use this to get a phantom-typed channel from your schema:
    ///
    /// ```swift
    /// let channel = ReminderNotifications.channel
    /// for try await notification in try await db.notifications(channel: channel) {
    ///     // notification.payload is already decoded as ReminderNotifications.Payload
    /// }
    /// ```
    @inlinable
    public static var channel: Database.Notification.Channel<Payload> {
        Database.Notification.Channel(channelName)
    }
}
