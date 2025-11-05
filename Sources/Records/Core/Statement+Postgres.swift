import StructuredQueriesPostgres

// MARK: - TemporaryView Validation

/// Error thrown when attempting to create a view with parameterized queries
public struct ParameterizedViewError: Error, CustomStringConvertible {
    public let parameterCount: Int
    public let sql: String

    public init(parameterCount: Int, sql: String) {
        self.parameterCount = parameterCount
        self.sql = sql
    }

    public var description: String {
        """
        Views cannot contain parameterized queries.

        Found \(parameterCount) parameter(s) in the view definition.

        Avoid using:
        - .limit() / .offset() with literal values
        - .where { } closures with literal comparisons (e.g., .where { $0.id == 1 })

        Use instead:
        - Keypath-based operations (e.g., .where(\\.isActive))
        - Column-to-column comparisons (e.g., .where { $0.column.eq($1.otherColumn) })

        Generated SQL with parameters:
        \(sql)
        """
    }
}

extension TemporaryView {
    /// Executes a CREATE TEMPORARY VIEW statement with validation.
    ///
    /// PostgreSQL views cannot contain parameterized queries. This method validates
    /// that the view definition has no query parameters before execution.
    ///
    /// - Parameter db: A database connection.
    /// - Throws: `ParameterizedViewError` if the view contains parameterized queries.
    @inlinable
    public func execute(_ db: any Database.Connection.`Protocol`) async throws {
        let (sql, bindings) = query.prepare { "$\($0)" }

        guard bindings.isEmpty else {
            throw ParameterizedViewError(parameterCount: bindings.count, sql: sql)
        }

        try await db.execute(sql)
    }
}

// MARK: - General Statement Extensions

extension Statement {
    /// Executes a structured query on the given database connection.
    ///
    /// For example:
    ///
    /// ```swift
    /// try await database.write { db in
    ///   try Player.insert { $0.name } values: { "Arthur" }
    ///     .execute(db)
    ///   // INSERT INTO "players" ("name")
    ///   // VALUES ('Arthur');
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    @inlinable
    public func execute(_ db: any Database.Connection.`Protocol`) async throws
    where QueryValue == () {
        try await db.execute(self)
    }

    /// Returns an array of all values fetched from the database.
    ///
    /// For example:
    ///
    /// ```swift
    /// let players = try await database.read { db in
    ///   let lastName = "O'Reilly"
    ///   try Player
    ///     .where { $0.lastName == lastName }
    ///     .fetchAll(db)
    ///   // SELECT … FROM "players"
    ///   // WHERE "players"."lastName" = 'O''Reilly'
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all values decoded from the database.
    @inlinable
    public func fetchAll(
        _ db: any Database.Connection.`Protocol`
    ) async throws -> [QueryValue.QueryOutput]
    where QueryValue: QueryRepresentable {
        try await db.fetchAll(self)
    }

    /// Parameter pack overload for fetching tuples of QueryRepresentable types.
    ///
    /// This overload explicitly handles statements with parameter pack tuple types,
    /// allowing type-safe execution of multi-column SELECT queries.
    ///
    /// For example:
    ///
    /// ```swift
    /// let data = try await database.read { db in
    ///   try Player
    ///     .select { ($0.name, $0.score) }
    ///     .fetchAll(db)
    ///   // Returns [(String, Int)]
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of tuples matching the statement's column types.
    @inlinable
    public func fetchAll<each V: QueryRepresentable>(
        _ db: any Database.Connection.`Protocol`
    ) async throws -> [(repeat (each V).QueryOutput)]
    where QueryValue == (repeat each V) {
        try await db.fetchAll(self)
    }

    /// Returns a single value fetched from the database.
    ///
    /// For example:
    ///
    /// ```swift
    /// let player = try await database.read { db in
    ///   let lastName = "O'Reilly"
    ///   try Player
    ///     .where { $0.lastName == lastName }
    ///     .limit(1)
    ///     .fetchOne(db)
    ///   // SELECT … FROM "players"
    ///   // WHERE "players"."lastName" = 'O''Reilly'
    ///   // LIMIT 1
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: A single value decoded from the database.
    @inlinable
    public func fetchOne(_ db: any Database.Connection.`Protocol`) async throws -> QueryValue
        .QueryOutput?
    where QueryValue: QueryRepresentable {
        try await db.fetchOne(self)
    }
}

extension SelectStatement where QueryValue == (), Joins == () {
    /// Returns the number of rows fetched by the query.
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The number of rows fetched by the query.
    @inlinable
    public func fetchCount(_ db: any Database.Connection.`Protocol`) async throws -> Int {
        let query = asSelect().select { _ in AggregateFunction<Int>.count() }
        return try await query.fetchOne(db) ?? 0
    }
}

extension SelectStatement where QueryValue == (), Joins == () {
    /// Returns an array of all values fetched from the database.
    ///
    /// This extension enables the pattern: `User.all.fetchAll(db)`
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all values decoded from the database.
    @inlinable
    public func fetchAll(_ db: any Database.Connection.`Protocol`) async throws -> [From
        .QueryOutput]
    where From: QueryRepresentable {
        // Use selectStar() to select all columns from the From table
        // This returns Select<From, From, ()> where QueryValue = From
        let query = self.selectStar()
        return try await query.fetchAll(db)
    }

    /// Returns a single value fetched from the database.
    ///
    /// This extension enables the pattern: `User.all.fetchOne(db)`
    ///
    /// - Parameter db: A database connection.
    /// - Returns: A single value decoded from the database.
    @inlinable
    public func fetchOne(_ db: any Database.Connection.`Protocol`) async throws -> From.QueryOutput?
    where From: QueryRepresentable {
        // Use selectStar() to select all columns from the From table
        let query = self.selectStar().limit(1)
        return try await query.fetchOne(db)
    }
}
