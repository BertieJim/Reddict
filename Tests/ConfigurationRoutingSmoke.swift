import Foundation

@main
struct ConfigurationRoutingSmoke {
  static func main() {
    let defaults = UserDefaults.standard
    let keys = [
      "llm.selectedProvider.v2",
      "llm.featureAssignments.v1",
      "llm.configuration.v2.deepSeek",
      "llm.configuration.v2.gemini",
      "llm.availableModels.v1.gemini",
    ]
    keys.forEach(defaults.removeObject(forKey:))
    defer { keys.forEach(defaults.removeObject(forKey:)) }

    let store = LLMConfigurationStore.shared
    for mode in AnalysisMode.allCases {
      precondition(store.provider(for: mode) == .deepSeek)
    }

    store.save(
      .defaults(for: .gemini),
      assigningTo: [.closeReading, .replies]
    )
    precondition(store.provider(for: .closeReading) == .gemini)
    precondition(store.provider(for: .replies) == .gemini)
    precondition(store.provider(for: .howToSay) == .deepSeek)

    store.save(.defaults(for: .deepSeek), assigningTo: [])
    precondition(store.provider(for: .closeReading) == .gemini)
    precondition(store.provider(for: .replies) == .gemini)
    precondition(store.provider(for: .howToSay) == nil)
    precondition(store.assignedModes(for: .gemini) == [.closeReading, .replies])

    store.saveAvailableModels(["gemini-pro", " gemini-flash ", "gemini-pro"], for: .gemini)
    precondition(store.availableModels(for: .gemini) == ["gemini-flash", "gemini-pro"])

    print("CONFIGURATION_ROUTING_SMOKE_OK")
  }
}
