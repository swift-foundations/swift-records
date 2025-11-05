import Foundation

extension Database {
    /// A database writer provides read-write database access.
    ///
    /// Writers can perform both read and write operations. They ensure proper
    /// serialization of write operations to maintain data consistency.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @Dependency(\.defaultDatabase) var db
    ///
    /// // Insert a new user
    /// try await db.write { db in
    ///     try await User.insert {
    ///         ($0.name, $0.email, $0.createdAt)
    ///     } values: {
    ///         ("Alice", "alice@example.com", Date())
    ///     }.execute(db)
    /// }
    ///
    /// // Update and return the updated record
    /// let updatedUser = try await db.write { db in
    ///     try await User
    ///         .filter { $0.id == userId }
    ///         .update { $0.lastLoginAt = Date() }
    ///         .returning(\.self)
    ///         .fetchOne(db)
    /// }
    /// ```
    public protocol Writer: Reader, Sendable {
        /// Performs a database operation that can write.
        ///
        /// The provided block receives a `Database.Connection.`Protocol`` instance that can be used
        /// to execute both read and write queries. Write operations are properly
        /// serialized to prevent conflicts.
        ///
        /// - Parameter block: An async closure that performs database operations.
        /// - Returns: The value returned by the block.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let newUserId = try await db.write { db in
        ///     let result = try await User.insert {
        ///         ($0.name, $0.email)
        ///     } values: {
        ///         ("Bob", "bob@example.com")
        ///     }
        ///     .returning(\.id)
        ///     .fetchOne(db)
        ///
        ///     return result ?? 0
        /// }
        /// ```
        func write<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T
    }
}
