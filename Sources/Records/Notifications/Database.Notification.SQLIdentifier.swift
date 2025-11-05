import Foundation
import StructuredQueriesPostgres
import Tagged

// MARK: - Tagged Type Aliases for SQL Identifiers

// Note: Tagged is available through the StructuredQueriesPostgresTagged trait
// which is enabled in Package.swift. This provides zero-cost phantom types
// for type-safe SQL identifiers.

/// Tag types for compile-time SQL identifier safety.
///
/// These phantom types ensure that channel names, function names, and trigger names
/// cannot be accidentally mixed up at compile time, while maintaining zero runtime overhead.
extension Database.Notification {
    /// Tag for PostgreSQL channel names (used with LISTEN/NOTIFY)
    public enum ChannelNameTag {}

    /// Tag for PostgreSQL function names
    public enum FunctionNameTag {}

    /// Tag for PostgreSQL trigger names
    public enum TriggerNameTag {}
}

/// A type-safe PostgreSQL channel name.
///
/// Channel names are validated to contain only alphanumeric characters, underscores,
/// and hyphens, with a maximum length of 63 characters (PostgreSQL identifier limit).
///
/// ## Example
///
/// ```swift
/// // From string literal (validated at runtime)
/// let channel: ChannelName = "reminder_events"
///
/// // Explicit validation
/// let channel = try ChannelName(validating: "reminder_events")
///
/// // From table name (already validated by @Table macro)
/// let channel = ChannelName(tableName: Reminder.tableName)
/// ```
public typealias ChannelName = Tagged<Database.Notification.ChannelNameTag, String>

/// A type-safe PostgreSQL function name.
public typealias FunctionName = Tagged<Database.Notification.FunctionNameTag, String>

/// A type-safe PostgreSQL trigger name.
public typealias TriggerName = Tagged<Database.Notification.TriggerNameTag, String>

// MARK: - ChannelName Extensions

extension Tagged where Tag == Database.Notification.ChannelNameTag, RawValue == String {
    /// Creates a validated channel name.
    ///
    /// Channel names must:
    /// - Contain only alphanumeric characters, underscores, and hyphens
    /// - Be non-empty
    /// - Not exceed 63 characters (PostgreSQL identifier limit)
    ///
    /// - Parameter name: The channel name to validate
    /// - Throws: `Database.Error.invalidNotificationChannels` if validation fails
    public init(validating name: String) throws {
        guard Self.isValid(name) else {
            throw Database.Error.invalidNotificationChannels(
                "Invalid channel name '\(name)': must contain only alphanumeric characters, underscores, and hyphens (max 63 chars)"
            )
        }
        self.init(rawValue: name)
    }

    /// Creates a channel name from a validated table name.
    ///
    /// Table names from the `@Table` macro are already validated, so this is a safe conversion.
    ///
    /// - Parameter tableName: A validated table name from `@Table`
    @inlinable
    public init(tableName: String) {
        // Safe: @Table macro ensures tableName is valid
        self.init(rawValue: tableName)
    }

    /// Creates a channel name from a string literal with runtime validation.
    ///
    /// - Warning: This will crash if the string literal is invalid. Use `init(validating:)` for runtime strings.
    @inlinable
    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure("Invalid channel name '\(value)': \(error)")
        }
    }

    /// Returns true if the channel name is valid for PostgreSQL.
    private static func isValid(_ name: String) -> Bool {
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !name.isEmpty
            && name.count <= 63  // PostgreSQL identifier limit
            && name.unicodeScalars.allSatisfy { allowedCharacterSet.contains($0) }
    }

    /// The channel name quoted for use in SQL statements.
    ///
    /// This ensures the identifier is properly escaped for PostgreSQL.
    @inlinable
    public var quoted: String {
        "\"\(rawValue)\""
    }
}

// MARK: - FunctionName Extensions

extension Tagged where Tag == Database.Notification.FunctionNameTag, RawValue == String {
    /// Creates a validated function name.
    ///
    /// - Parameter name: The function name to validate
    /// - Throws: `Database.Error.invalidNotificationChannels` if validation fails
    public init(validating name: String) throws {
        guard Self.isValid(name) else {
            throw Database.Error.invalidNotificationChannels(
                "Invalid function name '\(name)': must contain only alphanumeric characters, underscores, and hyphens (max 63 chars)"
            )
        }
        self.init(rawValue: name)
    }

    /// Creates a function name from a string literal with runtime validation.
    @inlinable
    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure("Invalid function name '\(value)': \(error)")
        }
    }

    private static func isValid(_ name: String) -> Bool {
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !name.isEmpty
            && name.count <= 63
            && name.unicodeScalars.allSatisfy { allowedCharacterSet.contains($0) }
    }

    /// The function name quoted for use in SQL statements.
    @inlinable
    public var quoted: String {
        "\"\(rawValue)\""
    }
}

// MARK: - TriggerName Extensions

extension Tagged where Tag == Database.Notification.TriggerNameTag, RawValue == String {
    /// Creates a validated trigger name.
    ///
    /// - Parameter name: The trigger name to validate
    /// - Throws: `Database.Error.invalidNotificationChannels` if validation fails
    public init(validating name: String) throws {
        guard Self.isValid(name) else {
            throw Database.Error.invalidNotificationChannels(
                "Invalid trigger name '\(name)': must contain only alphanumeric characters, underscores, and hyphens (max 63 chars)"
            )
        }
        self.init(rawValue: name)
    }

    /// Creates a trigger name from a string literal with runtime validation.
    @inlinable
    public init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure("Invalid trigger name '\(value)': \(error)")
        }
    }

    private static func isValid(_ name: String) -> Bool {
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !name.isEmpty
            && name.count <= 63
            && name.unicodeScalars.allSatisfy { allowedCharacterSet.contains($0) }
    }

    /// The trigger name quoted for use in SQL statements.
    @inlinable
    public var quoted: String {
        "\"\(rawValue)\""
    }
}
