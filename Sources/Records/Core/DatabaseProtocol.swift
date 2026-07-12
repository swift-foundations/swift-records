import Foundation
import PostgreSQL_Standard

/// A type that provides database access.
///
/// This protocol is the main interface for executing database operations.
/// It's implemented by connection types and passed to read/write blocks.
///
/// You typically don't call these methods directly. Instead, use the
/// extension methods on `Table` types for more convenient access.
///
/// ## Example
///
/// ```swift
/// // Using Table extensions (preferred)
/// try await db.read { db in
///     let users = try await User.fetchAll(db)
///     let posts = try await Post
///         .filter { $0.userId == userId }
///         .fetchAll(db)
/// }
///
/// // Using Database.Connection.`Protocol` directly (low-level)
/// try await db.read { db in
///     let users = try await db.fetchAll(User.all)
///     try await db.execute("VACUUM ANALYZE users")
/// }
/// ```
extension Database.Connection {
    public protocol `Protocol`: Sendable {
        /// Executes a statement that doesn't return any values.
        ///
        /// Use this for INSERT, UPDATE, DELETE statements without RETURNING clauses.
        ///
        /// - Parameter statement: The statement to execute.
        ///
        /// ## Example
        ///
        /// ```swift
        /// try await db.execute(
        ///     User.delete().where { $0.isDeleted }
        /// )
        /// ```
        func execute(_ statement: some Statement<()>) async throws

        /// Executes a raw SQL string.
        ///
        /// Use this for DDL statements, maintenance commands, or SQL that
        /// can't be expressed with StructuredQueries.
        ///
        /// - Parameter sql: The SQL string to execute.
        ///
        /// ## Example
        ///
        /// ```swift
        /// try await db.execute("""
        ///     CREATE INDEX CONCURRENTLY idx_users_email
        ///     ON users(email)
        /// """)
        /// ```
        func execute(_ sql: String) async throws

        /// Executes a query fragment.
        ///
        /// This is a low-level method primarily used internally.
        ///
        /// - Parameter fragment: The query fragment to execute.
        func executeFragment(_ fragment: QueryFragment) async throws

        /// Fetches all results from a statement.
        ///
        /// Returns an array of all matching records. Be mindful of memory
        /// usage when fetching large result sets.
        ///
        /// - Parameter statement: The statement to execute.
        /// - Returns: An array of results.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let activeUsers = try await db.fetchAll(
        ///     User.filter { $0.isActive }
        /// )
        /// ```
        func fetchAll<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> [QueryValue.QueryOutput]

        /// Parameter pack overload for fetching tuples of QueryRepresentable types.
        ///
        /// This overload explicitly handles statements with parameter pack tuple types.
        ///
        /// - Parameter statement: A statement with a tuple QueryValue type.
        /// - Returns: An array of tuples matching the statement's column types.
        func fetchAll<each V: QueryRepresentable>(
            _ statement: some Statement<(repeat each V)>
        ) async throws -> [(repeat (each V).QueryOutput)]

        /// Fetches a single result from a statement.
        ///
        /// Returns the first matching record or nil if no records match.
        /// The query is automatically limited to 1 result.
        ///
        /// - Parameter statement: The statement to execute.
        /// - Returns: The first result or nil.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let user = try await db.fetchOne(
        ///     User.filter { $0.id == userId }
        /// )
        /// ```
        func fetchOne<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> QueryValue.QueryOutput?

        /// Returns a cursor for streaming results from a statement.
        ///
        /// Cursors allow you to iterate over large result sets without loading
        /// all rows into memory at once. This is ideal for processing large
        /// datasets or when memory usage is a concern.
        ///
        /// - Parameter statement: The statement to execute.
        /// - Returns: A cursor for iterating over results.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let cursor = try await db.fetchCursor(
        ///     User.order { $0.createdAt }
        /// )
        ///
        /// for try await user in cursor {
        ///     // Process each user one at a time
        ///     await processUser(user)
        /// }
        /// ```
        ///
        /// - Note: Cursors stream results from the database, so they must be
        ///   consumed while the database connection is active. In pooled
        ///   connections, the cursor holds onto a connection until consumed.
        func fetchCursor<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> Database.Cursor<QueryValue.QueryOutput>

        /// Executes a block within a nested transaction.
        ///
        /// Default implementation delegates to the extension method.
        /// TransactionConnection overrides this to provide proper nesting.
        func withNestedTransaction<T: Sendable>(
            isolation: TransactionIsolationLevel?,
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T

        /// Executes a block within a savepoint.
        ///
        /// Default implementation delegates to raw SQL execution.
        /// TransactionConnection overrides this to track nesting depth.
        func withSavepoint<T: Sendable>(
            _ name: String?,
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T
    }
}

// MARK: - Default Implementations

extension Database.Connection.`Protocol` {
    /// Default implementation starts a new transaction.
    public func withNestedTransaction<T: Sendable>(
        isolation: TransactionIsolationLevel?,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        // For non-transaction connections, start a new transaction
        let isolationLevel = isolation ?? .readCommitted
        try await execute("BEGIN ISOLATION LEVEL \(isolationLevel.rawValue)")
        do {
            let result = try await block(self)
            try await execute("COMMIT")
            return result
        } catch {
            try await execute("ROLLBACK")
            throw error
        }
    }

    /// Default implementation uses raw SQL savepoint commands.
    public func withSavepoint<T: Sendable>(
        _ name: String?,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let savepointName = name ?? "sp_\(UUID().uuidString.prefix(8))"

        try await execute("SAVEPOINT \(savepointName)")
        do {
            let result = try await block(self)
            try await execute("RELEASE SAVEPOINT \(savepointName)")
            return result
        } catch {
            try await execute("ROLLBACK TO SAVEPOINT \(savepointName)")
            throw error
        }
    }
}
