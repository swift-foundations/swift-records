import Foundation
import Testing

// Snapshot integration test namespaces
extension SnapshotIntegrationTests {
    @Suite("Execution") struct Execution {
        @Suite("Select") struct Select {}
        @Suite("Insert") struct Insert {}
        @Suite("Update") struct Update {}
        @Suite("Delete") struct Delete {}
    }

    @Suite("Features") struct Features {
        @Suite("JSONB") struct JSONB {}
        @Suite("FullTextSearch") struct FullTextSearch {}
    }
}
