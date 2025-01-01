import Foundation

enum ConfigurationError: Error {
    case missingKey(String)
}

struct Configuration {
    static let shared = Configuration()
    
    private init() {}
    
    var pushServiceKey: String {
        guard let key = Bundle.main.infoDictionary?["PUSH_SERVICE_KEY"] as? String ?? 
                       Bundle.main.object(forInfoDictionaryKey: "INFOPLIST_KEY_PUSH_SERVICE_KEY") as? String,
              !key.contains("your_push_service_key_here") else {
            #if DEBUG
            print("⚠️ Warning: Using development push service key. Make sure to set up Config.xcconfig in production.")
            return "development_key"
            #else
            fatalError("Push service key not configured. Please set up Config.xcconfig with your production key.")
            #endif
        }
        return key
    }
} 
