import StructuredQueriesPostgres

// MARK: - Extensions for SelectStatement with nothing selected

// MARK: - Table Extensions for static convenience methods

extension Table where Self: QueryRepresentable, Self.QueryOutput == Self {
    /// Fetches all records from the table.
    ///
    /// For example:
    /// ```swift
    /// let users = try await User.fetchAll(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all records in the table.
    @inlinable
    public static func fetchAll(_ db: any Database.Connection.`Protocol`) async throws -> [Self] {
        // Use selectStar() to select all columns from the table
        // This matches the pattern used in SharingGRDB
        let query = Self.all.selectStar()
        return try await query.fetchAll(db)
    }

    /// Fetches the first record from the table.
    ///
    /// For example:
    /// ```swift
    /// let user = try await User.fetchOne(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The first record in the table, or nil if empty.
    @inlinable
    public static func fetchOne(_ db: any Database.Connection.`Protocol`) async throws -> Self? {
        // Use selectStar() and limit to 1
        let query = Self.all.selectStar().limit(1)
        return try await query.fetchOne(db)
    }

    /// Returns the number of records in the table.
    ///
    /// For example:
    /// ```swift
    /// let count = try await User.fetchCount(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The number of records in the table.
    @inlinable
    public static func fetchCount(_ db: any Database.Connection.`Protocol`) async throws -> Int {
        // Use the existing fetchCount extension on SelectStatement
        try await Self.all.asSelect().fetchCount(db)
    }
}
