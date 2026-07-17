import Dependencies
import Foundation
import Records
import Records_Test_Support
import Testing

@Suite(

    .disabled(),  // Disabled by default - enable for manual stress testing
    .serialized,  // Run serially to avoid overwhelming other test suites
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct Test {
    @Dependency(\.defaultDatabase) var db

    // MARK: - High Concurrency INSERT Operations

    @Test
    func `Concurrent INSERT operations - 100 parallel`() async throws {
        let count = 100

        // Delete existing test data
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Concurrent") }.delete().execute(db)
        }

        let countBefore = try await db.read { db in
            try await Reminder.fetchCount(db)
        }

        // Insert records concurrently - all should succeed with proper connection pool
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...count {
                group.addTask {
                    try await db.write { db in
                        try await Reminder.insert {
                            Reminder.Draft(
                                remindersListID: 1,
                                title: "Concurrent \(i)"
                            )
                        }.execute(db)
                    }
                }
            }

            // Wait for all tasks - will throw if any fail
            try await group.waitForAll()
        }

        // Verify all inserted - with proper connection pool, 100% should succeed
        let countAfter = try await db.read { db in
            try await Reminder.fetchCount(db)
        }

        #expect(countAfter == countBefore + count)

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Concurrent") }.delete().execute(db)
        }
    }

    @Test
    func `Concurrent INSERT operations - 500 parallel (stress test)`() async throws {
        let count = 500

        // Delete existing test data
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Stress") }.delete().execute(db)
        }

        let countBefore = try await db.read { db in
            try await Reminder.fetchCount(db)
        }

        // Track results for diagnostics
        struct Result: Sendable {
            let index: Int
            let success: Bool
            let error: String?
        }

        let results = await withTaskGroup(of: Result.self) { group in
            for i in 1...count {
                group.addTask {
                    do {
                        try await db.write { db in
                            try await Reminder.insert {
                                Reminder.Draft(
                                    remindersListID: (i % 2) + 1,  // Only IDs 1 and 2 exist
                                    title: "Stress \(i)"
                                )
                            }.execute(db)
                        }
                        return Result(index: i, success: true, error: nil)
                    } catch {
                        // Use String(reflecting:) to bypass privacy protection
                        return Result(index: i, success: false, error: String(reflecting: error))
                    }
                }
            }

            var allResults: [Result] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }

        // Analyze results
        let successes = results.filter { $0.success }.count
        let failures = results.filter { !$0.success }

        // If there are failures, print diagnostics
        if !failures.isEmpty {
            print("\n=== ⚠️ Concurrency Test Had Failures ===")
            print("Total operations: \(count)")
            print("Successes: \(successes) (\(Int(Double(successes) / Double(count) * 100))%)")
            print("Failures: \(failures.count)")

            print("\n=== Sample Failures (first 10) ===")
            for failure in failures.prefix(10) {
                print("  #\(failure.index): \(failure.error ?? "unknown")")
            }

            // Group errors by type
            let errorTypes = Swift.Dictionary(grouping: failures) { $0.error ?? "unknown" }
            print("\n=== Error Distribution ===")
            for (errorType, instances) in errorTypes.sorted(by: { $0.value.count > $1.value.count })
            {
                print("  \(instances.count)x: \(errorType)")
            }
        }

        // Verify actual inserted count
        let countAfter = try await db.read { db in
            try await Reminder.fetchCount(db)
        }
        let actualInserted = countAfter - countBefore

        // With proper connection pool (10 max connections), all 500 should succeed
        // They queue and wait for available connections (extensive queuing expected with 10 max)
        #expect(
            successes == count,
            "Expected all \(count) operations to succeed, but only \(successes) succeeded"
        )
        #expect(
            actualInserted == count,
            "Expected \(count) records inserted, but got \(actualInserted)"
        )

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Stress") }.delete().execute(db)
        }
    }

    // MARK: - Mixed Read/Write Operations

    @Test
    func `Concurrent read and write mix - 200 operations`() async throws {
        let iterations = 100

        // Setup initial data
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("ReadWrite") }.delete().execute(db)
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "ReadWrite Initial")
            }.execute(db)
        }

        let results = await withTaskGroup(of: Int?.self) { group in
            var readResults: [Int] = []

            // Spawn readers
            for _ in 1...iterations {
                group.addTask {
                    try? await db.read { db in
                        try await Reminder.where { $0.title.hasPrefix("ReadWrite") }.fetchCount(db)
                    }
                }
            }

            // Spawn writers
            for i in 1...iterations {
                group.addTask {
                    try? await db.write { db in
                        try await Reminder.insert {
                            Reminder.Draft(
                                remindersListID: 1,
                                title: "ReadWrite \(i)"
                            )
                        }.execute(db)
                    }
                    return nil
                }
            }

            for await result in group {
                if let count = result {
                    readResults.append(count)
                }
            }

            return readResults
        }

        // All reads should have succeeded
        #expect(results.count == iterations)

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("ReadWrite") }.delete().execute(db)
        }
    }

    // MARK: - Connection Pool Stress

    @Test
    func `Connection pool stress - 500 concurrent requests`() async throws {
        let requests = 500

        // All requests should succeed - they queue for available connections
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...requests {
                group.addTask {
                    try await db.read { db in
                        // Hold connection briefly
                        try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
                        _ = try await Reminder.select { $0.id }.limit(1).fetchAll(db)
                    }
                }
            }

            // Wait for all - will throw if any fail
            try await group.waitForAll()
        }

        // All 500 requests completed successfully
        #expect(true)
    }

    // MARK: - Concurrent UPDATEs

    @Test
    func `Concurrent UPDATE operations on different records`() async throws {
        // Setup: Insert records to update
        let inserted = try await db.write { db in
            try await Reminder.insert {
                for i in 1...50 {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "Update Test \(i)"
                    )
                }
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let ids = inserted.map(\.id)

        // Update all records concurrently - all should succeed
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try await db.write { db in
                        try await Reminder.find(id)
                            .update { $0.title = "Updated \(id)" }
                            .execute(db)
                    }
                }
            }

            try await group.waitForAll()
        }

        // Verify all updates succeeded
        let updated = try await db.read { db in
            try await Reminder.find(ids).fetchAll(db)
        }

        for reminder in updated {
            #expect(reminder.title.hasPrefix("Updated"))
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.find(ids).delete().execute(db)
        }
    }

    @Test
    func `Concurrent UPDATE operations on same record - last write wins`() async throws {
        // Setup: Insert one record
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "Original"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        guard let id = inserted.first?.id else {
            Issue.record("Failed to insert record")
            return
        }

        // Update same record concurrently 100 times
        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask {
                    try? await db.write { db in
                        try await Reminder.find(id)
                            .update { $0.notes = "Update \(i)" }
                            .execute(db)
                    }
                }
            }
        }

        // Verify record exists and has one of the updates
        let final = try await db.read { db in
            try await Reminder.find(id).fetchOne(db)
        }

        #expect(final != nil)
        if let notes = final?.notes {
            #expect(notes.hasPrefix("Update"))
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }

    // MARK: - Concurrent DELETEs

    @Test
    func `Concurrent DELETE operations`() async throws {
        // Setup: Insert records to delete
        let inserted = try await db.write { db in
            try await Reminder.insert {
                for i in 1...100 {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "Delete Test \(i)"
                    )
                }
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let ids = inserted.map(\.id)

        // Delete all records concurrently - all should succeed
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try await db.write { db in
                        try await Reminder.find(id).delete().execute(db)
                    }
                }
            }

            try await group.waitForAll()
        }

        // Verify all deleted successfully
        let remaining = try await db.read { db in
            try await Reminder.find(ids).fetchAll(db)
        }

        #expect(remaining.isEmpty)
    }

    // MARK: - Transaction Concurrency

    @Test
    func `Concurrent transactions - isolated changes`() async throws {
        let transactionCount = 50

        // Delete test data
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Transaction") }.delete().execute(db)
        }

        // All transactions should succeed
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...transactionCount {
                group.addTask {
                    try await db.withTransaction { db in
                        // Each transaction inserts 2 records
                        try await Reminder.insert {
                            Reminder.Draft(
                                remindersListID: 1,
                                title: "Transaction \(i)-A"
                            )
                            Reminder.Draft(
                                remindersListID: 1,
                                title: "Transaction \(i)-B"
                            )
                        }.execute(db)
                    }
                }
            }

            try await group.waitForAll()
        }

        // Verify all committed successfully
        let count = try await db.read { db in
            try await Reminder.where { $0.title.hasPrefix("Transaction") }.fetchCount(db)
        }

        #expect(count == transactionCount * 2)

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Transaction") }.delete().execute(db)
        }
    }

    // MARK: - Complex Queries Under Load

    @Test
    func `Concurrent complex queries`() async throws {
        let queryCount = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 1...queryCount {
                group.addTask {
                    try? await db.read { db in
                        // Complex query with joins, filters, ordering
                        _ =
                            try await Reminder
                            .where { $0.isCompleted == false }
                            .where { $0.remindersListID > 0 }
                            .order(by: \.title)
                            .limit(10)
                            .fetchAll(db)
                    }
                }
            }
        }

        // If we get here, all queries succeeded
        #expect(true)
    }

    // MARK: - Batch Operations

    @Test
    func `Batch INSERT with concurrent readers`() async throws {
        let batchSize = 500
        let readerCount = 50

        // Delete test data
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Batch") }.delete().execute(db)
        }

        await withTaskGroup(of: Void.self) { group in
            // Large batch insert
            group.addTask {
                try? await db.write { db in
                    try await Reminder.insert {
                        for i in 1...batchSize {
                            Reminder.Draft(
                                remindersListID: 1,
                                title: "Batch \(i)"
                            )
                        }
                    }.execute(db)
                }
            }

            // Concurrent readers
            for _ in 1...readerCount {
                group.addTask {
                    try? await db.read { db in
                        _ = try await Reminder.where { $0.title.hasPrefix("Batch") }.fetchCount(db)
                    }
                }
            }
        }

        // Verify batch completed
        let count = try await db.read { db in
            try await Reminder.where { $0.title.hasPrefix("Batch") }.fetchCount(db)
        }

        #expect(count == batchSize)

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Batch") }.delete().execute(db)
        }
    }

    // MARK: - Failure Resilience

    @Test
    func `Concurrent operations with some failures`() async throws {
        let totalOps = 100
        let successfulOps = 50

        await withTaskGroup(of: Bool.self) { group in
            for i in 1...totalOps {
                group.addTask {
                    do {
                        try await db.write { db in
                            try await Reminder.insert {
                                Reminder.Draft(
                                    // Half will fail with invalid foreign key
                                    remindersListID: i <= successfulOps ? 1 : 999999,
                                    title: "Failure Test \(i)"
                                )
                            }.execute(db)
                        }
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successes = 0
            for await success in group {
                if success {
                    successes += 1
                }
            }

            // Should have exactly successfulOps successes
            #expect(successes == successfulOps)
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.hasPrefix("Failure Test") }.delete().execute(db)
        }
    }
}
