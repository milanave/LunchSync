import SwiftUI

struct APITestView: View {
    @State private var logText: String = ""
    private var api: LunchMoneyAPI
    private let keychain = Keychain()
    
    init(){
        let keychain = Keychain()
        var initialToken = ""
        do{
            //print("API Testview: retrieveTokenFromKeychain")
            initialToken = try keychain.retrieveTokenFromKeychain()
        } catch {
            initialToken = ""
        }
        api = LunchMoneyAPI(apiToken: initialToken, debug: true)
    }
    
    var body: some View {
        VStack {
            HStack{
                Button("Run") {
                    Task {
                        await runApiTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("List") {
                    Task {
                        await getTransactions()
                    }
                }
                .buttonStyle(.borderedProminent)
                
            }
            
            ScrollView {
                TextEditor(text: .constant(logText))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
            
        }
        .navigationTitle("API Test")
    }
    
    func runApiTest() async{
        //let timestamp = Date().formatted(date: .omitted, time: .standard)
        //logText += "[\(timestamp)] Running API test...\n"
        //await getAssets()
        await updateTransaction()
    }
    
    func addlog(_ message: String) {
        logText += "\(message)\n"
    }
    
    func testUser() async{
        do {
            let userInfo = try await api.getUser()
            addlog("User Name: \(userInfo.userName)")
            /*print("User Email: \(userInfo.userEmail)")
            print("Budget Name: \(userInfo.budgetName)")
            print("userId: \(userInfo.userId)")
            print("accountId: \(userInfo.accountId)")
            print("primaryCurrency: \(userInfo.primaryCurrency)")
            print("apiKeyLabel: \(userInfo.apiKeyLabel)")*/
        } catch {
            addlog("Error: \(error.localizedDescription)")
        }
    }
    
    func getAssets() async{
        do {
            let assets = try await api.getAssets()
            for asset in assets {
                addlog("Asset ID: \(asset.id), Balance: \(asset.balance), Name: \(asset.name), Ex: \(String(describing: asset.balanceAsOf))")
            }
        } catch {
            addlog("Error fetching assets: \(error)")
        }
    }
    
    func getTransaction(id: Int) async{
        do {
            _ = try await api.getTransaction(id: id)
            //print(transaction)
        } catch {
            print("Error fetching assets: \(error)")
        }
    }
    
    func getTransactions() async{
        do {
            let transactionRequest = GetTransactionsRequest(
                startDate: "2024-12-10",
                endDate: "2025-01-21"
            )

            let transactions = try await api.getTransactions(request:transactionRequest)
            for transaction in transactions {
                addlog("TID: \(transaction.id), AID: \(transaction.assetId ?? 0) Payee: \(transaction.payee), Amount: \(transaction.amount), Date: \(transaction.date) P=\(transaction.isPending)")
            }
            addlog("Found \(transactions.count) transactions")
        } catch {
            addlog("Error fetching assets: \(error)")
        }
    }
    
    func createTransations() async{
        do {
            let assets = try await api.getAssets()
            let asset = assets.first
            addlog("Creating with asset \(String(describing: asset?.id))")
            let transactions = [
                CreateTransactionRequest(
                    date: "2024-12-29",
                    payee: "Payee Test API 1",
                    amount: "50.00",
                    currency: "usd",
                    categoryId: nil,
                    assetId: asset?.id, // apple account
                    notes: "API test call 1",
                    status: "uncleared",
                    externalId: "test5",
                    isPending: true
                )
            ]
            
            let response = try await api.createTransactions(transactions: transactions)
            if let transactionIds = response.transactionIds {
                addlog("Created Transaction IDs: \(transactionIds)")
            } else {
                addlog("No transaction IDs returned; check API documentation or response structure.")
            }
        } catch {
            addlog("Error creating transactions: \(error)")
        }
        
    }
    
    func updateTransaction() async {
        do {
            let transactionRequest = GetTransactionsRequest(
                startDate: "2024-12-10",
                endDate: "2025-01-21"
            )
            let transactions = try await api.getTransactions(request:transactionRequest)
            
            guard let transaction = transactions.first else {
                addlog("No transaction found")
                return
            }
            
            // Convert the amount to a decimal, increment it, and format it back to string
            if let currentAmount = Decimal(string: transaction.amount) {
                let incrementedAmount = currentAmount + 1
                let formattedAmount = String(describing: incrementedAmount)
                
                let updateRequest = UpdateTransactionRequest(
                    transaction: UpdateTransactionRequest.TransactionUpdate(
                        date: nil,
                        payee: nil,
                        amount: formattedAmount,
                        currency: nil,
                        categoryId: nil,
                        assetId: nil,
                        notes: nil,
                        status: "uncleared",
                        externalId: nil,
                        isPending: false
                    )
                )
                
                // Call API to update the transaction
                let result = try await api.updateTransaction(id: transaction.id, request: updateRequest)
                
                if let errors = result.errors {
                    addlog("Failed to update transaction: \(errors.joined(separator: ", "))")
                } else {
                    addlog("Transaction updated successfully: updated=\(result.updated ?? false)")
                    if let split = result.split {
                        addlog("Split transaction IDs: \(split)")
                    }
                }
            }
        } catch {
            addlog("Error updating transaction: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        APITestView()
    }
} 
