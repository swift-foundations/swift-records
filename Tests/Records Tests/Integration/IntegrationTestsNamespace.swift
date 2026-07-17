import Foundation
import Testing

// Snapshot integration test namespaces
extension SnapshotIntegrationTests {
    @Suite struct Execution {
        @Suite struct `Execution` {}
        @Suite struct `Select` {}
        @Suite struct `Insert` {}
        @Suite struct `Update` {}
    }

    @Suite struct Features {
        @Suite struct `Features` {}
        @Suite struct `JSONB` {}
    }
}
