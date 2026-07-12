import PostgresNIO

extension Database {
    /// The database client configuration.
    ///
    /// Aliased to `PostgresClient.Configuration` so the PostgresNIO type name
    /// stays out of consumer-facing signatures. PostgresNIO execution is
    /// confined to `Core/PostgresNIO/` and the concrete client/config entry
    /// points; consumers spell the configuration as `Database.Configuration`.
    public typealias Configuration = PostgresClient.Configuration
}
