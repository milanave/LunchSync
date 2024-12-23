import SwiftData
import Foundation

@Model
class Transaction: Identifiable {
    enum SyncStatus: String, Codable {
        case pending = "pending"
        case yes = "yes"
        case never = "never"
        case complete = "complete"
    }
    
    var id: String
    var account: String
    var accountID: String
    var payee: String
    var amount: Double
    var date: Date
    var lm_id: String
    var lm_account: String
    var notes: String
    var category: String
    var type: String
    var status: String
    var isPending: Bool
    @Attribute(originalName: "sync") var syncStatus: String
    
    var sync: SyncStatus {
        get {
            return SyncStatus(rawValue: syncStatus) ?? .pending
        }
        set {
            syncStatus = newValue.rawValue
        }
    }
    
    init(id: String,
         account: String,
         payee: String,
         amount: Double,
         date: Date,
         lm_id: String,
         lm_account: String,
         notes: String = "",
         category: String = "",
         type: String = "",
         accountID: String = "",
         status: String = "",
         isPending: Bool = false,
         sync: SyncStatus = .pending) {
        self.id = id
        self.account = account
        self.payee = payee
        self.amount = amount
        self.date = date
        self.lm_id = lm_id
        self.lm_account = lm_account
        self.notes = notes
        self.category = category
        self.type = type
        self.accountID = accountID
        self.status = status
        self.syncStatus = sync.rawValue
        self.isPending = isPending
    }
}
