import Dependencies
import Dependencies_Test_Support
import Environment_Dependencies
import Foundation
import PostgresNIO
import Records
import Testing

@Suite
struct Test {

    @Test
    func `Configuration from environment variables`() async throws {
        // Inject the environment via the dependency: the test asserts the
        // env-var → configuration mapping, not the host machine's environment.
        let config = try withDependencies {
            $0.envVars = EnvVars([
                "DATABASE_HOST": "localhost",
                "DATABASE_PORT": "5432",
                "DATABASE_NAME": "test_db",
                "DATABASE_USER": "postgres",
                "DATABASE_PASSWORD": "secret",
            ])
        } operation: {
            try PostgresClient.Configuration.fromEnvironment()
        }
        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "test_db")
        #expect(config.username == "postgres")
    }

    @Test
    func `Database single connection initialization`() async throws {
        let config = try PostgresClient.Configuration.fromEnvironment()

        do {
            let queue = await Database.singleConnection(configuration: config)

            // Test that we can perform operations
            try await queue.write { db in
                try await db.execute("SELECT 1")
            }

            try await queue.close()
        } catch {
            throw error
        }
    }

    @Test
    func `Database.Pool initialization with pooling`() async throws {
        let config = try PostgresClient.Configuration.fromEnvironment()

        let pool = await Database.pool(
            configuration: config,
            minConnections: 2,
            maxConnections: 5
        )

        // Test that we can perform operations
        try await pool.read { db in
            try await db.execute("SELECT 1")
        }

        try await pool.close()
    }

    @Test
    func `Configuration stores values correctly`() async throws {
        let config = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "coenttb",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "database-postgres-dev")
        #expect(config.username == "coenttb")
        #expect(config.password == nil)
    }

    @Test
    func `Connection factory methods`() async throws {
        // Test single connection
        let singleConfig = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "coenttb",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        let single = await Database.singleConnection(configuration: singleConfig)
        // Just verify it was created
        try await single.close()

        // Test pool connection
        let poolConfig = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "coenttb",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        let pool = await Database.pool(
            configuration: poolConfig,
            minConnections: 3,
            maxConnections: 10
        )
        try await pool.close()
    }
}
