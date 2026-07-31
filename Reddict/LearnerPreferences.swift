import Foundation

extension Notification.Name {
    static let reddictInterfaceLanguageDidChange = Notification.Name(
        "Reddict.interfaceLanguageDidChange"
    )
}

enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var promptName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese（简体中文）"
        case .english: "English"
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .simplifiedChinese: chinese
        case .english: english
        }
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
        .italian, .portuguese, .russian, .vietnamese, .thai, .indonesian
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
        return interfaceLanguage == .simplifiedChinese ? title : promptName
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
           let legacy = Self.allCases.first(where: { $0.id == legacyID }) {
            self = legacy
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptName = try container.decode(String.self, forKey: .promptName)
        nativeName = try container.decodeIfPresent(String.self, forKey: .nativeName) ?? promptName
        usesJLPT = try container.decodeIfPresent(Bool.self, forKey: .usesJLPT) ?? false
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? id.hasPrefix("custom.")
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

struct LearnerPreferences: Codable, Equatable, Sendable {
    var interfaceLanguage: InterfaceLanguage
    var translationLanguage: LearningLanguage
    var languages: [LanguageProficiency]
    var customLanguages: [LearningLanguage]
    var displayPreference: AnalysisDisplayPreference

    static let defaults = LearnerPreferences(
        interfaceLanguage: .simplifiedChinese,
        translationLanguage: .chinese,
        languages: [
            LanguageProficiency(language: .english, cefr: .b2),
            LanguageProficiency(language: .japanese, jlpt: .n4)
        ],
        customLanguages: [],
        displayPreference: .atOrAboveLevel
    )

    var allLanguages: [LearningLanguage] {
        LearningLanguage.allCases + customLanguages
    }

    var promptDescription: String {
        let levels = languages
            .map { "\($0.language.promptName) \($0.language.usesJLPT ? "JLPT " : "CEFR ")\($0.selectedLevel)" }
            .joined(separator: ", ")
        let configuredLevels = levels.isEmpty ? "No specific learning level configured" : levels
        return """
        Interface and explanation language: \(interfaceLanguage.promptName); \
        translation target language: \(translationLanguage.promptName); \
        learner levels: \(configuredLevels); \(displayPreference.promptDescription)
        """
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
           let itemLevel = JapaneseProficiency(rawValue: normalized) {
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
        case languages
        case customLanguages
        case displayPreference
    }

    init(
        interfaceLanguage: InterfaceLanguage,
        translationLanguage: LearningLanguage,
        languages: [LanguageProficiency],
        customLanguages: [LearningLanguage],
        displayPreference: AnalysisDisplayPreference
    ) {
        self.interfaceLanguage = interfaceLanguage
        self.translationLanguage = translationLanguage
        self.languages = languages
        self.customLanguages = customLanguages
        self.displayPreference = displayPreference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interfaceLanguage = try container.decodeIfPresent(
            InterfaceLanguage.self,
            forKey: .interfaceLanguage
        ) ?? .simplifiedChinese
        translationLanguage = try container.decodeIfPresent(
            LearningLanguage.self,
            forKey: .translationLanguage
        ) ?? .chinese
        languages = try container.decodeIfPresent(
            [LanguageProficiency].self,
            forKey: .languages
        ) ?? Self.defaults.languages
        customLanguages = try container.decodeIfPresent(
            [LearningLanguage].self,
            forKey: .customLanguages
        ) ?? []
        displayPreference = try container.decodeIfPresent(
            AnalysisDisplayPreference.self,
            forKey: .displayPreference
        ) ?? .atOrAboveLevel
    }
}

final class LearnerPreferencesStore {
    static let shared = LearnerPreferencesStore()

    private let key = "learner.preferences.v3"
    private let previousKey = "learner.preferences.v2"
    private let legacyKey = "learner.preferences.v1"
    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> LearnerPreferences {
        if let data = defaults.data(forKey: key),
           let preferences = try? JSONDecoder().decode(LearnerPreferences.self, from: data) {
            return preferences
        }
        if let data = defaults.data(forKey: previousKey),
           let migrated = try? JSONDecoder().decode(LearnerPreferences.self, from: data) {
            save(migrated)
            return migrated
        }
        if let data = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(LegacyPreferences.self, from: data) {
            let migrated = LearnerPreferences(
                interfaceLanguage: .simplifiedChinese,
                translationLanguage: .chinese,
                languages: [
                    LanguageProficiency(
                        language: .english,
                        cefr: legacy.english.cefrEquivalent
                    ),
                    LanguageProficiency(language: .japanese, jlpt: legacy.japanese)
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
