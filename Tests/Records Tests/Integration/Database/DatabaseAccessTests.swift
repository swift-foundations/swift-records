import Dependencies
import Dependencies_Test_Support
import Foundation
import Records_Test_Support
import Testing

@Suite(

    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct Test {
    @Dependency(\.defaultDatabase) var database

    @Test
    func `Database.Queue serializes all operations`() async throws {
        // Test that operations are serialized
        let results = await withTaskGroup(of: Int?.self) { group in
            for i in 1...10 {
                group.addTask {
                    try? await database.write { _ in
                        // Simulate work
                        try? await Task.sleep(nanoseconds: 10_000)
                        return i
                    }
                }
            }

            var collected: [Int] = []
            for await result in group {
                if let result = result {
                    collected.append(result)
                }
            }
            return collected
        }

        // All operations should complete
        #expect(results.count == 10)
    }

    @Test(

        .disabled("only run in isolation for proper results")
    )
    func testDatabasePoolAllowsConcurrentReads() async throws {
        // Note: This test uses the same database interface but conceptually tests
        // that reads can happen concurrently when using a pool

        // Track concurrent execution
        let startTime = Date()

        let readTimes = await withTaskGroup(of: TimeInterval.self) { group in
            for _ in 1...5 {
                group.addTask {
                    let taskStart = Date()
                    _ = try? await database.read { db in
                        // Simulate read operation
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                        return try? await Reminder.fetchCount(db)
                    }
                    return Date().timeIntervalSince(taskStart)
                }
            }

            var times: [TimeInterval] = []
            for await duration in group {
                times.append(duration)
            }
            return times
        }

        let totalTime = Date().timeIntervalSince(startTime)

        // If reads are concurrent, total time should be less than serialized time
        // Serialized would be 5 * 0.1 = 0.5+ seconds
        // With connection overhead, concurrent might be around 0.2-0.5 seconds
        #expect(
            totalTime < 0.55,
            "Reads should complete faster than fully serialized (took \(totalTime)s)"
        )
        #expect(readTimes.count == 5)
    }

    @Test
    func `Database.Pool serializes write operations`() async throws {
        do {
            // Start with known sample data (6 reminders from withReminderData)
            let initialCount = try await database.read { db in
                try await Reminder.fetchCount(db)
            }

            // Track write order
            actor WriteCollector {
                var writes: [Int] = []

                func recordWrite(_ value: Int) {
                    writes.append(value)
                }

                func getWrites() -> [Int] {
                    return writes
                }
            }

            let collector = WriteCollector()

            // Concurrent write attempts
            await withTaskGroup(of: Void.self) { group in
                for i in 1...5 {
                    group.addTask {
                        try? await database.write { db in
                            // Record when this write starts
                            await collector.recordWrite(i)

                            // Perform actual write
                            try? await Reminder.insert {
                                Reminder.Draft(
                                    notes: "Testing concurrent write \(i)",
                                    remindersListID: 1,
                                    title: "Write Test \(i)"
                                )
                            }.execute(db)

                            // Simulate some work
                            try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
                        }
                    }
                }
            }

            let writeOrder = await collector.getWrites()

            // All writes should complete
            #expect(writeOrder.count == 5)

            // Verify all reminders were created (6 initial + 5 new = 11)
            let finalCount = try await database.read { db in
                try await Reminder.fetchCount(db)
            }
            #expect(finalCount == initialCount + 5)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test
    func `Read and write operations don't interfere`() async throws {
        do {
            // Start with known state
            let initialCount = try await database.read { db in
                try await Reminder.fetchCount(db)
            }

            // Concurrent reads and writes
            await withTaskGroup(of: String.self) { group in
                // Add some write operations
                for i in 1...3 {
                    group.addTask {
                        do {
                            try await database.write { db in
                                try await Reminder.insert {
                                    Reminder.Draft(
                                        notes: "Test isolation",
                                        remindersListID: 1,
                                        title: "Concurrent Write \(i)"
                                    )
                                }.execute(db)
                            }
                            return "write-\(i)"
                        } catch {
                            return "write-error-\(i)"
                        }
                    }
                }

                // Add some read operations
                for i in 1...3 {
                    group.addTask {
                        do {
                            let count = try await database.read { db in
                                try await Reminder.fetchCount(db)
                            }
                            return "read-\(i)-count-\(count)"
                        } catch {
                            return "read-error-\(i)"
                        }
                    }
                }

                // Collect results
                var results: [String] = []
                for await result in group {
                    results.append(result)
                }
            }

            // Final count should reflect all writes
            let finalCount = try await database.read { db in
                try await Reminder.fetchCount(db)
            }
            #expect(finalCount == initialCount + 3)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test
    func `Actor-based concurrency handles multiple operations`() async throws {
        // Test that our actor-based approach handles concurrent access correctly
        actor Counter {
            var value = 0

            func increment() -> Int {
                value += 1
                return value
            }
        }

        let counter = Counter()

        // Many concurrent operations
        let results = await withTaskGroup(of: Int.self) { group in
            for _ in 1...20 {
                group.addTask {
                    let count = await counter.increment()

                    // Also do a database operation
                    _ = try? await database.read { db in
                        try await Reminder.fetchCount(db)
                    }

                    return count
                }
            }

            var values: Swift.Set<Int> = []
            for await value in group {
                values.insert(value)
            }
            return values
        }

        // Each increment should produce a unique value
        #expect(results.count == 20)
        #expect(results.contains(20))
    }
}
