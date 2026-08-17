import Records
import Records_SQL_Integration
import SQL
import Testing

// Source-level contract tests for the additive membrane. They intentionally use SQL's engine-free
// test double: no provider, transport, pool, or network dependency is permitted in this target.
extension Database.SQL.Writer {
    @Suite struct Integration {
        @Suite struct Unit {}
    }
}

extension Database.SQL.Writer.Integration.Unit {
    @Test func `read enters one SQL read scope`() async throws {
        let database = SQL.TestDatabase()
        let writer = Database.SQL.Writer(database: database, close: {})

        _ = try await writer.read { _ in () }

        #expect(await database.scopes == [.read])
    }

    @Test func `write enters one SQL write scope`() async throws {
        let database = SQL.TestDatabase()
        let writer = Database.SQL.Writer(database: database, close: {})

        _ = try await writer.write { _ in () }

        #expect(await database.scopes == [.write])
    }

    @Test func `close uses injected lifecycle`() async throws {
        let lifecycle = SQL.TestDatabase()
        let writer = Database.SQL.Writer(database: lifecycle, close: {
            _ = try await lifecycle.write { _ in () }
        })

        try await writer.close()

        #expect(await lifecycle.scopes == [.write])
    }
}
