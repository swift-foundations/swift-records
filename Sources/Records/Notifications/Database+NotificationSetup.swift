import Foundation
import StructuredQueriesPostgres
import Tagged

// Note: Notification channel setup is provided as extensions on Database.Connection.Protocol
// See Database+NotificationSetup.swift for the type-safe API

// MARK: - Database Connection Protocol Extensions

extension Database.Connection.`Protocol` {
    // MARK: - Type-Safe Notification Setup

    /// Sets up a notification channel using a schema for maximum type safety.
    ///
    /// The table type is automatically derived from the schema, eliminating the possibility
    /// of mismatched table-channel pairs.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderNotifications: Database.Notification.ChannelSchema {
    ///     typealias TableType = Reminder
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let operation: String
    ///         let new: Reminder?
    ///     }
    ///     // channelName automatically: "reminders_notifications"
    /// }
    ///
    /// try await db.write { db in
    ///     try await db.setupNotificationChannel(
    ///         schema: ReminderNotifications.self,  // Table derived from schema!
    ///         on: .insert, .update, .delete
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type (contains table type)
    ///   - event: One or more database events (variadic)
    ///   - timing: When the trigger fires
    ///   - includeOldValues: Whether to include OLD row values
    /// - Returns: A type-safe channel instance
    /// - Throws: Database errors if setup fails
    @discardableResult
    public func setupNotificationChannel<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type,
        on event: Database.Notification.TriggerEvent...,
        timing: Database.Notification.TriggerTiming = .after,
        includeOldValues: Bool = false
    ) async throws -> Database.Notification.Channel<Schema.Payload> {
        let events = Array(event)
        return try await setupNotificationChannel(
            for: Schema.TableType.self,
            channel: Schema.channel,
            on: events,
            timing: timing,
            includeOldValues: includeOldValues
        )
    }

    // Helper overload that takes an array for internal use
    @discardableResult
    func setupNotificationChannel<On: Table, Payload: Codable & Sendable>(
        for table: On.Type,
        channel: Database.Notification.Channel<Payload>,
        on events: [Database.Notification.TriggerEvent],
        timing: Database.Notification.TriggerTiming = .after,
        includeOldValues: Bool = false
    ) async throws -> Database.Notification.Channel<Payload> {
        print("📢 Setting up notification channel '\(channel.name)' for table '\(On.tableName)'")

        // 1. Create trigger function
        try await createNotificationTriggerFunction(
            for: On.self,
            channel: channel.name,
            includeOldValues: includeOldValues
        )

        // 2. Drop existing trigger (if exists)
        try await dropNotificationTrigger(
            for: On.self,
            channel: channel.name,
            ifExists: true
        )

        // 3. Create trigger
        try await createNotificationTrigger(
            for: On.self,
            channel: channel.name,
            events: events,
            timing: timing
        )

        print(
            "✅ Successfully set up notification channel '\(channel.name)' for table '\(On.tableName)'"
        )
        return channel
    }

    /// Removes notification channel setup using a schema.
    ///
    /// The table type is automatically derived from the schema.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.removeNotificationChannel(
    ///         schema: ReminderNotifications.self  // Table derived from schema!
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The channel schema type (contains table type)
    /// - Throws: Database errors if removal fails
    public func removeNotificationChannel<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type
    ) async throws {
        let functionName = FunctionName(
            stringLiteral: "\(Schema.TableType.tableName)_\(Schema.channel.name.rawValue)_notify"
        )

        print(
            "📢 Removing notification channel '\(Schema.channel.name)' from table '\(Schema.TableType.tableName)'"
        )

        // 1. Drop trigger
        try await dropNotificationTrigger(
            for: Schema.TableType.self,
            channel: Schema.channel.name,
            ifExists: true
        )

        // 2. Drop function
        try await dropNotificationTriggerFunction(name: functionName, ifExists: true)

        print(
            "✅ Successfully removed notification channel '\(Schema.channel.name)' from table '\(Schema.TableType.tableName)'"
        )
    }

    // MARK: - Internal Helpers (Type-Safe)

    /// Creates a notification trigger function for a table.
    ///
    /// - Parameters:
    ///   - table: The table type
    ///   - channel: The type-safe channel name
    ///   - includeOldValues: Whether to include OLD row values
    /// - Throws: Database errors if function creation fails
    func createNotificationTriggerFunction<On: Table>(
        for table: On.Type,
        channel: ChannelName,
        includeOldValues: Bool
    ) async throws {
        let functionName = FunctionName(stringLiteral: "\(On.tableName)_\(channel.rawValue)_notify")

        let payloadExpression: String
        if includeOldValues {
            payloadExpression = """
                json_build_object(
                      'operation', TG_OP,
                      'new', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
                      'old', CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END
                    )
                """
        } else {
            payloadExpression = """
                json_build_object(
                      'operation', TG_OP,
                      'new', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END
                    )
                """
        }

        let sql = """
            CREATE OR REPLACE FUNCTION \(functionName.quoted)() RETURNS trigger AS $$
            DECLARE
              payload text;
            BEGIN
              payload := \(payloadExpression)::text;
              PERFORM pg_notify(\(channel.quoted), payload);
              RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
            END;
            $$ LANGUAGE plpgsql
            """

        print(
            "📢 Creating notification trigger function '\(functionName.rawValue)' for channel '\(channel.rawValue)'"
        )
        do {
            try await execute(sql)
            print("✅ Successfully created notification trigger function '\(functionName.rawValue)'")
        } catch {
            print("❌ Failed to create notification trigger function: \(String(reflecting: error))")
            throw error
        }
    }

    /// Creates a notification trigger for a table.
    ///
    /// - Parameters:
    ///   - table: The table type
    ///   - channel: The type-safe channel name
    ///   - events: Database events to trigger on
    ///   - timing: When the trigger fires
    /// - Throws: Database errors if trigger creation fails
    func createNotificationTrigger<On: Table>(
        for table: On.Type,
        channel: ChannelName,
        events: [Database.Notification.TriggerEvent],
        timing: Database.Notification.TriggerTiming
    ) async throws {
        guard !events.isEmpty else {
            throw Database.Error.invalidNotificationChannels("At least one trigger event required")
        }

        let triggerName = TriggerName(stringLiteral: "\(On.tableName)_\(channel.rawValue)_trigger")
        let functionName = FunctionName(stringLiteral: "\(On.tableName)_\(channel.rawValue)_notify")

        let eventList = events.map(\.rawValue).sorted().joined(separator: " OR ")
        let timingKeyword = timing.rawValue

        let sql = """
            CREATE TRIGGER \(triggerName.quoted)
            \(timingKeyword) \(eventList) ON \(On.tableName.quoted())
            FOR EACH ROW EXECUTE FUNCTION \(functionName.quoted)()
            """

        print(
            "📢 Creating notification trigger '\(triggerName.rawValue)' on table '\(On.tableName)'"
        )
        do {
            try await execute(sql)
            print("✅ Successfully created notification trigger '\(triggerName.rawValue)'")
        } catch {
            print("❌ Failed to create notification trigger: \(String(reflecting: error))")
            throw error
        }
    }

    /// Drops a notification trigger from a table.
    ///
    /// - Parameters:
    ///   - table: The table type
    ///   - channel: The type-safe channel name
    ///   - ifExists: Whether to skip if trigger doesn't exist
    /// - Throws: Database errors if trigger drop fails
    func dropNotificationTrigger<On: Table>(
        for table: On.Type,
        channel: ChannelName,
        ifExists: Bool
    ) async throws {
        let triggerName = TriggerName(stringLiteral: "\(On.tableName)_\(channel.rawValue)_trigger")
        let ifExistsClause = ifExists ? "IF EXISTS " : ""
        let sql = "DROP TRIGGER \(ifExistsClause)\(triggerName.quoted) ON \(On.tableName.quoted())"

        print(
            "📢 Dropping notification trigger '\(triggerName.rawValue)' from table '\(On.tableName)'"
        )
        do {
            try await execute(sql)
            print("✅ Successfully dropped notification trigger '\(triggerName.rawValue)'")
        } catch {
            print("❌ Failed to drop notification trigger: \(String(reflecting: error))")
            throw error
        }
    }

    /// Drops a notification trigger function.
    ///
    /// - Parameters:
    ///   - name: The type-safe function name
    ///   - ifExists: Whether to skip if function doesn't exist
    /// - Throws: Database errors if function drop fails
    func dropNotificationTriggerFunction(
        name: FunctionName,
        ifExists: Bool
    ) async throws {
        let ifExistsClause = ifExists ? "IF EXISTS " : ""
        let sql = "DROP FUNCTION \(ifExistsClause)\(name.quoted)()"

        print("📢 Dropping notification trigger function '\(name.rawValue)'")
        do {
            try await execute(sql)
            print("✅ Successfully dropped notification trigger function '\(name.rawValue)'")
        } catch {
            print("❌ Failed to drop notification trigger function: \(String(reflecting: error))")
            throw error
        }
    }
}

// MARK: - Channel Name Validation

/// Validates that a channel name is safe for use in SQL.
///
/// This prevents SQL injection by ensuring the channel name only contains
/// alphanumeric characters, underscores, and hyphens (valid PostgreSQL identifier characters).
///
/// - Parameter channelName: The channel name to validate
/// - Throws: Database.Error.invalidNotificationChannels if name contains invalid characters
private func validateChannelName(_ channelName: String) throws {
    let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    guard channelName.unicodeScalars.allSatisfy({ allowedCharacterSet.contains($0) }) else {
        throw Database.Error.invalidNotificationChannels(
            "Invalid channel name '\(channelName)': must contain only alphanumeric characters, underscores, and hyphens"
        )
    }
    guard !channelName.isEmpty else {
        throw Database.Error.invalidNotificationChannels("Channel name cannot be empty")
    }
    guard channelName.count <= 63 else {
        throw Database.Error.invalidNotificationChannels(
            "Channel name '\(channelName)' exceeds PostgreSQL's 63 character limit"
        )
    }
}
