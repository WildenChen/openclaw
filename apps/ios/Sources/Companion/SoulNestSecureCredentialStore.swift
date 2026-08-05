import Foundation
import Security

/// Secrets that may be persisted for the SoulNest Gateway connection.
enum SoulNestCredentialKey: String, CaseIterable, Sendable {
    case gatewayToken = "gateway-token"
    case pairingCredential = "pairing-credential"
    case deviceCredential = "device-credential"
}

enum SoulNestCredentialStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case unexpectedStatus(OSStatus)
}

protocol SoulNestSecureCredentialStore: Sendable {
    func save(_ value: String, for key: SoulNestCredentialKey) throws
    func value(for key: SoulNestCredentialKey) throws -> String?
    func remove(_ key: SoulNestCredentialKey) throws
    func removeAll() throws
}

/// Keychain-backed secret store. Values are device-local and unavailable while
/// the device is locked. Gateway URL and non-sensitive presentation settings
/// intentionally remain outside this store.
struct SoulNestKeychainCredentialStore: SoulNestSecureCredentialStore {
    private let service: String
    private let accessGroup: String?

    init(
        service: String = "com.wildenstudio.soulnest.gateway",
        accessGroup: String? = nil)
    {
        self.service = service
        self.accessGroup = accessGroup
    }

    func save(_ value: String, for key: SoulNestCredentialKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw SoulNestCredentialStoreError.encodingFailed
        }

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SoulNestCredentialStoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SoulNestCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func value(for key: SoulNestCredentialKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw SoulNestCredentialStoreError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: SoulNestCredentialKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SoulNestCredentialStoreError.unexpectedStatus(status)
        }
    }

    func removeAll() throws {
        for key in SoulNestCredentialKey.allCases {
            try remove(key)
        }
    }

    private func baseQuery(for key: SoulNestCredentialKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// Test and preview implementation that preserves the same API without writing
/// secrets to UserDefaults or disk.
final class SoulNestInMemoryCredentialStore: SoulNestSecureCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SoulNestCredentialKey: String] = [:]

    func save(_ value: String, for key: SoulNestCredentialKey) throws {
        lock.withLock { values[key] = value }
    }

    func value(for key: SoulNestCredentialKey) throws -> String? {
        lock.withLock { values[key] }
    }

    func remove(_ key: SoulNestCredentialKey) throws {
        lock.withLock { values.removeValue(forKey: key) }
    }

    func removeAll() throws {
        lock.withLock { values.removeAll() }
    }
}
