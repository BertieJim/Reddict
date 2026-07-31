import AppKit
import CryptoKit
import Foundation

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var selectedText = ""
    @Published var sourceInput = "" {
        didSet {
            guard sourceInput != oldValue, !isSynchronizingSourceInput else { return }
            sourceInputDidChange()
        }
    }
    @Published var activeMode: AnalysisMode = .closeReading
    @Published private(set) var results: [AnalysisMode: AnalysisResponse] = [:]
    @Published private(set) var states: [AnalysisMode: LoadState] = [:]
    @Published private(set) var cacheHits: Set<AnalysisMode> = []
    @Published private(set) var closeReadingProgress: [SegmentProgress] = []
    @Published private(set) var closeReadingStatus = ""
    @Published private(set) var closeReadingFailedCount = 0
    @Published private(set) var closeReadingDeferredCount = 0
    @Published private(set) var closeReadingSourceLanguage = ""

    @Published var isShowingAPISettings = false
    @Published var isShowingHistory = false
    @Published var historyQuery = ""
    @Published private(set) var historyRecords: [HistoryRecord] = []

    @Published var providerDraft: LLMProvider = .deepSeek {
        didSet {
            guard providerDraft != oldValue else { return }
            loadSettingsDraft(for: providerDraft)
        }
    }
    @Published var baseURLDraft = "" {
        didSet { settingsDraftDidChange(from: oldValue, to: baseURLDraft) }
    }
    @Published var modelDraft = "" {
        didSet { settingsDraftDidChange(from: oldValue, to: modelDraft) }
    }
    @Published var useJSONModeDraft = true {
        didSet {
            guard useJSONModeDraft != oldValue else { return }
            invalidateSettingsTest()
        }
    }
    @Published var apiKeyDraft = "" {
        didSet { settingsDraftDidChange(from: oldValue, to: apiKeyDraft) }
    }
    @Published var settingsMessage = ""
    @Published private(set) var isTestingConnection = false
    @Published private(set) var testedSettingsFingerprint: String?
    @Published var languageDrafts: [LanguageProficiency] = LearnerPreferences.defaults.languages
    @Published var interfaceLanguageDraft: InterfaceLanguage = .simplifiedChinese
    @Published var translationLanguageDraft: LearningLanguage = .chinese
    @Published var customLanguageDrafts: [LearningLanguage] = []
    @Published var displayPreferenceDraft: AnalysisDisplayPreference = .atOrAboveLevel
    @Published var learningSettingsMessage = ""
    @Published var customLanguageInput = ""
    @Published var customLanguageMessage = ""
    @Published private(set) var isValidatingCustomLanguage = false

    @Published var howToSayInput = "" {
        didSet {
            guard howToSayInput != oldValue, !isRestoringHistory else { return }
            clearHowToSayResult()
        }
    }
    @Published var howToSayTargetLanguage: HowToSayTargetLanguage = .english {
        didSet {
            guard howToSayTargetLanguage != oldValue, !isRestoringHistory else { return }
            clearHowToSayResult()
        }
    }

    private let client = LLMClient()
    private let configurationStore = LLMConfigurationStore.shared
    private let historyStore = HistoryStore.shared
    private let preferencesStore = LearnerPreferencesStore.shared
    private var activeConfiguration: LLMConfiguration
    @Published private(set) var activePreferences: LearnerPreferences
    private var cachedKeys: [LLMProvider: String] = [:]
    private var tasks: [AnalysisMode: Task<Void, Never>] = [:]
    private var requestIDs: [AnalysisMode: UUID] = [:]
    private var settingsTestTask: Task<Void, Never>?
    private var customLanguageTestTask: Task<Void, Never>?
    private var manualSegmentTasks: [String: Task<Void, Never>] = [:]
    private var isRestoringHistory = false
    private var isSynchronizingSourceInput = false
    private var isLoadingSettingsDraft = false

    init() {
        let provider = configurationStore.selectedProvider()
        activeConfiguration = configurationStore.configuration(for: provider)
        activePreferences = preferencesStore.load()
        providerDraft = provider
        baseURLDraft = activeConfiguration.baseURL
        modelDraft = activeConfiguration.model
        useJSONModeDraft = activeConfiguration.useJSONMode
        if let key = APIKeyStore.shared.apiKey(for: provider) {
            cachedKeys[provider] = key
        }
        apiKeyDraft = cachedKeys[provider] ?? ""
        interfaceLanguageDraft = activePreferences.interfaceLanguage
        translationLanguageDraft = activePreferences.translationLanguage
        languageDrafts = activePreferences.languages
        customLanguageDrafts = activePreferences.customLanguages
        displayPreferenceDraft = activePreferences.displayPreference
        historyRecords = historyStore.records
    }

    var activeState: LoadState {
        states[activeMode] ?? .idle
    }

    var activeResult: AnalysisResponse? {
        results[activeMode]
    }

    var canRunHowToSay: Bool {
        !howToSayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRunManualAnalysis: Bool {
        activeMode != .howToSay
            && !sourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && states[activeMode] != .loading
    }

    var isAnyRequestRunning: Bool {
        !tasks.isEmpty || !manualSegmentTasks.isEmpty
    }

    var hasUnsubmittedManualInput: Bool {
        normalize(sourceInput) != selectedText
    }

    var currentSettingsTestPassed: Bool {
        testedSettingsFingerprint == settingsFingerprint && !isTestingConnection
    }

    var currentModelLabel: String {
        activeConfiguration.displayName
    }

    var availableLearningLanguages: [LearningLanguage] {
        let selected = Set(languageDrafts.map(\.language))
        return languageCatalog.filter { !selected.contains($0) }
    }

    var languageCatalog: [LearningLanguage] {
        LearningLanguage.allCases + customLanguageDrafts
    }

    var howToSayLanguages: [LearningLanguage] {
        activePreferences.allLanguages
    }

    var uiLanguage: InterfaceLanguage {
        activePreferences.interfaceLanguage
    }

    var canValidateCustomLanguage: Bool {
        !customLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isValidatingCustomLanguage
    }

    var filteredHistory: [HistoryRecord] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return historyRecords }
        return historyRecords.filter {
            $0.sourceText.localizedCaseInsensitiveContains(query)
                || $0.model.localizedCaseInsensitiveContains(query)
                || $0.mode.title.localizedCaseInsensitiveContains(query)
        }
    }

    func begin(text: String, mode: AnalysisMode) {
        let normalized = normalize(text)
        if normalized != selectedText {
            cancelAllTasks()
            results.removeAll()
            states.removeAll()
            cacheHits.removeAll()
            clearCloseReadingProgress()
            selectedText = normalized
        }
        synchronizeSourceInput(normalized)
        activeMode = mode
        guard mode != .howToSay else { return }
        analyzeIfNeeded(mode)
    }

    func select(_ mode: AnalysisMode) {
        activeMode = mode
        guard mode != .howToSay else { return }
        guard !hasUnsubmittedManualInput else {
            states[mode] = .idle
            return
        }
        analyzeIfNeeded(mode)
    }

    func runManualAnalysis() {
        guard activeMode != .howToSay else { return }
        let normalized = normalize(sourceInput)
        guard !normalized.isEmpty else {
            states[activeMode] = .failed(uiLanguage.text(
                "先输入或粘贴需要分析的内容。",
                "Type or paste some text to analyze."
            ))
            return
        }
        if normalized != selectedText {
            cancelAllTasks()
            results.removeAll()
            states.removeAll()
            cacheHits.removeAll()
            clearCloseReadingProgress()
            selectedText = normalized
            synchronizeSourceInput(normalized)
        }
        results[activeMode] = nil
        states[activeMode] = .idle
        analyzeIfNeeded(activeMode)
    }

    func retry() {
        if activeMode == .howToSay {
            runHowToSay()
        } else {
            states[activeMode] = .idle
            results[activeMode] = nil
            analyzeIfNeeded(activeMode)
        }
    }

    func runHowToSay() {
        let normalized = normalize(howToSayInput)
        activeMode = .howToSay
        guard !normalized.isEmpty else {
            states[.howToSay] = .failed(uiLanguage.text(
                "先输入你想表达的内容。",
                "Enter what you want to say first."
            ))
            results[.howToSay] = nil
            return
        }
        request(
            text: normalized,
            mode: .howToSay,
            targetLanguage: howToSayTargetLanguage
        )
    }

    func openAPISettings() {
        settingsTestTask?.cancel()
        customLanguageTestTask?.cancel()
        providerDraft = activeConfiguration.provider
        loadSettingsDraft(for: activeConfiguration.provider)
        settingsMessage = ""
        learningSettingsMessage = ""
        customLanguageMessage = ""
        customLanguageInput = ""
        interfaceLanguageDraft = activePreferences.interfaceLanguage
        translationLanguageDraft = activePreferences.translationLanguage
        languageDrafts = activePreferences.languages
        customLanguageDrafts = activePreferences.customLanguages
        displayPreferenceDraft = activePreferences.displayPreference
        isShowingAPISettings = true
    }

    func saveLearningPreferences() {
        let catalog = LearningLanguage.allCases + customLanguageDrafts
        guard catalog.contains(translationLanguageDraft) else {
            learningSettingsMessage = uiLanguage.text(
                "请选择有效的翻译目标语言。",
                "Choose a valid translation target language."
            )
            return
        }
        let preferences = LearnerPreferences(
            interfaceLanguage: interfaceLanguageDraft,
            translationLanguage: translationLanguageDraft,
            languages: languageDrafts,
            customLanguages: customLanguageDrafts,
            displayPreference: displayPreferenceDraft
        )
        activePreferences = preferences
        preferencesStore.save(preferences)
        NotificationCenter.default.post(name: .reddictInterfaceLanguageDidChange, object: nil)
        learningSettingsMessage = interfaceLanguageDraft.text(
            "已保存；界面、解释与新查询会按此设置执行。",
            "Saved. The interface, explanations, and new requests now use these settings."
        )
    }

    func addLearningLanguage(_ language: LearningLanguage) {
        guard !languageDrafts.contains(where: { $0.language == language }) else { return }
        languageDrafts.append(LanguageProficiency(language: language))
        learningSettingsMessage = ""
    }

    func removeLearningLanguage(_ language: LearningLanguage) {
        languageDrafts.removeAll { $0.language == language }
        learningSettingsMessage = ""
    }

    func removeCustomLanguage(_ language: LearningLanguage) {
        guard language.isCustom else { return }
        customLanguageDrafts.removeAll { $0.id == language.id }
        languageDrafts.removeAll { $0.language.id == language.id }
        if translationLanguageDraft.id == language.id {
            translationLanguageDraft = .chinese
        }
        if howToSayTargetLanguage.id == language.id {
            howToSayTargetLanguage = .english
        }
        customLanguageMessage = ""
        learningSettingsMessage = ""
    }

    func validateAndAddCustomLanguage() {
        let candidate = customLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        let duplicate = languageCatalog.first {
            [$0.title, $0.promptName, $0.nativeName]
                .contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
        if let duplicate {
            customLanguageMessage = uiLanguage.text(
                "“\(duplicate.displayName(for: uiLanguage))”已在语言列表中。",
                "\(duplicate.displayName(for: uiLanguage)) is already in the language list."
            )
            return
        }
        guard let apiKey = cachedKeys[activeConfiguration.provider]
                ?? APIKeyStore.shared.apiKey(for: activeConfiguration.provider),
              !apiKey.isEmpty else {
            customLanguageMessage = uiLanguage.text(
                "请先保存一个可用的模型配置和 API Key。",
                "Save a working model configuration and API key first."
            )
            return
        }

        customLanguageTestTask?.cancel()
        isValidatingCustomLanguage = true
        customLanguageMessage = uiLanguage.text(
            "正在让 \(activeConfiguration.displayName) 验证语言与分析能力…",
            "Asking \(activeConfiguration.displayName) to verify the language and its own analysis ability…"
        )
        let configuration = activeConfiguration
        let responseLanguage = interfaceLanguageDraft

        customLanguageTestTask = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await self.client.validateCustomLanguage(
                    candidate,
                    configuration: configuration,
                    apiKey: apiKey,
                    responseLanguage: responseLanguage
                )
                guard !Task.isCancelled else { return }
                self.isValidatingCustomLanguage = false
                self.customLanguageTestTask = nil

                guard result.isRecognizedLanguage, result.isWorthTranslating else {
                    self.customLanguageMessage = result.reason.isEmpty
                        ? responseLanguage.text(
                            "未通过：这不是可供翻译与语言学习的语言名称。",
                            "Not accepted: this is not a language suitable for translation and study."
                        )
                        : result.reason
                    return
                }
                guard result.canUnderstandAndAnalyze else {
                    let recommendation = result.recommendedModelBrand
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedRecommendation = recommendation.lowercased()
                    let refusedRecommendation = recommendation.isEmpty
                        || normalizedRecommendation.contains("cannot")
                        || normalizedRecommendation.contains("can't")
                        || normalizedRecommendation.contains("no recommendation")
                        || recommendation.contains("无法")
                        || recommendation.contains("拒绝")
                    let fallback = refusedRecommendation ? "OpenAI GPT" : recommendation
                    self.customLanguageMessage = responseLanguage.text(
                        "它是一种有效语言，但当前模型无法可靠理解和分析。建议改用：\(fallback)。",
                        "This is a valid language, but the current model cannot analyze it reliably. Suggested model: \(fallback)."
                    )
                    return
                }

                let canonical = result.canonicalName.isEmpty ? candidate : result.canonicalName
                let native = result.nativeName.isEmpty ? canonical : result.nativeName
                let display = result.displayName.isEmpty ? canonical : result.displayName
                let language = LearningLanguage.custom(
                    canonicalName: canonical,
                    nativeName: native,
                    displayName: display
                )
                self.customLanguageDrafts.append(language)
                self.languageDrafts.append(LanguageProficiency(language: language))
                self.customLanguageInput = ""
                self.customLanguageMessage = responseLanguage.text(
                    "验证通过：\(language.displayName(for: responseLanguage))。已加入学习语言；保存后即可使用。",
                    "Verified: \(language.displayName(for: responseLanguage)). It was added as a learning language and will be available after saving."
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.isValidatingCustomLanguage = false
                self?.customLanguageTestTask = nil
                self?.customLanguageMessage = responseLanguage.text(
                    "验证失败：\(error.localizedDescription)",
                    "Validation failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func visibleVocabulary(_ items: [LinguisticVocabulary]) -> [LinguisticVocabulary] {
        items.filter {
            activePreferences.shouldDisplay(
                level: $0.level,
                sourceLanguage: closeReadingSourceLanguage
            )
        }
    }

    func visibleContext(_ items: [HistoricalContextItem]) -> [HistoricalContextItem] {
        items.filter {
            activePreferences.shouldDisplay(
                level: $0.level,
                sourceLanguage: closeReadingSourceLanguage
            )
        }
    }

    func saveAPISettings() {
        guard let (configuration, normalizedKey) = validatedSettingsDraft() else {
            return
        }
        guard currentSettingsTestPassed else {
            settingsMessage = uiLanguage.text(
                "请先点“测试连接”，确认当前配置可以完成模型请求。",
                "Run Test Connection before saving this configuration."
            )
            return
        }
        APIKeyStore.shared.saveAPIKey(normalizedKey, for: providerDraft)
        configurationStore.save(configuration)
        activeConfiguration = configuration
        cachedKeys[providerDraft] = normalizedKey
        settingsMessage = ""
        isShowingAPISettings = false

        if case .failed = activeState {
            retry()
        }
    }

    func testAPISettings() {
        guard let (configuration, apiKey) = validatedSettingsDraft() else { return }
        settingsTestTask?.cancel()
        isTestingConnection = true
        testedSettingsFingerprint = nil
        settingsMessage = interfaceLanguageDraft.text(
            "正在发送一个极小的真实模型请求…",
            "Sending a very small real model request…"
        )
        let fingerprint = settingsFingerprint
        let startedAt = Date()

        settingsTestTask = Task { [weak self] in
            do {
                guard let self else { return }
                let reply = try await self.client.testConnection(
                    configuration: configuration,
                    apiKey: apiKey
                )
                guard !Task.isCancelled, self.settingsFingerprint == fingerprint else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                self.testedSettingsFingerprint = fingerprint
                self.isTestingConnection = false
                self.settingsMessage = self.interfaceLanguageDraft.text(
                    String(format: "连接成功 · %.1f 秒 · 模型回复：%@", elapsed, reply),
                    String(format: "Connected · %.1f s · Model reply: %@", elapsed, reply)
                )
                self.settingsTestTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.testedSettingsFingerprint = nil
                self?.isTestingConnection = false
                self?.settingsMessage = self?.interfaceLanguageDraft.text(
                    "连接失败：\(error.localizedDescription)",
                    "Connection failed: \(error.localizedDescription)"
                ) ?? error.localizedDescription
                self?.settingsTestTask = nil
            }
        }
    }

    func resetProviderDefaults() {
        let defaults = LLMConfiguration.defaults(for: providerDraft)
        baseURLDraft = defaults.baseURL
        modelDraft = defaults.model
        useJSONModeDraft = defaults.useJSONMode
        invalidateSettingsTest()
    }

    func showHistory() {
        historyRecords = historyStore.records
        historyQuery = ""
        isShowingHistory = true
    }

    func restore(_ record: HistoryRecord) {
        cancelAllTasks()
        isRestoringHistory = true
        activeMode = record.mode
        if record.mode == .howToSay {
            howToSayInput = record.sourceText
            howToSayTargetLanguage = record.targetLanguage ?? .english
        } else {
            selectedText = record.sourceText
            synchronizeSourceInput(record.sourceText)
        }
        results = [record.mode: record.response]
        states = [record.mode: .loaded]
        cacheHits = [record.mode]
        clearCloseReadingProgress()
        if record.mode == .closeReading {
            closeReadingStatus = uiLanguage.text(
                "已从查询历史恢复，不消耗 Token。",
                "Restored from history with no token use."
            )
            hydrateCloseReadingProgress(from: record.response)
        }
        isRestoringHistory = false
        isShowingHistory = false
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func analyzeIfNeeded(_ mode: AnalysisMode) {
        guard mode != .howToSay else { return }
        guard results[mode] == nil else { return }
        guard states[mode] != .loading else { return }
        guard !selectedText.isEmpty else {
            states[mode] = .idle
            return
        }
        request(text: selectedText, mode: mode, targetLanguage: nil)
    }

    private func request(
        text: String,
        mode: AnalysisMode,
        targetLanguage: HowToSayTargetLanguage?
    ) {
        if let cached = historyStore.cached(
            text: text,
            mode: mode,
            targetLanguage: targetLanguage
        ), shouldUseCached(cached, for: mode) {
            results[mode] = cached.response
            states[mode] = .loaded
            cacheHits.insert(mode)
            if mode == .closeReading {
                clearCloseReadingProgress()
                closeReadingSourceLanguage = cached.response.closeReading?.sourceLanguage ?? ""
                closeReadingStatus = uiLanguage.text(
                    "已从查询历史恢复，不消耗 Token。",
                    "Restored from history with no token use."
                )
                hydrateCloseReadingProgress(from: cached.response)
            }
            return
        }

        guard let apiKey = cachedKeys[activeConfiguration.provider], !apiKey.isEmpty else {
            states[mode] = .failed(uiLanguage.text(
                "还没有配置 \(activeConfiguration.provider.title) API Key。",
                "No API key is configured for \(activeConfiguration.provider.title)."
            ))
            results[mode] = nil
            return
        }

        tasks[mode]?.cancel()
        states[mode] = .loading
        results[mode] = nil
        cacheHits.remove(mode)
        let configuration = activeConfiguration
        let requestID = UUID()
        requestIDs[mode] = requestID

        if mode == .closeReading {
            startProgressiveCloseReading(
                text: text,
                configuration: configuration,
                apiKey: apiKey,
                requestID: requestID
            )
            return
        }

        tasks[mode] = Task { [weak self] in
            do {
                guard let self else { return }
                let response = try await self.client.analyze(
                    text: text,
                    mode: mode,
                    configuration: configuration,
                    apiKey: apiKey,
                    preferences: self.activePreferences,
                    targetLanguage: targetLanguage
                )
                guard !Task.isCancelled, self.requestIDs[mode] == requestID else { return }
                self.results[mode] = response
                self.states[mode] = .loaded
                _ = self.historyStore.save(
                    text: text,
                    mode: mode,
                    targetLanguage: targetLanguage,
                    response: response,
                    configuration: configuration
                )
                self.historyRecords = self.historyStore.records
                self.tasks[mode] = nil
                self.requestIDs[mode] = nil
            } catch is CancellationError {
                if self?.requestIDs[mode] == requestID,
                   self?.states[mode] == .loading {
                    self?.states[mode] = .idle
                    self?.tasks[mode] = nil
                    self?.requestIDs[mode] = nil
                }
                return
            } catch {
                guard !Task.isCancelled, self?.requestIDs[mode] == requestID else { return }
                self?.states[mode] = .failed(error.localizedDescription)
                self?.tasks[mode] = nil
                self?.requestIDs[mode] = nil
            }
        }
    }

    private func shouldUseCached(_ record: HistoryRecord, for mode: AnalysisMode) -> Bool {
        guard mode == .closeReading,
              let analysis = record.response.closeReading else { return true }
        return !TextSegmenter.containsOrphanListMarker(analysis.segmentPlan)
    }

    private func startProgressiveCloseReading(
        text: String,
        configuration: LLMConfiguration,
        apiKey: String,
        requestID: UUID
    ) {
        let plan = TextSegmenter.plan(text)
        guard !plan.segments.isEmpty else {
            states[.closeReading] = .failed(uiLanguage.text(
                "没有找到可分析的文字。",
                "No text was found to analyze."
            ))
            requestIDs[.closeReading] = nil
            return
        }

        closeReadingProgress = plan.segments.map {
            SegmentProgress(
                source: $0,
                state: plan.requiresAISegmentation ? .segmenting : .queued,
                analysis: nil
            )
        }
        closeReadingFailedCount = 0
        closeReadingDeferredCount = 0
        closeReadingStatus = plan.requiresAISegmentation
            ? uiLanguage.text(
                "这段文字缺少清晰句界，正在识别语义边界并评估难度。",
                "The text lacks clear boundaries; detecting semantic units and difficulty."
            )
            : uiLanguage.text(
                "本地分句完成：\(plan.segments.count) 个语义单元。",
                "Local segmentation complete: \(plan.segments.count) semantic units."
            )

        let client = self.client
        let preferences = activePreferences
        tasks[.closeReading] = Task { [weak self] in
            guard let self else { return }
            var sourceLanguage = ""
            var toneParts: [String] = []
            var completedCount = 0
            var segments = plan.segments
            var usedAISegmentation = false

            if plan.requiresAISegmentation {
                do {
                    let aiSegments = try await client.segmentUnclearText(
                        text,
                        configuration: configuration,
                        apiKey: apiKey,
                        preferences: preferences
                    )
                    guard !Task.isCancelled,
                          self.requestIDs[.closeReading] == requestID else { return }
                    if !aiSegments.isEmpty {
                        segments = aiSegments
                        usedAISegmentation = true
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.closeReadingStatus = self.uiLanguage.text(
                        "语义分段请求未完成，已使用本地结果继续。",
                        "Semantic segmentation did not finish; continuing with the local result."
                    )
                }
            }

            let automaticSegments = segments.filter {
                TextSegmenter.shouldAnalyzeAutomatically(
                    $0,
                    totalTextLength: text.count,
                    usedAISegmentation: usedAISegmentation
                )
            }
            let automaticIDs = Set(automaticSegments.map(\.id))
            self.closeReadingProgress = segments.map {
                SegmentProgress(
                    source: $0,
                    state: automaticIDs.contains($0.id) ? .queued : .deferred,
                    analysis: nil
                )
            }
            self.closeReadingDeferredCount = segments.count - automaticSegments.count
            self.closeReadingStatus = self.selectionStatus(
                total: segments.count,
                automatic: automaticSegments.count,
                usedAI: usedAISegmentation
            )

            let batches = TextSegmenter.batches(from: automaticSegments)

            await withTaskGroup(of: CloseReadingBatchOutcome.self) { group in
                var iterator = batches.makeIterator()
                var activeBatchCount = 0

                for _ in 0..<min(3, batches.count) {
                    guard let batch = iterator.next() else { break }
                    self.mark(batch, as: .analyzing)
                    activeBatchCount += 1
                    group.addTask {
                        do {
                            let response = try await client.analyzeCloseReadingBatch(
                                segments: batch,
                                configuration: configuration,
                                apiKey: apiKey,
                                preferences: preferences
                            )
                            return .success(batch, response)
                        } catch {
                            return .failure(batch, error.localizedDescription)
                        }
                    }
                }

                while let outcome = await group.next() {
                    guard !Task.isCancelled,
                          self.requestIDs[.closeReading] == requestID else {
                        group.cancelAll()
                        return
                    }

                    activeBatchCount -= 1
                    switch outcome {
                    case let .success(batch, response):
                        if sourceLanguage.isEmpty, !response.sourceLanguage.isEmpty {
                            sourceLanguage = response.sourceLanguage
                            self.closeReadingSourceLanguage = response.sourceLanguage
                        }
                        if !response.overallTone.isEmpty,
                           !toneParts.contains(response.overallTone) {
                            toneParts.append(response.overallTone)
                        }
                        self.apply(response, to: batch)
                        completedCount += batch.count
                    case let .failure(batch, message):
                        self.mark(batch, as: .failed(message))
                        self.closeReadingFailedCount += batch.count
                        completedCount += batch.count
                    }

                    if let nextBatch = iterator.next() {
                        self.mark(nextBatch, as: .analyzing)
                        activeBatchCount += 1
                        group.addTask {
                            do {
                                let response = try await client.analyzeCloseReadingBatch(
                                    segments: nextBatch,
                                    configuration: configuration,
                                    apiKey: apiKey,
                                    preferences: preferences
                                )
                                return .success(nextBatch, response)
                            } catch {
                                return .failure(nextBatch, error.localizedDescription)
                            }
                        }
                    }

                    let successful = self.closeReadingProgress.filter {
                        if case .loaded = $0.state { return true }
                        return false
                    }.count
                    if completedCount < automaticSegments.count {
                        self.closeReadingStatus = self.uiLanguage.text(
                            "已完成 \(successful)/\(automaticSegments.count) 个自动分析段；\(activeBatchCount) 个批次正在处理。",
                            "Completed \(successful)/\(automaticSegments.count) automatic segments; \(activeBatchCount) batches are running."
                        )
                    }
                }
            }

            guard !Task.isCancelled,
                  self.requestIDs[.closeReading] == requestID else { return }
            self.finishProgressiveCloseReading(
                text: text,
                configuration: configuration,
                sourceLanguage: sourceLanguage,
                toneParts: toneParts
            )
            self.tasks[.closeReading] = nil
            self.requestIDs[.closeReading] = nil
        }
    }

    func analyzeSegment(_ id: String) {
        guard let index = closeReadingProgress.firstIndex(where: { $0.id == id }),
              closeReadingProgress[index].analysis == nil else { return }
        guard manualSegmentTasks[id] == nil else { return }
        guard let apiKey = cachedKeys[activeConfiguration.provider], !apiKey.isEmpty else {
            closeReadingProgress[index].state = .failed(uiLanguage.text(
                "请先配置 API Key。",
                "Configure an API key first."
            ))
            closeReadingFailedCount += 1
            return
        }

        let source = closeReadingProgress[index].source
        let configuration = activeConfiguration
        let preferences = activePreferences
        cacheHits.remove(.closeReading)
        closeReadingProgress[index].state = .analyzing
        closeReadingStatus = uiLanguage.text(
            "正在单独深度分析第 \(index + 1) 段。",
            "Running deep analysis on segment \(index + 1)."
        )

        manualSegmentTasks[id] = Task { [weak self] in
            do {
                guard let self else { return }
                let response = try await self.client.analyzeCloseReadingBatch(
                    segments: [source],
                    configuration: configuration,
                    apiKey: apiKey,
                    preferences: preferences
                )
                guard !Task.isCancelled else { return }
                if !response.sourceLanguage.isEmpty {
                    self.closeReadingSourceLanguage = response.sourceLanguage
                }
                self.apply(response, to: [source])
                let existing = self.results[.closeReading]?.closeReading
                self.finishProgressiveCloseReading(
                    text: self.selectedText,
                    configuration: configuration,
                    sourceLanguage: response.sourceLanguage.isEmpty
                        ? (existing?.sourceLanguage ?? "")
                        : response.sourceLanguage,
                    toneParts: [existing?.overallTone ?? "", response.overallTone]
                        .filter { !$0.isEmpty }
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      let failedIndex = self?.closeReadingProgress.firstIndex(where: { $0.id == id }) else {
                    return
                }
                self?.closeReadingProgress[failedIndex].state = .failed(error.localizedDescription)
                self?.closeReadingFailedCount += 1
                self?.closeReadingStatus = self?.uiLanguage.text(
                    "这一段未完成；其他结果不受影响。",
                    "This segment did not finish; other results are unaffected."
                ) ?? ""
            }
            self?.manualSegmentTasks[id] = nil
        }
    }

    private func mark(_ batch: [SourceSegment], as state: SegmentAnalysisState) {
        let ids = Set(batch.map(\.id))
        for index in closeReadingProgress.indices where ids.contains(closeReadingProgress[index].id) {
            closeReadingProgress[index].state = state
        }
    }

    private func apply(_ response: CloseReadingBatchResponse, to batch: [SourceSegment]) {
        for (offset, source) in batch.enumerated() {
            let returned = response.segments.first { $0.id == source.id }
                ?? (response.segments.indices.contains(offset) ? response.segments[offset] : nil)
            guard let returned,
                  let index = closeReadingProgress.firstIndex(where: { $0.id == source.id }) else {
                if let index = closeReadingProgress.firstIndex(where: { $0.id == source.id }) {
                    closeReadingProgress[index].state = .failed(uiLanguage.text(
                        "模型漏掉了这一段。",
                        "The model omitted this segment."
                    ))
                    closeReadingFailedCount += 1
                }
                continue
            }
            closeReadingProgress[index].analysis = AnalysisSegment(
                id: source.id,
                source: source.text,
                translation: returned.translation,
                difficultyReason: returned.difficultyReason,
                vocabulary: returned.vocabulary,
                syntaxAnalysis: returned.syntaxAnalysis,
                alternativeParses: returned.alternativeParses,
                historicalContext: returned.historicalContext,
                slangInterpretations: returned.slangInterpretations
            )
            closeReadingProgress[index].state = .loaded
        }
    }

    private func finishProgressiveCloseReading(
        text: String,
        configuration: LLMConfiguration,
        sourceLanguage: String,
        toneParts: [String]
    ) {
        let loadedSegments = closeReadingProgress.compactMap(\.analysis)
        let deferredIDs = closeReadingProgress.compactMap {
            if case .deferred = $0.state { return $0.id }
            return nil
        }
        let failed = closeReadingProgress.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
        closeReadingFailedCount = failed
        closeReadingDeferredCount = deferredIDs.count
        let analysis = CloseReadingAnalysis(
            sourceLanguage: sourceLanguage.isEmpty
                ? uiLanguage.text("自动识别", "Auto-detected")
                : sourceLanguage,
            completeTranslation: loadedSegments
                .map(\.translation)
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            overallTone: toneParts.joined(separator: "；"),
            segments: loadedSegments,
            uncertainty: failed > 0
                ? uiLanguage.text(
                    "有 \(failed) 段未完成；已保留其余结果。",
                    "\(failed) segments did not finish; all other results were kept."
                )
                : "",
            segmentPlan: closeReadingProgress.map(\.source),
            deferredSegmentIDs: deferredIDs
        )
        closeReadingSourceLanguage = analysis.sourceLanguage
        let response = AnalysisResponse(closeReading: analysis)
        results[.closeReading] = response
        states[.closeReading] = .loaded

        if failed == 0 {
            closeReadingStatus = deferredIDs.isEmpty
                ? uiLanguage.text(
                    "全部 \(loadedSegments.count) 段分析完成。",
                    "All \(loadedSegments.count) segments are complete."
                )
                : uiLanguage.text(
                    "已自动分析 \(loadedSegments.count) 段；\(deferredIDs.count) 个短段可按需展开深度分析。",
                    "Automatically analyzed \(loadedSegments.count) segments; \(deferredIDs.count) short segments can be analyzed on demand."
                )
            _ = historyStore.save(
                text: text,
                mode: .closeReading,
                targetLanguage: nil,
                response: response,
                configuration: configuration
            )
            historyRecords = historyStore.records
        } else {
            closeReadingStatus = uiLanguage.text(
                "已完成 \(loadedSegments.count)/\(closeReadingProgress.count) 段；失败部分没有写入缓存。",
                "Completed \(loadedSegments.count)/\(closeReadingProgress.count) segments; failed parts were not cached."
            )
        }
    }

    private func loadSettingsDraft(for provider: LLMProvider) {
        isLoadingSettingsDraft = true
        let configuration = configurationStore.configuration(for: provider)
        baseURLDraft = configuration.baseURL
        modelDraft = configuration.model
        useJSONModeDraft = configuration.useJSONMode
        if cachedKeys[provider] == nil,
           let stored = APIKeyStore.shared.apiKey(for: provider) {
            cachedKeys[provider] = stored
        }
        apiKeyDraft = cachedKeys[provider] ?? ""
        isLoadingSettingsDraft = false
        testedSettingsFingerprint = nil
        isTestingConnection = false
        settingsMessage = ""
    }

    private func validatedSettingsDraft() -> (LLMConfiguration, String)? {
        let normalizedURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURL.isEmpty,
              let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            settingsMessage = interfaceLanguageDraft.text(
                "请填写有效的 HTTP 或 HTTPS API Base URL。",
                "Enter a valid HTTP or HTTPS API Base URL."
            )
            return nil
        }
        guard !normalizedModel.isEmpty else {
            settingsMessage = interfaceLanguageDraft.text(
                "请填写模型名称。",
                "Enter a model name."
            )
            return nil
        }
        guard !normalizedKey.isEmpty else {
            settingsMessage = interfaceLanguageDraft.text(
                "请填写 API Key。",
                "Enter an API key."
            )
            return nil
        }
        return (
            LLMConfiguration(
                provider: providerDraft,
                baseURL: normalizedURL,
                model: normalizedModel,
                useJSONMode: useJSONModeDraft
            ),
            normalizedKey
        )
    }

    private var settingsFingerprint: String {
        let payload = [
            providerDraft.rawValue,
            baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            modelDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            String(useJSONModeDraft)
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func settingsDraftDidChange(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else { return }
        invalidateSettingsTest()
    }

    private func invalidateSettingsTest() {
        guard !isLoadingSettingsDraft else { return }
        settingsTestTask?.cancel()
        settingsTestTask = nil
        testedSettingsFingerprint = nil
        isTestingConnection = false
        settingsMessage = ""
    }

    private func sourceInputDidChange() {
        guard normalize(sourceInput) != selectedText else { return }
        cancelAllTasks()
        results.removeAll()
        states.removeAll()
        cacheHits.removeAll()
        clearCloseReadingProgress()
    }

    private func synchronizeSourceInput(_ text: String) {
        isSynchronizingSourceInput = true
        sourceInput = text
        isSynchronizingSourceInput = false
    }

    private func clearHowToSayResult() {
        if states[.howToSay] == .loading {
            tasks[.howToSay]?.cancel()
            requestIDs[.howToSay] = nil
        }
        results[.howToSay] = nil
        states[.howToSay] = .idle
        cacheHits.remove(.howToSay)
    }

    private func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10_000 else { return trimmed }
        return String(trimmed.prefix(10_000)) + uiLanguage.text(
            "\n[…内容过长，已分析前 10,000 字符]",
            "\n[…Text too long; analyzing the first 10,000 characters]"
        )
    }

    private func cancelAllTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        manualSegmentTasks.values.forEach { $0.cancel() }
        manualSegmentTasks.removeAll()
        requestIDs.removeAll()
    }

    private func clearCloseReadingProgress() {
        closeReadingProgress = []
        closeReadingStatus = ""
        closeReadingFailedCount = 0
        closeReadingDeferredCount = 0
        closeReadingSourceLanguage = ""
    }

    private func selectionStatus(total: Int, automatic: Int, usedAI: Bool) -> String {
        let prefix = usedAI
            ? uiLanguage.text(
                "AI 语义分段与难度评分完成",
                "AI semantic segmentation and difficulty scoring complete"
            )
            : uiLanguage.text("本地分句完成", "Local segmentation complete")
        let deferred = total - automatic
        if deferred == 0 {
            return uiLanguage.text(
                "\(prefix)：\(total) 段都值得自动分析。",
                "\(prefix): all \(total) segments will be analyzed automatically."
            )
        }
        return uiLanguage.text(
            "\(prefix)：自动分析 \(automatic) 段，跳过 \(deferred) 个短/简单段。",
            "\(prefix): analyzing \(automatic) segments and skipping \(deferred) short/simple ones."
        )
    }

    private func hydrateCloseReadingProgress(from response: AnalysisResponse) {
        guard let analysis = response.closeReading else { return }
        closeReadingSourceLanguage = analysis.sourceLanguage
        guard
              !analysis.segmentPlan.isEmpty,
              !analysis.deferredSegmentIDs.isEmpty else { return }
        let loaded = Dictionary(uniqueKeysWithValues: analysis.segments.map { ($0.id, $0) })
        let deferred = Set(analysis.deferredSegmentIDs)
        closeReadingProgress = analysis.segmentPlan.map { source in
            if let segment = loaded[source.id] {
                return SegmentProgress(source: source, state: .loaded, analysis: segment)
            }
            return SegmentProgress(
                source: source,
                state: deferred.contains(source.id)
                    ? .deferred
                    : .failed(uiLanguage.text(
                        "历史记录中缺少本段结果。",
                        "This segment is missing from history."
                    )),
                analysis: nil
            )
        }
        closeReadingDeferredCount = deferred.count
        closeReadingFailedCount = closeReadingProgress.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }
}

private enum CloseReadingBatchOutcome: Sendable {
    case success([SourceSegment], CloseReadingBatchResponse)
    case failure([SourceSegment], String)
}
