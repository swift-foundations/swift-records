import Testing
import Tests_Apple_Testing_Bridge

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
///
/// Re-record with `swift test -c release` while `record: .all` is in place, then
/// put `.never` back — a left-behind `.all` records instead of verifying, so the
/// suite silently stops testing anything.
///
/// ## Organization
///
/// Integration tests nest under this suite as a namespace hierarchy:
///
/// ```
/// SnapshotIntegrationTests
/// ├── Execution
/// │   ├── Select   → SelectExecutionTests
/// │   ├── Insert   → InsertExecutionTests
/// │   ├── Update
/// │   └── Delete
/// └── Features
///     ├── JSONB            → JSONBIntegrationTests
///     └── FullTextSearch   → FullTextSearchIntegrationTests
/// ```
///
/// Any level of that hierarchy is a filter, so a group runs on its own:
///
/// ```bash
/// swift test -c release --filter SnapshotIntegrationTests
/// swift test -c release --filter SnapshotIntegrationTests.Execution
/// swift test -c release --filter SnapshotIntegrationTests.Execution.Select
/// swift test -c release --filter SnapshotIntegrationTests.Features.JSONB
/// ```
///
/// ## What each assertion records
///
/// Every `assertQuery` call records two snapshots: the generated SQL, validated
/// against swift-structured-queries-postgres, and the rows PostgreSQL actually
/// returned. Together they cover both query generation and database behaviour,
/// so a change that alters the SQL and a change that alters the result are
/// distinguishable in the diff.
@MainActor @Suite(.serialized, .snapshots(record: .never)) struct SnapshotIntegrationTests {}
