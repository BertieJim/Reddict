import Foundation

@main
struct LanguagePreferencesSmoke {
  static func main() throws {
    let legacyV2 = """
      {
        "languages": [
          {"language":"english","cefr":"B2","jlpt":"N4"},
          {"language":"japanese","cefr":"B2","jlpt":"N3"}
        ],
        "displayPreference":"atOrAboveLevel"
      }
      """.data(using: .utf8)!

    let migrated = try JSONDecoder().decode(LearnerPreferences.self, from: legacyV2)
    precondition(migrated.interfaceLanguage == .simplifiedChinese)
    precondition(migrated.translationLanguage == .chinese)
    precondition(migrated.howToSayLanguages == LearningLanguage.allCases)
    precondition(migrated.howToSayStyles == HowToSayStyleProfile.defaults)
    precondition(migrated.howToSayStyles.allSatisfy(\.isEnabled))
    precondition(migrated.languages.map(\.language) == [.english, .japanese])

    let styleWithoutCheckbox = """
      {
        "interfaceLanguage":"zh-Hans",
        "translationLanguage":{"id":"english","title":"英语","promptName":"English","nativeName":"English","usesJLPT":false,"isCustom":false},
        "howToSayStyles":[{"id":"legacy","name":"旧文风","prompt":"保留原意","icon":"text.quote"}],
        "languages":[],
        "customLanguages":[],
        "displayPreference":"all"
      }
      """.data(using: .utf8)!
    let decodedLegacyStyle = try JSONDecoder().decode(
      LearnerPreferences.self,
      from: styleWithoutCheckbox
    )
    precondition(decodedLegacyStyle.howToSayStyles.first?.isEnabled == true)

    let latin = LearningLanguage.custom(
      canonicalName: "Latin",
      nativeName: "Latina",
      displayName: "拉丁语"
    )
    let latinInterface = InterfaceLanguage.custom(from: latin)
    let preferences = LearnerPreferences(
      interfaceLanguage: latinInterface,
      translationLanguage: latin,
      howToSayLanguages: [latin, .english],
      howToSayStyles: [
        HowToSayStyleProfile(
          id: "custom.test",
          name: "学术简洁",
          prompt: "使用简洁、克制的学术表达。",
          icon: "slider.horizontal.3",
          isEnabled: false
        )
      ],
      languages: [LanguageProficiency(language: latin, cefr: .b1)],
      customLanguages: [latin],
      displayPreference: .all
    )
    let encoded = try JSONEncoder().encode(preferences)
    let decoded = try JSONDecoder().decode(LearnerPreferences.self, from: encoded)

    precondition(decoded == preferences)
    precondition(decoded.interfaceLanguage == latinInterface)
    precondition(decoded.interfaceLanguage.promptName == "Latin")
    InterfaceLocalizationStore.save(["Settings": "Optiones"], for: latinInterface.id)
    precondition(latinInterface.text("设置", "Settings") == "Optiones")
    InterfaceLocalizationStore.removeTranslations(for: latinInterface.id)
    precondition(latinInterface.text("设置", "Settings") == "Settings")
    precondition(decoded.howToSayLanguages == [latin, .english])
    precondition(decoded.howToSayStyles == preferences.howToSayStyles)
    precondition(decoded.howToSayStyles.first?.isEnabled == false)
    precondition(decoded.enabledHowToSayStyles.isEmpty)
    precondition(decoded.promptDescription.contains("Latin"))
    print("LANGUAGE_PREFERENCES_SMOKE_OK")
  }
}
