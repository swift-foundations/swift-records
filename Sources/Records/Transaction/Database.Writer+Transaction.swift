import Foundation

extension Database.Writer {
    /// Executes a block of operations within a database transaction.
    ///
    /// If the block throws an error, the transaction is rolled back.
    /// Otherwise, the transaction is committed.
    ///
    /// ```swift
    /// try await database.withTransaction { db in
    ///     try Player.insert { ... }.execute(db)
    ///     try Team.update { ... }.execute(db)
    ///     // Both operations succeed or both are rolled back
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isolation: The transaction isolation level.
    ///   - block: The operations to perform within the transaction.
    /// - Returns: The value returned by the block.
    public func withTransaction<T: Sendable>(
        isolation: TransactionIsolationLevel = .readCommitted,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await write { db in
            try await db.execute("BEGIN ISOLATION LEVEL \(isolation.rawValue)")
            do {
                let result = try await block(Database.TransactionConnection(db))
                try await db.execute("COMMIT")
                return result
            } catch {
                try await db.execute("ROLLBACK")
                #if DEBUG
                    Swift.print(String(reflecting: error))
                #endif
                throw error
            }
        }
    }

    /// Executes a block of operations within a database transaction and rolls it back.
    ///
    /// This is useful for testing or dry-run operations where you want to see
    /// the effects of database operations without actually committing them.
    ///
    /// ```swift
    /// let result = try await database.withRollback { db in
    ///     try Player.insert { ... }.execute(db)
    ///     return try Player.fetchCount(db)
    ///     // Transaction is rolled back, no data is persisted
    /// }
    /// ```
    ///
    /// - Parameter block: The operations to perform within the transaction.
    /// - Returns: The value returned by the block.
    public func withRollback<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await write { db in
            try await db.execute("BEGIN")
            do {
                let result = try await block(db)
                try await db.execute("ROLLBACK")
                return result
            } catch {
                try await db.execute("ROLLBACK")
                #if DEBUG
                    Swift.print(String(reflecting: error))
                #endif
                throw error
            }
        }
    }

    /// Executes a block of operations within a nested transaction.
    ///
    /// If already in a transaction, this creates a savepoint. Otherwise,
    /// it starts a new transaction. This provides automatic nesting support
    /// without requiring the caller to track transaction state.
    ///
    /// ```swift
    /// try await db.withTransaction { db in
    ///     // Main transaction
    ///     try await Order.insert { ... }.execute(db)
    ///
    ///     // Nested transaction (uses savepoint automatically)
    ///     try await db.withNestedTransaction { db in
    ///         try await OrderItem.insert { ... }.execute(db)
    ///         // If this fails, only the nested transaction rolls back
    ///     }
    ///
    ///     // Main transaction continues
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isolation: The isolation level (only used for new transactions).
    ///   - block: The operations to perform within the nested transaction.
    /// - Returns: The value returned by the block.
    public func withNestedTransaction<T: Sendable>(
        isolation: TransactionIsolationLevel? = nil,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        do {
            // This method will be overridden by TransactionConnection
            // For non-transaction connections, start a new transaction
            return try await withTransaction(
                isolation: isolation ?? .readCommitted,
                block
            )
        } catch {
            #if DEBUG
                Swift.print(String(reflecting: error))
            #endif
            throw error
        }
    }

    /// Executes a block of operations within a savepoint.
    ///
    /// Savepoints allow you to rollback to a specific point within a transaction
    /// without rolling back the entire transaction. The savepoint name is optional
    /// and will be auto-generated if not provided.
    ///
    /// ```swift
    /// try await database.withTransaction { db in
    ///     try Player.insert { ... }.execute(db)
    ///
    ///     do {
    ///         // Auto-generated savepoint name
    ///         try await db.withSavepoint { db in
    ///             try Team.update { ... }.execute(db)
    ///             // If this fails, only this operation is rolled back
    ///         }
    ///     } catch {
    ///         // Handle the error, but continue with the transaction
    ///     }
    ///
    ///     // Named savepoint for clarity
    ///     try await db.withSavepoint("critical_update") { db in
    ///         try Score.insert { ... }.execute(db)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the savepoint (auto-generated if nil).
    ///   - block: The operations to perform within the savepoint.
    /// - Returns: The value returned by the block.
    public func withSavepoint<T: Sendable>(
        _ name: String? = nil,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        // Ring review R-05: savepoint names cannot be bound parameters, so the
        // identifier is validated and quoted before interpolation.
        let savepointName = try Database.quotedSavepointName(
            name ?? "sp_\(UUID().uuidString.prefix(8))"
        )

        return try await write { db in
            try await db.execute("SAVEPOINT \(savepointName)")
            do {
                let result = try await block(db)
                try await db.execute("RELEASE SAVEPOINT \(savepointName)")
                return result
            } catch {
                try await db.execute("ROLLBACK TO SAVEPOINT \(savepointName)")
                #if DEBUG
                    Swift.print(String(reflecting: error))
                #endif
                throw error
            }
        }
    }
}

extension Database {
    /// Validates and quotes a savepoint identifier for safe SQL interpolation.
    ///
    /// Savepoint names cannot be bound parameters, so the identifier is validated
    /// (alphanumerics plus `_-`, non-empty, at most 63 characters — the PostgreSQL
    /// identifier limit) and then double-quoted. Mirrors the notification
    /// `SQLIdentifier` validation discipline.
    ///
    /// - Parameter name: The savepoint name to validate.
    /// - Returns: The quoted identifier, safe to interpolate into savepoint statements.
    /// - Throws: ``Database/Error/invalidSavepointName(_:)`` if validation fails.
    package static func quotedSavepointName(_ name: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard
            !name.isEmpty,
            name.count <= 63,
            name.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw Database.Error.invalidSavepointName(name)
        }
        return "\"\(name)\""
    }
}
