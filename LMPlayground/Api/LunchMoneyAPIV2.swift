//
//  LunchMoneyAPIV2.swift
//  LMPlayground
//
//  Lunch Money API v2 client. Speaks the v2 wire format (spec 2.9.4, the
//  surface production serves as of 2026-07) but exposes the same neutral
//  request/response structs as the v1 client, so callers never see a v2
//  shape. Every v1↔v2 difference is absorbed here:
//    - base path /v2, resources renamed (assets → manual_accounts)
//    - field renames (user_name → name, asset_id → manual_account_id, …)
//    - status vocabulary (cleared/uncleared ↔ reviewed/unreviewed)
//    - strict request validation: v2 rejects unknown body properties, so the
//      encodable types below contain exactly the spec's writable fields
//      (notably: insert has no is_pending, and check_for_recurring no longer
//      exists — it is accepted from callers and deliberately not sent)
//    - POST /transactions returns full inserted transactions plus a
//      skipped_duplicates report instead of a bare ids array
//    - errors arrive as {message, errors: [{errMsg}]} and never inside a 2xx
//
//  Lunch Money's v2 API is in open alpha; if a call fails after a server-side
//  change, switching back to v1 in Settings restores the stable path.
//
import Foundation

class LunchMoneyAPIV2 {
    private let baseURL = "https://api.lunchmoney.dev/v2"
    private let apiToken: String
    private var debug: Bool = false
    /// Total HTTP requests issued by this instance, including retries.
    /// SyncBroker diffs this across a run for its summary log line.
    private(set) var requestCount = 0

    init(apiToken: String, debug: Bool = false) {
        self.apiToken = apiToken
        self.debug = debug
    }

    // MARK: - Status vocabulary mapping

    /// v2 → neutral (v1 vocabulary). `delete_pending` has no v1 equivalent and
    /// passes through; nothing in the app branches on it.
    static func v1Status(fromV2 status: String?) -> String {
        switch status {
        case "reviewed": return "cleared"
        case "unreviewed": return "uncleared"
        default: return status ?? "uncleared"
        }
    }

    /// Neutral (v1 vocabulary) → v2. Insert only accepts reviewed/unreviewed;
    /// anything else is omitted so the server default (unreviewed) applies.
    static func v2Status(fromV1 status: String?) -> String? {
        switch status {
        case "cleared": return "reviewed"
        case "uncleared": return "unreviewed"
        default: return nil
        }
    }

    // MARK: - Transport

    private func makeRequest<T: Decodable>(request: URLRequest, responseType: T.Type) async throws -> T {
        requestCount += 1
        let (data, response) = try await URLSession.shared.data(for: request)

        if debug {
            print("================================================")
            print("Request URL: \(request.url?.absoluteString ?? "No URL") \(request.httpMethod ?? "No HTTP Method")")
            if let body = request.httpBody, let bodyText = String(data: body, encoding: .utf8) {
                print("Body: \(bodyText)")
            } else {
                print("Body: None")
            }
            if let responseText = String(data: data, encoding: .utf8) {
                print("Response: \(responseText)")
                print("================================================")
            }
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw RateLimitedError(retryAfter: min(max(retryAfter ?? 60, 1), 120))
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(V2ErrorResponse.self, from: data),
               errorResponse.message != nil || errorResponse.errors?.isEmpty == false {
                let details = (errorResponse.errors ?? []).compactMap(\.errMsg)
                let combined = ([errorResponse.message].compactMap { $0 } + details).joined(separator: ", ")
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(combined)"])
            } else {
                let rawResponse = String(data: data, encoding: .utf8) ?? "No response body"
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred in makeRequest to LM API v2. Status: \(httpResponse.statusCode). Response: \(rawResponse)"])
            }
        }

        guard response is HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }

        return try JSONDecoder().decode(responseType, from: data)
    }

    private func call<T: Decodable>(
        path: String,
        responseType: T.Type,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        requestBody: Encodable? = nil
    ) async throws -> T {
        guard var urlComponents = URLComponents(string: "\(baseURL)\(path)") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        guard let url = urlComponents.url else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if method != "GET", let requestBody {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(requestBody))
        }

        return try await makeRequest(request: request, responseType: responseType)
    }
}

// MARK: - LunchMoneyService conformance

extension LunchMoneyAPIV2: LunchMoneyService {
    var apiVersion: LMAPIVersion { .v2 }

    func getUser() async throws -> User {
        let user = try await call(path: "/me", responseType: V2User.self)
        return User(
            userName: user.name,
            userEmail: user.email,
            userId: user.id,
            accountId: user.accountId,
            budgetName: user.budgetName,
            primaryCurrency: user.primaryCurrency,
            apiKeyLabel: user.apiKeyLabel
        )
    }

    func getAssets() async throws -> [Asset] {
        let response = try await call(path: "/manual_accounts", responseType: V2ManualAccountsResponse.self)
        return response.manualAccounts.map { Self.asset(fromV2: $0) }
    }

    func createAsset(requestBody: CreateAssetRequest) async throws -> CreateAssetResponse {
        // v2 requires a name; the neutral struct allows nil because v1 didn't.
        guard let name = requestBody.name, !name.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API v2 requires a name when creating an account"])
        }
        // created_at and note are not writable on v2 manual accounts and are
        // dropped; v2 rejects unknown body properties outright.
        let body = V2CreateManualAccountRequest(
            name: name,
            type: requestBody.typeName,
            subtype: requestBody.subTypeName.isEmpty ? nil : requestBody.subTypeName,
            balance: requestBody.balance,
            currency: requestBody.currency.lowercased(),
            institutionName: requestBody.institutionName
        )
        let account = try await call(path: "/manual_accounts", responseType: V2ManualAccount.self, method: "POST", requestBody: body)
        return CreateAssetResponse(assetId: account.id, id: nil, asset: nil)
    }

    func updateAsset(id: Int, request: UpdateAssetRequest) async throws -> UpdateAssetResponse {
        let body = V2UpdateManualAccountRequest(
            balance: request.balance,
            balanceAsOf: request.balanceAsOf,
            name: request.name,
            displayName: request.displayName,
            institutionName: request.institutionName,
            currency: request.currency?.lowercased(),
            excludeFromTransactions: request.excludeTransactions
        )
        let account = try await call(path: "/manual_accounts/\(id)", responseType: V2ManualAccount.self, method: "PUT", requestBody: body)
        return UpdateAssetResponse(
            id: account.id,
            typeName: account.type,
            subtypeName: account.subtype,
            name: account.name,
            balance: account.balance,
            balanceAsOf: account.balanceAsOf ?? "",
            currency: account.currency ?? "",
            institutionName: account.institutionName,
            excludeTransactions: account.excludeFromTransactions ?? false,
            createdAt: account.createdAt ?? "",
            errors: nil
        )
    }

    func getCategories() async throws -> [LMCategoryAPI] {
        // v2 defaults to nested; flattened matches what the v1 endpoint returns
        // (groups and their children all at the top level).
        let response = try await call(
            path: "/categories",
            responseType: V2CategoriesResponse.self,
            queryItems: [URLQueryItem(name: "format", value: "flattened")]
        )
        return response.categories.map { Self.category(fromV2: $0) }
    }

    func getTransactions(request: GetTransactionsRequest?) async throws -> [LMTransaction] {
        let response = try await getTransactionsPage(request: request ?? GetTransactionsRequest())
        return response.transactions
    }

    func getTransactionsPage(request: GetTransactionsRequest) async throws -> GetTransactionsResponse {
        var queryItems: [URLQueryItem] = []
        if let startDate = request.startDate { queryItems.append(URLQueryItem(name: "start_date", value: startDate)) }
        if let endDate = request.endDate { queryItems.append(URLQueryItem(name: "end_date", value: endDate)) }
        if let assetId = request.assetId { queryItems.append(URLQueryItem(name: "manual_account_id", value: String(assetId))) }
        if let limit = request.limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset = request.offset { queryItems.append(URLQueryItem(name: "offset", value: String(offset))) }
        // v2 hides grouped children and split parents by default; include them
        // so external_id duplicate detection sees everything v1 could see.
        queryItems.append(URLQueryItem(name: "include_group_children", value: "true"))
        queryItems.append(URLQueryItem(name: "include_split_parents", value: "true"))

        let response = try await call(path: "/transactions", responseType: V2TransactionsResponse.self, queryItems: queryItems)
        return GetTransactionsResponse(
            transactions: response.transactions.map { Self.transaction(fromV2: $0) },
            hasMore: response.hasMore
        )
    }

    func getTransaction(id: Int) async throws -> LMTransaction {
        let transaction = try await call(path: "/transactions/\(id)", responseType: V2Transaction.self)
        return Self.transaction(fromV2: transaction)
    }

    func createTransactions(
        transactions: [CreateTransactionRequest],
        applyRules: Bool?,
        skipDuplicates: Bool?,
        checkForRecurring: Bool?,
        skipBalanceUpdate: Bool?
    ) async throws -> CreateTransactionsResponse {
        // checkForRecurring is accepted for signature parity but not sent:
        // check_for_recurring does not exist on v2 and would fail validation.
        _ = checkForRecurring
        let body = V2InsertTransactionsRequest(
            transactions: transactions.map { Self.insertItem(fromNeutral: $0) },
            applyRules: applyRules,
            skipDuplicates: skipDuplicates,
            skipBalanceUpdate: skipBalanceUpdate
        )
        let response = try await call(path: "/transactions", responseType: V2InsertTransactionsResponse.self, method: "POST", requestBody: body)
        return Self.createResponse(fromV2: response, requestItems: transactions)
    }

    func updateTransaction(id: Int, request: UpdateTransactionRequest) async throws -> UpdateTransactionResponse {
        let update = request.transaction
        // Omitted deliberately: external_id (it is the sync join key and never
        // changes; re-sending it trips v2's uniqueness validation) and
        // is_pending (read-only in v2). Optionals encode only when non-nil, so
        // metadata-only updates stay partial updates.
        let body = V2UpdateTransactionRequest(
            date: update.date,
            payee: update.payee,
            amount: update.amount,
            currency: update.currency?.lowercased(),
            categoryId: update.categoryId,
            manualAccountId: Self.manualAccountId(fromNeutralAssetId: update.assetId),
            notes: update.notes,
            status: Self.v2Status(fromV1: update.status),
            customMetadata: update.customMetadata
        )
        // The spec declares 201 for this endpoint (200 elsewhere); the
        // transport accepts any 2xx. The response is the full updated
        // transaction; the neutral response only needs a success marker.
        _ = try await call(path: "/transactions/\(id)", responseType: V2Transaction.self, method: "PUT", requestBody: body)
        return UpdateTransactionResponse(updated: true, split: nil, errors: nil)
    }
}

// MARK: - Wire ↔ neutral mapping

extension LunchMoneyAPIV2 {
    /// lm_account is stamped "0" when a wallet account has no linked LM
    /// account; v1 tolerated asset_id 0, v2 validates account ids, so 0 maps
    /// to "no account" (a cash transaction).
    static func manualAccountId(fromNeutralAssetId assetId: Int?) -> Int? {
        guard let assetId, assetId > 0 else { return nil }
        return assetId
    }

    static func transaction(fromV2 t: V2Transaction) -> LMTransaction {
        LMTransaction(
            id: t.id,
            date: t.date,
            payee: t.payee,
            amount: t.amount,
            currency: t.currency ?? "",
            categoryId: t.categoryId,
            assetId: t.manualAccountId,
            notes: t.notes,
            status: v1Status(fromV2: t.status),
            isPending: t.isPending ?? false,
            externalId: t.externalId
        )
    }

    static func category(fromV2 c: V2Category) -> LMCategoryAPI {
        LMCategoryAPI(
            id: c.id,
            name: c.name,
            description: c.description,
            excludeFromBudget: c.excludeFromBudget ?? false,
            excludeFromTotals: c.excludeFromTotals ?? false,
            archived: c.archived ?? false,
            archivedOn: c.archivedAt,
            updatedAt: c.updatedAt ?? "",
            createdAt: c.createdAt ?? "",
            isIncome: c.isIncome ?? false,
            groupId: c.groupId
        )
    }

    static func asset(fromV2 a: V2ManualAccount) -> Asset {
        Asset(
            id: a.id,
            typeName: a.type,
            subtypeName: a.subtype,
            name: a.name,
            displayName: a.displayName,
            balance: a.balance,
            balanceAsOf: a.balanceAsOf,
            closedOn: a.closedOn,
            currency: a.currency ?? "",
            institutionName: a.institutionName,
            excludeTransactions: a.excludeFromTransactions ?? false,
            createdAt: a.createdAt ?? ""
        )
    }

    static func insertItem(fromNeutral item: CreateTransactionRequest) -> V2InsertTransaction {
        V2InsertTransaction(
            date: item.date,
            amount: item.amount,
            currency: item.currency.lowercased(),
            payee: item.payee,
            categoryId: item.categoryId,
            notes: item.notes,
            manualAccountId: manualAccountId(fromNeutralAssetId: item.assetId),
            status: v2Status(fromV1: item.status),
            externalId: item.externalId,
            customMetadata: item.customMetadata
        )
    }

    /// Builds the neutral insert response. `transactionIds` is populated in
    /// request order only when every request item resolves to an id (inserted
    /// rows matched by external_id, external_id duplicates matched through the
    /// skip report); otherwise it is left empty so callers fall back to the
    /// per-item `inserted`/`skippedDuplicates` data. Duplicates flagged by the
    /// payee/amount/date heuristic are intentionally never resolved to an id —
    /// they matched someone else's transaction, mirroring the v1 outcome.
    static func createResponse(fromV2 response: V2InsertTransactionsResponse, requestItems: [CreateTransactionRequest]) -> CreateTransactionsResponse {
        let insertedNeutral = response.transactions.map { transaction(fromV2: $0) }

        var insertedIdByExternalId: [String: Int] = [:]
        for t in response.transactions {
            if let externalId = t.externalId, insertedIdByExternalId[externalId] == nil {
                insertedIdByExternalId[externalId] = t.id
            }
        }

        var resolved: [Int?] = Array(repeating: nil, count: requestItems.count)
        for (index, item) in requestItems.enumerated() {
            if let externalId = item.externalId, let id = insertedIdByExternalId[externalId] {
                resolved[index] = id
            }
        }

        let skips = response.skippedDuplicates ?? []
        for skip in skips {
            guard skip.reason == SkippedDuplicateInfo.Reason.duplicateExternalId.rawValue,
                  let existingId = skip.existingTransactionId else { continue }
            if let index = skip.requestTransactionsIndex, requestItems.indices.contains(index), resolved[index] == nil {
                resolved[index] = existingId
            } else if let externalId = skip.requestTransaction?.externalId,
                      let index = requestItems.firstIndex(where: { $0.externalId == externalId }),
                      resolved[index] == nil {
                resolved[index] = existingId
            }
        }

        // Single insert with no external_id (nothing to match on): the one
        // inserted row is unambiguous.
        if requestItems.count == 1, resolved[0] == nil, skips.isEmpty, response.transactions.count == 1 {
            resolved[0] = response.transactions[0].id
        }

        let orderedIds = resolved.compactMap { $0 }
        let skippedNeutral = skips.map { skip in
            SkippedDuplicateInfo(
                reason: SkippedDuplicateInfo.Reason(rawValue: skip.reason ?? "") ?? .unknown,
                requestIndex: skip.requestTransactionsIndex,
                existingTransactionId: skip.existingTransactionId,
                requestExternalId: skip.requestTransaction?.externalId
            )
        }

        return CreateTransactionsResponse(
            transactionIds: orderedIds.count == requestItems.count ? orderedIds : [],
            errors: nil,
            inserted: insertedNeutral,
            skippedDuplicates: skippedNeutral
        )
    }
}

// MARK: - v2 wire types (spec 2.9.4)

struct V2ErrorDetail: Decodable {
    let errMsg: String?
}

struct V2ErrorResponse: Decodable {
    let message: String?
    let errors: [V2ErrorDetail]?
}

struct V2User: Decodable {
    let id: Int
    let name: String
    let email: String
    let accountId: Int
    let budgetName: String
    let primaryCurrency: String
    let apiKeyLabel: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case accountId = "account_id"
        case budgetName = "budget_name"
        case primaryCurrency = "primary_currency"
        case apiKeyLabel = "api_key_label"
    }
}

struct V2ManualAccount: Decodable {
    let id: Int
    let name: String
    let institutionName: String?
    let displayName: String?
    let type: String
    let subtype: String?
    let balance: String
    let currency: String?
    let balanceAsOf: String?
    let status: String?
    let closedOn: String?
    let excludeFromTransactions: Bool?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case institutionName = "institution_name"
        case displayName = "display_name"
        case type
        case subtype
        case balance
        case currency
        case balanceAsOf = "balance_as_of"
        case status
        case closedOn = "closed_on"
        case excludeFromTransactions = "exclude_from_transactions"
        case createdAt = "created_at"
    }
}

struct V2ManualAccountsResponse: Decodable {
    let manualAccounts: [V2ManualAccount]

    private enum CodingKeys: String, CodingKey {
        case manualAccounts = "manual_accounts"
    }
}

struct V2CreateManualAccountRequest: Encodable {
    let name: String
    let type: String
    let subtype: String?
    let balance: Double
    let currency: String?
    let institutionName: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case subtype
        case balance
        case currency
        case institutionName = "institution_name"
    }
}

struct V2UpdateManualAccountRequest: Encodable {
    let balance: Double?
    let balanceAsOf: String?
    let name: String?
    let displayName: String?
    let institutionName: String?
    let currency: String?
    let excludeFromTransactions: Bool?

    private enum CodingKeys: String, CodingKey {
        case balance
        case balanceAsOf = "balance_as_of"
        case name
        case displayName = "display_name"
        case institutionName = "institution_name"
        case currency
        case excludeFromTransactions = "exclude_from_transactions"
    }
}

struct V2Category: Decodable {
    let id: Int
    let name: String
    let description: String?
    let isIncome: Bool?
    let excludeFromBudget: Bool?
    let excludeFromTotals: Bool?
    let archived: Bool?
    let archivedAt: String?
    let updatedAt: String?
    let createdAt: String?
    let groupId: Int?
    let isGroup: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case isIncome = "is_income"
        case excludeFromBudget = "exclude_from_budget"
        case excludeFromTotals = "exclude_from_totals"
        case archived
        case archivedAt = "archived_at"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case groupId = "group_id"
        case isGroup = "is_group"
    }
}

struct V2CategoriesResponse: Decodable {
    let categories: [V2Category]
}

struct V2Transaction: Decodable {
    let id: Int
    let date: String
    let payee: String?
    let amount: String
    let currency: String?
    let categoryId: Int?
    let notes: String?
    let status: String?
    let isPending: Bool?
    let externalId: String?
    let manualAccountId: Int?
    let plaidAccountId: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case payee
        case amount
        case currency
        case categoryId = "category_id"
        case notes
        case status
        case isPending = "is_pending"
        case externalId = "external_id"
        case manualAccountId = "manual_account_id"
        case plaidAccountId = "plaid_account_id"
    }
}

struct V2TransactionsResponse: Decodable {
    let transactions: [V2Transaction]
    let hasMore: Bool?

    private enum CodingKeys: String, CodingKey {
        case transactions
        case hasMore = "has_more"
    }
}

struct V2InsertTransaction: Encodable {
    let date: String
    let amount: String
    let currency: String?
    let payee: String?
    let categoryId: Int?
    let notes: String?
    let manualAccountId: Int?
    let status: String?
    let externalId: String?
    let customMetadata: WalletMetadata?

    private enum CodingKeys: String, CodingKey {
        case date
        case amount
        case currency
        case payee
        case categoryId = "category_id"
        case notes
        case manualAccountId = "manual_account_id"
        case status
        case externalId = "external_id"
        case customMetadata = "custom_metadata"
    }
}

struct V2InsertTransactionsRequest: Encodable {
    let transactions: [V2InsertTransaction]
    let applyRules: Bool?
    let skipDuplicates: Bool?
    let skipBalanceUpdate: Bool?

    private enum CodingKeys: String, CodingKey {
        case transactions
        case applyRules = "apply_rules"
        case skipDuplicates = "skip_duplicates"
        case skipBalanceUpdate = "skip_balance_update"
    }
}

struct V2SkippedDuplicateEcho: Decodable {
    let externalId: String?

    private enum CodingKeys: String, CodingKey {
        case externalId = "external_id"
    }
}

struct V2SkippedDuplicate: Decodable {
    let reason: String?
    let requestTransactionsIndex: Int?
    let existingTransactionId: Int?
    let requestTransaction: V2SkippedDuplicateEcho?

    private enum CodingKeys: String, CodingKey {
        case reason
        case requestTransactionsIndex = "request_transactions_index"
        case existingTransactionId = "existing_transaction_id"
        case requestTransaction = "request_transaction"
    }
}

struct V2InsertTransactionsResponse: Decodable {
    let transactions: [V2Transaction]
    let skippedDuplicates: [V2SkippedDuplicate]?

    private enum CodingKeys: String, CodingKey {
        case transactions
        case skippedDuplicates = "skipped_duplicates"
    }
}

struct V2UpdateTransactionRequest: Encodable {
    let date: String?
    let payee: String?
    let amount: String?
    let currency: String?
    let categoryId: Int?
    let manualAccountId: Int?
    let notes: String?
    let status: String?
    let customMetadata: WalletMetadata?

    private enum CodingKeys: String, CodingKey {
        case date
        case payee
        case amount
        case currency
        case categoryId = "category_id"
        case manualAccountId = "manual_account_id"
        case notes
        case status
        case customMetadata = "custom_metadata"
    }
}
