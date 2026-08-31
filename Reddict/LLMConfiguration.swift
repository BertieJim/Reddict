import Foundation

enum LLMProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case deepSeek
  case gemini
  case kimi
  case studyHuyu
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .deepSeek: "DeepSeek"
    case .gemini: "Gemini"
    case .kimi: "Kimi"
    case .studyHuyu: "CLI-Proxy"
    case .custom: "自定义"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .deepSeek: "https://api.deepseek.com"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
    case .kimi: "https://api.moonshot.cn/v1"
    case .studyHuyu: "https://studyhuyu.com/llm/v1"
    case .custom: ""
    }
  }

  var defaultModel: String {
    switch self {
    case .deepSeek: "deepseek-v4-flash"
    case .gemini: "gemini-3.7-flash"
    case .kimi: "kimi-k2.5"
    case .studyHuyu: "gpt-5.5"
    case .custom: ""
    }
  }

  var subtitle: String {
    switch self {
    case .deepSeek: "DeepSeek 官方 OpenAI-compatible API"
    case .gemini: "Google Gemini OpenAI compatibility"
    case .kimi: "Moonshot 官方 API"
    case .studyHuyu: "CLI-Proxy · SELF_API_USAGE.md 中的 JP 网关"
    case .custom: "任意 OpenAI-compatible Chat Completions"
    }
  }
}

struct LLMConfiguration: Codable, Equatable, Sendable {
  var provider: LLMProvider
  var baseURL: String
  var model: String
  var useJSONMode: Bool

  static func defaults(for provider: LLMProvider) -> LLMConfiguration {
    LLMConfiguration(
      provider: provider,
      baseURL: provider.defaultBaseURL,
      model: provider.defaultModel,
      useJSONMode: true
    )
  }

  var displayName: String {
    model.isEmpty ? provider.title : "\(provider.title) · \(model)"
  }

  var chatCompletionsURL: URL? {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let withoutSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    if withoutSlash.hasSuffix("/chat/completions") {
      return URL(string: withoutSlash)
    }
    return URL(string: withoutSlash + "/chat/completions")
  }

  var modelsURL: URL? {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var withoutSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    if withoutSlash.hasSuffix("/chat/completions") {
      withoutSlash.removeLast("/chat/completions".count)
    }
    if withoutSlash.hasSuffix("/models") {
      return URL(string: withoutSlash)
    }
    return URL(string: withoutSlash + "/models")
  }

  var isCredentialTransportSecure: Bool {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      url.user == nil,
      url.password == nil,
      let scheme = url.scheme?.lowercased(),
      let host = url.host?.lowercased()
    else {
      return false
    }
    if scheme == "https" { return true }
    guard scheme == "http" else { return false }
    return host == "localhost"
      || host.hasSuffix(".localhost")
      || host == "::1"
      || host == "0:0:0:0:0:0:0:1"
      || host.hasPrefix("127.")
  }
}

final class LLMConfigurationStore {
  static let shared = LLMConfigurationStore()

  private let defaults = UserDefaults.standard
  private let selectedProviderKey = "llm.selectedProvider.v2"
  private let featureAssignmentsKey = "llm.featureAssignments.v1"

  private init() {}

  func selectedProvider() -> LLMProvider {
    guard let raw = defaults.string(forKey: selectedProviderKey),
      let provider = LLMProvider(rawValue: raw)
    else {
      return .deepSeek
    }
    return provider
  }

  func configuration(for provider: LLMProvider) -> LLMConfiguration {
    let key = configurationKey(provider)
    guard let data = defaults.data(forKey: key),
      var configuration = try? JSONDecoder().decode(LLMConfiguration.self, from: data)
    else {
      return .defaults(for: provider)
    }
    configuration.provider = provider
    return configuration
  }

  func save(_ configuration: LLMConfiguration) {
    defaults.set(configuration.provider.rawValue, forKey: selectedProviderKey)
    if let data = try? JSONEncoder().encode(configuration) {
      defaults.set(data, forKey: configurationKey(configuration.provider))
    }
  }

  func save(
    _ configuration: LLMConfiguration,
    assigningTo modes: Set<AnalysisMode>
  ) {
    var assignments = featureAssignments()
    for mode in AnalysisMode.allCases where assignments[mode] == configuration.provider {
      assignments.removeValue(forKey: mode)
    }
    for mode in modes {
      assignments[mode] = configuration.provider
    }
    persist(assignments)
    save(configuration)
  }

  func provider(for mode: AnalysisMode) -> LLMProvider? {
    featureAssignments()[mode]
  }

  func assignedModes(for provider: LLMProvider) -> Set<AnalysisMode> {
    Set(
      featureAssignments().compactMap { mode, assignedProvider in
        assignedProvider == provider ? mode : nil
      })
  }

  func availableModels(for provider: LLMProvider) -> [String] {
    defaults.stringArray(forKey: modelsKey(provider)) ?? []
  }

  func saveAvailableModels(_ models: [String], for provider: LLMProvider) {
    let normalized = Array(
      Set(
        models.compactMap { model -> String? in
          let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
          return value.isEmpty ? nil : value
        })
    ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    defaults.set(normalized, forKey: modelsKey(provider))
  }

  private func featureAssignments() -> [AnalysisMode: LLMProvider] {
    guard let data = defaults.data(forKey: featureAssignmentsKey) else {
      let legacyProvider = selectedProvider()
      return Dictionary(
        uniqueKeysWithValues: AnalysisMode.allCases.map { ($0, legacyProvider) }
      )
    }
    guard let rawAssignments = try? JSONDecoder().decode([String: String].self, from: data) else {
      return [:]
    }
    return rawAssignments.reduce(into: [:]) { result, item in
      guard let mode = AnalysisMode(rawValue: item.key),
        let provider = LLMProvider(rawValue: item.value)
      else { return }
      result[mode] = provider
    }
  }

  private func persist(_ assignments: [AnalysisMode: LLMProvider]) {
    let rawAssignments = Dictionary(
      uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value.rawValue) }
    )
    if let data = try? JSONEncoder().encode(rawAssignments) {
      defaults.set(data, forKey: featureAssignmentsKey)
    }
  }

  private func configurationKey(_ provider: LLMProvider) -> String {
    "llm.configuration.v2.\(provider.rawValue)"
  }

  private func modelsKey(_ provider: LLMProvider) -> String {
    "llm.availableModels.v1.\(provider.rawValue)"
  }
}
