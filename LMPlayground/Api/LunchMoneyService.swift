//
//  LunchMoneyService.swift
//  LMPlayground
//
//  Version-neutral facade over the Lunch Money REST API. The app talks to
//  `LunchMoneyService` using the request/response structs defined in
//  LunchMoneyAPI.swift (the v1 wire shapes double as the app's neutral types);
//  `LunchMoneyAPI` (v1) conforms natively and `LunchMoneyAPIV2` maps at its
//  wire boundary, so every v1↔v2 difference stays inside the v2 client.
//
import Foundation

/// Which Lunch Money API version a client speaks. Stored in the shared app
/// group defaults (key `lm_api_version`) so the app, the background delivery
/// extension, and App Intents all follow the same selection. v1 is the
/// default; v2 is opt-in while Lunch Money's v2 API remains in alpha.
enum LMAPIVersion: String, CaseIterable, Identifiable {
    case v1
    case v2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v1: return "v1 (stable, default)"
        case .v2: return "v2 (alpha)"
        }
    }

    /// Key in the shared app-group UserDefaults holding the selected version.
    static let defaultsKey = "lm_api_version"
    /// The app-group suite shared with the background extension and intents.
    static let appGroupSuiteName = "group.com.littlebluebug.AppleCardSync"
}

/// One server-side duplicate reported by the v2 insert endpoint. v2 always
/// dedupes on (manual_account_id, external_id) and reports each skip with the
/// id of the transaction it collided with, which is how the v2 sync path
/// recovers `lm_id`s without fetching a transaction window first.
struct SkippedDuplicateInfo {
    enum Reason: String {
        case duplicateExternalId = "duplicate_external_id"
        case duplicatePayeeAmountDate = "duplicate_payee_amount_date"
        case unknown
    }

    let reason: Reason
    /// Index into the request's transactions array, as reported by the API.
    let requestIndex: Int?
    /// The id of the existing LM transaction the request item duplicates.
    let existingTransactionId: Int?
    /// external_id echoed back from the skipped request item.
    let requestExternalId: String?
}

protocol LunchMoneyService: AnyObject {
    var apiVersion: LMAPIVersion { get }
    /// Total HTTP requests issued by this instance, including retries.
    /// SyncBroker diffs this across a run for its summary log line.
    var requestCount: Int { get }

    func getUser() async throws -> User
    func getAssets() async throws -> [Asset]
    func createAsset(requestBody: CreateAssetRequest) async throws -> CreateAssetResponse
    func updateAsset(id: Int, request: UpdateAssetRequest) async throws -> UpdateAssetResponse
    func getCategories() async throws -> [LMCategoryAPI]
    func getTransactions(request: GetTransactionsRequest?) async throws -> [LMTransaction]
    /// One page of transactions including the `has_more` flag, for pagination.
    func getTransactionsPage(request: GetTransactionsRequest) async throws -> GetTransactionsResponse
    func getTransaction(id: Int) async throws -> LMTransaction
    func createTransactions(
        transactions: [CreateTransactionRequest],
        applyRules: Bool?,
        skipDuplicates: Bool?,
        checkForRecurring: Bool?,
        skipBalanceUpdate: Bool?
    ) async throws -> CreateTransactionsResponse
    func updateTransaction(id: Int, request: UpdateTransactionRequest) async throws -> UpdateTransactionResponse
}

extension LunchMoneyService {
    func createTransactions(transactions: [CreateTransactionRequest]) async throws -> CreateTransactionsResponse {
        try await createTransactions(
            transactions: transactions,
            applyRules: nil,
            skipDuplicates: nil,
            checkForRecurring: nil,
            skipBalanceUpdate: nil
        )
    }

    /// Fetches every transaction in the date range, following pagination until
    /// the API reports no more records. A single GET returns at most `limit`
    /// records (the API default is 1000), so callers that need the full window
    /// for duplicate detection must use this instead of `getTransactions`.
    /// `onPage` is invoked after each page with (page number, records on that
    /// page, running total) so callers can surface fetch progress in their logs.
    func getAllTransactions(
        startDate: String,
        endDate: String,
        onPage: ((_ page: Int, _ pageCount: Int, _ runningTotal: Int) -> Void)? = nil
    ) async throws -> [LMTransaction] {
        let pageSize = 1000
        let maxPages = 50 // safety valve against a server that always reports more
        var all: [LMTransaction] = []
        var offset = 0

        for page in 0..<maxPages {
            let request = GetTransactionsRequest(
                startDate: startDate,
                endDate: endDate,
                limit: pageSize,
                offset: offset
            )
            let response = try await getTransactionsPage(request: request)
            all.append(contentsOf: response.transactions)
            onPage?(page + 1, response.transactions.count, all.count)

            // Older API responses may omit has_more; fall back to a full-page check.
            let hasMore = response.hasMore ?? (response.transactions.count >= pageSize)
            if response.transactions.isEmpty || !hasMore {
                return all
            }
            offset += response.transactions.count
        }

        print("getAllTransactions: stopped after \(maxPages) pages (\(all.count) transactions), results may be incomplete")
        return all
    }
}

extension LunchMoneyAPI: LunchMoneyService {
    var apiVersion: LMAPIVersion { .v1 }
}

enum LunchMoneyServiceFactory {
    /// The version currently selected in the shared app-group defaults.
    static func currentVersion() -> LMAPIVersion {
        let defaults = UserDefaults(suiteName: LMAPIVersion.appGroupSuiteName) ?? .standard
        let raw = defaults.string(forKey: LMAPIVersion.defaultsKey) ?? ""
        return LMAPIVersion(rawValue: raw) ?? .v1
    }

    /// Builds a client for `version`, or for the user's selected version when
    /// `version` is nil. Read the selection once per operation and keep using
    /// the returned instance so a mid-run settings change can't mix versions.
    static func make(apiToken: String, version: LMAPIVersion? = nil, debug: Bool = false) -> any LunchMoneyService {
        switch version ?? currentVersion() {
        case .v1:
            return LunchMoneyAPI(apiToken: apiToken, debug: debug)
        case .v2:
            return LunchMoneyAPIV2(apiToken: apiToken, debug: debug)
        }
    }
}
