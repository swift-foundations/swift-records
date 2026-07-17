import Dependencies
import Foundation
import Records_Test_Support
import PostgreSQL_Standard
import Testing

@Suite(

    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct Test {
    @Dependency(\.defaultDatabase) var db

    // MARK: - Test Tables

    @Table("test_accounts")
    struct Account: Identifiable {
        @Column var id: Int = 0
        @Column var name: String
        @Column var balance: Decimal

        init(name: String = "", balance: Decimal = 0) {
            self.name = name
            self.balance = balance
        }
    }

    @Table("test_transactions")
    struct Transaction: Identifiable {
        @Column var id: Int = 0
        @Column("account_id") var accountId: Int
        @Column var amount: Decimal
        @Column var description: String

        init(accountId: Int = 0, amount: Decimal = 0, description: String = "") {
            self.accountId = accountId
            self.amount = amount
            self.description = description
        }
    }

    // MARK: - Setup

    init() async throws {
        // Create test tables
        try await db.write { db in
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS test_accounts (
                        id SERIAL PRIMARY KEY,
                        name TEXT NOT NULL,
                        balance DECIMAL NOT NULL
                    )
                """
            )

            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS test_transactions (
                        id SERIAL PRIMARY KEY,
                        account_id INTEGER NOT NULL REFERENCES test_accounts(id),
                        amount DECIMAL NOT NULL,
                        description TEXT NOT NULL
                    )
                """
            )
        }
    }

    // MARK: - Basic Transaction Tests

    @Test
    func `Basic transaction commit`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_transactions")
            try await db.execute("DELETE FROM test_accounts")
        }

        // Test transaction commit
        let accountId = try await db.withTransaction { db in
            let account = Account(name: "Test Account", balance: 1000)
            let result = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                (account.name, account.balance)
            }
            .returning(\.self)
            .fetchOne(db)

            #expect(result != nil)
            return result!.id
        }

        // Verify data was committed
        let count = try await db.read { db in
            try await Account.where { $0.id == accountId }.asSelect().fetchCount(db)
        }
        #expect(count == 1)
    }

    @Test
    func `Basic transaction rollback`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        // Test transaction rollback
        do {
            try await db.withTransaction { db in
                _ = try await Account.insert {
                    ($0.name, $0.balance)
                } values: {
                    ("Rollback Test", Decimal(500))
                }
                .returning(\.id)
                .fetchOne(db)

                throw TestError.intentionalRollback
            }
            Issue.record("Transaction should have rolled back")
        } catch TestError.intentionalRollback {
            // Expected
        }

        // Verify data was not committed
        let count = try await db.read { db in
            try await Account.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - Savepoint Tests

    @Test
    func `Savepoint with auto-generated name`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        try await db.withTransaction { db in
            // Insert first account
            let account1 = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                ("Account 1", Decimal(1000))
            }
            .returning(\.self)
            .fetchOne(db)!.id

            // Try savepoint that fails
            do {
                try await db.withSavepoint(nil) { db in
                    _ = try await Account.insert {
                        ($0.name, $0.balance)
                    } values: {
                        ("Account 2", Decimal(2000))
                    }
                    .returning(\.id)
                    .fetchOne(db)

                    throw TestError.intentionalRollback
                }
                Issue.record("Savepoint should have rolled back")
            } catch TestError.intentionalRollback {
                // Expected
            }

            // Insert third account after savepoint rollback
            _ = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                ("Account 3", Decimal(3000))
            }
            .returning(\.id)
            .fetchOne(db)
        }

        // Verify only accounts 1 and 3 were committed
        let accounts = try await db.read { db in
            try await Account.order { $0.id }.fetchAll(db)
        }
        #expect(accounts.count == 2)
        #expect(accounts[0].name == "Account 1")
        #expect(accounts[1].name == "Account 3")
    }

    @Test
    func `Named savepoint`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        try await db.withTransaction { db in
            _ = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                ("Main Account", Decimal(5000))
            }
            .execute(db)

            // Named savepoint
            try await db.withSavepoint("test_point") { db in
                _ = try await Account.insert {
                    ($0.name, $0.balance)
                } values: {
                    ("Savepoint Account", Decimal(1000))
                }
                .execute(db)
            }
        }

        let count = try await db.read { db in
            try await Account.fetchCount(db)
        }
        #expect(count == 2)
    }

    // MARK: - Nested Transaction Tests

    @Test
    func `Nested transactions with savepoints`() async throws {
        // Clear existing data - delete in correct order due to foreign key constraints
        try await db.write { db in
            try await db.execute("DELETE FROM test_transactions")
            try await db.execute("DELETE FROM test_accounts")
        }

        try await db.withTransaction { db in
            // Level 1: Main transaction
            let account = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                ("Nested Test", Decimal(10000))
            }
            .returning(\.self)
            .fetchOne(db)!

            // Debug: Verify account was created
            #expect(account.id > 0)

            // Level 2: First nested transaction
            try await db.withNestedTransaction(isolation: nil) { db in
                _ = try await Transaction.insert {
                    ($0.accountId, $0.amount, $0.description)
                } values: {
                    (account.id, Decimal(100), "Level 2 transaction")
                }
                .execute(db)

                // Level 3: Deeply nested transaction
                try await db.withNestedTransaction(isolation: nil) { db in
                    _ = try await Transaction.insert {
                        ($0.accountId, $0.amount, $0.description)
                    } values: {
                        (account.id, Decimal(200), "Level 3 transaction")
                    }
                    .execute(db)
                }
            }

            // Level 2: Second nested transaction that fails
            do {
                try await db.withNestedTransaction(isolation: nil) { db in
                    _ = try await Transaction.insert {
                        ($0.accountId, $0.amount, $0.description)
                    } values: {
                        (account.id, Decimal(-500), "Failed transaction")
                    }
                    .execute(db)

                    throw TestError.intentionalRollback
                }
            } catch TestError.intentionalRollback {
                // Expected - nested transaction rolled back
            }

            // Level 2: Third nested transaction succeeds
            try await db.withNestedTransaction(isolation: nil) { db in
                _ = try await Transaction.insert {
                    ($0.accountId, $0.amount, $0.description)
                } values: {
                    (account.id, Decimal(300), "Success after failure")
                }
                .execute(db)
            }
        }

        // Verify results
        let transactions = try await db.read { db in
            try await Transaction.order { $0.id }.fetchAll(db)
        }

        #expect(transactions.count == 3)
        #expect(transactions[0].description == "Level 2 transaction")
        #expect(transactions[1].description == "Level 3 transaction")
        #expect(transactions[2].description == "Success after failure")
    }

    @Test
    func `Nested transaction isolation`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        let (outerAccountId, _) = try await db.withTransaction { outerDb -> (Int, Int?) in
            let outerAccount = try await Account.insert {
                ($0.name, $0.balance)
            } values: {
                ("Outer", Decimal(1000))
            }
            .returning(\.self)
            .fetchOne(outerDb)!
            let outerAccountId = outerAccount.id

            let innerAccountId: Int? = try? await { () async throws -> Int in
                try await outerDb.withNestedTransaction(isolation: nil) { innerDb in
                    let innerAccount = try await Account.insert {
                        ($0.name, $0.balance)
                    } values: {
                        ("Inner", Decimal(2000))
                    }
                    .returning(\.self)
                    .fetchOne(innerDb)!
                    let accountId = innerAccount.id

                    // Verify inner account exists in nested transaction
                    let innerCount =
                        try await Account
                        .where { $0.id == accountId }
                        .asSelect()
                        .fetchCount(innerDb)
                    #expect(innerCount == 1)

                    throw TestError.intentionalRollback
                }
            }()

            // Verify inner account was rolled back but outer still exists
            let outerCount =
                try await Account
                .where { $0.id == outerAccountId }
                .asSelect()
                .fetchCount(outerDb)
            #expect(outerCount == 1)

            if let innerAccId = innerAccountId {
                let innerCount =
                    try await Account
                    .where { $0.id == innerAccId }
                    .asSelect()
                    .fetchCount(outerDb)
                #expect(innerCount == 0)
            }

            return (outerAccountId, innerAccountId)
        }

        // Verify final state
        let finalAccounts = try await db.read { db in
            try await Account.fetchAll(db)
        }
        #expect(finalAccounts.count == 1)
        #expect(finalAccounts[0].name == "Outer")
    }

    // MARK: - Error Handling Tests

    @Test
    func `Multiple savepoint rollbacks`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        let successfulAttempts = try await db.withTransaction { db -> [String] in
            var attempts: [String] = []

            for i in 1...5 {
                do {
                    try await db.withSavepoint("attempt_\(i)") { db in
                        _ = try await Account.insert {
                            ($0.name, $0.balance)
                        } values: {
                            ("Attempt \(i)", Decimal(i * 100))
                        }
                        .execute(db)

                        // Fail even attempts
                        if i % 2 == 0 {
                            throw TestError.intentionalRollback
                        }
                    }
                    // Only record success if no error thrown
                    attempts.append("Attempt \(i)")
                } catch TestError.intentionalRollback {
                    // Continue with next attempt
                }
            }

            return attempts
        }

        #expect(successfulAttempts.count == 3)  // Odd attempts succeed

        let accounts = try await db.read { db in
            try await Account.order { $0.id }.fetchAll(db)
        }
        #expect(accounts.count == 3)
        #expect(accounts.map(\.name) == ["Attempt 1", "Attempt 3", "Attempt 5"])
    }

    // MARK: - Performance Tests

    @Test
    func `Nested transaction performance`() async throws {
        // Clear existing data
        try await db.write { db in
            try await db.execute("DELETE FROM test_accounts")
        }

        let startTime = Date()

        try await db.withTransaction { db in
            for i in 1...10 {
                try await db.withNestedTransaction(isolation: nil) { db in
                    for j in 1...10 {
                        _ = try await Account.insert {
                            ($0.name, $0.balance)
                        } values: {
                            ("Account \(i)-\(j)", Decimal(i * j * 100))
                        }
                        .execute(db)
                    }
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("Nested transaction performance: \(elapsed) seconds for 100 inserts")

        let count = try await db.read { db in
            try await Account.fetchCount(db)
        }
        #expect(count == 100)
    }

    // MARK: - Helpers

    enum TestError: Error {
        case intentionalRollback
    }
}

// MARK: - Extensions for testing

// Note: fetchCount is already implemented in Statement+Postgres.swift and Table+Database.swift
// No custom extension needed
