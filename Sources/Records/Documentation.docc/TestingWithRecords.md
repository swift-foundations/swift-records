# Testing with Records

Learn how to write reliable database tests using Swift Records' testing utilities.

## Test Database Setup

Swift Records provides `TestDatabase` for isolated testing:

```swift
import Testing
import Records
import RecordsTestSupport
import Dependencies

@Suite(
    "User Tests",
    .dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
)
struct UserTests {
    // Each test gets its own schema for isolation
    @Test func createUser() async throws {
        @Dependency(\.defaultDatabase) var db

        let user = try await db.write { db in
            try await User.insert {
                User.Draft(
                    name: "Alice",
                    email: "alice@example.com"
                )
            }
            .returning(\.self)
            .fetchOne(db)!
        }

        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
    }
}
```

## Schema Isolation

Each test runs in its own PostgreSQL schema, enabling parallel test execution:

```swift
@Suite("Parallel Tests", .dependency(\.defaultDatabase, TestDatabase.withSchema()))
struct ParallelTests {
    @Dependency(\.defaultDatabase) var db
    
    @Test func test1() async throws {
        // Runs in schema like "test_abc123"
        try await db.write { db in
            try await User.insert { ... }.execute(db)
        }
    }
    
    @Test func test2() async throws {
        // Runs in different schema like "test_def456"
        // Can run in parallel with test1
        try await db.write { db in
            try await User.insert { ... }.execute(db)
        }
    }
}
```

## Transaction Rollback

Use `withRollback` for test isolation without schema switching:

```swift
@Test func updateUser() async throws {
    try await withDependencies {
        $0.defaultDatabase = try await TestDatabase()
    } operation: {
        @Dependency(\.defaultDatabase) var db
        
        try await db.withRollback { db in
            // Create user
            let user = try await User.insert {
                User.Draft(
                    name: "Bob",
                    email: "bob@example.com"
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            
            // Update user
            try await User
                .filter { $0.id == user.id }
                .update { $0.name = "Robert" }
                .execute(db)
            
            // Verify update
            let updated = try await User
                .filter { $0.id == user.id }
                .fetchOne(db)!
            
            #expect(updated.name == "Robert")
            
            // All changes rolled back after block
        }
    }
}
```

## Testing Migrations

Test your migrations in isolation:

```swift
@Suite("Migration Tests")
struct MigrationTests {
    @Test func migrationsApplyCleanly() async throws {
        try await withDependencies {
            $0.defaultDatabase = try await TestDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var db
            
            let migrator = Database.Migrator.appMigrations()
            
            // Run all migrations
            try await migrator.migrate(db)
            
            // Verify migrations completed
            let completed = try await migrator.hasCompletedMigrations(db)
            #expect(completed == true)
            
            // Verify schema is correct
            try await db.read { db in
                // Check tables exist
                let users = try await User.fetchAll(db)
                #expect(users.isEmpty)
                
                let posts = try await Post.fetchAll(db)
                #expect(posts.isEmpty)
            }
        }
    }
    
    @Test func dataMigrationWorks() async throws {
        try await withDependencies {
            $0.defaultDatabase = try await TestDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var db
            
            // Apply initial migration
            var migrator = Database.Migrator()
            migrator.registerMigration("create_users") { db in
                try await db.execute("""
                    CREATE TABLE users (
                        id SERIAL PRIMARY KEY,
                        email TEXT NOT NULL
                    )
                """)
            }
            try await migrator.migrate(db)
            
            // Insert test data
            try await db.write { db in
                try await db.execute("""
                    INSERT INTO users (email) VALUES 
                    ('USER@EXAMPLE.COM'),
                    ('Admin@Example.Com')
                """)
            }
            
            // Apply data migration
            migrator.registerMigration("normalize_emails") { db in
                try await db.execute("""
                    UPDATE users 
                    SET email = LOWER(email)
                """)
            }
            try await migrator.migrate(db)
            
            // Verify migration worked
            let users = try await db.read { db in
                try await User.fetchAll(db)
            }
            
            #expect(users[0].email == "user@example.com")
            #expect(users[1].email == "admin@example.com")
        }
    }
}
```

## Testing Transactions

Verify transactional behavior:

```swift
@Test func transactionRollback() async throws {
    try await withDependencies {
        $0.defaultDatabase = try await TestDatabase()
    } operation: {
        @Dependency(\.defaultDatabase) var db
        
        // Setup initial data
        try await db.write { db in
            try await Account.insert {
                Account.Draft(
                    id: 1,
                    balance: 100.0
                )
            }.execute(db)
        }
        
        // Try transaction that should fail
        do {
            try await db.withTransaction { db in
                // First operation succeeds
                try await Account
                    .filter { $0.id == 1 }
                    .update { $0.balance -= 50 }
                    .execute(db)
                
                // Force failure
                throw TestError.intentionalFailure
            }
        } catch {
            // Expected failure
        }
        
        // Verify rollback
        let account = try await db.read { db in
            try await Account
                .filter { $0.id == 1 }
                .fetchOne(db)!
        }
        
        #expect(account.balance == 100.0) // Unchanged
    }
}
```

## Testing Queries

Test complex queries and relationships:

```swift
@Test func complexQuery() async throws {
    try await withDependencies {
        $0.defaultDatabase = try await TestDatabase()
    } operation: {
        @Dependency(\.defaultDatabase) var db
        
        // Setup test data
        try await db.write { db in
            // Create users
            for i in 1...3 {
                let user = try await User.insert {
                    User.Draft(
                        name: "User \(i)",
                        email: "user\(i)@example.com"
                    )
                }
                .returning(\.id)
                .fetchOne(db)!
                
                // Create posts for each user
                for j in 1...i {
                    try await Post.insert {
                        Post.Draft(
                            userId: user,
                            title: "Post \(j) by User \(i)",
                            published: j % 2 == 0
                        )
                    }.execute(db)
                }
            }
        }
        
        // Test query
        let publishedPosts = try await db.read { db in
            try await Post
                .filter { $0.published == true }
                .join(User.self) { $0.userId == $1.id }
                .order(by: .ascending(\.title))
                .fetchAll(db)
        }
        
        #expect(publishedPosts.count == 3)
    }
}
```

## Test Helpers

Create reusable test helpers:

```swift
extension TestDatabase {
    func seedTestData() async throws {
        try await self.write { db in
            // Create test users
            let users = [
                ("Alice", "alice@test.com"),
                ("Bob", "bob@test.com"),
                ("Charlie", "charlie@test.com")
            ]
            
            for (name, email) in users {
                try await User.insert {
                    User.Draft(
                        name: name,
                        email: email
                    )
                }.execute(db)
            }
        }
    }
}

@Test func withSeededData() async throws {
    try await withDependencies {
        $0.defaultDatabase = try await TestDatabase()
    } operation: {
        @Dependency(\.defaultDatabase) var db
        
        // Use helper
        try await (db as! TestDatabase).seedTestData()
        
        let users = try await db.read { db in
            try await User.fetchAll(db)
        }
        
        #expect(users.count == 3)
    }
}
```

## Performance Testing

Test query performance:

```swift
@Test func performanceTest() async throws {
    try await withDependencies {
        $0.defaultDatabase = try await TestDatabase()
    } operation: {
        @Dependency(\.defaultDatabase) var db
        
        // Insert many records
        try await db.write { db in
            for i in 1...1000 {
                try await Product.insert {
                    Product.Draft(
                        name: "Product \(i)",
                        price: Decimal(i)
                    )
                }.execute(db)
            }
        }
        
        // Measure query time
        let start = Date()
        
        let products = try await db.read { db in
            try await Product
                .filter { $0.price > 500 }
                .order(by: .descending(\.price))
                .limit(10)
                .fetchAll(db)
        }
        
        let elapsed = Date().timeIntervalSince(start)
        
        #expect(products.count == 10)
        #expect(elapsed < 0.1) // Should be fast
    }
}
```

## Recording Integration Snapshots

Integration tests that use `assertQuery` are nested below the
`SnapshotIntegrationTests` suite. Recording is controlled centrally in
`Tests/Records Tests/Support/IntegrationTestsSuite.swift`:

```swift
@MainActor @Suite(.serialized, .snapshots(record: .never))
struct SnapshotIntegrationTests {}
```

Temporarily change the recording mode from `.never` to `.all` to regenerate every
SQL and result snapshot, run the package tests through the Institute coordinator,
review the resulting source changes, and restore `.never` before committing.

The suite hierarchy supports focused runs of the complete integration surface or
an individual namespace such as `SnapshotIntegrationTests.Execution.Select` or
`SnapshotIntegrationTests.Features.JSONB`.

## Environment Setup

Configure test database via environment variables:

```bash
# .env.test or export in shell
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=test_db
export DATABASE_USER=postgres
export DATABASE_PASSWORD=password
```

Or in your test configuration:

```swift
extension TestDatabase {
    static func configured() async throws -> TestDatabase {
        try await TestDatabase(
            configuration: .init(
                host: "localhost",
                port: 5432,
                database: "test_db",
                username: "postgres",
                password: "password"
            )
        )
    }
}
```

## Complete Test Example

```swift
import Testing
import Records
import RecordsTestSupport
import Dependencies

@Table("products")
struct Product {
    let id: Int
    let name: String
    let price: Decimal
    let stock: Int
}

@Table("orders")
struct Order {
    let id: Int
    let productId: Int
    let quantity: Int
    let total: Decimal
}

@Suite("Order Service Tests", .dependency(\.defaultDatabase, TestDatabase.withSchema()))
struct OrderServiceTests {
    @Dependency(\.defaultDatabase) var db
    
    struct OrderService {
        let db: any Database.Writer
        
        func placeOrder(productId: Int, quantity: Int) async throws -> Order {
            try await db.withTransaction { db in
                // Get product
                let product = try await Product
                    .filter { $0.id == productId }
                    .fetchOne(db)
                
                guard let product else {
                    throw OrderError.productNotFound
                }
                
                guard product.stock >= quantity else {
                    throw OrderError.insufficientStock
                }
                
                // Update stock
                try await Product
                    .filter { $0.id == productId }
                    .update { $0.stock -= quantity }
                    .execute(db)
                
                // Create order
                return try await Order.insert {
                    Order.Draft(
                        productId: productId,
                        quantity: quantity,
                        total: product.price * Decimal(quantity)
                    )
                }
                .returning(\.self)
                .fetchOne(db)!
            }
        }
    }
    
    @Test func successfulOrder() async throws {
        // Setup
        try await db.write { db in
            try await Product.insert {
                Product.Draft(
                    name: "Widget",
                    price: 10.00,
                    stock: 100
                )
            }.execute(db)
        }
        
        // Test
        let service = OrderService(db: db)
        let order = try await service.placeOrder(productId: 1, quantity: 5)
        
        // Verify
        #expect(order.quantity == 5)
        #expect(order.total == 50.00)
        
        let product = try await db.read { db in
            try await Product.filter { $0.id == 1 }.fetchOne(db)!
        }
        #expect(product.stock == 95)
    }
    
    @Test func insufficientStock() async throws {
        // Setup
        try await db.write { db in
            try await Product.insert {
                Product.Draft(
                    name: "Widget",
                    price: 10.00,
                    stock: 3
                )
            }.execute(db)
        }
        
        // Test
        let service = OrderService(db: db)
        
        await #expect(throws: OrderError.insufficientStock) {
            try await service.placeOrder(productId: 1, quantity: 5)
        }
        
        // Verify stock unchanged
        let product = try await db.read { db in
            try await Product.filter { $0.id == 1 }.fetchOne(db)!
        }
        #expect(product.stock == 3)
    }
}
```

## Best Practices

1. **Use schema isolation** for parallel test execution
2. **Keep tests independent** - each test should set up its own data
3. **Test both success and failure paths**
4. **Use withRollback** for faster tests when schema isolation isn't needed
5. **Create test helpers** for common setup operations
6. **Test migrations separately** from business logic
