import CryptoKit
import Foundation

struct HistoryRecord: Codable, Identifiable {
  let id: UUID
  let sourceText: String
  let mode: AnalysisMode
  let targetLanguage: HowToSayTargetLanguage?
  let response: AnalysisResponse
  let createdAt: Date
  let providerName: String
  let model: String
  let cacheKey: String

  enum CodingKeys: String, CodingKey {
    case id
    case sourceText = "source_text"
    case mode
    case targetLanguage = "target_language"
    case response
    case createdAt = "created_at"
    case providerName = "provider_name"
    case model
    case cacheKey = "cache_key"
  }
}

final class HistoryStore {
  static let shared = HistoryStore()
  static let schemaVersion = "feature-routing-v7"

  private(set) var records: [HistoryRecord] = []
  private let directoryURL: URL
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private convenience init() {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let directory = applicationSupport.appendingPathComponent("Reddict", isDirectory: true)
    self.init(directoryURL: directory)
  }

  init(directoryURL directory: URL) {
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try? FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o700)],
      ofItemAtPath: directory.path
    )
    directoryURL = directory
    fileURL = directory.appendingPathComponent("history-v3.json")

    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let data = try? Data(contentsOf: fileURL),
      let saved = try? decoder.decode([HistoryRecord].self, from: data)
    {
      records = saved.sorted { $0.createdAt > $1.createdAt }
    }
    if FileManager.default.fileExists(atPath: fileURL.path) {
      secureFilePermissions()
    } else {
      persist()
    }
  }

  func cached(
    text: String,
    mode: AnalysisMode,
    targetLanguage: HowToSayTargetLanguage?,
    configuration: LLMConfiguration
  ) -> HistoryRecord? {
    let key = cacheKey(
      text: text,
      mode: mode,
      targetLanguage: targetLanguage,
      configuration: configuration
    )
    return records.first { $0.cacheKey == key }
  }

  @discardableResult
  func save(
    text: String,
    mode: AnalysisMode,
    targetLanguage: HowToSayTargetLanguage?,
    response: AnalysisResponse,
    configuration: LLMConfiguration
  ) -> HistoryRecord {
    let key = cacheKey(
      text: text,
      mode: mode,
      targetLanguage: targetLanguage,
      configuration: configuration
    )
    records.removeAll { $0.cacheKey == key }
    let record = HistoryRecord(
      id: UUID(),
      sourceText: text,
      mode: mode,
      targetLanguage: targetLanguage,
      response: response,
      createdAt: Date(),
      providerName: configuration.provider.title,
      model: configuration.model,
      cacheKey: key
    )
    records.insert(record, at: 0)
    if records.count > 300 {
      records.removeLast(records.count - 300)
    }
    persist()
    return record
  }

  @discardableResult
  func clear() -> Bool {
    let previous = records
    records.removeAll()
    guard persist() else {
      records = previous
      return false
    }
    return true
  }

  var hasPrivateFilePermissions: Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let permissions = attributes[.posixPermissions] as? NSNumber
    else {
      return false
    }
    return permissions.intValue & 0o077 == 0
  }

  private func cacheKey(
    text: String,
    mode: AnalysisMode,
    targetLanguage: HowToSayTargetLanguage?,
    configuration: LLMConfiguration
  ) -> String {
    let normalized =
      text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\r\n", with: "\n")
    let payload = [
      Self.schemaVersion,
      mode.rawValue,
      targetLanguage?.id ?? "-",
      configuration.provider.rawValue,
      configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
      String(configuration.useJSONMode),
      LearnerPreferencesStore.shared.load().cacheDescription,
      normalized,
    ].joined(separator: "\u{1F}")
    return SHA256.hash(data: Data(payload.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  @discardableResult
  private func persist() -> Bool {
    guard let data = try? encoder.encode(records) else { return false }
    do {
      try data.write(to: fileURL, options: .atomic)
      secureFilePermissions()
      return true
    } catch {
      return false
    }
  }

  private func secureFilePermissions() {
    try? FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o700)],
      ofItemAtPath: directoryURL.path
    )
    try? FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o600)],
      ofItemAtPath: fileURL.path
    )
  }
}
