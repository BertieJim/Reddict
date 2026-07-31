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
        precondition(migrated.languages.map(\.language) == [.english, .japanese])

        let latin = LearningLanguage.custom(
            canonicalName: "Latin",
            nativeName: "Latina",
            displayName: "拉丁语"
        )
        let preferences = LearnerPreferences(
            interfaceLanguage: .english,
            translationLanguage: latin,
            languages: [LanguageProficiency(language: latin, cefr: .b1)],
            customLanguages: [latin],
            displayPreference: .all
        )
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(LearnerPreferences.self, from: encoded)

        precondition(decoded == preferences)
        precondition(decoded.promptDescription.contains("Latin"))
        precondition(decoded.promptDescription.contains("English"))
        print("LANGUAGE_PREFERENCES_SMOKE_OK")
    }
}
