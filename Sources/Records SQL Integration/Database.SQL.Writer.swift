public import Records
public import SQL

extension Database.SQL {
    /// A `Records` writer backed by an engine-neutral ``SQL/Database``.
    ///
    /// The supplied `close` operation remains owned by the application or provider integration;
    /// Records does not infer pool, transport, or engine lifecycle from an SQL database handle.
    public struct Writer: Database.Writer {
        private let database: any SQL.Database
        private let closeDatabase: @Sendable () async throws -> Void

        /// Creates a Records writer over an SQL database and its explicit lifecycle operation.
        public init(
            database: any SQL.Database,
            close: @escaping @Sendable () async throws -> Void
        ) {
            self.database = database
            self.closeDatabase = close
        }
    }
}

extension Database.SQL.Writer {
    /// Enters exactly one SQL read scope for `body`.
    public func read<Value: Sendable>(
        _ body: @Sendable (any Database.Connection.`Protocol`) async throws -> Value
    ) async throws -> Value {
        try await database.read { connection throws(SQL.Error) in
            do {
                return try await body(Database.SQL.Connection(connection: connection))
            } catch let error as SQL.Error {
                throw error
            } catch {
                throw .execution("\(error)")
            }
        }
    }

    /// Enters exactly one SQL write scope for `body`.
    public func write<Value: Sendable>(
        _ body: @Sendable (any Database.Connection.`Protocol`) async throws -> Value
    ) async throws -> Value {
        try await database.write { connection throws(SQL.Error) in
            do {
                return try await body(Database.SQL.Connection(connection: connection))
            } catch let error as SQL.Error {
                throw error
            } catch {
                throw .execution("\(error)")
            }
        }
    }

    /// Closes the provider-owned lifecycle exactly as injected at construction.
    public func close() async throws {
        try await closeDatabase()
    }
}
