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

func runCreateFetchUpdateDemo() async throws {
    guard let token = "a1c31d3ecabc0d0b55c4285317c150a4cc13d6001fc912fe3d"

    let api = LunchMoneyAPI(apiToken: token, debug: false)

    // Create
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate]
    let today = dateFormatter.string(from: Date())

    let create = CreateTransactionRequest(
        date: today,
        payee: "CLI Test Payee",
        amount: "1.00",
        currency: "USD",
        categoryId: nil,
        assetId: nil,
        notes: "Created from CLI script",
        status: "cleared",
        externalId: UUID().uuidString,
        isPending: false
    )
    let createResp = try await api.createTransactions(transactions: [create])
    if let errs = createResp.errors, !errs.isEmpty { throw CLIError.api(errs.joined(separator: ", ")) }
    guard let id = createResp.transactionIds?.first else { throw CLIError.api("Create did not return an id") }

    // Fetch original
    let original = try await api.getTransaction(id: id)

    // Update
    let updateReq = UpdateTransactionRequest(transaction: .init(
        date: nil,
        payee: "CLI Updated Payee",
        amount: "2.00",
        currency: nil,
        categoryId: nil,
        assetId: nil,
        notes: "Updated from CLI script",
        status: nil,
        externalId: nil,
        isPending: nil
    ))
    let updateResp = try await api.updateTransaction(id: id, request: updateReq)
    if let errs = updateResp.errors, !errs.isEmpty { throw CLIError.api(errs.joined(separator: ", ")) }

    // Fetch updated
    let updated = try await api.getTransaction(id: id)
    printSideBySide(original: original, updated: updated)
}

// MARK: - Entry point for command-line execution

Task {
    do {
        try await runCreateFetchUpdateDemo()
        exit(EXIT_SUCCESS)
    } catch {
        if let cli = error as? CLIError { fputs("Error: \(cli.description)\n", stderr) }
        else { fputs("Error: \(error.localizedDescription)\n", stderr) }
        exit(EXIT_FAILURE)
    }
}

dispatchMain()


