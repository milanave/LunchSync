import Foundation

// MARK: transations
struct CreateTransactionRequest: Encodable {
    let date: String
    let payee: String
    let amount: String
    let currency: String
    let categoryId: Int?
    let assetId: Int?
    let notes: String?
    let status: String?
    let externalId: String?
    let isPending: Bool

    private enum CodingKeys: String, CodingKey {
        case date
        case payee
        case amount
        case currency
        case categoryId = "category_id"
        case assetId = "asset_id"
        case notes
        case status
        case externalId = "external_id"
        case isPending = "is_pending"
    }
}

struct DeleteTransactionsRequest: Encodable {
    let transactions: [Int]?
}

struct DeleteTransactionsResponse: Decodable {
    let transactionIds: [Int]?
    let errors: [String]?

    private enum CodingKeys: String, CodingKey {
        case transactionIds = "transactions"
        case errors
    }
}

struct CreateTransactionsRequest: Encodable {
    let transactions: [CreateTransactionRequest]
    let applyRules: Bool?
    let skipDuplicates: Bool?
    let checkForRecurring: Bool?
    let skipBalanceUpdate: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case transactions
        case applyRules = "apply_rules"
        case skipDuplicates = "skip_duplicates"
        case checkForRecurring = "check_for_recurring"
        case skipBalanceUpdate = "skip_balance_update"
    }
}

struct CreateTransactionsResponse: Decodable {
    let transactionIds: [Int]?
    let errors: [String]?

    private enum CodingKeys: String, CodingKey {
        case transactionIds = "ids"
        case errors
    }
}

struct LMTransaction: Decodable {
    let id: Int
    let date: String
    let payee: String
    let amount: String
    let currency: String
    let categoryId: Int?
    let assetId: Int?
    let notes: String?
    let status: String
    let isPending: Bool
    let externalId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case payee
        case amount
        case currency
        case categoryId = "category_id"
        case assetId = "asset_id"
        case notes
        case status
        case isPending = "is_pending"
        case externalId = "external_id"
    }
}

struct GetTransactionsRequest: Encodable {
    let startDate: String?
    let endDate: String?
    let assetId: Int?
    
    private enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case assetId = "asset_id"
    }
    
    init(startDate: String? = nil, endDate: String? = nil, assetId: Int? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.assetId = assetId
    }
}


struct GetTransactionsResponse: Decodable {
    let transactions: [LMTransaction]
}

struct User: Decodable {
    let userName: String
    let userEmail: String
    let userId: Int
    let accountId: Int
    let budgetName: String
    let primaryCurrency: String
    let apiKeyLabel: String?

    private enum CodingKeys: String, CodingKey {
        case userName = "user_name"
        case userEmail = "user_email"
        case userId = "user_id"
        case accountId = "account_id"
        case budgetName = "budget_name"
        case primaryCurrency = "primary_currency"
        case apiKeyLabel = "api_key_label"
    }
}

struct Asset: Decodable {
    let id: Int
    let typeName: String
    let subtypeName: String?
    let name: String
    let displayName: String?
    let balance: String  // Changed to String to match API response
    let balanceAsOf: String?
    let closedOn: String?
    let currency: String
    let institutionName: String?
    let excludeTransactions: Bool
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case typeName = "type_name"
        case subtypeName = "subtype_name"
        case name
        case displayName = "display_name"
        case balance
        case balanceAsOf = "balance_as_of"
        case closedOn = "closed_on"
        case currency
        case institutionName = "institution_name"
        case excludeTransactions = "exclude_transactions"
        case createdAt = "created_at"
    }
}

struct GetAssetsResponse: Decodable {
    let assets: [Asset]
}

struct CreateAssetRequest: Encodable {
    let typeName: String
    let balance: Double
    let currency: String
    let name: String?
    let institutionName: String?
    let createdAt: String?
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case typeName = "type_name"
        case balance
        case currency
        case name
        case institutionName = "institution_name"
        case createdAt = "created_at"
        case note
    }
}

struct CreateAssetResponse: Decodable {
    let assetId: Int?
    let id: Int?
    let asset: AssetIdContainer?

    var resolvedId: Int? { assetId ?? id ?? asset?.id }

    struct AssetIdContainer: Decodable {
        let id: Int
    }

    private enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case id
        case asset
    }
}

struct APIErrorResponse: Decodable {
    let errors: [String]
}

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

extension Encodable {
    /// Converts an Encodable object to a dictionary of key-value pairs for URL query parameters
    func asDictionary() -> [String: String]? {
        guard let data = try? JSONEncoder().encode(self),
              let dictionary = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        
        return dictionary.reduce(into: [String: String]()) { result, item in
            if let value = item.value as? String {
                result[item.key] = value
            } else if let value = item.value as? Int {
                result[item.key] = String(value)
            }
        }
    }
}

struct UpdateTransactionRequest: Encodable {
    let transaction: TransactionUpdate
    
    struct TransactionUpdate: Encodable {
        let date: String?
        let payee: String?
        let amount: String?
        let currency: String?
        let categoryId: Int?
        let assetId: Int?
        let notes: String?
        let status: String?
        let externalId: String?
        let isPending: Bool?

        private enum CodingKeys: String, CodingKey {
            case date
            case payee
            case amount
            case currency
            case categoryId = "category_id"
            case assetId = "asset_id"
            case notes
            case status
            case externalId = "external_id"
            case isPending = "is_pending"
        }
    }
}

struct UpdateTransactionResponse: Decodable {
    let updated: Bool?
    let split: [Int]?
    let errors: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case updated
        case split
        case errors = "error"  // API returns "error" but we'll use "errors" in our code
    }
}

// Add these structures before the LunchMoneyAPI class
struct UpdateAssetRequest: Encodable {
    let balance: Double?
    let balanceAsOf: String?
    let name: String?
    let displayName: String?
    let institutionName: String?
    let currency: String?
    let excludeTransactions: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case balance
        case balanceAsOf = "balance_as_of"
        case name
        case displayName = "display_name"
        case institutionName = "institution_name"
        case currency
        case excludeTransactions = "exclude_transactions"
    }
    
    init(
        balance: Double? = nil,
        balanceAsOf: String? = nil,
        name: String? = nil,
        displayName: String? = nil,
        institutionName: String? = nil,
        currency: String? = nil,
        excludeTransactions: Bool? = nil
    ) {
        self.balance = balance
        self.balanceAsOf = balanceAsOf
        self.name = name
        self.displayName = displayName
        self.institutionName = institutionName
        self.currency = currency
        self.excludeTransactions = excludeTransactions
    }
}

struct UpdateAssetResponse: Decodable {
    let id: Int
    let typeName: String
    let subtypeName: String?
    let name: String
    let balance: String
    let balanceAsOf: String
    let currency: String
    let institutionName: String?
    let excludeTransactions: Bool
    let createdAt: String
    let errors: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case typeName = "type_name"
        case subtypeName = "subtype_name"
        case name
        case balance
        case balanceAsOf = "balance_as_of"
        case currency
        case institutionName = "institution_name"
        case excludeTransactions = "exclude_transactions"
        case createdAt = "created_at"
        case errors
    }
}

// MARK: - Categories
struct LMCategoryAPI: Decodable {
    let id: Int
    let name: String
    let description: String?
    let excludeFromBudget: Bool
    let excludeFromTotals: Bool
    let archived: Bool
    let archivedOn: String?
    let updatedAt: String
    let createdAt: String
    let isIncome: Bool
    let groupId: Int?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case excludeFromBudget = "exclude_from_budget"
        case excludeFromTotals = "exclude_from_totals"
        case archived
        case archivedOn = "archived_on"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case isIncome = "is_income"
        case groupId = "group_id"
    }
}

struct GetCategoriesResponse: Decodable {
    let categories: [LMCategoryAPI]
}

// MARK: LunchMoneyAPI
class LunchMoneyAPI {
    private let baseURL = "https://dev.lunchmoney.app/v1"
    private let apiToken: String
    private var debug: Bool = false
    
    init(apiToken: String, debug: Bool = false) {
        self.apiToken = apiToken
        self.debug = debug
    }

    private func makeRequest<T: Decodable>(request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if debug {
            print("================================================")
            print("Request URL: \(request.url?.absoluteString ?? "No URL") \(request.httpMethod ?? "No HTTP Method")")
            //if let headers = request.allHTTPHeaderFields {
                //print("Headers: \(headers)")
            //}
            if let body = request.httpBody, let bodyText = String(data: body, encoding: .utf8) {
                print("Body: \(bodyText)")
            }else{
                print("Body: None")
            }
            
            if let responseText = String(data: data, encoding: .utf8) {
                print("Response: \(responseText)")
                print("================================================")
            }
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorResponse.errors.joined(separator: ", "))"])
            } else {
                let rawResponse = String(data: data, encoding: .utf8) ?? "No response body"
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred in makeRequest to LM API. Status: \(httpResponse.statusCode). Response: \(rawResponse)"])
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }
        
        let decodedResponse = try JSONDecoder().decode(responseType, from: data)
        return decodedResponse
    }

    private func call<T: Decodable>(path: String, responseType: T.Type, requestBody: Any? = nil, method: String? = nil) async throws -> T {
        // Build URL with query parameters for GET requests
        var urlString = "\(baseURL)\(path)"
        
        if method == "GET", let requestBody = requestBody as? Encodable, let queryParameters = requestBody.asDictionary() {
            let queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            var urlComponents = URLComponents(string: urlString)
            urlComponents?.queryItems = queryItems
            urlString = urlComponents?.url?.absoluteString ?? urlString
        }
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method ?? (requestBody == nil ? "GET" : "POST")
        request.addValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if request.httpMethod != "GET", let requestBody = requestBody as? Encodable {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(requestBody))
        }
        
        return try await makeRequest(request: request, responseType: responseType)
    }
    
    func getUser() async throws -> User {
        return try await call(path: "/me", responseType: User.self)
    }

    func createAsset(requestBody: CreateAssetRequest) async throws -> CreateAssetResponse {
        return try await call(path: "/assets", responseType: CreateAssetResponse.self, requestBody: requestBody)
    }
    
    func getAssets() async throws -> [Asset] {
        let response = try await call(path: "/assets", responseType: GetAssetsResponse.self)
        return response.assets
    }
    
    func getCategories() async throws -> [LMCategoryAPI] {
        let response = try await call(path: "/categories", responseType: GetCategoriesResponse.self)
        return response.categories
    }
    
    func getTransactions(request: GetTransactionsRequest? = nil) async throws -> [LMTransaction] {
            // Pass `nil` for requestBody if request is not provided
            let response = try await call(path: "/transactions", responseType: GetTransactionsResponse.self, requestBody: request, method: "GET")
            return response.transactions
        }
    
    func getTransactions2() async throws -> [LMTransaction] {
        //let response = try await call(path: "/transactions", responseType: GetTransactionsResponse.self)
        //assetId: "99813"
        let transactionRequest = GetTransactionsRequest(
            startDate: "2024-10-20",
            endDate: "2024-10-21"
        )
        let response = try await call(path: "/transactions", responseType: GetTransactionsResponse.self, requestBody: transactionRequest, method: "GET")
        
        return response.transactions
    }
    
    func createTransactions(transactions: [CreateTransactionRequest], applyRules: Bool? = nil, skipDuplicates: Bool? = nil, checkForRecurring: Bool? = nil, skipBalanceUpdate: Bool? = nil) async throws -> CreateTransactionsResponse {
        let requestBody = CreateTransactionsRequest(
            transactions: transactions,
            applyRules: applyRules,
            skipDuplicates: skipDuplicates,
            checkForRecurring: checkForRecurring,
            skipBalanceUpdate: skipBalanceUpdate
        )
        print("INSERT-----")
        print(applyRules!, skipDuplicates!, checkForRecurring!, skipBalanceUpdate!)
        let response = try await call(path: "/transactions", responseType: CreateTransactionsResponse.self, requestBody: requestBody)

        if let errors = response.errors, !errors.isEmpty {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errors.joined(separator: ", "))"])
        }

        return response
    }
    
    func deleteTransactions(transactionId: Int) async throws -> DeleteTransactionsResponse {
        
        let requestBody = DeleteTransactionsRequest(transactions: [transactionId])
        let response = try await call(path: "/transactions/group/\(transactionId)", responseType: DeleteTransactionsResponse.self, requestBody: requestBody, method: "DELETE")

        if let errors = response.errors, !errors.isEmpty {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errors.joined(separator: ", "))"])
        }

        return response
    }
    
    func getTransaction(id: Int) async throws -> LMTransaction {
        return try await call(path: "/transactions/\(id)", responseType: LMTransaction.self)
    }

    func updateTransaction(id: Int, request: UpdateTransactionRequest) async throws -> UpdateTransactionResponse {
        return try await call(path: "/transactions/\(id)", responseType: UpdateTransactionResponse.self, requestBody: request, method: "PUT")
    }

    func updateAsset(id: Int, request: UpdateAssetRequest) async throws -> UpdateAssetResponse {
        return try await call(path: "/assets/\(id)", responseType: UpdateAssetResponse.self, requestBody: request, method: "PUT")
    }

    func getLastTransactionForAsset(assetId: Int) async throws -> [LMTransaction] {
        // Calculate date 30 days ago
        let calendar = Calendar.current
        let today = Date()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error calculating date"])
        }
        
        // Format dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDate = dateFormatter.string(from: thirtyDaysAgo)
        let endDate = dateFormatter.string(from: today)
        
        let request = GetTransactionsRequest(
            startDate: startDate,
            endDate: endDate,
            assetId: assetId
        )
        
        return try await getTransactions(request: request)
    }

    func getAssetsWithLastTransaction() async throws -> [Asset] {
        let assets = try await getAssets()
        var assetsWithTransactions: [Asset] = []
        
        for asset in assets {
            do {
                let transactions = try await getLastTransactionForAsset(assetId: asset.id)
                if transactions.first != nil {
                    //print("Asset: \(asset.name) - Last transaction: \(lastTransaction.date) \(lastTransaction.payee) \(lastTransaction.amount) \(lastTransaction.currency)")
                    assetsWithTransactions.append(asset)
                }
            } catch {
                print("Error fetching transactions for asset \(asset.name): \(error.localizedDescription)")
            }
        }
        
        return assetsWithTransactions
    }

}
