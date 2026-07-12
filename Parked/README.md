# Parked (W-B native spine swap 2026-07-12)

swift-records was ported off the pointfreeco `swift-structured-queries-postgres`
(sqp) fork onto the institute-native line (L1 Structured Queries Primitives + L2
PostgreSQL Standard). The `Records` product spine swap is complete and green. The
directories below are parked out of the built source tree to keep the port bounded
and the closure pointfreeco-zero / coenttb-zero; each is restored by its named
follow-up.

## `Notifications/` and `FullTextSearch/` — app-unused, pointfree-Tagged coupled

- App-unused (0 consumers in the repotraffic graph; 49% of the package by LOC).
- `Notifications/` drags `import Tagged` (pointfreeco/swift-tagged): a pointfree
  coupling that must not re-enter the port closure.
- **Restore (R2, demand-gated):** re-derive natively against the LISTEN/NOTIFY and
  `tsvector` surfaces in `swift-postgresql-standard`, with `Tagged` replaced by the
  L1 `Tagged Primitives` functor. See `persistence-stack-strategy.md` §4-R2.

## `RecordsTestSupport/` and `Tests/` (the `RecordsTests` target) — swift-tests migration

The test surface is entangled with pointfreeco test infrastructure that has **no
drop-in institute equivalent**, so a verbatim re-point does not compile:

- `RecordsTestSupport/AssertQuery.swift` calls
  `assertInlineSnapshot(of:as:message:syntaxDescriptor:matches:...)` — the institute
  compat shim (`PostgreSQL Standard Test Support` → `Tests_Inline_Snapshot`) has a
  reduced signature with **no `syntaxDescriptor:`** parameter (multi-labeled inline
  recording is not expressible through it).
- `printTable` uses `customDump` (pointfreeco/swift-custom-dump) — **absent from the
  entire institute surface** (verified: no institute `customDump` / `CustomDump`
  module). Replacing it changes table output and forces a full snapshot re-record.
- The `RecordsTests` target uses `import SnapshotTesting` + the `.snapshots(record:)`
  swift-testing trait (pointfreeco) — no direct institute trait equivalent wired.
- Almost every test is a live-PostgreSQL integration test (`Database.TestDatabase`),
  so it is not a meaningful standalone `swift test` gate without a DB-provisioned CI
  job anyway.

Per the W-B step (g) fallback ("if this balloons into something structural you
cannot finish, STOP that step, report honestly, do not improvise a new pattern"),
the whole test surface is parked rather than half-migrated.

- **Restore (R2):** migrate to the institute `swift-tests` nested test package per
  `[INST-TEST]` — re-point onto `PostgreSQL Standard` + `PostgreSQL Standard Test
  Support`, rewrite `assertQuery`/`printTable` onto `snapshot(as:)` + the `.sql`/
  `.lines` strategies, replace `customDump`, and wire the recording-mode trait. This
  kills the pointfreeco snapshot-testing pin natively. When restored, re-vend the
  `RecordsTestSupport` product and re-add the `RecordsTests` target in `Package.swift`.

Precedent: swift-email `Parked/Email/` (coenttb-ectomy 2026-07-12).
