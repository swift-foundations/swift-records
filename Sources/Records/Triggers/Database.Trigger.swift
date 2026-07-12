import Foundation

// MARK: - Trigger Support

extension Database {
    /// Namespace for trigger-related functionality.
    ///
    /// Swift-Records delegates trigger creation to swift-structured-queries,
    /// which provides comprehensive trigger support via the TemporaryTrigger type.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Use triggers from swift-structured-queries directly
    /// try await db.write { db in
    ///     try await db.execute(
    ///         User.createTemporaryTrigger(
    ///             afterUpdateTouch: \.updatedAt
    ///         )
    ///     )
    /// }
    /// ```
    ///
    /// See swift-structured-queries documentation for full trigger API.
    public enum Trigger {
        // Namespace only - all functionality comes from swift-structured-queries
    }
}

// MARK: - PostgreSQL-Specific Helpers

extension Database.Connection.`Protocol` {
    /// Creates a PostgreSQL trigger function.
    ///
    /// This is a low-level helper for creating PostgreSQL-specific trigger functions
    /// when the built-in swift-structured-queries triggers aren't sufficient.
    ///
    /// - Parameters:
    ///   - name: The function name.
    ///   - body: The PL/pgSQL function body.
    ///   - returns: The return type (default: "trigger").
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await db.createTrigger.Function(
    ///     "update_timestamp",
    ///     body: "NEW.updated_at = CURRENT_TIMESTAMP; RETURN NEW;"
    /// )
    /// ```
    public func createTriggerFunction(
        _ name: String,
        body: String,
        returns: String = "trigger"
    ) async throws {
        let sql = """
            CREATE OR REPLACE FUNCTION \(name)() RETURNS \(returns) AS $$
            BEGIN
                \(body)
            END;
            $$ LANGUAGE plpgsql
            """
        try await execute(sql)
    }
}
