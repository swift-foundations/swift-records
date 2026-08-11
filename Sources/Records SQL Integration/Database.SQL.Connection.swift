public import PostgreSQL_Standard
public import Records
public import SQL

extension Database.SQL {
    /// A connection-scoped Records adapter over an engine-neutral ``SQL/Connection``.
    ///
    /// This type never enters an SQL database scope itself. ``Database/SQL/Writer`` owns scope
    /// entry, while this adapter forwards operations to the single connection it receives.
    public struct Connection: Database.Connection.`Protocol` {
        private let connection: any SQL.Connection

        /// Creates a Records connection over an already scoped SQL connection.
        public init(connection: any SQL.Connection) {
            self.connection = connection
        }
    }
}

extension Database.SQL.Connection {
    public func execute(_ statement: some Statement<()>) async throws {
        try await connection.execute(statement)
    }

    public func execute(_ sql: String) async throws {
        try await connection.execute(SQL.Query(sql: sql))
    }

    public func executeFragment(_ fragment: QueryFragment) async throws {
        try await connection.execute(fragment)
    }

    public func fetchAll<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> [QueryValue.QueryOutput] {
        try await connection.fetchAll(statement)
    }

    public func fetchAll<each Value: QueryRepresentable>(
        _ statement: some Statement<(repeat each Value)>
    ) async throws -> [(repeat (each Value).QueryOutput)] {
        try await connection.fetchAll(statement)
    }

    public func fetchOne<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> QueryValue.QueryOutput? {
        try await connection.fetchOne(statement)
    }

    public func fetchCursor<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> Database.Cursor<QueryValue.QueryOutput> {
        let cursor: SQL.Cursor<QueryValue.QueryOutput> = try await connection.fetchCursor(statement)
        return Database.Cursor {
            try await cursor.next()
        }
    }
}
