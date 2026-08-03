//
//  MirrorAPI.swift
//  LMPlayground
//
//  Optional "mirror server" support: when the user has configured a base URL
//  on the API token page, each sync also POSTs a JSON snapshot of accounts
//  and transactions to <base URL>/finance-kit-sync. Failures are always
//  non-fatal to the Lunch Money sync.
//
import Foundation

// MARK: - Packet schema (schema_version 1)

struct MirrorPacket: Encodable {
    let schemaVersion: Int
    let accounts: [MirrorAccount]
    let transactions: [MirrorTransaction]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case accounts
        case transactions
    }
}

struct MirrorAccount: Encodable {
    let id: String
    let name: String
    let institution: String
    let balance: Double
    let currency: String
}

struct MirrorTransaction: Encodable {
    let id: String
    let accountId: String
    let date: String
    let amount: Double
    let currency: String
    let payee: String
    let status: String
    let notes: String
    let category: String
    let metadata: AnyEncodable

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case date
        case amount
        case currency
        case payee
        case status
        case notes
        case category
        case metadata
    }
}

// MARK: - Client

struct MirrorAPI {
    /// Key in the shared app-group UserDefaults holding the mirror base URL.
    static let defaultsKey = "mirror_base_url"
    /// Key in the shared app-group UserDefaults holding the mirror-only flag.
    /// When true (and a valid mirror URL is configured) syncs skip Lunch
    /// Money entirely and only POST to the mirror server.
    static let mirrorOnlyDefaultsKey = "mirror_only"

    enum MirrorError: LocalizedError {
        case badResponse
        case serverError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "Mirror server returned an unexpected response"
            case .serverError(let statusCode):
                return "Mirror server returned HTTP \(statusCode)"
            }
        }
    }

    /// Validates a user-entered base URL: must be https with a host.
    /// Returns the normalized URL (trailing slash stripped) or nil.
    static func validatedBaseURL(from string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// The configured mirror base URL, or nil when unset or invalid.
    static func configuredBaseURL() -> URL? {
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        guard let stored = sharedDefaults.string(forKey: defaultsKey), !stored.isEmpty else {
            return nil
        }
        return validatedBaseURL(from: stored)
    }

    /// True only when the mirror-only flag is set AND a valid mirror URL is
    /// configured. A stale flag with no (or an invalid) URL degrades to
    /// normal Lunch Money mode.
    static func isMirrorOnlyEnabled() -> Bool {
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        return sharedDefaults.bool(forKey: mirrorOnlyDefaultsKey) && configuredBaseURL() != nil
    }

    let baseURL: URL

    /// POSTs the packet to <base URL>/finance-kit-sync, throwing on any
    /// transport error or non-2xx status.
    func sync(packet: MirrorPacket) async throws {
        let url = baseURL.appendingPathComponent("finance-kit-sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(packet)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MirrorError.badResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MirrorError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}
