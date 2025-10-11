import Foundation
import SwiftData

@Model
class TransactionHistory {
    var date: Date = Date()
    var note: String = ""
    var transaction: Transaction?
    
    init(date: Date = Date(), note: String) {
        self.date = date
        self.note = note
    }
}


