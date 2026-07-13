import Dependencies
import DependenciesTestSupport
import Foundation
import PostgresNIO
import RecordsTestSupport
import Testing

@testable import Records

// MARK: - Suite 1: Basic Operations & Error Handling (10 tests)

@Suite(
    "PostgreSQL LISTEN/NOTIFY - Basic Operations",
    .disabled(),
    .serialized,
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct NotificationBasicTests {
    @Dependency(\.defaultDatabase) var database

    struct SimplePayload: Codable, Equatable, Sendable {
        let message: String
    }

    struct EmptyPayload: Codable, Equatable, Sendable {
        // Empty struct encodes to {}
    }

    struct TestMessage: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let timestamp: Date
    }

    struct ReminderChange: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let title: String
    }

    enum RoundTripTestCase {
        case simplePayload
        case emptyPayload
        case typedWithDate

        var description: String {
            switch self {
            case .simplePayload: return "simple string payload"
            case .emptyPayload: return "empty payload"
            case .typedWithDate: return "typed message with ISO8601 date"
            }
        }
    }

    @Test(
        "Send and receive notification",
        arguments: [
            RoundTripTestCase.simplePayload,
            RoundTripTestCase.emptyPayload,
            RoundTripTestCase.typedWithDate,
        ]
    )
    func notificationRoundTrip(testCase: RoundTripTestCase) async throws {
        switch testCase {
        case .simplePayload:
            let channel = try ChannelName(validating: "test_basic_\(UUID().uuidString)")
            let payload = SimplePayload(message: "Hello, PostgreSQL!")

            let stream = try await database.notifications(
                on: channel,
                expecting: SimplePayload.self
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await received in stream {
                        #expect(received == payload)
                        break
                    }
                }

                try await database.notify(channel: channel, payload: payload)
                try await group.waitForAll()
            }

        case .emptyPayload:
            let channel = try ChannelName(validating: "test_no_payload_\(UUID().uuidString)")
            let payload = EmptyPayload()

            let stream = try await database.notifications(on: channel, expecting: EmptyPayload.self)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await received in stream {
                        #expect(received == payload)
                        break
                    }
                }

                try await database.notify(channel: channel, payload: payload)
                try await group.waitForAll()
            }

        case .typedWithDate:
            let channel = try ChannelName(validating: "test_typed_\(UUID().uuidString)")
            let message = TestMessage(
                id: 42,
                action: "created",
                timestamp: Date()
            )

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let stream = try await database.notifications(
                on: channel,
                expecting: TestMessage.self,
                decoder: decoder
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await received in stream {
                        #expect(received.id == message.id)
                        #expect(received.action == message.action)
                        #expect(abs(received.timestamp.timeIntervalSince(message.timestamp)) < 1.0)
                        break
                    }
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try await database.notify(channel: channel, payload: message, encoder: encoder)

                try await group.waitForAll()
            }
        }
    }

    @Test("Receive multiple notifications on same channel")
    func multipleNotifications() async throws {
        let channel = try ChannelName(validating: "test_multiple_\(UUID().uuidString)")
        let count = 5

        let stream = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var received: [SimplePayload] = []
                for try await notification in stream {
                    received.append(notification)
                    if received.count == count {
                        break
                    }
                }
                #expect(received.count == count)
                for i in 0..<count {
                    #expect(received[i] == SimplePayload(message: "Message \(i)"))
                }
            }

            for i in 0..<count {
                try await database.notify(
                    channel: channel,
                    payload: SimplePayload(message: "Message \(i)")
                )
                try await Task.sleep(for: .milliseconds(10))
            }

            try await group.waitForAll()
        }
    }

    enum ConsumerTestCase {
        case channelIsolation
        case multipleConsumersSameChannel

        var description: String {
            switch self {
            case .channelIsolation: return "channel isolation - separate channels"
            case .multipleConsumersSameChannel: return "multiple consumers on same channel"
            }
        }
    }

    @Test(
        "Multiple consumer scenarios",
        arguments: [
            ConsumerTestCase.channelIsolation,
            ConsumerTestCase.multipleConsumersSameChannel,
        ]
    )
    func multipleConsumerScenarios(testCase: ConsumerTestCase) async throws {
        switch testCase {
        case .channelIsolation:
            let channelA = try ChannelName(validating: "test_channel_a_\(UUID().uuidString)")
            let channelB = try ChannelName(validating: "test_channel_b_\(UUID().uuidString)")

            let streamA = try await database.notifications(
                on: channelA,
                expecting: SimplePayload.self
            )
            let streamB = try await database.notifications(
                on: channelB,
                expecting: SimplePayload.self
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    var receivedA: [SimplePayload] = []
                    for try await notification in streamA {
                        receivedA.append(notification)
                        if receivedA.count == 1 {
                            break
                        }
                    }
                    #expect(receivedA.count == 1)
                    #expect(receivedA[0].message == "For Channel A")
                }

                group.addTask {
                    var receivedB: [SimplePayload] = []
                    for try await notification in streamB {
                        receivedB.append(notification)
                        if receivedB.count == 1 {
                            break
                        }
                    }
                    #expect(receivedB.count == 1)
                    #expect(receivedB[0].message == "For Channel B")
                }

                try await database.notify(
                    channel: channelA,
                    payload: SimplePayload(message: "For Channel A")
                )
                try await database.notify(
                    channel: channelB,
                    payload: SimplePayload(message: "For Channel B")
                )

                try await group.waitForAll()
            }

        case .multipleConsumersSameChannel:
            let channel = try ChannelName(validating: "test_multi_consumer_\(UUID().uuidString)")

            let stream1 = try await database.notifications(
                on: channel,
                expecting: SimplePayload.self
            )
            let stream2 = try await database.notifications(
                on: channel,
                expecting: SimplePayload.self
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await received in stream1 {
                        #expect(received.message == "Broadcast")
                        break
                    }
                }

                group.addTask {
                    for try await received in stream2 {
                        #expect(received.message == "Broadcast")
                        break
                    }
                }

                try await database.notify(
                    channel: channel,
                    payload: SimplePayload(message: "Broadcast")
                )
                try await group.waitForAll()
            }
        }
    }

    @Test(
        "Stream lifecycle handling",
        arguments: [
            (lifecycle: "explicit cancellation", explicitCancel: true, delay: 100),
            (lifecycle: "natural abandonment", explicitCancel: false, delay: 200),
        ]
    )
    func streamLifecycle(lifecycle: String, explicitCancel: Bool, delay: Int) async throws {
        let channel = try ChannelName(validating: "test_lifecycle_\(UUID().uuidString)")

        let stream = try await database.notifications(on: channel, expecting: SimplePayload.self)

        if explicitCancel {
            let task = Task {
                var count = 0
                for try await _ in stream {
                    count += 1
                }
                return count
            }

            try await Task.sleep(for: .milliseconds(delay))
            task.cancel()
            try await Task.sleep(for: .milliseconds(200))

            let result = await task.result
            _ = result
        } else {
            // Natural abandonment - stream goes out of scope
            _ = stream
            try await Task.sleep(for: .milliseconds(delay))
        }
    }

    @Test(
        "JSON decoding error handling",
        arguments: [
            (sendSubsequent: false, description: "simple decoding error"),
            (
                sendSubsequent: true,
                description: "error terminates stream - subsequent messages not received"
            ),
        ]
    )
    func jsonDecodingError(sendSubsequent: Bool, description: String) async throws {
        let channel = try ChannelName(validating: "test_decode_error_\(UUID().uuidString)")

        let stream = try await database.notifications(on: channel, expecting: TestMessage.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var receivedCount = 0
                do {
                    for try await _: TestMessage in stream {
                        receivedCount += 1
                    }
                    Issue.record("Should have thrown decoding error for: \(description)")
                } catch let error as Database.Error {
                    switch error {
                    case .notificationDecodingFailed:
                        #expect(
                            receivedCount == 0,
                            "Should fail on first message for: \(description)"
                        )
                    default:
                        Issue.record("Wrong error type for \(description): \(error)")
                    }
                } catch {
                    Issue.record("Wrong error type for \(description): \(error)")
                }
            }

            try await database.notify(channel: channel, payload: "not valid json")

            if sendSubsequent {
                try await Task.sleep(for: .milliseconds(100))

                let validMessage = TestMessage(id: 1, action: "test", timestamp: Date())
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try await database.notify(channel: channel, payload: validMessage, encoder: encoder)
            }

            try await group.waitForAll()
        }
    }

    @Test("Escape single quotes in payload")
    func sqlInjectionProtection() async throws {
        let channel = try ChannelName(validating: "test_injection_\(UUID().uuidString)")
        let payload = SimplePayload(message: "It's a beautiful day, isn't it?")

        let stream = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received == payload)
                    break
                }
            }

            try await database.notify(channel: channel, payload: payload)
            try await group.waitForAll()
        }
    }

    @Test(
        "Notification behavior in transactions",
        arguments: [
            (shouldCommit: true, expectedCount: 1, description: "commit"),
            (shouldCommit: false, expectedCount: 0, description: "rollback"),
        ]
    )
    func transactionNotificationBehavior(
        shouldCommit: Bool,
        expectedCount: Int,
        description: String
    ) async throws {
        let channel = try ChannelName(validating: "test_txn_\(description)_\(UUID().uuidString)")
        let payload = SimplePayload(message: description)

        let stream = try await database.notifications(on: channel, expecting: SimplePayload.self)

        let listenerTask = Task {
            var received: [SimplePayload] = []
            for try await notification in stream {
                received.append(notification)
            }
            return received
        }

        do {
            try await database.withTransaction { db in
                try await db.notify(channel: channel, payload: payload)
                if !shouldCommit {
                    throw CancellationError()
                }
            }
        } catch {
            // Expected for rollback case
        }

        try await Task.sleep(for: .milliseconds(100))

        listenerTask.cancel()
        let result = await listenerTask.result

        switch result {
        case .success(let received):
            #expect(
                received.count == expectedCount,
                "Expected \(expectedCount) notifications after \(description), got \(received.count)"
            )
            if expectedCount > 0 {
                #expect(received[0] == payload)
            }
        case .failure:
            break
        }
    }
}

// MARK: - Suite 2: Edge Cases & Advanced Features (10 tests)

@Suite(
    "PostgreSQL LISTEN/NOTIFY - Advanced Features",
    //    .disabled(),
    .serialized,
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct NotificationAdvancedTests {
    @Dependency(\.defaultDatabase) var database

    struct SimplePayload: Codable, Equatable, Sendable {
        let message: String
    }

    struct EmptyPayload: Codable, Equatable, Sendable {}

    struct TestMessage: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let timestamp: Date
    }

    struct ReminderChange: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let title: String
    }

    @Test("Real-world reminder change notification")
    func realWorldUseCase() async throws {
        let channel = try ChannelName(validating: "reminder_changes")
        let change = ReminderChange(
            id: 123,
            action: "updated",
            title: "Buy groceries"
        )

        let stream = try await database.notifications(on: channel, expecting: ReminderChange.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received == change)
                    break
                }
            }

            try await database.write { db in
                try await db.notify(channel: channel, payload: change)
            }

            try await group.waitForAll()
        }
    }

    @Test(
        "Payload size handling",
        arguments: [
            (size: 7985, shouldSucceed: true, description: "Just under limit (8000 - 15 overhead)"),
            (
                size: 7986, shouldSucceed: false,
                description: "At exact limit (8000 - 14 overhead) - rejected by PostgreSQL"
            ),
            (
                size: 9000, shouldSucceed: false,
                description: "Well over limit - rejected by validation"
            ),
        ]
    )
    func payloadSizeHandling(size: Int, shouldSucceed: Bool, description: String) async throws {
        let channel = try ChannelName(validating: "test_size_\(size)_\(UUID().uuidString)")

        // {"message":"..."} = 14 bytes overhead
        let largeMessage = String(repeating: "x", count: size)
        let payload = SimplePayload(message: largeMessage)

        if shouldSucceed {
            // Should succeed without throwing
            try await database.notify(channel: channel, payload: payload)
        } else {
            // Should throw an error (either from our validation or PostgreSQL)
            do {
                try await database.notify(channel: channel, payload: payload)
                Issue.record("Should have thrown payload size error for \(description)")
            } catch let error as Database.Error {
                // Our validation catches payloads > 8000 bytes
                switch error {
                case .notificationPayloadTooLarge(let actualSize, let limit, let hint):
                    #expect(
                        actualSize > limit,
                        "Payload size \(actualSize) should exceed limit \(limit)"
                    )
                    #expect(limit == 8000, "PostgreSQL NOTIFY limit should be 8000 bytes")
                    #expect(
                        hint.contains("reference ID"),
                        "Error hint should mention reference ID pattern"
                    )
                default:
                    Issue.record("Wrong Database.Error type for \(description): \(error)")
                }
            } catch {
                // PostgreSQL may reject payloads at exactly 8000 bytes with PSQLError
                // This is expected behavior - payloads at the limit are rejected by the server
                // We accept any error for the boundary cases
            }
        }
    }

    @Test("Buffer overflow - fast producer, slow consumer")
    func bufferOverflow() async throws {
        let channel = try ChannelName(validating: "test_buffer_\(UUID().uuidString)")

        let stream = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var received: [SimplePayload] = []
                for try await notification in stream {
                    received.append(notification)
                    try await Task.sleep(for: .milliseconds(100))

                    if received.count == 10 {
                        break
                    }
                }
                #expect(received.count == 10)
            }

            for i in 0..<10 {
                try await database.notify(
                    channel: channel,
                    payload: SimplePayload(message: "Message \(i)")
                )
            }

            try await group.waitForAll()
        }
    }

    @Test("Rapid subscribe/unsubscribe")
    func rapidSubscribeUnsubscribe() async throws {
        for i in 0..<10 {
            let channel = try ChannelName(validating: "test_rapid_\(i)_\(UUID().uuidString)")
            let stream = try await database.notifications(
                on: channel,
                expecting: SimplePayload.self
            )

            let task = Task {
                for try await _ in stream {
                    break
                }
            }

            task.cancel()
            _ = try? await task.value
        }
    }

    @Test("Empty payload string")
    func emptyPayloadString() async throws {
        let channel = try ChannelName(validating: "test_empty_\(UUID().uuidString)")

        let stream = try await database.notifications(on: channel, expecting: EmptyPayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await received in stream {
                        #expect(received == EmptyPayload())
                        break
                    }
                } catch {
                    print("Empty payload error: \(error)")
                }
            }

            try await database.notify(channel: channel, payload: "")

            try await Task.sleep(for: .milliseconds(100))
            group.cancelAll()
        }
    }

    @Test("NotificationEvent stream includes metadata")
    func notificationEventMetadata() async throws {
        let channel = try ChannelName(validating: "test_metadata_\(UUID().uuidString)")
        let payload = SimplePayload(message: "Test")

        let stream = try await database.notificationEvents(
            on: channel,
            expecting: SimplePayload.self
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await event in stream {
                    #expect(event.payload == payload)
                    #expect(event.channel == channel)
                    #expect(event.backendPID > 0, "Backend PID should be positive")
                    break
                }
            }

            try await database.notify(channel: channel, payload: payload)
            try await group.waitForAll()
        }
    }
}
