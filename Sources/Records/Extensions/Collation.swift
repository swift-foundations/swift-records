//
//  File.swift
//  swift-records
//
//  Created by Coen ten Thije Boonkkamp on 31/08/2025.
//

import Foundation
import StructuredQueriesPostgres

extension Collation {
    /// The `C` collation provides byte-order comparison.
    /// This is the fastest collation and is locale-independent.
    public static let c = Self(rawValue: "C")

    /// The `POSIX` collation is equivalent to `C`.
    public static let posix = Self(rawValue: "POSIX")

    /// US English collation.
    public static let enUS = Self(rawValue: "en_US")

    /// US English UTF-8 collation.
    public static let enUSutf8 = Self(rawValue: "en_US.utf8")

    /// Default collation (uses database default).
    public static let `default` = Self(rawValue: "default")
}
