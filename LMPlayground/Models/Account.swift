import SwiftData
import Foundation

@Model
class Account {
    var id: String // Just a regular property, SwiftData will handle object IDs automatically
    var name: String
    var lm_id: String
    var lm_name: String
    var balance: Double
    var available: Double
    var currency: String
    var institution_name: String
    var institution_id: String
    var lastUpdated: Date
    var sync: Bool
    
    init(id: String,
         name: String,
         balance: Double,
         lm_id: String,
         lm_name: String,
         available: Double = 0.0,
         currency: String = "USD",
         institution_name: String = "",
         institution_id: String = "",
         lastUpdated: Date = Date(),
         sync: Bool = true) {
        self.id = id
        self.name = name
        self.balance = balance
        self.lm_id = lm_id
        self.lm_name = lm_name
        self.available = available
        self.currency = currency
        self.institution_name = institution_name
        self.institution_id = institution_id
        self.lastUpdated = lastUpdated
        self.sync = sync
    }
}
