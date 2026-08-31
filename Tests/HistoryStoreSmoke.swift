import Foundation

@main
struct HistoryStoreSmoke {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Reddict-HistoryStore-Smoke-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = HistoryStore(directoryURL: directory)
    precondition(store.hasPrivateFilePermissions)
    _ = store.save(
      text: "private history test",
      mode: .replies,
      targetLanguage: nil,
      response: AnalysisResponse(replyContext: "test", replies: []),
      configuration: .defaults(for: .deepSeek)
    )
    precondition(store.records.count == 1)
    precondition(store.clear())
    precondition(store.records.isEmpty)

    let historyFile = directory.appendingPathComponent("history-v3.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: historyFile.path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
      preconditionFailure("History file is missing POSIX permissions")
    }
    precondition(permissions.intValue & 0o077 == 0)
    let data = try Data(contentsOf: historyFile)
    let decoded = try JSONDecoder().decode([HistoryRecord].self, from: data)
    precondition(decoded.isEmpty)
    print("HISTORY_STORE_SMOKE_OK")
  }
}
