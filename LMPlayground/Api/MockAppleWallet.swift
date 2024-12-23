//
//  MockAppleWallet.swift
//  LMPlayground
//
//  Created by Bob Sanders on 12/7/24.
import SwiftUI
import SwiftData
import FinanceKit

class MockAppleWallet: AppleWallet {
    private var _authStatus: AuthorizationStatus = .authorized
    
    override var authStatus: AuthorizationStatus {
        get { return _authStatus }
        set { _authStatus = newValue }
    }
    
    override func getSimulatedAccounts() -> [Account] {
        return [
            Account(id: "1", name: "Mock Account 1", balance: 1000, lm_id: "", lm_name: ""),
            Account(id: "2", name: "Mock Account 2", balance: 2000, lm_id: "", lm_name: "")
        ]
    }
    
    override func getWalletAccounts() async throws -> [Account] {
        return [
            Account(id: "1", name: "Mock Account 1", balance: 1000, lm_id: "", lm_name: ""),
            Account(id: "2", name: "Mock Account 2", balance: 2000, lm_id: "", lm_name: "")
        ]
    }
    
    override func fetchhWalletTransactionsForAccounts(accounts: [Account]) async throws -> [Transaction] {
        return [
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Store", amount: 42.0, date: Date(), lm_id: "", lm_account: "", sync: .pending),
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Shop", amount: 24.0, date: Date(), lm_id: "", lm_account: "", sync: .pending)
        ]
    }
    
    override func refreshWalletTransactionsForAccounts(accounts: [Account]) async throws -> [Transaction] {
        return [
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "New Store", amount: 15.0, date: Date(), lm_id: "", lm_account: "", sync: .pending)
        ]
    }
    
    override func requestAuth() async -> AuthorizationStatus {
        return .authorized
    }
}
