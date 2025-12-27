import Foundation
import SwiftData

@Model
class TransactionHistory {
    var date: Date = Date()
    var note: String = ""
    var transaction: Transaction?
    var source: String = ""
    
    init(date: Date = Date(), note: String, source: String = "") {
        self.date = date
        self.note = note
        self.source = source
    }
}


