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
  @Published private(set) var priorityTranslation: PriorityTranslationResponse?
  @Published private(set) var selectedCloseReadingSegmentID: String?

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
    didSet {
      settingsDraftDidChange(from: oldValue, to: baseURLDraft)
      guard baseURLDraft != oldValue, !isLoadingSettingsDraft else { return }
      availableModelDrafts = []
      modelListMessage = ""
    }
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
  @Published var featureAssignmentsDraft: Set<AnalysisMode> = Set(AnalysisMode.allCases)
  @Published private(set) var availableModelDrafts: [String] = []
  @Published private(set) var isRefreshingModels = false
  @Published private(set) var modelListHasError = false
  @Published var modelListMessage = ""
  @Published var settingsMessage = ""
  @Published private(set) var isTestingConnection = false
  @Published private(set) var testedSettingsFingerprint: String?
  @Published var languageDrafts: [LanguageProficiency] = LearnerPreferences.defaults.languages
  @Published var interfaceLanguageDraft: InterfaceLanguage = .simplifiedChinese
  @Published var translationLanguageDraft: LearningLanguage = .chinese
  @Published var howToSayLanguageDrafts: [LearningLanguage] = LearningLanguage.allCases
  @Published var howToSayStyleDrafts: [HowToSayStyleProfile] = HowToSayStyleProfile.defaults
  @Published var customLanguageDrafts: [LearningLanguage] = []
  @Published var displayPreferenceDraft: AnalysisDisplayPreference = .atOrAboveLevel
  @Published var learningSettingsMessage = ""
  @Published var customLanguageInput = ""
  @Published var customLanguageMessage = ""
  @Published private(set) var isValidatingCustomLanguage = false
  @Published private(set) var isPreparingInterfaceLanguage = false
  @Published private(set) var preparingInterfaceLanguageID: String?
  @Published var interfaceLanguageMessage = ""

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
  @Published private(set) var voiceInputPhase: VoiceInputPhase = .idle
  @Published var voiceInputMessage = ""

  private let client = LLMClient()
  private let configurationStore = LLMConfigurationStore.shared
  private let historyStore = HistoryStore.shared
  private let preferencesStore = LearnerPreferencesStore.shared
  @Published private(set) var activePreferences: LearnerPreferences
  private var cachedKeys: [LLMProvider: String] = [:]
  private var tasks: [AnalysisMode: Task<Void, Never>] = [:]
  private var requestIDs: [AnalysisMode: UUID] = [:]
  private var settingsTestTask: Task<Void, Never>?
  private var modelListTask: Task<Void, Never>?
  private var customLanguageTestTask: Task<Void, Never>?
  private var interfaceLocalizationTask: Task<Void, Never>?
  private var manualSegmentTasks: [String: Task<Void, Never>] = [:]
  private var isRestoringHistory = false
  private var isSynchronizingSourceInput = false
  private var isLoadingSettingsDraft = false
  private let voiceTranscriber = VoiceInputTranscriber()
  private var voiceInputPrefix = ""

  init() {
    let provider = configurationStore.selectedProvider()
    let configuration = configurationStore.configuration(for: provider)
    activePreferences = preferencesStore.load()
    providerDraft = provider
    baseURLDraft = configuration.baseURL
    modelDraft = configuration.model
    useJSONModeDraft = configuration.useJSONMode
    featureAssignmentsDraft = configurationStore.assignedModes(for: provider)
    if let key = APIKeyStore.shared.apiKey(for: provider) {
      cachedKeys[provider] = key
    }
    apiKeyDraft = cachedKeys[provider] ?? ""
    interfaceLanguageDraft = activePreferences.interfaceLanguage
    translationLanguageDraft = activePreferences.translationLanguage
    howToSayLanguageDrafts = activePreferences.howToSayLanguages
    howToSayStyleDrafts = activePreferences.howToSayStyles
    languageDrafts = activePreferences.languages
    customLanguageDrafts = activePreferences.customLanguages
    displayPreferenceDraft = activePreferences.displayPreference
    if !activePreferences.howToSayLanguages.contains(howToSayTargetLanguage),
      let firstTarget = activePreferences.howToSayLanguages.first
    {
      howToSayTargetLanguage = firstTarget
    }
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
      && !activePreferences.enabledHowToSayStyles.isEmpty
      && voiceInputPhase == .idle
  }

  var isRecordingVoiceInput: Bool { voiceInputPhase == .recording }

  var isFinishingVoiceInput: Bool {
    voiceInputPhase == .requestingPermission || voiceInputPhase == .transcribing
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

  var canSaveAPISettings: Bool {
    currentSettingsTestPassed || persistedSettingsFingerprint == settingsFingerprint
  }

  var canRefreshModels: Bool {
    !isRefreshingModels
      && !baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var modelPickerOptions: [String] {
    let selected = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if !selected.isEmpty, !availableModelDrafts.contains(selected) {
      return [selected] + availableModelDrafts
    }
    return availableModelDrafts
  }

  var currentModelLabel: String {
    guard let provider = configurationStore.provider(for: activeMode) else {
      return uiLanguage.text(
        "\(activeMode.title) · 未分配 API", "\(activeMode.title(for: uiLanguage)) · No API")
    }
    let configuration = configurationStore.configuration(for: provider)
    return "\(activeMode.shortTitle(for: uiLanguage)) · \(configuration.displayName)"
  }

  var availableLearningLanguages: [LearningLanguage] {
    let selected = Set(languageDrafts.map(\.language))
    return languageCatalog.filter { !selected.contains($0) }
  }

  var languageCatalog: [LearningLanguage] {
    LearningLanguage.allCases + customLanguageDrafts
  }

  var interfaceLanguageCatalog: [InterfaceLanguage] {
    InterfaceLanguage.allCases + languageCatalog
      .filter { $0.id != LearningLanguage.chinese.id && $0.id != LearningLanguage.english.id }
      .map(InterfaceLanguage.custom(from:))
      .filter { InterfaceLocalizationStore.hasTranslations(for: $0.id) }
  }

  var availableInterfaceLanguages: [LearningLanguage] {
    languageCatalog.filter { language in
      language.id != LearningLanguage.chinese.id
        && language.id != LearningLanguage.english.id
        && !InterfaceLocalizationStore.hasTranslations(for: language.id)
    }
  }

  var howToSayLanguages: [LearningLanguage] {
    activePreferences.howToSayLanguages
  }

  var availableHowToSayLanguages: [LearningLanguage] {
    let selected = Set(howToSayLanguageDrafts.map(\.id))
    return languageCatalog.filter { !selected.contains($0.id) }
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

  var historyCount: Int { historyRecords.count }

  var historyFileIsPrivate: Bool { historyStore.hasPrivateFilePermissions }

  var isShowingCompleteTranslation: Bool {
    selectedCloseReadingSegmentID == nil
  }

  func showCompleteTranslation() {
    selectedCloseReadingSegmentID = nil
  }

  func selectCloseReadingSegment(_ id: String) {
    guard closeReadingProgress.contains(where: { $0.id == id }) else { return }
    selectedCloseReadingSegmentID = id
  }

  func closeReadingTranslation(for id: String) -> String {
    if let aligned = closeReadingTranslationMap()[id], !aligned.isEmpty {
      return aligned
    }
    return closeReadingProgress.first(where: { $0.id == id })?.analysis?.translation ?? ""
  }

  func begin(text: String, mode: AnalysisMode) {
    let normalized = normalize(text)
    isShowingAPISettings = false
    isShowingHistory = false

    if mode == .howToSay {
      if voiceInputPhase != .idle {
        cancelHowToSayVoiceInput()
      }
      activeMode = .howToSay
      if !normalized.isEmpty {
        howToSayInput = normalized
      }
      return
    }

    if voiceInputPhase != .idle {
      cancelHowToSayVoiceInput()
    }
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
    if mode != .howToSay, voiceInputPhase != .idle {
      cancelHowToSayVoiceInput()
    }
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
      states[activeMode] = .failed(
        uiLanguage.text(
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
      states[.howToSay] = .failed(
        uiLanguage.text(
          "先输入你想表达的内容。",
          "Enter what you want to say first."
        ))
      results[.howToSay] = nil
      return
    }
    guard !activePreferences.enabledHowToSayStyles.isEmpty else {
      states[.howToSay] = .failed(
        uiLanguage.text(
          "请先在设置中至少启用一个 How To Say 文风。",
          "Enable at least one How To Say style in Settings first."
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

  func toggleHowToSayVoiceInput() {
    switch voiceInputPhase {
    case .recording:
      Task { await stopHowToSayVoiceInput() }
    case .idle:
      Task { await startHowToSayVoiceInput() }
    case .requestingPermission, .transcribing:
      break
    }
  }

  private func startHowToSayVoiceInput() async {
    voiceInputPhase = .requestingPermission
    voiceInputMessage = uiLanguage.text("正在请求麦克风权限…", "Requesting microphone access…")
    voiceInputPrefix = howToSayInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let localeID = preferredSpeechLocaleID
    do {
      try await voiceTranscriber.start(localeID: localeID) { [weak self] text in
        guard let self else { return }
        self.howToSayInput = self.composedVoiceInput(text)
      }
      let languageName = SpeechLocaleResolver.displayName(
        for: localeID,
        interfaceLanguage: uiLanguage
      )
      voiceInputMessage = uiLanguage.text(
        "正在听（\(languageName)）；再次点话筒结束",
        "Listening in \(languageName); click the mic again to finish"
      )
      voiceInputPhase = .recording
    } catch {
      voiceInputPhase = .idle
      voiceInputMessage = error.localizedDescription
      voiceInputPrefix = ""
    }
  }

  private func stopHowToSayVoiceInput() async {
    voiceInputPhase = .transcribing
    voiceInputMessage = uiLanguage.text("正在完成转写…", "Finishing transcription…")
    do {
      let transcript = try await voiceTranscriber.stop()
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if transcript.isEmpty {
        voiceInputMessage = uiLanguage.text(
          "没有听清内容，请靠近话筒再试一次。",
          "Nothing was recognized. Try again closer to the microphone."
        )
      } else {
        howToSayInput = composedVoiceInput(transcript)
        voiceInputMessage = uiLanguage.text("转写完成", "Transcription ready")
      }
    } catch {
      voiceInputMessage = error.localizedDescription
    }
    voiceInputPhase = .idle
    voiceInputPrefix = ""
  }

  private func cancelHowToSayVoiceInput() {
    voiceTranscriber.cancel()
    voiceInputPhase = .idle
    voiceInputMessage = ""
    voiceInputPrefix = ""
  }

  private func composedVoiceInput(_ transcript: String) -> String {
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !voiceInputPrefix.isEmpty else { return text }
    guard !text.isEmpty else { return voiceInputPrefix }
    return voiceInputPrefix + "\n" + text
  }

  private var preferredSpeechLocaleID: String {
    SpeechLocaleResolver.localeID(
      interfaceLanguage: activePreferences.interfaceLanguage,
      existingText: howToSayInput
    )
  }

  func openAPISettings() {
    if voiceInputPhase != .idle {
      cancelHowToSayVoiceInput()
    }
    settingsTestTask?.cancel()
    modelListTask?.cancel()
    customLanguageTestTask?.cancel()
    interfaceLocalizationTask?.cancel()
    interfaceLocalizationTask = nil
    isPreparingInterfaceLanguage = false
    preparingInterfaceLanguageID = nil
    let provider = configurationStore.selectedProvider()
    providerDraft = provider
    loadSettingsDraft(for: provider)
    settingsMessage = ""
    learningSettingsMessage = ""
    customLanguageMessage = ""
    interfaceLanguageMessage = ""
    customLanguageInput = ""
    customLanguageDrafts = activePreferences.customLanguages
    let savedInterfaceLanguage = activePreferences.interfaceLanguage
    if savedInterfaceLanguage.isCustom,
      !InterfaceLocalizationStore.hasTranslations(for: savedInterfaceLanguage.id)
    {
      interfaceLanguageDraft = .simplifiedChinese
      interfaceLanguageMessage = uiLanguage.text(
        "当前软件语言需要重新生成界面译文，请从“增加软件语言”中添加。",
        "The current app language needs a refreshed interface translation. Add it again from Add app language."
      )
    } else {
      interfaceLanguageDraft = savedInterfaceLanguage
    }
    translationLanguageDraft = activePreferences.translationLanguage
    howToSayLanguageDrafts = activePreferences.howToSayLanguages
    howToSayStyleDrafts = activePreferences.howToSayStyles
    languageDrafts = activePreferences.languages
    displayPreferenceDraft = activePreferences.displayPreference
    isShowingAPISettings = true
  }

  func saveLearningPreferences() {
    let catalog = LearningLanguage.allCases + customLanguageDrafts
    let interfaceCatalog = interfaceLanguageCatalog
    guard interfaceCatalog.contains(interfaceLanguageDraft) else {
      learningSettingsMessage = uiLanguage.text(
        "请选择有效的软件与解释语言。",
        "Choose a valid app and explanation language."
      )
      return
    }
    if interfaceLanguageDraft.isCustom,
      !InterfaceLocalizationStore.hasTranslations(for: interfaceLanguageDraft.id)
    {
      learningSettingsMessage = uiLanguage.text(
        "请先通过“增加软件语言”生成该语言的界面译文。",
        "Generate this interface translation through Add app language first."
      )
      return
    }
    guard catalog.contains(translationLanguageDraft) else {
      learningSettingsMessage = uiLanguage.text(
        "请选择有效的翻译目标语言。",
        "Choose a valid translation target language."
      )
      return
    }
    guard !howToSayLanguageDrafts.isEmpty,
      howToSayLanguageDrafts.allSatisfy({ catalog.contains($0) })
    else {
      learningSettingsMessage = uiLanguage.text(
        "请至少保留一个有效的 How To Say 目标语言。",
        "Keep at least one valid How To Say target language."
      )
      return
    }
    let normalizedStyles = howToSayStyleDrafts.map { style in
      HowToSayStyleProfile(
        id: style.id,
        name: style.name.trimmingCharacters(in: .whitespacesAndNewlines),
        prompt: style.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
        icon: style.icon,
        isEnabled: style.isEnabled
      )
    }
    guard !normalizedStyles.isEmpty,
      normalizedStyles.allSatisfy({ !$0.name.isEmpty && !$0.prompt.isEmpty }),
      Set(normalizedStyles.map(\.id)).count == normalizedStyles.count
    else {
      learningSettingsMessage = interfaceLanguageDraft.text(
        "请至少保留一个文风，并填写每个文风的名称和 Prompt。",
        "Keep at least one style and fill in every style name and prompt."
      )
      return
    }
    guard normalizedStyles.contains(where: \.isEnabled) else {
      learningSettingsMessage = interfaceLanguageDraft.text(
        "请至少勾选一个参与生成的文风。未勾选的文风仍会保留。",
        "Select at least one style to generate. Unselected styles are still kept."
      )
      return
    }
    let preferences = LearnerPreferences(
      interfaceLanguage: interfaceLanguageDraft,
      translationLanguage: translationLanguageDraft,
      howToSayLanguages: howToSayLanguageDrafts,
      howToSayStyles: normalizedStyles,
      languages: languageDrafts,
      customLanguages: customLanguageDrafts,
      displayPreference: displayPreferenceDraft
    )
    activePreferences = preferences
    howToSayStyleDrafts = normalizedStyles
    clearHowToSayResult()
    if !preferences.howToSayLanguages.contains(howToSayTargetLanguage),
      let firstTarget = preferences.howToSayLanguages.first
    {
      howToSayTargetLanguage = firstTarget
    }
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

  func addHowToSayLanguage(_ language: LearningLanguage) {
    guard !howToSayLanguageDrafts.contains(where: { $0.id == language.id }) else { return }
    howToSayLanguageDrafts.append(language)
    learningSettingsMessage = ""
  }

  func removeHowToSayLanguage(_ language: LearningLanguage) {
    guard howToSayLanguageDrafts.count > 1 else {
      learningSettingsMessage = interfaceLanguageDraft.text(
        "How To Say 至少需要一个目标语言。",
        "How To Say needs at least one target language."
      )
      return
    }
    howToSayLanguageDrafts.removeAll { $0.id == language.id }
    learningSettingsMessage = ""
  }

  func addHowToSayStyle() {
    howToSayStyleDrafts.append(.custom())
    learningSettingsMessage = ""
  }

  func removeHowToSayStyle(id: String) {
    guard howToSayStyleDrafts.count > 1 else {
      learningSettingsMessage = interfaceLanguageDraft.text(
        "How To Say 至少需要一个文风。",
        "How To Say needs at least one style."
      )
      return
    }
    howToSayStyleDrafts.removeAll { $0.id == id }
    learningSettingsMessage = ""
  }

  func resetHowToSayStyles() {
    howToSayStyleDrafts = HowToSayStyleProfile.defaults
    learningSettingsMessage = ""
  }

  func howToSayStyleProfile(for id: String) -> HowToSayStyleProfile? {
    activePreferences.howToSayStyles.first { $0.id == id }
      ?? HowToSayStyleProfile.defaults.first { $0.id == id }
  }

  func setFeatureAssignment(_ mode: AnalysisMode, enabled: Bool) {
    if enabled {
      featureAssignmentsDraft.insert(mode)
    } else {
      featureAssignmentsDraft.remove(mode)
    }
  }

  func removeCustomLanguage(_ language: LearningLanguage) {
    guard language.isCustom else { return }
    if preparingInterfaceLanguageID == language.id {
      interfaceLocalizationTask?.cancel()
      interfaceLocalizationTask = nil
      preparingInterfaceLanguageID = nil
      isPreparingInterfaceLanguage = false
      interfaceLanguageMessage = ""
    }
    if interfaceLanguageDraft.id == language.id {
      interfaceLanguageDraft = .simplifiedChinese
    }
    InterfaceLocalizationStore.removeTranslations(for: language.id)
    customLanguageDrafts.removeAll { $0.id == language.id }
    languageDrafts.removeAll { $0.language.id == language.id }
    howToSayLanguageDrafts.removeAll { $0.id == language.id }
    if howToSayLanguageDrafts.isEmpty {
      howToSayLanguageDrafts = [.english]
    }
    if translationLanguageDraft.id == language.id {
      translationLanguageDraft = .chinese
    }
    if howToSayTargetLanguage.id == language.id,
      let firstTarget = howToSayLanguageDrafts.first
    {
      howToSayTargetLanguage = firstTarget
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
    let validationConfiguration = configurationStore.configuration(for: providerDraft)
    guard let apiKey = apiKey(for: providerDraft),
      !apiKey.isEmpty
    else {
      customLanguageMessage = uiLanguage.text(
        "请先保存一个可用的模型配置和 API Key。",
        "Save a working model configuration and API key first."
      )
      return
    }

    customLanguageTestTask?.cancel()
    isValidatingCustomLanguage = true
    customLanguageMessage = uiLanguage.text(
      "正在让 \(validationConfiguration.displayName) 验证语言与分析能力…",
      "Asking \(validationConfiguration.displayName) to verify the language and its own analysis ability…"
    )
    let configuration = validationConfiguration
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
          self.customLanguageMessage =
            result.reason.isEmpty
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
          let refusedRecommendation =
            recommendation.isEmpty
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
        self.customLanguageInput = ""
        self.customLanguageMessage = responseLanguage.text(
          "验证通过：\(language.displayName(for: responseLanguage)) 已加入语言库。现在可按需添加到各个列表。",
          "Verified: \(language.displayName(for: responseLanguage)) is now in the language library and can be enabled where needed."
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

  func addInterfaceLanguage(_ learningLanguage: LearningLanguage) {
    interfaceLocalizationTask?.cancel()
    interfaceLanguageMessage = ""
    let language = InterfaceLanguage.custom(from: learningLanguage)
    if InterfaceLocalizationStore.hasTranslations(for: language.id) {
      isPreparingInterfaceLanguage = false
      preparingInterfaceLanguageID = nil
      interfaceLanguageMessage = uiLanguage.text(
        "该语言已经可以作为软件与解释语言使用。",
        "This language is already available as the app and explanation language."
      )
      return
    }
    guard let provider = configurationStore.provider(for: .closeReading),
      let apiKey = apiKey(for: provider),
      !apiKey.isEmpty
    else {
      isPreparingInterfaceLanguage = false
      preparingInterfaceLanguageID = nil
      interfaceLanguageMessage = uiLanguage.text(
        "请先为精读功能保存可用的 API 与 Key，再增加软件语言。",
        "Save a working API and key for Close Reading before adding an app language."
      )
      return
    }

    let configuration = configurationStore.configuration(for: provider)
    isPreparingInterfaceLanguage = true
    preparingInterfaceLanguageID = language.id
    interfaceLanguageMessage = uiLanguage.text(
      "正在把软件界面翻译为 \(learningLanguage.displayName(for: uiLanguage))…",
      "Translating the app interface into \(learningLanguage.displayName(for: uiLanguage))…"
    )
    interfaceLocalizationTask = Task { [weak self] in
      do {
        guard let self else { return }
        let translations = try await self.client.translateInterfaceStrings(
          InterfaceLocalizationStore.sourceStrings,
          to: language,
          configuration: configuration,
          apiKey: apiKey
        )
        guard !Task.isCancelled, self.preparingInterfaceLanguageID == language.id else { return }
        InterfaceLocalizationStore.save(translations, for: language.id)
        self.isPreparingInterfaceLanguage = false
        self.preparingInterfaceLanguageID = nil
        self.interfaceLocalizationTask = nil
        self.interfaceLanguageMessage = self.uiLanguage.text(
          "\(learningLanguage.displayName(for: self.uiLanguage)) 已翻译完成，现在可以在软件语言列表中选择。",
          "\(learningLanguage.displayName(for: self.uiLanguage)) is ready and can now be selected from the app language list."
        )
        self.objectWillChange.send()
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.isPreparingInterfaceLanguage = false
        self?.preparingInterfaceLanguageID = nil
        self?.interfaceLocalizationTask = nil
        self?.interfaceLanguageMessage =
          self?.uiLanguage.text(
            "界面翻译失败：\(error.localizedDescription)",
            "Interface translation failed: \(error.localizedDescription)"
          ) ?? error.localizedDescription
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
    guard canSaveAPISettings else {
      settingsMessage = uiLanguage.text(
        "请先点“测试连接”，确认当前配置可以完成模型请求。",
        "Run Test Connection before saving this configuration."
      )
      return
    }
    APIKeyStore.shared.saveAPIKey(normalizedKey, for: providerDraft)
    configurationStore.save(configuration, assigningTo: featureAssignmentsDraft)
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
        self?.settingsMessage =
          self?.interfaceLanguageDraft.text(
            "连接失败：\(error.localizedDescription)",
            "Connection failed: \(error.localizedDescription)"
          ) ?? error.localizedDescription
        self?.settingsTestTask = nil
      }
    }
  }

  func refreshModels() {
    let normalizedURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: normalizedURL),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else {
      modelListHasError = true
      modelListMessage = interfaceLanguageDraft.text(
        "请先填写有效的 API Base URL。",
        "Enter a valid API Base URL first."
      )
      return
    }
    let discoveryConfiguration = LLMConfiguration(
      provider: providerDraft,
      baseURL: normalizedURL,
      model: modelDraft.trimmingCharacters(in: .whitespacesAndNewlines),
      useJSONMode: useJSONModeDraft
    )
    guard discoveryConfiguration.isCredentialTransportSecure else {
      modelListHasError = true
      modelListMessage = interfaceLanguageDraft.text(
        "为防止 API Key 被窃听，远程地址必须使用 HTTPS；HTTP 只允许 localhost/127.0.0.1。",
        "Remote APIs must use HTTPS to protect the key; HTTP is only allowed for localhost/127.0.0.1."
      )
      return
    }
    guard !normalizedKey.isEmpty else {
      modelListHasError = true
      modelListMessage = interfaceLanguageDraft.text(
        "请先填写 API Key。",
        "Enter the API key first."
      )
      return
    }

    modelListTask?.cancel()
    isRefreshingModels = true
    modelListHasError = false
    modelListMessage = interfaceLanguageDraft.text(
      "正在读取供应商模型列表…",
      "Loading the provider model list…"
    )
    let configuration = discoveryConfiguration
    let provider = providerDraft
    modelListTask = Task { [weak self] in
      do {
        guard let self else { return }
        let models = try await self.client.listModels(
          configuration: configuration,
          apiKey: normalizedKey
        )
        guard !Task.isCancelled, self.providerDraft == provider else { return }
        self.availableModelDrafts = models
        self.configurationStore.saveAvailableModels(models, for: provider)
        if self.modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let first = models.first
        {
          self.modelDraft = first
        }
        self.isRefreshingModels = false
        self.modelListHasError = false
        self.modelListMessage = self.interfaceLanguageDraft.text(
          "已发现 \(models.count) 个模型，请从下拉列表选择。",
          "Found \(models.count) models. Choose one from the menu."
        )
        self.modelListTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.isRefreshingModels = false
        self?.modelListHasError = true
        self?.modelListMessage =
          self?.interfaceLanguageDraft.text(
            "刷新失败：\(error.localizedDescription)",
            "Refresh failed: \(error.localizedDescription)"
          ) ?? error.localizedDescription
        self?.modelListTask = nil
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

  func clearHistory() {
    if historyStore.clear() {
      historyRecords = []
      historyQuery = ""
    }
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
    guard let provider = configurationStore.provider(for: mode) else {
      states[mode] = .failed(
        uiLanguage.text(
          "还没有为“\(mode.title)”分配 API，请在设置中选择。",
          "No API is assigned to \(mode.title(for: uiLanguage)); choose one in Settings."
        ))
      results[mode] = nil
      return
    }
    let configuration = configurationStore.configuration(for: provider)
    if let cached = historyStore.cached(
      text: text,
      mode: mode,
      targetLanguage: targetLanguage,
      configuration: configuration
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

    guard let apiKey = apiKey(for: provider) else {
      states[mode] = .failed(
        uiLanguage.text(
          "\(provider.title) 还没有保存 API Key。",
          "No API key is saved for \(provider.title)."
        ))
      results[mode] = nil
      return
    }

    tasks[mode]?.cancel()
    states[mode] = .loading
    results[mode] = nil
    cacheHits.remove(mode)
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
          self?.states[mode] == .loading
        {
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
      let analysis = record.response.closeReading
    else { return true }
    guard !TextSegmenter.containsOrphanListMarker(analysis.segmentPlan) else { return false }

    let currentPlan = TextSegmenter.plan(record.sourceText)
    guard !currentPlan.requiresAISegmentation else { return true }
    let cachedShape = analysis.segmentPlan.map {
      ($0.text, $0.paragraphIndex)
    }
    let currentShape = currentPlan.segments.map {
      ($0.text, $0.paragraphIndex)
    }
    return cachedShape.elementsEqual(currentShape) {
      $0.0 == $1.0 && $0.1 == $1.1
    }
  }

  private func startProgressiveCloseReading(
    text: String,
    configuration: LLMConfiguration,
    apiKey: String,
    requestID: UUID
  ) {
    let plan = TextSegmenter.plan(text)
    guard !plan.segments.isEmpty else {
      states[.closeReading] = .failed(
        uiLanguage.text(
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
    priorityTranslation = nil
    selectedCloseReadingSegmentID = nil
    closeReadingStatus = uiLanguage.text(
      "本地分句已就绪；正在优先生成整段译文。",
      "Local segmentation is ready; generating the full translation first."
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

      do {
        let overview = try await client.translatePriorityOverview(
          text: plan.normalizedText,
          configuration: configuration,
          apiKey: apiKey,
          preferences: preferences
        )
        guard !Task.isCancelled,
          self.requestIDs[.closeReading] == requestID
        else { return }
        self.priorityTranslation = overview
        if !overview.sourceLanguage.isEmpty {
          sourceLanguage = overview.sourceLanguage
          self.closeReadingSourceLanguage = overview.sourceLanguage
        }
        if !overview.overallTone.isEmpty {
          toneParts = [overview.overallTone]
        }
        self.closeReadingStatus =
          plan.requiresAISegmentation
          ? self.uiLanguage.text(
            "整段译文已显示；正在识别语义边界并评估难度。",
            "Full translation is ready; detecting semantic boundaries and difficulty."
          )
          : self.uiLanguage.text(
            "整段译文已显示；正在启动逐段深度分析。",
            "Full translation is ready; starting detailed segment analysis."
          )
      } catch {
        guard !Task.isCancelled,
          self.requestIDs[.closeReading] == requestID
        else { return }
        self.closeReadingStatus = self.uiLanguage.text(
          "整段译文请求未完成；继续逐段分析并在完成后合成译文。",
          "The priority translation did not finish; continuing with segment analysis and fallback translation."
        )
      }

      if plan.requiresAISegmentation {
        do {
          let aiSegments = try await client.segmentUnclearText(
            plan.normalizedText,
            configuration: configuration,
            apiKey: apiKey,
            preferences: preferences
          )
          guard !Task.isCancelled,
            self.requestIDs[.closeReading] == requestID
          else { return }
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
          totalTextLength: plan.normalizedText.count,
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
      if let selectedID = self.selectedCloseReadingSegmentID,
        !segments.contains(where: { $0.id == selectedID })
      {
        self.selectedCloseReadingSegmentID = nil
      }
      self.closeReadingDeferredCount = segments.count - automaticSegments.count
      self.closeReadingStatus = self.selectionStatus(
        total: segments.count,
        automatic: automaticSegments.count,
        usedAI: usedAISegmentation
      )

      let batches = TextSegmenter.batches(from: automaticSegments)
      let translationsBySegmentID = self.closeReadingTranslationMap()

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
                translationsBySegmentID: translationsBySegmentID,
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
            self.requestIDs[.closeReading] == requestID
          else {
            group.cancelAll()
            return
          }

          activeBatchCount -= 1
          switch outcome {
          case .success(let batch, let response):
            if sourceLanguage.isEmpty, !response.sourceLanguage.isEmpty {
              sourceLanguage = response.sourceLanguage
              self.closeReadingSourceLanguage = response.sourceLanguage
            }
            if !response.overallTone.isEmpty,
              !toneParts.contains(response.overallTone)
            {
              toneParts.append(response.overallTone)
            }
            self.apply(response, to: batch)
            completedCount += batch.count
          case .failure(let batch, let message):
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
                  translationsBySegmentID: translationsBySegmentID,
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
        self.requestIDs[.closeReading] == requestID
      else { return }
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
      closeReadingProgress[index].analysis == nil
    else { return }
    guard manualSegmentTasks[id] == nil else { return }
    guard let provider = configurationStore.provider(for: .closeReading) else {
      closeReadingProgress[index].state = .failed(
        uiLanguage.text(
          "请先为精读分配 API。",
          "Assign an API to Close Reading first."
        ))
      closeReadingFailedCount += 1
      return
    }
    guard let apiKey = apiKey(for: provider) else {
      closeReadingProgress[index].state = .failed(
        uiLanguage.text(
          "请先配置 \(provider.title) API Key。",
          "Configure the \(provider.title) API key first."
        ))
      closeReadingFailedCount += 1
      return
    }

    let source = closeReadingProgress[index].source
    let configuration = configurationStore.configuration(for: provider)
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
          translationsBySegmentID: self.closeReadingTranslationMap(),
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
          let failedIndex = self?.closeReadingProgress.firstIndex(where: { $0.id == id })
        else {
          return
        }
        self?.closeReadingProgress[failedIndex].state = .failed(error.localizedDescription)
        self?.closeReadingFailedCount += 1
        self?.closeReadingStatus =
          self?.uiLanguage.text(
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
      let returned =
        response.segments.first { $0.id == source.id }
        ?? (response.segments.indices.contains(offset) ? response.segments[offset] : nil)
      guard let returned,
        let index = closeReadingProgress.firstIndex(where: { $0.id == source.id })
      else {
        if let index = closeReadingProgress.firstIndex(where: { $0.id == source.id }) {
          closeReadingProgress[index].state = .failed(
            uiLanguage.text(
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
        translation: closeReadingTranslationMap()[source.id] ?? returned.translation,
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
      completeTranslation: priorityTranslation?.completeTranslation
        ?? loadedSegments
        .map(\.translation)
        .filter { !$0.isEmpty }
        .joined(separator: "\n"),
      overallTone: priorityTranslation?.overallTone.isEmpty == false
        ? (priorityTranslation?.overallTone ?? "")
        : toneParts.joined(separator: "；"),
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
    if priorityTranslation == nil,
      !analysis.completeTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      priorityTranslation = PriorityTranslationResponse(
        sourceLanguage: analysis.sourceLanguage,
        completeTranslation: analysis.completeTranslation,
        overallTone: analysis.overallTone
      )
    }
    let response = AnalysisResponse(closeReading: analysis)
    results[.closeReading] = response
    states[.closeReading] = .loaded

    if failed == 0 {
      closeReadingStatus =
        deferredIDs.isEmpty
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
    modelListTask?.cancel()
    isLoadingSettingsDraft = true
    let configuration = configurationStore.configuration(for: provider)
    baseURLDraft = configuration.baseURL
    modelDraft = configuration.model
    useJSONModeDraft = configuration.useJSONMode
    if cachedKeys[provider] == nil,
      let stored = APIKeyStore.shared.apiKey(for: provider)
    {
      cachedKeys[provider] = stored
    }
    apiKeyDraft = cachedKeys[provider] ?? ""
    featureAssignmentsDraft = configurationStore.assignedModes(for: provider)
    availableModelDrafts = configurationStore.availableModels(for: provider)
    isLoadingSettingsDraft = false
    testedSettingsFingerprint = nil
    isTestingConnection = false
    settingsMessage = ""
    modelListMessage = ""
    modelListHasError = false
    isRefreshingModels = false
  }

  private func validatedSettingsDraft() -> (LLMConfiguration, String)? {
    let normalizedURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedModel = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedURL.isEmpty,
      let url = URL(string: normalizedURL),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else {
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
    let configuration = LLMConfiguration(
      provider: providerDraft,
      baseURL: normalizedURL,
      model: normalizedModel,
      useJSONMode: useJSONModeDraft
    )
    guard configuration.isCredentialTransportSecure else {
      settingsMessage = interfaceLanguageDraft.text(
        "为防止 API Key 被窃听，远程地址必须使用 HTTPS；HTTP 只允许 localhost/127.0.0.1。",
        "Remote APIs must use HTTPS to protect the key; HTTP is only allowed for localhost/127.0.0.1."
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
      configuration,
      normalizedKey
    )
  }

  private var settingsFingerprint: String {
    let payload = [
      providerDraft.rawValue,
      baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines),
      modelDraft.trimmingCharacters(in: .whitespacesAndNewlines),
      apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
      String(useJSONModeDraft),
    ].joined(separator: "\u{1F}")
    return SHA256.hash(data: Data(payload.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private var persistedSettingsFingerprint: String? {
    guard let storedKey = APIKeyStore.shared.apiKey(for: providerDraft) else { return nil }
    let configuration = configurationStore.configuration(for: providerDraft)
    let payload = [
      providerDraft.rawValue,
      configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
      storedKey,
      String(configuration.useJSONMode),
    ].joined(separator: "\u{1F}")
    return SHA256.hash(data: Data(payload.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func apiKey(for provider: LLMProvider) -> String? {
    if let cached = cachedKeys[provider], !cached.isEmpty {
      return cached
    }
    guard let stored = APIKeyStore.shared.apiKey(for: provider), !stored.isEmpty else {
      return nil
    }
    cachedKeys[provider] = stored
    return stored
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
    return String(trimmed.prefix(10_000))
      + uiLanguage.text(
        "\n[…内容过长，已分析前 10,000 字符]",
        "\n[…Text too long; analyzing the first 10,000 characters]"
      )
  }

  private func cancelAllTasks() {
    for task in tasks.values {
      task.cancel()
    }
    tasks.removeAll()
    for task in manualSegmentTasks.values {
      task.cancel()
    }
    manualSegmentTasks.removeAll()
    requestIDs.removeAll()
  }

  private func clearCloseReadingProgress() {
    closeReadingProgress = []
    closeReadingStatus = ""
    closeReadingFailedCount = 0
    closeReadingDeferredCount = 0
    closeReadingSourceLanguage = ""
    priorityTranslation = nil
    selectedCloseReadingSegmentID = nil
  }

  private func closeReadingTranslationMap() -> [String: String] {
    let completeTranslation =
      priorityTranslation?.completeTranslation
      ?? results[.closeReading]?.closeReading?.completeTranslation
      ?? ""
    return TextSegmenter.alignedTranslations(
      from: completeTranslation,
      to: closeReadingProgress.map(\.source)
    )
  }

  private func selectionStatus(total: Int, automatic: Int, usedAI: Bool) -> String {
    let prefix =
      usedAI
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
    priorityTranslation = PriorityTranslationResponse(
      sourceLanguage: analysis.sourceLanguage,
      completeTranslation: analysis.completeTranslation,
      overallTone: analysis.overallTone
    )
    guard !analysis.segmentPlan.isEmpty else { return }
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
          : .failed(
            uiLanguage.text(
              "历史记录中缺少本段结果。",
              "This segment is missing from history."
            )),
        analysis: nil
      )
    }
    closeReadingDeferredCount = deferred.count
    closeReadingFailedCount =
      closeReadingProgress.filter {
        if case .failed = $0.state { return true }
        return false
      }.count
  }
}

private enum CloseReadingBatchOutcome: Sendable {
  case success([SourceSegment], CloseReadingBatchResponse)
  case failure([SourceSegment], String)
}
