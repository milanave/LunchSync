import Foundation
import Dispatch

enum CLIError: Error, CustomStringConvertible {
    case missingEnv(String)
    case api(String)
    var description: String {
        switch self {
        case .missingEnv(let key): return "Missing required environment variable: \(key)"
        case .api(let message): return message
        }
    }
}

// MARK: - Presentation helpers

func pad(_ text: String, to width: Int) -> String {
    if text.count >= width { return String(text.prefix(width)) }
    return text + String(repeating: " ", count: width - text.count)
}

func printSideBySide(original: LMTransaction, updated: LMTransaction) {
    let labelWidth = 16
    let colWidth = 36

    func row(_ label: String, _ left: String, _ right: String) {
        let l = pad(label, to: labelWidth)
        let a = pad(left, to: colWidth)
        let b = pad(right, to: colWidth)
        print("\(l) | \(a) | \(b)")
    }

    print("\nTransaction ID: \(original.id)")
    print(pad("Field", to: labelWidth) + " | " + pad("Original", to: colWidth) + " | " + pad("Updated", to: colWidth))
    print(String(repeating: "-", count: labelWidth + 3 + colWidth + 3 + colWidth))

    row("date", original.date, updated.date)
    row("payee", original.payee, updated.payee)
    row("amount", original.amount, updated.amount)
    row("currency", original.currency, updated.currency)
    row("category_id", original.categoryId.map(String.init) ?? "", updated.categoryId.map(String.init) ?? "")
    row("asset_id", original.assetId.map(String.init) ?? "", updated.assetId.map(String.init) ?? "")
    row("notes", original.notes ?? "", updated.notes ?? "")
    row("status", original.status, updated.status)
    row("is_pending", String(original.isPending), String(updated.isPending))
    row("external_id", original.externalId ?? "", updated.externalId ?? "")

}

// MARK: - Orchestrator



private let statusValues = ["uncleared", "cleared"]
private let externalIds = ["ExtId1", "ExtId2"]

private let API: LunchMoneyAPI = {
    let token = "a1c31d3ecabc0d0b55c4285317c150a4cc13d6001fc912fe3d"
    return LunchMoneyAPI(apiToken: token, debug: false)
}()

private var firstTwoCategoryIdsCache: [Int]? = nil

// Returns the first two category IDs from LM, cached for reuse
@MainActor
func getFirstTwoCategoryIds() async throws -> [Int] {
    if let cached = firstTwoCategoryIdsCache { return cached }
    let categories = try await API.getCategories()
    let ids = categories.map { $0.id }
    let firstTwo = Array(ids.prefix(2))
    firstTwoCategoryIdsCache = firstTwo
    return firstTwo
}

// Returns an asset id, creating one if none exist
func getOrCreateAssetId() async throws -> Int {
    let existingAssets: [Asset]
    do {
        existingAssets = try await API.getAssets()
    } catch {
        throw CLIError.api("getAssets failed: \(error.localizedDescription)")
    }
    if let first = existingAssets.first {
        print("Using existing asset with ID: \(first.id), \(first.name)")
        return first.id
    } else {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let today = dateFormatter.string(from: Date())

        let assetRequest = CreateAssetRequest(
            typeName: "cash",
            balance: 0.0,
            currency: "usd",
            name: "CLI Asset",
            institutionName: "Bank 1",
            createdAt: today,
            note: "Created from CLI script"
        )
        let assetResponse: CreateAssetResponse
        do {
            assetResponse = try await API.createAsset(requestBody: assetRequest)
        } catch {
            throw CLIError.api("createAsset failed: \(error.localizedDescription)")
        }
        guard let newId = assetResponse.resolvedId else { throw CLIError.api("Failed to create asset: missing id") }
        return newId
    }
}

func runCreateFetchUpdateDemo() async throws {
    // Obtain an assetId (use first, or create if none)
    let assetId = try await getOrCreateAssetId()
    let categoryIds = try await getFirstTwoCategoryIds()

    // Create
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate]
    let today = dateFormatter.string(from: Date())

    print("Creating transaction with status: \(statusValues[0]) and categoryId: \(String(describing: categoryIds.first))")

    let create = CreateTransactionRequest(
        date: today,
        payee: "CLI Test Payee",
        amount: "1.00",
        currency: "usd",
        categoryId: categoryIds.first,
		assetId: assetId,
        notes: "Created from CLI script",
        status: statusValues[0],
        externalId: externalIds.first,
        isPending: false
    )
    let createResp: CreateTransactionsResponse
    do {
        createResp = try await API.createTransactions(transactions: [create])
    } catch {
        throw CLIError.api("createTransactions failed: \(error.localizedDescription)")
    }
    if let errs = createResp.errors, !errs.isEmpty { throw CLIError.api(errs.joined(separator: ", ")) }
    guard let id = createResp.transactionIds?.first else { throw CLIError.api("Create did not return an id") }

    // Fetch original
    let original: LMTransaction
    do {
        original = try await API.getTransaction(id: id)
    } catch {
        throw CLIError.api("getTransaction (original) failed: \(error.localizedDescription)")
    }

    // Update
    let parseFormatter = DateFormatter()
    parseFormatter.dateFormat = "yyyy-MM-dd"
    let originalDateParsed = parseFormatter.date(from: original.date) ?? Date()
    let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: originalDateParsed) ?? originalDateParsed
    let nextDayString = parseFormatter.string(from: nextDay)

    let originalAmountDouble = Double(original.amount) ?? 0.0
    let incrementedAmount = String(format: "%.2f", originalAmountDouble + 1.0)
    let toggledStatus = (original.status.lowercased() == statusValues[0]) ? statusValues[1] : statusValues[0]
    let toggledCategoryId: Int? = {
        if categoryIds.count >= 2 {
            return (original.categoryId == categoryIds.first) ? categoryIds[1] : categoryIds.first
        } else {
            return categoryIds.first
        }
    }()
    let toggledExtId: String? = {
        if externalIds.count >= 2 {
            return (original.externalId == externalIds.first) ? externalIds[1] : externalIds.first
        } else {
            return externalIds.first
        }
    }()
    

    let updateReq = UpdateTransactionRequest(transaction: .init(
        date: nextDayString,
        payee: "CLI Updated Payee",
        amount: incrementedAmount,
        currency: nil,
        categoryId: toggledCategoryId,
        assetId: assetId,
        notes: "Updated from CLI script",
        status: toggledStatus,
        externalId: toggledExtId,
        isPending: nil
    ))
    let updateResp: UpdateTransactionResponse
    do {
        updateResp = try await API.updateTransaction(id: id, request: updateReq)
    } catch {
        throw CLIError.api("updateTransaction failed: \(error.localizedDescription)")
    }
    if let errs = updateResp.errors, !errs.isEmpty { throw CLIError.api(errs.joined(separator: ", ")) }

    // Fetch updated
    let updated: LMTransaction
    do {
        updated = try await API.getTransaction(id: id)
    } catch {
        throw CLIError.api("getTransaction (updated) failed: \(error.localizedDescription)")
    }
    printSideBySide(original: original, updated: updated)
}

// MARK: - Entry point for command-line execution
do {
    try await runCreateFetchUpdateDemo()
} catch {
    if let cli = error as? CLIError { fputs("Error: \(cli.description)\n", stderr) }
    else { fputs("Error: \(error.localizedDescription)\n", stderr) }
}





