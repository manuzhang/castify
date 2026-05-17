import Foundation
import Security

enum KeychainServiceError: LocalizedError {
  case invalidData
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      return LocalizationService.shared.text(.githubTokenInvalid)
    case .unexpectedStatus(let status):
      return LocalizationService.shared.keychainError(status: status)
    }
  }
}

final class KeychainService {

  private let service: String
  private let account: String

  init(service: String = "io.github.manuzhang.Castify",
       account: String = "githubToken") {
    self.service = service
    self.account = account
  }

  func saveToken(_ token: String) throws {
    let data = Data(token.utf8)
    var attributes = baseQuery()
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    SecItemDelete(baseQuery() as CFDictionary)
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainServiceError.unexpectedStatus(status)
    }
  }

  func loadToken() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess else {
      throw KeychainServiceError.unexpectedStatus(status)
    }

    guard let data = result as? Data,
          let token = String(data: data, encoding: .utf8) else {
      throw KeychainServiceError.invalidData
    }

    return token
  }

  func deleteToken() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainServiceError.unexpectedStatus(status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}
