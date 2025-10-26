//
//  PushAPI.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/2/25.
//
import Foundation

// Add this struct at the top level
struct PushRegistrationResponse: Codable {
    let status: Bool
    let message: String
    let frequency: Int?
}

struct PushAPI {
    private init() {}
    
    // MARK: - Private Helpers
    private static var serviceURL: URL? {
        URL(string: "https://push.littlebluebug.com/register.php")
    }
    
    private static func currentEnvironment() -> String {
        #if DEBUG
        return "Test"
        #else
        return "Production"
        #endif
    }
    
    private static func appVersionString() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(appVersion) (\(buildNumber))"
    }
    
    private static func isTestFlightBuild() -> Bool {
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        return sharedDefaults.bool(forKey: "is_test_flight")
    }
    
    private static func basePayload(deviceToken: String) -> [String: Any] {
        
        let runStateString = Utility.getRunState()?.description ?? "unknown"
        return [
            "device_token": deviceToken,
            "app_id": "WalletSync",
            "key": Configuration.shared.pushServiceKey,
            "environment": currentEnvironment(),
            "app_version": appVersionString(),
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "run_state": runStateString
        ]
    }
    
    private static func mapFrequencyToHour(_ frequency: Int) -> Int {
        switch frequency {
            case 0: return 1
            case 1: return 1
            case 2: return 6
            case 3: return 12
            case 4: return 24
            case 5: return 2
            case 6: return 3
            default: return 1
        }
    }
    
    @discardableResult
    private static func sendRequest(payload: [String: Any]) async throws -> PushRegistrationResponse {
        guard let url = serviceURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PushRegistrationResponse.self, from: data)
    }
    
    static func registerWalletCheck(deviceToken: String, logPrefix: String="") async {
        var payload = basePayload(deviceToken: deviceToken)
        payload["action_id"] = (logPrefix == "BGD") ? "bgd_complete" : "push_received"
        do {
            let response = try await sendRequest(payload: payload)
            print("Wallet check registration status: \(response.status)")
        } catch {
            print("Error in wallet check registration: \(error.localizedDescription)")
        }
    }
    
    static func registerForPushNotifications(deviceToken: String, active: Bool = true, frequency: Int = 1) async -> PushRegistrationResponse {
        var payload = basePayload(deviceToken: deviceToken)
        payload["active"] = active
        payload["frequency"] = mapFrequencyToHour(frequency)
        payload["action_id"] = "register"
        do {
            let response = try await sendRequest(payload: payload)
            return response
        } catch {
            return PushRegistrationResponse(status: false, message: "Error: \(error.localizedDescription)", frequency: nil)
        }
    }
    
}
