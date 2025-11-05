import Foundation
import StructuredQueriesPostgres

extension Database {
    /// A wrapper for database connections that are within a transaction.
    ///
    /// This connection wrapper allows tracking of transaction state and enables
    /// nested transaction support through savepoints.
    struct TransactionConnection: Database.Connection.`Protocol` {
        private let underlying: any Database.Connection.`Protocol`
        private(set) var transactionDepth: Int

        /// Creates a new transaction connection wrapper.
        ///
        /// - Parameters:
        ///   - underlying: The underlying database connection.
        ///   - transactionDepth: The current transaction nesting depth (default 1).
        init(
            _ underlying: any Database.Connection.`Protocol`,
            transactionDepth: Int = 1
        ) {
            self.underlying = underlying
            self.transactionDepth = transactionDepth
        }

        /// Returns true if this connection is within a transaction.
        var isInTransaction: Bool {
            transactionDepth > 0
        }

        // MARK: - Database.Connection.Protocol Conformance

        func execute(_ statement: some Statement<()>) async throws {
            try await underlying.execute(statement)
        }

        func execute(_ sql: String) async throws {
            try await underlying.execute(sql)
        }

        func executeFragment(_ fragment: QueryFragment) async throws {
            try await underlying.executeFragment(fragment)
        }

        func fetchAll<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> [QueryValue.QueryOutput] {
            try await underlying.fetchAll(statement)
        }

        func fetchAll<each V: QueryRepresentable>(
            _ statement: some Statement<(repeat each V)>
        ) async throws -> [(repeat (each V).QueryOutput)] {
            try await underlying.fetchAll(statement)
        }

        func fetchOne<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> QueryValue.QueryOutput? {
            try await underlying.fetchOne(statement)
        }

        func fetchCursor<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> Database.Cursor<QueryValue.QueryOutput> {
            try await underlying.fetchCursor(statement)
        }
    }
}

// MARK: - Nested Transaction Support

extension Database.TransactionConnection {
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
    ///     // Nested transaction (uses savepoint)
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
        if isInTransaction {
            // Use savepoint for nested transaction
            let savepointName = "sp_\(UUID().uuidString.prefix(8))"
            return try await withSavepoint(savepointName, block)
        } else {
            // Start new transaction (though this shouldn't happen with TransactionConnection)
            try await execute(
                "BEGIN ISOLATION LEVEL \(isolation?.rawValue ?? TransactionIsolationLevel.readCommitted.rawValue)"
            )
            do {
                let nestedConnection = Database.TransactionConnection(self, transactionDepth: 1)
                let result = try await block(nestedConnection)
                try await execute("COMMIT")
                return result
            } catch {
                try await execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Executes a block of operations within a savepoint.
    ///
    /// Savepoints allow you to rollback to a specific point within a transaction
    /// without rolling back the entire transaction.
    ///
    /// ```swift
    /// try await db.withTransaction { db in
    ///     try await Player.insert { ... }.execute(db)
    ///
    ///     do {
    ///         try await db.withSavepoint("risky_operation") { db in
    ///             try await Team.update { ... }.execute(db)
    ///             // If this fails, only this operation is rolled back
    ///         }
    ///     } catch {
    ///         // Handle the error, but continue with the transaction
    ///     }
    ///
    ///     try await Score.insert { ... }.execute(db)
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
        let savepointName = name ?? "sp_\(UUID().uuidString.prefix(8))"

        try await execute("SAVEPOINT \(savepointName)")
        do {
            let nestedConnection = Database.TransactionConnection(
                underlying,
                transactionDepth: transactionDepth + 1
            )
            let result = try await block(nestedConnection)
            try await execute("RELEASE SAVEPOINT \(savepointName)")
            return result
        } catch {
            try await execute("ROLLBACK TO SAVEPOINT \(savepointName)")
            throw error
        }
    }
}
