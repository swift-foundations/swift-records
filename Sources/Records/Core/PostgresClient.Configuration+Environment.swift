import Dependencies
import EnvironmentVariables
import Foundation
import NIOSSL
import PostgresNIO

// MARK: - Configuration Errors

extension Database {
    /// Errors that can occur during configuration.
    public enum ConfigurationError: Swift.Error, CustomStringConvertible {
        case missingEnvironmentVariable(String)
        case invalidPort(String)

        public var description: String {
            switch self {
            case .missingEnvironmentVariable(let key):
                return "Missing required environment variable: \(key)"
            case .invalidPort(let value):
                return "Invalid port value: \(value)"
            }
        }
    }
}

// MARK: - PostgresClient.Configuration Extensions

extension PostgresClient.Configuration {
    /// Creates configuration from environment variables.
    ///
    /// Looks for the following environment variables:
    /// - `DATABASE_HOST` or `POSTGRES_HOST` (required)
    /// - `DATABASE_PORT` or `POSTGRES_PORT` (required)
    /// - `DATABASE_NAME` or `POSTGRES_DB` (required)
    /// - `DATABASE_USER` or `POSTGRES_USER` (required)
    /// - `DATABASE_PASSWORD` or `POSTGRES_PASSWORD` (optional)
    ///
    /// ## Example
    ///
    /// ```bash
    /// # Set environment variables
    /// export DATABASE_HOST=localhost
    /// export DATABASE_PORT=5432
    /// export DATABASE_NAME=myapp
    /// export DATABASE_USER=postgres
    /// export DATABASE_PASSWORD=secret
    /// ```
    ///
    /// ```swift
    /// // In your app
    /// let config = try PostgresClient.Configuration.fromEnvironment()
    /// let pool = try await Database.pool(
    ///     configuration: config,
    ///     minConnections: 5,
    ///     maxConnections: 20
    /// )
    /// ```
    ///
    /// - Returns: A configuration built from environment variables.
    /// - Throws: ``Database.ConfigurationError`` if required environment variables are missing or invalid.
    public static func fromEnvironment() throws -> PostgresClient.Configuration {
        @Dependency(\.envVars) var envVars

        // Get host
        guard let host = envVars["DATABASE_HOST"] ?? envVars["POSTGRES_HOST"] else {
            throw Database.ConfigurationError.missingEnvironmentVariable(
                "DATABASE_HOST or POSTGRES_HOST"
            )
        }

        // Get port
        let portString = envVars["DATABASE_PORT"] ?? envVars["POSTGRES_PORT"]
        guard let portString else {
            throw Database.ConfigurationError.missingEnvironmentVariable(
                "DATABASE_PORT or POSTGRES_PORT"
            )
        }
        guard let port = Int(portString) else {
            throw Database.ConfigurationError.invalidPort(portString)
        }

        // Get database name
        guard let database = envVars["DATABASE_NAME"] ?? envVars["POSTGRES_DB"] else {
            throw Database.ConfigurationError.missingEnvironmentVariable(
                "DATABASE_NAME or POSTGRES_DB"
            )
        }

        // Get username
        guard let username = envVars["DATABASE_USER"] ?? envVars["POSTGRES_USER"] else {
            throw Database.ConfigurationError.missingEnvironmentVariable(
                "DATABASE_USER or POSTGRES_USER"
            )
        }

        // Password is optional
        let password = envVars["DATABASE_PASSWORD"] ?? envVars["POSTGRES_PASSWORD"]

        return PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
    }
}
