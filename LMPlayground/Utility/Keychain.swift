import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unableToConvertData
    case unexpectedStatus(OSStatus)
}

class Keychain {
    private let appId = "com.milanave.lmwallet"
    private let tokenKey = "apiToken" // Use a constant for the token account name
    private let sharedAccessGroup = "group.com.littlebluebug.AppleCardSync"
    
    public func listAllKeychainItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrAccessGroup as String: sharedAccessGroup
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            if let items = result as? [[String: Any]] {
                for item in items {
                    if let service = item[kSecAttrService as String] as? String,
                       let account = item[kSecAttrAccount as String] as? String,
                       let data = item[kSecValueData as String] as? Data,
                       let value = String(data: data, encoding: .utf8) {
                        print("Service: \(service), Account: \(account), Value: \(value)")
                    }
                }
            }
        } else if status == errSecItemNotFound {
            print("No Keychain items found.")
        } else {
            print("Failed to retrieve Keychain items: \(String(describing: SecCopyErrorMessageString(status, nil)))")
        }
    }
    
    func storeTokenInKeychain(token: String) {
        let tokenData = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appId,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrAccessGroup as String: sharedAccessGroup
        ]

        // Attempt to delete any existing item
        let deleteStatus = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appId,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: sharedAccessGroup
        ] as CFDictionary)

        if deleteStatus == errSecSuccess {
            print("🔄 Successfully deleted existing Keychain item.")
        } else if deleteStatus == errSecItemNotFound {
            print("ℹ️ No existing Keychain item found to delete.")
        } else {
            print("⚠️ Failed to delete Keychain item: \(String(describing: SecCopyErrorMessageString(deleteStatus, nil)))")
        }

        // Add the new item to the Keychain
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            print("✅ Keychain item successfully added.")
        } else {
            print("❌ Failed to add Keychain item: \(String(describing: SecCopyErrorMessageString(addStatus, nil)))")
        }
        
        listAllKeychainItems()
    }

    func retrieveTokenFromKeychain() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appId,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: sharedAccessGroup
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            // Convert data to a string
            if let data = item as? Data, let token = String(data: data, encoding: .utf8) {
                //print("retrieveTokenFromKeychain returning \(token)")
                return token
            } else {
                throw KeychainError.unableToConvertData
            }
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
