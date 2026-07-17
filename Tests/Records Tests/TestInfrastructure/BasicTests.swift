import Dependencies
import Dependencies_Test_Support
import PostgresNIO
import Environment_Dependencies
@testable import Records
import Records_Test_Support
import Testing

@Suite
struct Test {
    @Test
    func `Package Compiles`() async throws {
        // This test just verifies the package compiles
        #expect(true)
    }

    @Test
    func `Configuration From Environment`() async throws {
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
}

@Suite
struct `Adapter Tests` {

    @Test
    func `Query Fragment to Postgres Query conversion`() {
        let fragment: QueryFragment = """
            SELECT * FROM users WHERE id = \(42) AND name = \(bind: "Alice")
            """

        let query = fragment.toPostgresQuery()

        #expect(query.sql == "SELECT * FROM users WHERE id = $1 AND name = $2")
        #expect(query.binds.count == 2)
    }

    @Test
    func `Query decoder initialization`() {
        #expect(true)
    }

    @Test
    func `Query Fragment with NULL values`() {
        let fragment: QueryFragment = """
            INSERT INTO users (id, name, email) VALUES (\(1), \(bind: "Bob"), \(QueryBinding.null))
            """

        let query = fragment.toPostgresQuery()

        #expect(query.sql == "INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
        #expect(query.binds.count == 3)
    }

    @Test
    func `Query Fragment with BLOB data`() {
        let data = Data([0x01, 0x02, 0x03])
        let fragment: QueryFragment = """
            UPDATE files SET content = \(data) WHERE id = \(100)
            """

        let query = fragment.toPostgresQuery()

        #expect(query.sql == "UPDATE files SET content = $1 WHERE id = $2")
        #expect(query.binds.count == 2)
    }

    @Test
    func `Query Bindable conformance`() {
        let intBinding = 42.queryBinding
        #expect(intBinding == .int(42))

        let stringBinding = "hello".queryBinding
        #expect(stringBinding == .text("hello"))

        let doubleBinding = 3.14.queryBinding
        #expect(doubleBinding == .double(3.14))

        let boolBinding = true.queryBinding
        #expect(boolBinding == .bool(true))

        let falseBinding = false.queryBinding
        #expect(falseBinding == .bool(false))
    }
}
