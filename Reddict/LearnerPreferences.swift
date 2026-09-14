import Foundation

extension Notification.Name {
  static let reddictInterfaceLanguageDidChange = Notification.Name(
    "Reddict.interfaceLanguageDidChange"
  )
}

struct InterfaceLanguage: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let promptName: String
  let isCustom: Bool

  static let simplifiedChinese = InterfaceLanguage(
    id: "zh-Hans",
    title: "简体中文",
    promptName: "Simplified Chinese（简体中文）",
    isCustom: false
  )
  static let english = InterfaceLanguage(
    id: "en",
    title: "English",
    promptName: "English",
    isCustom: false
  )
  static let allCases: [InterfaceLanguage] = [.simplifiedChinese, .english]

  static func custom(from language: LearningLanguage) -> InterfaceLanguage {
    InterfaceLanguage(
      id: language.id,
      title: language.nativeName == language.promptName
        ? language.promptName
        : "\(language.nativeName) · \(language.promptName)",
      promptName: language.promptName,
      isCustom: true
    )
  }

  func text(_ chinese: String, _ english: String) -> String {
    if self == .simplifiedChinese { return chinese }
    if self == .english { return english }
    return InterfaceLocalizationStore.translation(for: english, languageID: id) ?? english
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case promptName
    case isCustom
  }

  init(id: String, title: String, promptName: String, isCustom: Bool) {
    self.id = id
    self.title = title
    self.promptName = promptName
    self.isCustom = isCustom
  }

  init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let legacyID = try? single.decode(String.self)
    {
      self = legacyID == Self.english.id ? .english : .simplifiedChinese
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedID = try container.decode(String.self, forKey: .id)
    id = decodedID
    title = try container.decode(String.self, forKey: .title)
    promptName = try container.decode(String.self, forKey: .promptName)
    isCustom =
      try container.decodeIfPresent(Bool.self, forKey: .isCustom)
      ?? !Self.allCases.contains(where: { $0.id == decodedID })
  }

  func encode(to encoder: Encoder) throws {
    if !isCustom {
      var container = encoder.singleValueContainer()
      try container.encode(id)
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(promptName, forKey: .promptName)
    try container.encode(isCustom, forKey: .isCustom)
  }
}

enum InterfaceLocalizationStore {
  private static let keyPrefix = "interface.localization.v2."

  static let sourceStrings: [String] = [
    "Settings", "Interface, translation, learning levels, and OpenAI-compatible API",
    "Languages", "App & explanation language", "Close-reading translation",
    "The app language also controls model explanations, reply meanings, and back-translations.",
    "Add app language…", "Translating…",
    "No language is waiting to be added",
    "This language is already available as the app and explanation language.",
    "Save a working API and key for Close Reading before adding an app language.",
    "Generate this interface translation through Add app language first.",
    "The current app language needs a refreshed interface translation. Add it again from Add app language.",
    "Custom languages", "Verified", "Delete from language library",
    "For example: Classical Chinese, Latin, Klingon", "Testing", "Test & Add",
    "One model request checks whether it is a translatable language and whether the current model can analyze it. Failed entries are not saved.",
    "Verified languages are added to your language library. You can then enable them for learning levels, How To Say targets, translation, or the app language.",
    "Learning levels", "About CEFR and JLPT levels", "Add preset language",
    "How To Say styles", "Restore presets", "Add style", "Style name",
    "Only selected styles are generated; unselected styles remain saved. Names appear on result cards, and prompts control tone, context, and wording.",
    "How To Say targets", "Add language",
    "The main screen shows one dropdown; configure its available languages here.",
    "Display", "Analysis results", "Save preferences",
    "Filtering only affects vocabulary, grammar, culture, and etymology items.",
    "Privacy & local data", "Clear history",
    "API configuration & routing", "Provider", "Use for features",
    "Refresh models", "Refreshing", "Choose from discovered models",
    "Test connection", "Testing connection", "Save API & routing",
    "Close Reading", "Reply", "Expression", "History", "Quit Reddict",
    "Analyze Current Clipboard", "Language, Display & API Settings…",
    "Chinese", "English", "Japanese", "Korean", "French", "Spanish", "German",
    "Italian", "Portuguese", "Russian", "Vietnamese", "Thai", "Indonesian",
  ]

  static func translation(for source: String, languageID: String) -> String? {
    translations(for: languageID)[source]
  }

  static func hasTranslations(for languageID: String) -> Bool {
    !translations(for: languageID).isEmpty
  }

  static func save(_ translations: [String: String], for languageID: String) {
    UserDefaults.standard.set(translations, forKey: keyPrefix + languageID)
  }

  static func removeTranslations(for languageID: String) {
    UserDefaults.standard.removeObject(forKey: keyPrefix + languageID)
  }

  private static func translations(for languageID: String) -> [String: String] {
    UserDefaults.standard.dictionary(forKey: keyPrefix + languageID) as? [String: String] ?? [:]
  }
}

enum CEFRLevel: String, Codable, CaseIterable, Identifiable, Sendable {
  case a1 = "A1"
  case a2 = "A2"
  case b1 = "B1"
  case b2 = "B2"
  case c1 = "C1"
  case c2 = "C2"

  var id: String { rawValue }
  var title: String { rawValue }

  var rank: Int {
    switch self {
    case .a1: 1
    case .a2: 2
    case .b1: 3
    case .b2: 4
    case .c1: 5
    case .c2: 6
    }
  }
}

enum JapaneseProficiency: String, Codable, CaseIterable, Identifiable, Sendable {
  case n5 = "N5"
  case n4 = "N4"
  case n3 = "N3"
  case n2 = "N2"
  case n1 = "N1"

  var id: String { rawValue }
  var title: String { rawValue }

  var rank: Int {
    switch self {
    case .n5: 1
    case .n4: 2
    case .n3: 3
    case .n2: 4
    case .n1: 5
    }
  }
}

struct LearningLanguage: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let promptName: String
  let nativeName: String
  let usesJLPT: Bool
  let isCustom: Bool

  private init(
    id: String,
    title: String,
    promptName: String,
    nativeName: String,
    usesJLPT: Bool,
    isCustom: Bool
  ) {
    self.id = id
    self.title = title
    self.promptName = promptName
    self.nativeName = nativeName
    self.usesJLPT = usesJLPT
    self.isCustom = isCustom
  }

  static let chinese = builtin("chinese", "中文", "Chinese", "中文")
  static let english = builtin("english", "英语", "English", "English")
  static let japanese = builtin("japanese", "日语", "Japanese", "日本語", usesJLPT: true)
  static let korean = builtin("korean", "韩语", "Korean", "한국어")
  static let french = builtin("french", "法语", "French", "Français")
  static let spanish = builtin("spanish", "西班牙语", "Spanish", "Español")
  static let german = builtin("german", "德语", "German", "Deutsch")
  static let italian = builtin("italian", "意大利语", "Italian", "Italiano")
  static let portuguese = builtin("portuguese", "葡萄牙语", "Portuguese", "Português")
  static let russian = builtin("russian", "俄语", "Russian", "Русский")
  static let vietnamese = builtin("vietnamese", "越南语", "Vietnamese", "Tiếng Việt")
  static let thai = builtin("thai", "泰语", "Thai", "ภาษาไทย")
  static let indonesian = builtin("indonesian", "印度尼西亚语", "Indonesian", "Bahasa Indonesia")

  static let allCases: [LearningLanguage] = [
    .chinese, .english, .japanese, .korean, .french, .spanish, .german,
    .italian, .portuguese, .russian, .vietnamese, .thai, .indonesian,
  ]

  static func custom(
    canonicalName: String,
    nativeName: String,
    displayName: String
  ) -> LearningLanguage {
    LearningLanguage(
      id: "custom.\(UUID().uuidString.lowercased())",
      title: displayName,
      promptName: canonicalName,
      nativeName: nativeName.isEmpty ? canonicalName : nativeName,
      usesJLPT: false,
      isCustom: true
    )
  }

  func displayName(for interfaceLanguage: InterfaceLanguage) -> String {
    if isCustom {
      return nativeName == promptName ? promptName : "\(nativeName) · \(promptName)"
    }
    return interfaceLanguage.text(title, promptName)
  }

  func matches(_ sourceLanguage: String) -> Bool {
    let normalized = sourceLanguage.lowercased()
    let names = [title, promptName, nativeName]
    return names.contains { normalized.contains($0.lowercased()) }
  }

  private static func builtin(
    _ id: String,
    _ title: String,
    _ promptName: String,
    _ nativeName: String,
    usesJLPT: Bool = false
  ) -> LearningLanguage {
    LearningLanguage(
      id: id,
      title: title,
      promptName: promptName,
      nativeName: nativeName,
      usesJLPT: usesJLPT,
      isCustom: false
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case promptName
    case nativeName
    case usesJLPT
    case isCustom
  }

  init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let legacyID = try? single.decode(String.self),
      let legacy = Self.allCases.first(where: { $0.id == legacyID })
    {
      self = legacy
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    promptName = try container.decode(String.self, forKey: .promptName)
    nativeName = try container.decodeIfPresent(String.self, forKey: .nativeName) ?? promptName
    usesJLPT = try container.decodeIfPresent(Bool.self, forKey: .usesJLPT) ?? false
    isCustom =
      try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? id.hasPrefix("custom.")
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(promptName, forKey: .promptName)
    try container.encode(nativeName, forKey: .nativeName)
    try container.encode(usesJLPT, forKey: .usesJLPT)
    try container.encode(isCustom, forKey: .isCustom)
  }
}

struct LanguageProficiency: Codable, Equatable, Identifiable, Sendable {
  var language: LearningLanguage
  var cefr: CEFRLevel
  var jlpt: JapaneseProficiency

  var id: String { language.id }
  var selectedLevel: String { language.usesJLPT ? jlpt.rawValue : cefr.rawValue }

  init(
    language: LearningLanguage,
    cefr: CEFRLevel = .b2,
    jlpt: JapaneseProficiency = .n4
  ) {
    self.language = language
    self.cefr = cefr
    self.jlpt = jlpt
  }
}

enum AnalysisDisplayPreference: String, Codable, CaseIterable, Identifiable, Sendable {
  case atOrAboveLevel
  case all

  var id: String { rawValue }

  func title(for language: InterfaceLanguage) -> String {
    switch self {
    case .atOrAboveLevel:
      language.text("只显示本水平以上分析结果", "Show results at or above my level")
    case .all:
      language.text("显示全部分析结果", "Show all analysis results")
    }
  }

  var promptDescription: String {
    switch self {
    case .atOrAboveLevel:
      "Only return analysis items at or above the learner's configured level."
    case .all:
      "Do not hide useful analysis items by level, but still exclude insignificant function words."
    }
  }
}

struct HowToSayStyleProfile: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var prompt: String
  var icon: String
  var isEnabled: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case prompt
    case icon
    case isEnabled
  }

  init(
    id: String,
    name: String,
    prompt: String,
    icon: String,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.name = name
    self.prompt = prompt
    self.icon = icon
    self.isEnabled = isEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    prompt = try container.decode(String.self, forKey: .prompt)
    icon = try container.decode(String.self, forKey: .icon)
    // Styles saved by versions before the checkbox existed remain selected.
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
  }

  static let defaults: [HowToSayStyleProfile] = [
    HowToSayStyleProfile(
      id: "faithful",
      name: "普通信达雅",
      prompt: "忠实保留原意、语气和信息密度，同时表达自然顺口；不要擅自补充原文没有的信息。",
      icon: "character.book.closed"
    ),
    HowToSayStyleProfile(
      id: "professional",
      name: "领域专业",
      prompt: "根据内容选择合适领域的专业用语和清晰结构；领域不明确时按通用工作语境处理，并在说明中写明假设。",
      icon: "briefcase"
    ),
    HowToSayStyleProfile(
      id: "polite",
      name: "地道礼貌",
      prompt: "使用目标语言中自然、得体而不过度谦卑的礼貌表达，准确处理距离感、敬意和语气。",
      icon: "hand.wave"
    ),
    HowToSayStyleProfile(
      id: "local_slang",
      name: "本土俚语",
      prompt: "写成当地人自然使用的当代口语；不要堆砌网络黑话或文化刻板印象，不适合俚语时改为自然口语并说明。",
      icon: "sparkles"
    ),
    HowToSayStyleProfile(
      id: "voice_polish",
      name: "口述精炼",
      prompt:
        "沿用 audioGo 的语音转写清洗规则：把口述内容整理成简洁、可直接使用的目标语言表达。保留真实意图和每项要求，不回答内容、不补充事实；删除填充词、口头重复和错误开头，采用用户后说的自我修正；修复明显听错的技术术语、文件路径、命令、参数和口述符号；技术标识符保持原样。多个独立请求使用简短编号列表，单一请求保持自然紧凑。",
      icon: "waveform.badge.mic"
    ),
  ]

  static func custom() -> HowToSayStyleProfile {
    HowToSayStyleProfile(
      id: "custom.\(UUID().uuidString.lowercased())",
      name: "自定义文风",
      prompt: "描述希望模型采用的语气、场景、用词和表达方式。",
      icon: "slider.horizontal.3"
    )
  }
}

struct LearnerPreferences: Codable, Equatable, Sendable {
  var interfaceLanguage: InterfaceLanguage
  var translationLanguage: LearningLanguage
  var howToSayLanguages: [LearningLanguage]
  var howToSayStyles: [HowToSayStyleProfile]
  var languages: [LanguageProficiency]
  var customLanguages: [LearningLanguage]
  var displayPreference: AnalysisDisplayPreference

  static let defaults = LearnerPreferences(
    interfaceLanguage: .simplifiedChinese,
    translationLanguage: .chinese,
    howToSayLanguages: LearningLanguage.allCases,
    howToSayStyles: HowToSayStyleProfile.defaults,
    languages: [
      LanguageProficiency(language: .english, cefr: .b2),
      LanguageProficiency(language: .japanese, jlpt: .n4),
    ],
    customLanguages: [],
    displayPreference: .atOrAboveLevel
  )

  var allLanguages: [LearningLanguage] {
    LearningLanguage.allCases + customLanguages
  }

  var enabledHowToSayStyles: [HowToSayStyleProfile] {
    let styles = howToSayStyles.isEmpty ? HowToSayStyleProfile.defaults : howToSayStyles
    return styles.filter(\.isEnabled)
  }

  var promptDescription: String {
    let levels =
      languages
      .map {
        "\($0.language.promptName) \($0.language.usesJLPT ? "JLPT " : "CEFR ")\($0.selectedLevel)"
      }
      .joined(separator: ", ")
    let configuredLevels = levels.isEmpty ? "No specific learning level configured" : levels
    return """
      Interface and explanation language: \(interfaceLanguage.promptName); \
      translation target language: \(translationLanguage.promptName); \
      learner levels: \(configuredLevels); \(displayPreference.promptDescription)
      """
  }

  var cacheDescription: String {
    let styles =
      howToSayStyles
      .map { "\($0.id):\($0.isEnabled):\($0.name):\($0.prompt)" }
      .joined(separator: "|")
    return "\(promptDescription); how-to-say styles: \(styles)"
  }

  func profile(matching sourceLanguage: String, level: String) -> LanguageProficiency? {
    if level.uppercased().hasPrefix("N") {
      return languages.first { $0.language == .japanese }
    }
    return languages.first { $0.language.matches(sourceLanguage) }
  }

  func shouldDisplay(level: String, sourceLanguage: String) -> Bool {
    guard displayPreference == .atOrAboveLevel else { return true }
    let normalized = level.uppercased()
    guard let profile = profile(matching: sourceLanguage, level: normalized) else {
      return true
    }
    if profile.language.usesJLPT,
      let itemLevel = JapaneseProficiency(rawValue: normalized)
    {
      return itemLevel.rank >= profile.jlpt.rank
    }
    if let itemLevel = CEFRLevel(rawValue: normalized) {
      return itemLevel.rank >= profile.cefr.rank
    }
    return true
  }

  private enum CodingKeys: String, CodingKey {
    case interfaceLanguage
    case translationLanguage
    case howToSayLanguages
    case howToSayStyles
    case languages
    case customLanguages
    case displayPreference
  }

  init(
    interfaceLanguage: InterfaceLanguage,
    translationLanguage: LearningLanguage,
    howToSayLanguages: [LearningLanguage] = LearningLanguage.allCases,
    howToSayStyles: [HowToSayStyleProfile] = HowToSayStyleProfile.defaults,
    languages: [LanguageProficiency],
    customLanguages: [LearningLanguage],
    displayPreference: AnalysisDisplayPreference
  ) {
    self.interfaceLanguage = interfaceLanguage
    self.translationLanguage = translationLanguage
    self.howToSayLanguages = howToSayLanguages
    self.howToSayStyles = howToSayStyles
    self.languages = languages
    self.customLanguages = customLanguages
    self.displayPreference = displayPreference
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    interfaceLanguage =
      try container.decodeIfPresent(
        InterfaceLanguage.self,
        forKey: .interfaceLanguage
      ) ?? .simplifiedChinese
    translationLanguage =
      try container.decodeIfPresent(
        LearningLanguage.self,
        forKey: .translationLanguage
      ) ?? .chinese
    customLanguages =
      try container.decodeIfPresent(
        [LearningLanguage].self,
        forKey: .customLanguages
      ) ?? []
    let savedHowToSayLanguages = try container.decodeIfPresent(
      [LearningLanguage].self,
      forKey: .howToSayLanguages
    )
    howToSayLanguages =
      savedHowToSayLanguages
      ?? (LearningLanguage.allCases + customLanguages)
    howToSayStyles =
      try container.decodeIfPresent(
        [HowToSayStyleProfile].self,
        forKey: .howToSayStyles
      ) ?? HowToSayStyleProfile.defaults
    languages =
      try container.decodeIfPresent(
        [LanguageProficiency].self,
        forKey: .languages
      ) ?? Self.defaults.languages
    displayPreference =
      try container.decodeIfPresent(
        AnalysisDisplayPreference.self,
        forKey: .displayPreference
      ) ?? .atOrAboveLevel
  }
}

final class LearnerPreferencesStore {
  static let shared = LearnerPreferencesStore()

  private let key = "learner.preferences.v4"
  private let previousKey = "learner.preferences.v3"
  private let olderKey = "learner.preferences.v2"
  private let legacyKey = "learner.preferences.v1"
  private let defaults = UserDefaults.standard

  private init() {}

  func load() -> LearnerPreferences {
    if let data = defaults.data(forKey: key),
      let preferences = try? JSONDecoder().decode(LearnerPreferences.self, from: data)
    {
      return preferences
    }
    if let data = defaults.data(forKey: previousKey),
      var migrated = try? JSONDecoder().decode(LearnerPreferences.self, from: data)
    {
      // Add the audioGo-derived preset exactly once during the v3 → v4
      // migration. If the user later deletes it from v4, it stays deleted.
      if !migrated.howToSayStyles.contains(where: { $0.id == "voice_polish" }),
        let voiceStyle = HowToSayStyleProfile.defaults.first(where: {
          $0.id == "voice_polish"
        })
      {
        migrated.howToSayStyles.append(voiceStyle)
      }
      save(migrated)
      return migrated
    }
    if let data = defaults.data(forKey: olderKey),
      let migrated = try? JSONDecoder().decode(LearnerPreferences.self, from: data)
    {
      save(migrated)
      return migrated
    }
    if let data = defaults.data(forKey: legacyKey),
      let legacy = try? JSONDecoder().decode(LegacyPreferences.self, from: data)
    {
      let migrated = LearnerPreferences(
        interfaceLanguage: .simplifiedChinese,
        translationLanguage: .chinese,
        languages: [
          LanguageProficiency(
            language: .english,
            cefr: legacy.english.cefrEquivalent
          ),
          LanguageProficiency(language: .japanese, jlpt: legacy.japanese),
        ],
        customLanguages: [],
        displayPreference: .atOrAboveLevel
      )
      save(migrated)
      return migrated
    }
    return .defaults
  }

  func save(_ preferences: LearnerPreferences) {
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: key)
  }
}

private struct LegacyPreferences: Codable {
  let english: LegacyEnglishProficiency
  let japanese: JapaneseProficiency
}

private enum LegacyEnglishProficiency: Int, Codable {
  case toefl40 = 40
  case toefl55 = 55
  case toefl70 = 70
  case toefl85 = 85
  case toefl100 = 100

  var cefrEquivalent: CEFRLevel {
    switch self {
    case .toefl40: .a2
    case .toefl55: .b1
    case .toefl70, .toefl85: .b2
    case .toefl100: .c1
    }
  }
}
