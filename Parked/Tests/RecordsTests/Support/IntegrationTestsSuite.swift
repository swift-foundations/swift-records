import SnapshotTesting
import Testing

/// Top-level umbrella suite for all integration tests that use assertQuery with snapshot testing.
///
/// This allows re-recording all snapshots from one place by changing `.snapshots(record: .never)` to `.snapshots(record: .all)`.
///
/// Example usage:
/// ```swift
/// // To re-record all snapshots:
/// @MainActor @Suite(.snapshots(record: .all)) struct SnapshotIntegrationTests {}
///
/// // To never record (normal test mode):
/// @MainActor @Suite(.snapshots(record: .never)) struct SnapshotIntegrationTests {}
/// ```
@MainActor @Suite(.serialized, .snapshots(record: .never)) struct SnapshotIntegrationTests {}
