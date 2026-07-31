import Foundation

enum AnalysisMode: String, CaseIterable, Codable, Identifiable {
    case closeReading
    case replies
    case howToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closeReading: "精读"
        case .replies: "怎么回"
        case .howToSay: "How To Say"
        }
    }

    func title(for language: InterfaceLanguage) -> String {
        switch self {
        case .closeReading: language.text("精读", "Close Reading")
        case .replies: language.text("怎么回", "Reply")
        case .howToSay: "How To Say"
        }
    }

    var shortTitle: String {
        switch self {
        case .closeReading: "综合精读"
        case .replies: "自然回复"
        case .howToSay: "表达"
        }
    }

    func shortTitle(for language: InterfaceLanguage) -> String {
        switch self {
        case .closeReading: language.text("综合精读", "Close reading")
        case .replies: language.text("自然回复", "Natural replies")
        case .howToSay: language.text("表达", "Expression")
        }
    }

    var icon: String {
        switch self {
        case .closeReading: "text.book.closed"
        case .replies: "bubble.left.and.bubble.right"
        case .howToSay: "text.bubble"
        }
    }

}

enum Persona: String, Codable, CaseIterable {
    case witty
    case precise
    case warm
    case debating

    var title: String {
        switch self {
        case .witty: "有点幽默"
        case .precise: "严谨认真"
        case .warm: "善良温暖"
        case .debating: "愿意辩一辩"
        }
    }

    func title(for language: InterfaceLanguage) -> String {
        switch self {
        case .witty: language.text("有点幽默", "Witty")
        case .precise: language.text("严谨认真", "Precise")
        case .warm: language.text("善良温暖", "Warm")
        case .debating: language.text("愿意辩一辩", "Debating")
        }
    }

    var icon: String {
        switch self {
        case .witty: "sparkles"
        case .precise: "scope"
        case .warm: "heart"
        case .debating: "quote.bubble"
        }
    }
}

typealias HowToSayTargetLanguage = LearningLanguage

enum HowToSayStyle: String, Codable, CaseIterable {
    case faithful
    case professional
    case polite
    case localSlang = "local_slang"

    var title: String {
        switch self {
        case .faithful: "普通信达雅"
        case .professional: "领域专业"
        case .polite: "地道礼貌"
        case .localSlang: "本土俚语"
        }
    }

    func title(for language: InterfaceLanguage) -> String {
        switch self {
        case .faithful: language.text("普通信达雅", "Faithful")
        case .professional: language.text("领域专业", "Professional")
        case .polite: language.text("地道礼貌", "Natural & polite")
        case .localSlang: language.text("本土俚语", "Local phrasing")
        }
    }

    var icon: String {
        switch self {
        case .faithful: "character.book.closed"
        case .professional: "briefcase"
        case .polite: "hand.wave"
        case .localSlang: "sparkles"
        }
    }
}

struct AnalysisResponse: Codable {
    var closeReading: CloseReadingAnalysis?
    var replyContext: String?
    var replies: [ReplySuggestion]?
    var howToSayContext: String?
    var howToSaySuggestions: [HowToSaySuggestion]?

    enum CodingKeys: String, CodingKey {
        case closeReading = "close_reading"
        case replyContext = "reply_context"
        case replies
        case howToSayContext = "how_to_say_context"
        case howToSaySuggestions = "how_to_say"
    }

    init(
        closeReading: CloseReadingAnalysis? = nil,
        replyContext: String? = nil,
        replies: [ReplySuggestion]? = nil,
        howToSayContext: String? = nil,
        howToSaySuggestions: [HowToSaySuggestion]? = nil
    ) {
        self.closeReading = closeReading
        self.replyContext = replyContext
        self.replies = replies
        self.howToSayContext = howToSayContext
        self.howToSaySuggestions = howToSaySuggestions
    }
}

struct CloseReadingAnalysis: Codable {
    let sourceLanguage: String
    let completeTranslation: String
    let overallTone: String
    let segments: [AnalysisSegment]
    let uncertainty: String
    let segmentPlan: [SourceSegment]
    let deferredSegmentIDs: [String]

    enum CodingKeys: String, CodingKey {
        case sourceLanguage = "source_language"
        case completeTranslation = "complete_translation"
        case overallTone = "overall_tone"
        case segments
        case uncertainty
        case segmentPlan = "segment_plan"
        case deferredSegmentIDs = "deferred_segment_ids"
    }

    init(
        sourceLanguage: String,
        completeTranslation: String,
        overallTone: String,
        segments: [AnalysisSegment],
        uncertainty: String,
        segmentPlan: [SourceSegment] = [],
        deferredSegmentIDs: [String] = []
    ) {
        self.sourceLanguage = sourceLanguage
        self.completeTranslation = completeTranslation
        self.overallTone = overallTone
        self.segments = segments
        self.uncertainty = uncertainty
        self.segmentPlan = segmentPlan
        self.deferredSegmentIDs = deferredSegmentIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? ""
        completeTranslation = try container.decodeIfPresent(String.self, forKey: .completeTranslation) ?? ""
        overallTone = try container.decodeIfPresent(String.self, forKey: .overallTone) ?? ""
        segments = try container.decodeIfPresent([AnalysisSegment].self, forKey: .segments) ?? []
        uncertainty = try container.decodeIfPresent(String.self, forKey: .uncertainty) ?? ""
        segmentPlan = try container.decodeIfPresent([SourceSegment].self, forKey: .segmentPlan)
            ?? segments.map { SourceSegment(id: $0.id, text: $0.source) }
        deferredSegmentIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .deferredSegmentIDs
        ) ?? []
    }
}

struct AISegmentationResponse: Codable, Sendable {
    let segments: [SourceSegment]
}

struct CloseReadingBatchResponse: Codable, Sendable {
    let sourceLanguage: String
    let overallTone: String
    let segments: [AnalysisSegment]

    enum CodingKeys: String, CodingKey {
        case sourceLanguage = "source_language"
        case overallTone = "overall_tone"
        case segments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? ""
        overallTone = try container.decodeIfPresent(String.self, forKey: .overallTone) ?? ""
        segments = try container.decodeIfPresent([AnalysisSegment].self, forKey: .segments) ?? []
    }
}

enum SegmentAnalysisState: Equatable, Sendable {
    case segmenting
    case queued
    case deferred
    case analyzing
    case loaded
    case failed(String)

    var statusText: String {
        switch self {
        case .segmenting: "正在识别语义边界与难度"
        case .queued: "已分句，等待分析"
        case .deferred: "这段较短，已跳过深度分析"
        case .analyzing: "正在分析翻译、词汇、句法和文化线索"
        case .loaded: "分析完成"
        case let .failed(message): "本段分析失败：\(message)"
        }
    }

    func statusText(for language: InterfaceLanguage) -> String {
        switch self {
        case .segmenting:
            language.text("正在识别语义边界与难度", "Detecting semantic boundaries and difficulty")
        case .queued:
            language.text("已分句，等待分析", "Segmented and queued")
        case .deferred:
            language.text("这段较短，已跳过深度分析", "Short segment; deep analysis skipped")
        case .analyzing:
            language.text("正在分析翻译、词汇、句法和文化线索", "Analyzing translation, vocabulary, syntax, and culture")
        case .loaded:
            language.text("分析完成", "Analysis complete")
        case let .failed(message):
            message
        }
    }
}

struct SegmentProgress: Identifiable, Sendable {
    let source: SourceSegment
    var state: SegmentAnalysisState
    var analysis: AnalysisSegment?

    var id: String { source.id }
}

struct AnalysisSegment: Codable, Identifiable, Sendable {
    let id: String
    let source: String
    let translation: String
    let difficultyReason: String
    let vocabulary: [LinguisticVocabulary]
    let syntaxAnalysis: SyntaxAnalysis
    let alternativeParses: [AlternativeParse]
    let historicalContext: [HistoricalContextItem]
    let slangInterpretations: [SlangInterpretation]

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case translation
        case difficultyReason = "difficulty_reason"
        case vocabulary
        case syntaxAnalysis = "syntax_analysis"
        case alternativeParses = "alternative_parses"
        case historicalContext = "historical_context"
        case slangInterpretations = "slang_interpretations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(source.hashValue)-\(translation.hashValue)"
        difficultyReason = try container.decodeIfPresent(String.self, forKey: .difficultyReason) ?? ""
        vocabulary = try container.decodeIfPresent([LinguisticVocabulary].self, forKey: .vocabulary) ?? []
        syntaxAnalysis = try container.decodeIfPresent(SyntaxAnalysis.self, forKey: .syntaxAnalysis)
            ?? SyntaxAnalysis(coreStructure: "", constituents: [], confusingPoints: [])
        alternativeParses = try container.decodeIfPresent([AlternativeParse].self, forKey: .alternativeParses) ?? []
        historicalContext = try container.decodeIfPresent([HistoricalContextItem].self, forKey: .historicalContext) ?? []
        slangInterpretations = try container.decodeIfPresent([SlangInterpretation].self, forKey: .slangInterpretations) ?? []
    }

    init(
        id: String,
        source: String,
        translation: String,
        difficultyReason: String,
        vocabulary: [LinguisticVocabulary],
        syntaxAnalysis: SyntaxAnalysis,
        alternativeParses: [AlternativeParse],
        historicalContext: [HistoricalContextItem],
        slangInterpretations: [SlangInterpretation]
    ) {
        self.id = id
        self.source = source
        self.translation = translation
        self.difficultyReason = difficultyReason
        self.vocabulary = vocabulary
        self.syntaxAnalysis = syntaxAnalysis
        self.alternativeParses = alternativeParses
        self.historicalContext = historicalContext
        self.slangInterpretations = slangInterpretations
    }
}

struct LinguisticVocabulary: Codable, Identifiable, Sendable {
    var id: String { "\(word)-\(baseForm)-\(meaning)" }
    let word: String
    let reading: String
    let baseForm: String
    let partOfSpeech: String
    let conjugation: String
    let meaning: String
    let level: String
    let usage: String
    let distinctUsages: [String]

    enum CodingKeys: String, CodingKey {
        case word
        case reading
        case baseForm = "base_form"
        case partOfSpeech = "part_of_speech"
        case conjugation
        case meaning
        case level
        case usage
        case distinctUsages = "distinct_usages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        reading = try container.decodeIfPresent(String.self, forKey: .reading) ?? ""
        baseForm = try container.decodeIfPresent(String.self, forKey: .baseForm) ?? word
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        conjugation = try container.decodeIfPresent(String.self, forKey: .conjugation) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
        usage = try container.decodeIfPresent(String.self, forKey: .usage) ?? ""
        distinctUsages = try container.decodeIfPresent([String].self, forKey: .distinctUsages) ?? []
    }
}

struct SyntaxAnalysis: Codable, Sendable {
    let coreStructure: String
    let constituents: [SyntaxConstituent]
    let confusingPoints: [String]

    enum CodingKeys: String, CodingKey {
        case coreStructure = "core_structure"
        case constituents
        case confusingPoints = "confusing_points"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coreStructure = try container.decodeIfPresent(String.self, forKey: .coreStructure) ?? ""
        constituents = try container.decodeIfPresent([SyntaxConstituent].self, forKey: .constituents) ?? []
        confusingPoints = try container.decodeIfPresent([String].self, forKey: .confusingPoints) ?? []
    }

    init(coreStructure: String, constituents: [SyntaxConstituent], confusingPoints: [String]) {
        self.coreStructure = coreStructure
        self.constituents = constituents
        self.confusingPoints = confusingPoints
    }
}

struct SyntaxConstituent: Codable, Identifiable, Sendable {
    var id: String { "\(text)-\(role)" }
    let text: String
    let role: String
    let category: SyntaxConstituentCategory
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case text
        case role
        case category
        case explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        category = try container.decodeIfPresent(SyntaxConstituentCategory.self, forKey: .category)
            ?? SyntaxConstituentCategory.inferred(from: role)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    }
}

enum SyntaxConstituentCategory: String, Codable, Sendable {
    case subject
    case predicate
    case object
    case complement
    case modifier
    case clause
    case connector
    case punctuation
    case other

    static func inferred(from role: String) -> Self {
        let normalized = role.lowercased()
        if normalized.contains("主语") || normalized.contains("subject") || normalized.contains("topic") {
            return .subject
        }
        if normalized.contains("谓语") || normalized.contains("动词") || normalized.contains("predicate")
            || normalized.contains("verb") {
            return .predicate
        }
        if normalized.contains("宾语") || normalized.contains("object") {
            return .object
        }
        if normalized.contains("补语") || normalized.contains("表语") || normalized.contains("complement")
            || normalized.contains("predicative") {
            return .complement
        }
        if normalized.contains("从句") || normalized.contains("clause") {
            return .clause
        }
        if normalized.contains("连接") || normalized.contains("连词") || normalized.contains("connector")
            || normalized.contains("conjunction") {
            return .connector
        }
        if normalized.contains("标点") || normalized.contains("破折号") || normalized.contains("括号")
            || normalized.contains("punctuation") {
            return .punctuation
        }
        if normalized.contains("修饰") || normalized.contains("定语") || normalized.contains("状语")
            || normalized.contains("modifier") || normalized.contains("adverbial")
            || normalized.contains("attribute") {
            return .modifier
        }
        return .other
    }
}

struct AlternativeParse: Codable, Identifiable, Sendable {
    var id: String { "\(interpretation)-\(verdict)" }
    let interpretation: String
    let reasoning: String
    let verdict: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interpretation = try container.decodeIfPresent(String.self, forKey: .interpretation) ?? ""
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? ""
    }
}

enum HistoricalContextType: String, Codable, Sendable {
    case historicalOrigin = "historical_origin"
    case chineseComparison = "chinese_comparison"
    case similarOrConfusingUsage = "similar_or_confusing_usage"
    case keyGrammarPoints = "key_grammar_points"
    case culturalConnotation = "cultural_connotation"
    case etymology

    var title: String {
        switch self {
        case .historicalOrigin: "历史渊源"
        case .chineseComparison: "中文对比"
        case .similarOrConfusingUsage: "易混淆"
        case .keyGrammarPoints: "语法知识"
        case .culturalConnotation: "文化语感"
        case .etymology: "词源"
        }
    }

    func title(for language: InterfaceLanguage) -> String {
        switch self {
        case .historicalOrigin: language.text("历史渊源", "Historical origin")
        case .chineseComparison: language.text("中文对比", "Native-language comparison")
        case .similarOrConfusingUsage: language.text("易混淆", "Confusing usage")
        case .keyGrammarPoints: language.text("语法知识", "Grammar")
        case .culturalConnotation: language.text("文化语感", "Cultural nuance")
        case .etymology: language.text("词源", "Etymology")
        }
    }
}

struct HistoricalContextItem: Codable, Identifiable, Sendable {
    var id: String { "\(type.rawValue)-\(content)" }
    let type: HistoricalContextType
    let content: String
    let level: String

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case level
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        type = HistoricalContextType(rawValue: rawType) ?? .culturalConnotation
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
    }
}

struct SlangInterpretation: Codable, Identifiable, Sendable {
    var id: String { "\(expression)-\(literalTranslation)" }
    let expression: String
    let literalTranslation: String
    let usageScenarios: String
    let culturalHistoricalContext: String

    enum CodingKeys: String, CodingKey {
        case expression
        case literalTranslation = "literal_translation"
        case usageScenarios = "usage_scenarios"
        case culturalHistoricalContext = "cultural_historical_context"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expression = try container.decodeIfPresent(String.self, forKey: .expression) ?? ""
        literalTranslation = try container.decodeIfPresent(String.self, forKey: .literalTranslation) ?? ""
        usageScenarios = try container.decodeIfPresent(String.self, forKey: .usageScenarios) ?? ""
        culturalHistoricalContext = try container.decodeIfPresent(
            String.self,
            forKey: .culturalHistoricalContext
        ) ?? ""
    }
}

struct ReplySuggestion: Codable, Identifiable {
    var id: String { "\(persona.rawValue)-\(text)" }
    let persona: Persona
    let text: String
    let chinese: String
    let toneNote: String?

    enum CodingKeys: String, CodingKey {
        case persona
        case text = "reply"
        case legacyEnglish = "english"
        case chinese
        case toneNote = "tone_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        persona = try container.decode(Persona.self, forKey: .persona)
        text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decode(String.self, forKey: .legacyEnglish)
        chinese = try container.decodeIfPresent(String.self, forKey: .chinese) ?? ""
        toneNote = try container.decodeIfPresent(String.self, forKey: .toneNote)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(persona, forKey: .persona)
        try container.encode(text, forKey: .text)
        try container.encode(chinese, forKey: .chinese)
        try container.encodeIfPresent(toneNote, forKey: .toneNote)
    }
}

struct HowToSaySuggestion: Codable, Identifiable {
    var id: String { "\(style.rawValue)-\(translation)" }
    let style: HowToSayStyle
    let translation: String
    let backTranslation: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case style
        case translation
        case backTranslation = "back_translation"
        case note
    }
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
