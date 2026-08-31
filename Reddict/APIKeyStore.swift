import Foundation

/// Stores only keys explicitly entered and saved inside Reddict.
/// The app deliberately does not inspect or migrate entries from macOS Keychain.
final class APIKeyStore {
  static let shared = APIKeyStore()

  private let defaults = UserDefaults.standard

  private init() {}

  func apiKey(for provider: LLMProvider) -> String? {
    let value = defaults.string(forKey: storageKey(for: provider))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  func saveAPIKey(_ value: String, for provider: LLMProvider) {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty {
      defaults.removeObject(forKey: storageKey(for: provider))
    } else {
      defaults.set(normalized, forKey: storageKey(for: provider))
    }
  }

  private func storageKey(for provider: LLMProvider) -> String {
    "llm.manuallyEnteredAPIKey.v1.\(provider.rawValue)"
  }
}
