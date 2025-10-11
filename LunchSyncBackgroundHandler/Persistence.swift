import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        Item.self,
        Transaction.self,
        Account.self,
        Log.self,
        LMCategory.self,
        TrnCategory.self,
        TransactionHistory.self
    ])

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.com.littlebluebug.AppleCardSync")
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}


