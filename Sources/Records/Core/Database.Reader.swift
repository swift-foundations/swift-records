import Foundation

extension Database {
    /// A database reader provides read-only database access.
    ///
    /// Readers ensure that database operations are performed in a read-only context,
    /// which allows for optimizations like connection pooling for read operations.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @Dependency(\.defaultDatabase) var db
    ///
    /// // Fetch data using the reader
    /// let users = try await db.read { db in
    ///     try await User.fetchAll(db)
    /// }
    ///
    /// // Multiple operations in a single read transaction
    /// let (users, posts) = try await db.read { db in
    ///     let users = try await User.fetchAll(db)
    ///     let posts = try await Post.fetchAll(db)
    ///     return (users, posts)
    /// }
    /// ```
    public protocol Reader: Sendable {
        /// Performs a read-only database operation.
        ///
        /// The provided block receives a `Database.Connection.`Protocol`` instance that can be used
        /// to execute queries. The block's return value is returned from this method.
        ///
        /// - Parameter block: An async closure that performs database operations.
        /// - Returns: The value returned by the block.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let userCount = try await db.read { db in
        ///     try await User.fetchCount(db)
        /// }
        /// ```
        func read<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T

        func close() async throws
    }
}
