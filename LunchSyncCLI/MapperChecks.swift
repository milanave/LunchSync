//
//  MapperChecks.swift
//  LunchSyncCLI
//
//  Offline checks for the LunchMoneyAPIV2 wire↔neutral mapping layer — the
//  code most exposed to churn while Lunch Money's v2 API is in alpha. No
//  network, no token: run with `LunchSyncCLI mapper-checks`.
//
import Foundation

private var checkFailures: [String] = []

private func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok  \(label)")
    } else {
        checkFailures.append(label)
        print("FAIL  \(label)")
    }
}

private func jsonObject(from data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

func runMapperChecks() throws {
    print("\n=== LunchMoneyAPIV2 mapper checks ===\n")

    // MARK: status vocabulary
    expect(LunchMoneyAPIV2.v1Status(fromV2: "reviewed") == "cleared", "v2 reviewed → v1 cleared")
    expect(LunchMoneyAPIV2.v1Status(fromV2: "unreviewed") == "uncleared", "v2 unreviewed → v1 uncleared")
    expect(LunchMoneyAPIV2.v1Status(fromV2: "delete_pending") == "delete_pending", "v2 delete_pending passes through")
    expect(LunchMoneyAPIV2.v1Status(fromV2: nil) == "uncleared", "v2 nil status → v1 uncleared")
    expect(LunchMoneyAPIV2.v2Status(fromV1: "cleared") == "reviewed", "v1 cleared → v2 reviewed")
    expect(LunchMoneyAPIV2.v2Status(fromV1: "uncleared") == "unreviewed", "v1 uncleared → v2 unreviewed")
    expect(LunchMoneyAPIV2.v2Status(fromV1: nil) == nil, "v1 nil status → omitted")
    expect(LunchMoneyAPIV2.v2Status(fromV1: "pending") == nil, "v1 pending (unsupported) → omitted")

    // MARK: account-id edge (lm_account "0" sentinel must not reach v2)
    expect(LunchMoneyAPIV2.manualAccountId(fromNeutralAssetId: nil) == nil, "asset id nil → no manual_account_id")
    expect(LunchMoneyAPIV2.manualAccountId(fromNeutralAssetId: 0) == nil, "asset id 0 → no manual_account_id")
    expect(LunchMoneyAPIV2.manualAccountId(fromNeutralAssetId: 42) == 42, "asset id 42 → manual_account_id 42")

    // MARK: insert body encoding (strict v2 validation: exact keys only)
    let insertItem = LunchMoneyAPIV2.insertItem(fromNeutral: CreateTransactionRequest(
        date: "2026-07-11",
        payee: "Coffee",
        amount: "4.50",
        currency: "USD",
        categoryId: nil,
        assetId: 0,
        notes: nil,
        status: "cleared",
        externalId: "ABC-123",
        isPending: true
    ))
    let insertJSON = jsonObject(from: try JSONEncoder().encode(insertItem))
    expect(insertJSON["is_pending"] == nil, "insert body has no is_pending key (not writable on v2)")
    expect(insertJSON["category_id"] == nil, "nil category omitted from insert body")
    expect(insertJSON["manual_account_id"] == nil, "asset id 0 omitted from insert body")
    expect(insertJSON["status"] as? String == "reviewed", "insert status mapped to v2 vocabulary")
    expect(insertJSON["currency"] as? String == "usd", "insert currency lowercased")
    expect(insertJSON["external_id"] as? String == "ABC-123", "external_id preserved")

    let batchBody = V2InsertTransactionsRequest(transactions: [insertItem], applyRules: nil, skipDuplicates: false, skipBalanceUpdate: true)
    let batchJSON = jsonObject(from: try JSONEncoder().encode(batchBody))
    expect(batchJSON["check_for_recurring"] == nil, "check_for_recurring never sent to v2")
    expect(batchJSON["apply_rules"] == nil, "nil apply_rules omitted")
    expect(batchJSON["skip_balance_update"] as? Bool == true, "skip_balance_update passed through")

    // MARK: update body encoding (partial update semantics)
    let dateOnly = V2UpdateTransactionRequest(
        date: "2026-07-11", payee: nil, amount: nil, currency: nil,
        categoryId: nil, manualAccountId: nil, notes: nil, status: nil, customMetadata: nil
    )
    let dateOnlyJSON = jsonObject(from: try JSONEncoder().encode(dateOnly))
    expect(dateOnlyJSON.count == 1 && dateOnlyJSON["date"] as? String == "2026-07-11", "partial update encodes only set fields")

    // MARK: insert response mapping — mixed inserted + external_id duplicate
    let mixedResponse = """
    {
      "transactions": [
        {"id": 111, "date": "2026-07-10", "payee": "New Txn", "amount": "12.0000", "currency": "usd",
         "category_id": null, "notes": null, "status": "unreviewed", "is_pending": false,
         "external_id": "EXT-A", "manual_account_id": 9, "plaid_account_id": null}
      ],
      "skipped_duplicates": [
        {"reason": "duplicate_external_id", "request_transactions_index": 1,
         "existing_transaction_id": 222, "request_transaction": {"external_id": "EXT-B"}}
      ]
    }
    """
    let mixedWire = try JSONDecoder().decode(V2InsertTransactionsResponse.self, from: Data(mixedResponse.utf8))
    func neutralItem(_ externalId: String) -> CreateTransactionRequest {
        CreateTransactionRequest(
            date: "2026-07-10", payee: "x", amount: "1.00", currency: "usd", categoryId: nil,
            assetId: 9, notes: nil, status: "cleared", externalId: externalId, isPending: false
        )
    }
    let mixed = LunchMoneyAPIV2.createResponse(fromV2: mixedWire, requestItems: [neutralItem("EXT-A"), neutralItem("EXT-B")])
    expect(mixed.transactionIds == [111, 222], "ids reconstructed in request order incl. duplicate's existing id")
    expect(mixed.inserted?.count == 1 && mixed.inserted?.first?.id == 111, "inserted rows mapped")
    expect(mixed.inserted?.first?.status == "uncleared", "inserted status mapped back to v1 vocabulary")
    expect(mixed.inserted?.first?.assetId == 9, "manual_account_id mapped to neutral assetId")
    expect(mixed.skippedDuplicates?.first?.reason == .duplicateExternalId, "skip reason decoded")
    expect(mixed.skippedDuplicates?.first?.existingTransactionId == 222, "existing id preserved")
    expect(mixed.errors == nil, "v2 2xx never carries errors")

    // MARK: insert response mapping — heuristic duplicate never adopts an id
    let heuristicResponse = """
    {
      "transactions": [],
      "skipped_duplicates": [
        {"reason": "duplicate_payee_amount_date", "request_transactions_index": 0,
         "existing_transaction_id": 333, "request_transaction": {"external_id": "EXT-C"}}
      ]
    }
    """
    let heuristicWire = try JSONDecoder().decode(V2InsertTransactionsResponse.self, from: Data(heuristicResponse.utf8))
    let heuristic = LunchMoneyAPIV2.createResponse(fromV2: heuristicWire, requestItems: [neutralItem("EXT-C")])
    expect(heuristic.transactionIds == [], "payee/amount/date duplicate leaves ids unresolved")
    expect(heuristic.skippedDuplicates?.first?.reason == .duplicatePayeeAmountDate, "heuristic skip reason decoded")

    // MARK: single insert without external_id still resolves positionally
    let bareResponse = """
    {"transactions": [{"id": 444, "date": "2026-07-10", "payee": "Bare", "amount": "9.9900",
      "currency": "usd", "category_id": null, "notes": null, "status": "unreviewed",
      "is_pending": false, "external_id": null, "manual_account_id": null, "plaid_account_id": null}],
     "skipped_duplicates": []}
    """
    let bareWire = try JSONDecoder().decode(V2InsertTransactionsResponse.self, from: Data(bareResponse.utf8))
    let bareItem = CreateTransactionRequest(
        date: "2026-07-10", payee: "Bare", amount: "9.99", currency: "usd", categoryId: nil,
        assetId: nil, notes: nil, status: nil, externalId: nil, isPending: false
    )
    let bare = LunchMoneyAPIV2.createResponse(fromV2: bareWire, requestItems: [bareItem])
    expect(bare.transactionIds == [444], "single insert without external_id resolves to the one inserted id")

    // MARK: error envelope decoding
    let errorJSON = """
    {"message": "Unauthorized", "errors": [{"errMsg": "Missing authorization header"}]}
    """
    let decodedError = try JSONDecoder().decode(V2ErrorResponse.self, from: Data(errorJSON.utf8))
    expect(decodedError.message == "Unauthorized" && decodedError.errors?.first?.errMsg == "Missing authorization header",
           "v2 error envelope decodes")

    print("\n=== \(checkFailures.isEmpty ? "ALL CHECKS PASSED" : "\(checkFailures.count) CHECK(S) FAILED") ===\n")
    if !checkFailures.isEmpty {
        throw CLIError.api("mapper checks failed: \(checkFailures.joined(separator: "; "))")
    }
}
