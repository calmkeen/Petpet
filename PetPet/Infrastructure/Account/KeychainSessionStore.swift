import Foundation
import Security
import PetPetCore

actor KeychainSessionStore: BackendSessionStore {
    private let service: String
    init(serverOrigin: String) { service = "com.calmkeen.PetPet.backend.\(serverOrigin)" }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "session"]
    }

    func load() throws -> BackendSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw BackendError.storage }
        do { return try JSONDecoder().decode(BackendSession.self, from: data) }
        catch { throw BackendError.storage }
    }

    func save(_ session: BackendSession) throws {
        let data = try JSONEncoder().encode(session)
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            for (key, value) in updates { item[key] = value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BackendError.storage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BackendError.storage }
    }
}
