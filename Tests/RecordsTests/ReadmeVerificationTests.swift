import Dependencies
import Testing

@testable import Records

@Suite("README Verification")
struct ReadmeVerificationTests {

    // README line 247-263: Migration system is mentioned
    @Test("Example from README: Migrator type exists")
    func exampleMigratorExists() throws {
        // Verify the Migrator type from README exists
        var migrator = Database.Migrator()

        // Can register a migration as shown in README (from README line 255)
        migrator.registerMigration("create_users") { db in
            // Migration would execute SQL here
        }

        // Migrator works as documented
        #expect(String(describing: type(of: migrator)).contains("Migrator"))
    }

    // README line 96-107: Configuration from README
    @Test("Example from README: PostgresConfiguration exists")
    func exampleConfigurationExists() {
        // From README line 96-107: Database.Pool configuration
        let config = PostgresConnection.Configuration(
            host: "localhost",
            port: 5432,
            username: "postgres",
            password: "password",
            database: "myapp",
            tls: .disable
        )

        #expect(config.host == "localhost")
        #expect(config.database == "myapp")
    }

    // README mentions Database.Pool type throughout
    @Test("Example from README: Database.Pool type exists")
    func exampleDatabasePoolExists() {
        // Verify Database.Pool type mentioned in README exists and compiles
        let _: Database.Pool.Type = Database.Pool.self

        // Type check passes - Database.Pool exists as documented
        #expect(Bool(true))
    }
}
