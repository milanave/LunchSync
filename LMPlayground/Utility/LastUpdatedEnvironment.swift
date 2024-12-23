import SwiftUI

private struct LastUpdatedKey: EnvironmentKey {
    static let defaultValue: Date = Date()
}

extension EnvironmentValues {
    var lastUpdated: Date {
        get { self[LastUpdatedKey.self] }
        set { self[LastUpdatedKey.self] = newValue }
    }
} 