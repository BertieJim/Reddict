import AppKit
import SwiftUI

struct AnalysisView: View {
    @ObservedObject var viewModel: AnalysisViewModel
    @State private var isShowingLevelHelp = false
    @State private var isShowingJSONModeHelp = false

    private let coral = Color(red: 1.0, green: 0.31, blue: 0.20)
    private let ink = Color.primary.opacity(0.92)

    private func ui(_ chinese: String, _ english: String) -> String {
        viewModel.uiLanguage.text(chinese, english)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.30, blue: 0.58).opacity(0.16),
                    coral.opacity(0.09),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                topTextBox
                modePicker
                content
                footer
            }
            .padding(.top, 8)

            if viewModel.isShowingAPISettings {
                apiSettingsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if viewModel.isShowingHistory {
                historyOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(minWidth: 500, minHeight: 580)
        .animation(.snappy(duration: 0.25), value: viewModel.isShowingAPISettings)
        .animation(.snappy(duration: 0.25), value: viewModel.isShowingHistory)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(coral.gradient)
                Image(systemName: "quote.opening")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: coral.opacity(0.25), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text("Reddict")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(ui("读懂字面之外", "Beyond the literal"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(viewModel.currentModelLabel)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 145, alignment: .trailing)

            headerButton(icon: "clock.arrow.circlepath", help: ui("查询历史", "History")) {
                viewModel.showHistory()
            }
            headerButton(
                icon: "slider.horizontal.3",
                help: ui("语言、显示与 API 设置", "Language, display, and API settings")
            ) {
                viewModel.openAPISettings()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func headerButton(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 29, height: 29)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var topTextBox: some View {
        if viewModel.activeMode == .howToSay {
            howToSayComposer
        } else {
            sourceComposer
        }
    }

    private var sourceComposer: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.sourceInput)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(ink.opacity(0.82))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 58, maxHeight: 92)

                if viewModel.sourceInput.isEmpty {
                    Text(ui(
                        "输入、粘贴，或使用快捷键自动读取剪贴板…",
                        "Type, paste, or use the shortcut to read the clipboard…"
                    ))
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Label(
                    viewModel.hasUnsubmittedManualInput
                        ? ui("内容已修改", "Edited")
                        : ui("可直接编辑", "Editable"),
                    systemImage: viewModel.hasUnsubmittedManualInput ? "pencil.line" : "keyboard"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    viewModel.hasUnsubmittedManualInput
                        ? coral
                        : Color.secondary.opacity(0.65)
                )

                Spacer()

                Button(
                    viewModel.activeMode == .closeReading
                        ? ui("开始精读", "Analyze")
                        : ui("生成回复", "Generate replies")
                ) {
                    viewModel.runManualAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .tint(coral)
                .disabled(!viewModel.canRunManualAnalysis)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(13)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 11)
    }

    private var howToSayComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.howToSayInput)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(ink.opacity(0.84))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 78, maxHeight: 112)
                if viewModel.howToSayInput.isEmpty {
                    Text(ui(
                        "输入任何语言或混合语言的内容…",
                        "Enter content in any language or a mix of languages…"
                    ))
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 8) {
                Label(ui("把这句话说成", "Say this in"), systemImage: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $viewModel.howToSayTargetLanguage) {
                    ForEach(viewModel.howToSayLanguages) { language in
                        Text(language.displayName(for: viewModel.uiLanguage)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 104)
                Button("Go") { viewModel.runHowToSay() }
                    .buttonStyle(.borderedProminent)
                    .tint(coral)
                    .disabled(!viewModel.canRunHowToSay)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(13)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 11)
    }

    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach(AnalysisMode.allCases) { mode in
                Button {
                    viewModel.select(mode)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.title(for: viewModel.uiLanguage))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(viewModel.activeMode == mode ? coral : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 39)
                    .background {
                        if viewModel.activeMode == mode {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(coral.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(coral.opacity(0.2), lineWidth: 0.8)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch viewModel.activeState {
                case .idle:
                    if viewModel.activeMode == .howToSay {
                        howToSayIdleView
                    } else {
                        manualInputIdleView
                    }
                case .loading:
                    if viewModel.activeMode == .closeReading,
                       !viewModel.closeReadingProgress.isEmpty {
                        progressiveCloseReadingView
                    } else {
                        loadingView
                    }
                case let .failed(message):
                    errorView(message)
                case .loaded:
                    if viewModel.activeMode == .closeReading,
                       (viewModel.closeReadingFailedCount > 0
                        || viewModel.closeReadingDeferredCount > 0),
                       !viewModel.closeReadingProgress.isEmpty {
                        progressiveCloseReadingView
                    } else if let result = viewModel.activeResult {
                        resultView(result)
                    } else {
                        errorView(ui(
                            "结果暂时不见了，请重试。",
                            "The result is temporarily unavailable. Please retry."
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "ellipsis.message")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(coral.opacity(0.8))
            Text(loadingCopy)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ui(
                "窗口可以收起；任务会继续运行。",
                "You can hide the window; the task will keep running."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 54)
    }

    private var progressiveCloseReadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: viewModel.closeReadingFailedCount > 0
                      ? "exclamationmark.bubble"
                      : "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(coral)
                Text(viewModel.closeReadingStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.closeReadingFailedCount > 0,
                   viewModel.activeState == .loaded {
                    Button(ui("重试", "Retry")) { viewModel.retry() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(coral)
                }
            }
            .padding(.horizontal, 4)

            ForEach(Array(viewModel.closeReadingProgress.enumerated()), id: \.element.id) { index, item in
                if let analysis = item.analysis {
                    segmentCard(
                        analysis,
                        number: index + 1,
                        difficultyScore: item.source.difficultyScore
                    )
                        .transition(.opacity)
                } else {
                    segmentStatusCard(item, number: index + 1)
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.closeReadingStatus)
    }

    private func segmentStatusCard(_ item: SegmentProgress, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(coral)
                Text(item.source.text)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if item.source.difficultyScore > 0 {
                    Text("\(ui("难度", "Level")) \(item.source.difficultyScore)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(difficultyColor(item.source.difficultyScore))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            difficultyColor(item.source.difficultyScore).opacity(0.1),
                            in: Capsule()
                        )
                }
                copyButton(item.source.text)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: segmentStatusIcon(item.state))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(segmentStatusColor(item.state))
                    .padding(.top, 2)
                Text(item.state.statusText(for: viewModel.uiLanguage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                Spacer()
                if canManuallyAnalyze(item.state) {
                    Button(ui("深度分析", "Deep analysis")) { viewModel.analyzeSegment(item.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(coral)
                }
            }
        }
        .resultCard()
    }

    private func segmentStatusIcon(_ state: SegmentAnalysisState) -> String {
        switch state {
        case .segmenting: "square.split.2x1"
        case .queued: "clock"
        case .deferred: "hand.raised"
        case .analyzing: "text.magnifyingglass"
        case .loaded: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func segmentStatusColor(_ state: SegmentAnalysisState) -> Color {
        switch state {
        case .failed: .orange
        case .loaded: .green
        case .deferred: .secondary
        case .segmenting, .queued, .analyzing: coral
        }
    }

    private func canManuallyAnalyze(_ state: SegmentAnalysisState) -> Bool {
        switch state {
        case .deferred, .failed: true
        case .segmenting, .queued, .analyzing, .loaded: false
        }
    }

    private var loadingCopy: String {
        switch viewModel.activeMode {
        case .closeReading:
            ui(
                "正在分句，并把翻译、句法和文化线索串起来…",
                "Segmenting and connecting translation, syntax, and cultural context…"
            )
        case .replies:
            ui("正在把“像真人”放在第一位…", "Writing replies that sound genuinely human…")
        case .howToSay:
            ui("正在把意思换成真正能说出口的话…", "Turning your meaning into something natural to say…")
        }
    }

    private var howToSayIdleView: some View {
        VStack(spacing: 13) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(coral.opacity(0.78))
            Text(ui(
                "输入一句你想表达的话，选择目标语言，然后点 Go。",
                "Enter what you want to say, choose a target language, then press Go."
            ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ui(
                "会生成普通、专业、礼貌、本土口语四个版本。",
                "You’ll get faithful, professional, polite, and local versions."
            ))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 54)
    }

    private var manualInputIdleView: some View {
        VStack(spacing: 13) {
            Image(systemName: "text.cursor")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(coral.opacity(0.78))
            Text(
                viewModel.sourceInput.isEmpty
                    ? ui("输入或粘贴一段文字。", "Type or paste some text.")
                    : ui(
                        "内容已修改，点击上方按钮开始分析。",
                        "The text was edited. Use the button above to analyze it."
                    )
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ui(
                "也可以复制文字后按 ⌃⌥⌘L 自动读取。",
                "You can also copy text and press ⌃⌥⌘L."
            ))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 54)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.rain")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack {
                Button(ui("模型设置", "Model settings")) { viewModel.openAPISettings() }
                Button(ui("重试", "Retry")) { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(coral)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 54)
    }

    @ViewBuilder
    private func resultView(_ result: AnalysisResponse) -> some View {
        switch viewModel.activeMode {
        case .closeReading:
            closeReadingResult(result)
        case .replies:
            repliesResult(result)
        case .howToSay:
            howToSayResult(result)
        }
    }

    private func closeReadingResult(_ result: AnalysisResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let analysis = result.closeReading {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionEyebrow(ui("整段译文", "Full translation"), icon: "character.book.closed")
                        Spacer()
                        Text(analysis.sourceLanguage)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(coral)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(coral.opacity(0.1), in: Capsule())
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text(analysis.completeTranslation)
                            .font(.system(size: 18, weight: .medium, design: .serif))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        copyButton(analysis.completeTranslation)
                    }
                    if !analysis.overallTone.isEmpty {
                        Label(analysis.overallTone, systemImage: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }
                .resultCard()

                ForEach(Array(analysis.segments.enumerated()), id: \.element.id) { index, segment in
                    segmentCard(segment, number: index + 1)
                }

                if !analysis.uncertainty.isEmpty {
                    Label(analysis.uncertainty, systemImage: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            } else {
                emptyResult(ui(
                    "模型没有返回综合精读内容。请重试或更换模型。",
                    "The model did not return a close-reading analysis. Retry or choose another model."
                ))
            }
        }
    }

    private func segmentCard(
        _ segment: AnalysisSegment,
        number: Int,
        difficultyScore: Int? = nil
    ) -> some View {
        let visibleVocabulary = viewModel.visibleVocabulary(segment.vocabulary)
        let visibleContext = viewModel.visibleContext(segment.historicalContext)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(coral)
                Text(segment.source)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let difficultyScore, difficultyScore > 0 {
                    Text("\(ui("难度", "Level")) \(difficultyScore)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(difficultyColor(difficultyScore))
                }
                copyButton(segment.source)
            }
            Text(segment.translation)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ink.opacity(0.84))
                .lineSpacing(4)
                .textSelection(.enabled)

            if !segment.difficultyReason.isEmpty {
                labeledNote(
                    ui("为什么难懂", "Why it’s difficult"),
                    icon: "brain.head.profile",
                    text: segment.difficultyReason
                )
            }

            syntaxBlock(source: segment.source, syntax: segment.syntaxAnalysis)

            if !segment.alternativeParses.isEmpty {
                disclosureSection(ui("多种句法解释", "Alternative parses"), icon: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(segment.alternativeParses) { parse in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(parse.interpretation)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(parse.reasoning)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(parse.verdict)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(coral)
                            }
                        }
                    }
                }
            }

            if !visibleVocabulary.isEmpty {
                disclosureSection(ui("实词与灵活用法", "Vocabulary & flexible usage"), icon: "textformat.abc") {
                    vocabularyList(visibleVocabulary)
                }
            }

            if !visibleContext.isEmpty {
                disclosureSection(ui("语法 · 文化 · 词源", "Grammar · Culture · Etymology"), icon: "books.vertical") {
                    contextList(visibleContext)
                }
            }

            if !segment.slangInterpretations.isEmpty {
                disclosureSection(ui("俚语与梗", "Slang & references"), icon: "theatermasks") {
                    slangList(segment.slangInterpretations)
                }
            }
        }
        .resultCard()
    }

    private func syntaxBlock(source: String, syntax: SyntaxAnalysis) -> some View {
        disclosureSection(ui("句法拆解", "Syntax"), icon: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 13) {
                orderedAnalysisRow("1", ui("核心骨架", "Core structure"), syntax.coreStructure)
                if !syntax.constituents.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        miniStep("2", ui("彩色成分", "Color-coded components"))
                        ComponentFlowLayout(spacing: 6) {
                            ForEach(Array(syntax.constituents.enumerated()), id: \.element.id) { index, item in
                                let color = componentColor(item.category)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.text)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(ink)
                                    Text(item.role)
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(color)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    color.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 6.5, weight: .bold))
                                        .foregroundStyle(color)
                                        .offset(x: 3, y: 4)
                                }
                            }
                        }
                        .accessibilityLabel(source)

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(syntax.constituents.enumerated()), id: \.element.id) { index, item in
                                let color = componentColor(item.category)
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(color, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.role)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(color)
                                        Text(item.explanation)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(2)
                                    }
                                }
                            }
                        }
                    }
                }
                if !syntax.confusingPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        miniStep("3", ui("易混淆点", "Potential confusion"))
                        ForEach(syntax.confusingPoints, id: \.self) { point in
                            Text("• \(point)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 23)
                        }
                    }
                }
            }
        }
    }

    private func orderedAnalysisRow(_ number: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            miniStep(number, title)
            coreStructureText(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.leading, 23)
                .textSelection(.enabled)
        }
    }

    private func coreStructureText(_ text: String) -> Text {
        let normalized = text
            .replacingOccurrences(
                of: #"【([^】]+)】"#,
                with: "**$1**",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\[\]]+)\]"#,
                with: "**$1**",
                options: .regularExpression
            )
        guard let attributed = try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(normalized)
        }
        return Text(attributed)
    }

    private func miniStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Text(number)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(coral, in: Circle())
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ink.opacity(0.78))
        }
    }

    private func vocabularyList(_ items: [LinguisticVocabulary]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        levelBadge(item.level)
                        Text(item.word)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        if !item.reading.isEmpty {
                            Text(item.reading)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if !item.baseForm.isEmpty, item.baseForm != item.word {
                            Text("← \(item.baseForm)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    Text([item.partOfSpeech, item.meaning].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                    if !item.conjugation.isEmpty {
                        Text("\(ui("活用", "Inflection")): \(item.conjugation)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(coral)
                    }
                    if !item.usage.isEmpty {
                        Text(item.usage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    ForEach(item.distinctUsages, id: \.self) { usage in
                        Text("↳ \(usage)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .textSelection(.enabled)
                if index < items.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func contextList(_ items: [HistoricalContextItem]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 9) {
                    levelBadge(item.level)
                    Image(systemName: contextIcon(item.type))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(contextColor(item.type))
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.type.title(for: viewModel.uiLanguage))
                            .font(.system(size: 10, weight: .bold))
                        Text(item.content)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func levelBadge(_ level: String) -> some View {
        let displayLevel = level.isEmpty ? "—" : level.uppercased()
        return Text(displayLevel)
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(levelColor(displayLevel))
            .frame(width: 27, height: 17)
            .background(
                levelColor(displayLevel).opacity(0.11),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .accessibilityLabel("\(ui("难度", "Level")) \(displayLevel)")
    }

    private func slangList(_ items: [SlangInterpretation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.expression)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(coral)
                    fixedSlangRow(ui("字面翻译", "Literal"), item.literalTranslation)
                    fixedSlangRow(ui("适用场景", "Usage"), item.usageScenarios)
                    fixedSlangRow(ui("文化与历史", "Culture & history"), item.culturalHistoricalContext)
                }
                .padding(11)
                .background(coral.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func fixedSlangRow(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 55, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }

    private func labeledNote(_ title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(coral)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }

    private func disclosureSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            content()
                .padding(.top, 9)
        } label: {
            sectionEyebrow(title, icon: icon)
        }
        .tint(coral)
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private func repliesResult(_ result: AnalysisResponse) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionEyebrow(ui("自然地接这句话", "Natural replies"), icon: "bubble.left.and.bubble.right")
            if let context = result.replyContext, !context.isEmpty {
                Text(context)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            ForEach(result.replies ?? []) { reply in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            reply.persona.title(for: viewModel.uiLanguage),
                            systemImage: reply.persona.icon
                        )
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(personaColor(reply.persona))
                        Spacer()
                        copyButton(reply.text)
                    }
                    Text(reply.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Text(reply.chinese)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let note = reply.toneNote, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(13)
                .background(
                    personaColor(reply.persona).opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        }
        .resultCard()
    }

    private func howToSayResult(_ result: AnalysisResponse) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionEyebrow("How To Say", icon: "text.bubble")
            if let context = result.howToSayContext, !context.isEmpty {
                Text(context)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            let suggestions = result.howToSaySuggestions ?? []
            if suggestions.isEmpty {
                emptyResult(ui(
                    "没有生成表达版本。可以换一种更具体的输入再试。",
                    "No versions were generated. Try a more specific input."
                ))
            } else {
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                suggestion.style.title(for: viewModel.uiLanguage),
                                systemImage: suggestion.style.icon
                            )
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(howToSayColor(suggestion.style))
                            Spacer()
                            copyButton(suggestion.translation)
                        }
                        Text(suggestion.translation)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                        Text(suggestion.backTranslation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                        Text(suggestion.note)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineSpacing(2)
                    }
                    .padding(13)
                    .background(
                        howToSayColor(suggestion.style).opacity(0.062),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
            }
        }
        .resultCard()
    }

    private var footer: some View {
        HStack {
            Label(
                ui("自动读剪贴板，也可手动输入", "Clipboard or manual input"),
                systemImage: "keyboard"
            )
            Spacer()
            if viewModel.cacheHits.contains(viewModel.activeMode) {
                Label(ui("来自历史 · 0 Token", "From history · 0 tokens"), systemImage: "bolt.slash")
                    .foregroundStyle(coral.opacity(0.85))
            } else {
                Text(viewModel.activeMode.shortTitle(for: viewModel.uiLanguage))
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.025))
    }

    private var apiSettingsOverlay: some View {
        modalBackdrop(isPresented: $viewModel.isShowingAPISettings) {
            VStack(alignment: .leading, spacing: 14) {
                modalHeader(
                    ui("设置", "Settings"),
                    subtitle: ui(
                        "界面、翻译、学习水平与 OpenAI-compatible API",
                        "Interface, translation, learning levels, and OpenAI-compatible API"
                    )
                ) {
                    viewModel.isShowingAPISettings = false
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionEyebrow(ui("语言", "Languages"), icon: "character.bubble")

                            HStack(spacing: 10) {
                                Text(ui("软件与解释语言", "App & explanation language"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(width: 150, alignment: .leading)
                                Picker("", selection: $viewModel.interfaceLanguageDraft) {
                                    ForEach(InterfaceLanguage.allCases) { language in
                                        Text(language.title).tag(language)
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                Text(ui("精读翻译目标语言", "Close-reading translation"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(width: 150, alignment: .leading)
                                Picker("", selection: $viewModel.translationLanguageDraft) {
                                    ForEach(viewModel.languageCatalog) { language in
                                        Text(language.displayName(for: viewModel.interfaceLanguageDraft))
                                            .tag(language)
                                    }
                                }
                            }

                            Text(
                                ui(
                                    "软件语言同时决定模型解释、回复释义与回译所使用的语言。",
                                    "The app language also controls model explanations, reply meanings, and back-translations."
                                )
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) {
                                sectionEyebrow(ui("学习水平", "Learning levels"), icon: "graduationcap")
                                Button {
                                    isShowingLevelHelp.toggle()
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(ui("CEFR 与 JLPT 水平说明", "About CEFR and JLPT levels"))
                                .popover(isPresented: $isShowingLevelHelp, arrowEdge: .top) {
                                    levelHelpPopover
                                }
                                Spacer()
                            }

                            ForEach($viewModel.languageDrafts) { $profile in
                                HStack(spacing: 10) {
                                    Text(profile.language.displayName(for: viewModel.interfaceLanguageDraft))
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 132, alignment: .leading)
                                    if profile.language.usesJLPT {
                                        Picker("JLPT", selection: $profile.jlpt) {
                                            ForEach(JapaneseProficiency.allCases) { level in
                                                Text(level.title).tag(level)
                                            }
                                        }
                                    } else {
                                        Picker("CEFR", selection: $profile.cefr) {
                                            ForEach(CEFRLevel.allCases) { level in
                                                Text(level.title).tag(level)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        viewModel.removeLearningLanguage(profile.language)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(
                                        ui(
                                            "移除\(profile.language.displayName(for: viewModel.interfaceLanguageDraft))",
                                            "Remove \(profile.language.displayName(for: viewModel.interfaceLanguageDraft))"
                                        )
                                    )
                                }
                                .font(.system(size: 10.5))
                            }

                            Menu {
                                ForEach(viewModel.availableLearningLanguages) { language in
                                    Button(language.displayName(for: viewModel.interfaceLanguageDraft)) {
                                        viewModel.addLearningLanguage(language)
                                    }
                                }
                            } label: {
                                Label(ui("添加预设语言", "Add preset language"), systemImage: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .disabled(viewModel.availableLearningLanguages.isEmpty)

                            Divider().opacity(0.45)

                            VStack(alignment: .leading, spacing: 7) {
                                Text(ui("自定义语言", "Custom language"))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                ForEach(viewModel.customLanguageDrafts) { language in
                                    HStack(spacing: 7) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.green)
                                        Text(language.displayName(for: viewModel.interfaceLanguageDraft))
                                            .font(.system(size: 10.5, weight: .medium))
                                        Text(ui("已验证", "Verified"))
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Button {
                                            viewModel.removeCustomLanguage(language)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(ui("从语言库删除", "Delete from language library"))
                                    }
                                }
                                HStack(spacing: 8) {
                                    TextField(
                                        ui(
                                            "例如：古汉语、Latin、Klingon",
                                            "For example: Classical Chinese, Latin, Klingon"
                                        ),
                                        text: $viewModel.customLanguageInput
                                    )
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(9)
                                    .background(
                                        .primary.opacity(0.055),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )

                                    Button {
                                        viewModel.validateAndAddCustomLanguage()
                                    } label: {
                                        if viewModel.isValidatingCustomLanguage {
                                            HStack(spacing: 5) {
                                                ProgressView().controlSize(.mini)
                                                Text(ui("验证中", "Testing"))
                                            }
                                        } else {
                                            Text(ui("测试并添加", "Test & Add"))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!viewModel.canValidateCustomLanguage)
                                }

                                Text(
                                    ui(
                                        "使用当前模型一次检查：它是否为可翻译语言、当前模型能否理解；未通过不会保存。",
                                        "One model request checks whether it is a translatable language and whether the current model can analyze it. Failed entries are not saved."
                                    )
                                )
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)

                                if !viewModel.customLanguageMessage.isEmpty {
                                    Text(viewModel.customLanguageMessage)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(12)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 10) {
                            sectionEyebrow(ui("显示设置", "Display"), icon: "eye")
                            Picker(ui("分析结果", "Analysis results"), selection: $viewModel.displayPreferenceDraft) {
                                ForEach(AnalysisDisplayPreference.allCases) { preference in
                                    Text(preference.title(for: viewModel.interfaceLanguageDraft))
                                        .tag(preference)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Text(
                                    ui(
                                        "过滤只影响词汇与语法、文化、词源条目。",
                                        "Filtering only affects vocabulary, grammar, culture, and etymology items."
                                    )
                                )
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button(ui("保存语言设置", "Save language settings")) {
                                    viewModel.saveLearningPreferences()
                                }
                                .buttonStyle(.bordered)
                            }
                            if !viewModel.learningSettingsMessage.isEmpty {
                                Text(viewModel.learningSettingsMessage)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 11) {
                            sectionEyebrow(ui("模型供应商", "Model provider"), icon: "cpu")
                            Picker(ui("供应商", "Provider"), selection: $viewModel.providerDraft) {
                                ForEach(LLMProvider.allCases) { provider in
                                    Text(provider.title).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(viewModel.providerDraft.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            settingsField("API Base URL", placeholder: "https://…/v1", text: $viewModel.baseURLDraft)
                            settingsField("Model", placeholder: "model-name", text: $viewModel.modelDraft)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("API KEY")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                SecureField(
                                    ui(
                                        "在这里输入供应商提供的 Key",
                                        "Enter the API key supplied by the provider"
                                    ),
                                    text: $viewModel.apiKeyDraft
                                )
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(11)
                                    .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                                Text(ui(
                                    "仅使用你在 Reddict 中输入并保存的 Key；不会读取 macOS 钥匙串。",
                                    "Reddict only uses keys entered and saved here; it does not read macOS Keychain."
                                ))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }

                            HStack(spacing: 7) {
                                Toggle(
                                    ui(
                                        "发送 response_format: json_object",
                                        "Send response_format: json_object"
                                    ),
                                    isOn: $viewModel.useJSONModeDraft
                                )
                                .font(.system(size: 11))
                                .fixedSize()
                                Button {
                                    isShowingJSONModeHelp.toggle()
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(ui(
                                    "什么是 response_format: json_object？",
                                    "What is response_format: json_object?"
                                ))
                                .popover(isPresented: $isShowingJSONModeHelp, arrowEdge: .top) {
                                    jsonModeHelpPopover
                                }
                                Spacer()
                            }

                            if !viewModel.settingsMessage.isEmpty {
                                HStack(alignment: .top, spacing: 7) {
                                    if viewModel.isTestingConnection {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(
                                            systemName: viewModel.currentSettingsTestPassed
                                                ? "checkmark.circle.fill"
                                                : "exclamationmark.circle.fill"
                                        )
                                    }
                                    Text(viewModel.settingsMessage)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(
                                    viewModel.isTestingConnection
                                        ? Color.secondary
                                        : (viewModel.currentSettingsTestPassed ? Color.green : Color.red)
                                )
                            }

                            HStack {
                                Label(
                                    ui(
                                        "测试会产生极少量 Token",
                                        "The test uses a very small number of tokens"
                                    ),
                                    systemImage: "waveform.path.ecg"
                                )
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button(ui("恢复预设", "Restore defaults")) {
                                    viewModel.resetProviderDefaults()
                                }
                                Button {
                                    viewModel.testAPISettings()
                                } label: {
                                    if viewModel.isTestingConnection {
                                        HStack(spacing: 5) {
                                            ProgressView().controlSize(.mini)
                                            Text(ui("测试中", "Testing"))
                                        }
                                    } else {
                                        Text(ui("测试连接", "Test connection"))
                                    }
                                }
                                .disabled(viewModel.isTestingConnection)
                                Button(ui("保存并使用", "Save & Use")) {
                                    viewModel.saveAPISettings()
                                }
                                    .buttonStyle(.borderedProminent)
                                    .tint(coral)
                                    .disabled(!viewModel.currentSettingsTestPassed || viewModel.isTestingConnection)
                            }
                        }
                        .padding(12)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.visible)
            }
            .padding(20)
            .frame(width: 500)
            .frame(maxHeight: 760)
            .liquidGlass(cornerRadius: 22)
            .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        }
    }

    private var levelHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui("CEFR 大致怎么理解", "A quick guide to CEFR"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Text(ui("A1–A2 · 入门到基础日常交流", "A1–A2 · Beginner to basic everyday communication"))
                Text(ui("B1 · 能独立应对生活、旅行和熟悉话题", "B1 · Independent in daily life, travel, and familiar topics"))
                Text(ui("B2 · 能理解较复杂内容并自然讨论", "B2 · Understands complex content and discusses it naturally"))
                Text(ui("C1 · 能处理专业、学术与隐含语义", "C1 · Handles professional, academic, and implied meaning"))
                Text(ui("C2 · 接近熟练母语者的理解与表达", "C2 · Near highly proficient native-level comprehension"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            Divider()
            Text(ui(
                "除日语外均使用 CEFR。日语使用 JLPT：N5 最基础，N1 最高。",
                "All languages except Japanese use CEFR. Japanese uses JLPT, from N5 to N1."
            ))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(width: 285, alignment: .leading)
    }

    private var jsonModeHelpPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ui("JSON Object 模式", "JSON Object mode"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(ui("开启后，请求会附带：", "When enabled, requests include:"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(#"response_format: {"type":"json_object"}"#)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            Text(ui(
                "它要求兼容的模型只返回合法 JSON，能减少多余说明、Markdown 和结构损坏，让 Reddict 更容易读取分析结果。它不会改变分析内容，也不是隐私设置。",
                "It asks compatible models to return valid JSON, reducing extra prose, Markdown, and broken structures. It does not change the analysis and is not a privacy setting."
            ))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            Divider()
            Text(ui(
                "如果测试连接返回“不支持 response_format”或 HTTP 400，请关闭。Reddict 仍会通过 Prompt 要求模型返回 JSON。",
                "Disable it if the connection test reports an unsupported response_format or HTTP 400. The prompt will still request JSON."
            ))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(width: 310, alignment: .leading)
    }

    private var historyOverlay: some View {
        modalBackdrop(isPresented: $viewModel.isShowingHistory) {
            VStack(alignment: .leading, spacing: 14) {
                modalHeader(
                    ui("查询历史", "History"),
                    subtitle: ui(
                        "再次打开同一内容不会请求模型",
                        "Opening the same content again does not call the model"
                    )
                ) {
                    viewModel.isShowingHistory = false
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField(
                        ui("搜索原文、功能或模型", "Search source text, feature, or model"),
                        text: $viewModel.historyQuery
                    )
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.filteredHistory.isEmpty {
                            emptyResult(ui("还没有查询历史。", "No history yet."))
                        } else {
                            ForEach(viewModel.filteredHistory) { record in
                                Button {
                                    viewModel.restore(record)
                                } label: {
                                    historyRow(record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(height: 390)
            }
            .padding(20)
            .frame(width: 470)
            .liquidGlass(cornerRadius: 22)
            .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        }
    }

    private func historyRow(_ record: HistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: record.mode.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(coral)
                .frame(width: 27, height: 27)
                .background(coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(record.sourceText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(record.mode.title(for: viewModel.uiLanguage))
                    Text("·")
                    Text(record.model)
                    Text("·")
                    Text(record.createdAt, style: .relative)
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
                .padding(.top, 8)
        }
        .padding(11)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func modalBackdrop<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { isPresented.wrappedValue = false }
            content()
        }
    }

    private func modalHeader(
        _ title: String,
        subtitle: String,
        close: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsField(
        _ label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(11)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionEyebrow(_ text: String, icon: String) -> some View {
        Label(text.uppercased(), systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(coral)
    }

    private func copyButton(_ text: String) -> some View {
        Button { viewModel.copy(text) } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.primary.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .help(ui("复制", "Copy"))
    }

    private func emptyResult(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func personaColor(_ persona: Persona) -> Color {
        switch persona {
        case .witty: Color(red: 0.70, green: 0.38, blue: 0.88)
        case .precise: Color(red: 0.23, green: 0.53, blue: 0.88)
        case .warm: Color(red: 0.93, green: 0.42, blue: 0.43)
        case .debating: Color(red: 0.18, green: 0.65, blue: 0.54)
        }
    }

    private func howToSayColor(_ style: HowToSayStyle) -> Color {
        switch style {
        case .faithful: Color(red: 0.82, green: 0.35, blue: 0.24)
        case .professional: Color(red: 0.24, green: 0.48, blue: 0.88)
        case .polite: Color(red: 0.18, green: 0.62, blue: 0.50)
        case .localSlang: Color(red: 0.67, green: 0.39, blue: 0.90)
        }
    }

    private func contextIcon(_ type: HistoricalContextType) -> String {
        switch type {
        case .historicalOrigin: "building.columns"
        case .chineseComparison: "arrow.left.arrow.right"
        case .similarOrConfusingUsage: "exclamationmark.triangle"
        case .keyGrammarPoints: "graduationcap"
        case .culturalConnotation: "globe.asia.australia"
        case .etymology: "leaf"
        }
    }

    private func contextColor(_ type: HistoricalContextType) -> Color {
        switch type {
        case .historicalOrigin, .etymology: .brown
        case .chineseComparison: .blue
        case .similarOrConfusingUsage: .orange
        case .keyGrammarPoints: .purple
        case .culturalConnotation: .green
        }
    }

    private func difficultyColor(_ score: Int) -> Color {
        switch score {
        case 75...: .red
        case 55..<75: .orange
        case 35..<55: .blue
        default: .secondary
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "C2", "N1": Color(red: 0.88, green: 0.25, blue: 0.24)
        case "C1", "N2": Color(red: 0.93, green: 0.48, blue: 0.15)
        case "B2", "N3": Color(red: 0.60, green: 0.36, blue: 0.86)
        case "B1": Color(red: 0.20, green: 0.53, blue: 0.88)
        case "A2": Color(red: 0.16, green: 0.63, blue: 0.53)
        case "A1": Color(red: 0.36, green: 0.60, blue: 0.41)
        default: .secondary
        }
    }

    private func componentColor(_ category: SyntaxConstituentCategory) -> Color {
        switch category {
        case .subject: Color(red: 0.22, green: 0.50, blue: 0.90)
        case .predicate: Color(red: 0.91, green: 0.35, blue: 0.32)
        case .object: Color(red: 0.91, green: 0.58, blue: 0.18)
        case .complement: Color(red: 0.18, green: 0.65, blue: 0.48)
        case .modifier: Color(red: 0.20, green: 0.66, blue: 0.72)
        case .clause: Color(red: 0.32, green: 0.65, blue: 0.40)
        case .connector: Color(red: 0.68, green: 0.39, blue: 0.88)
        case .punctuation: Color(red: 0.78, green: 0.40, blue: 0.42)
        case .other: Color(red: 0.48, green: 0.48, blue: 0.52)
        }
    }
}

private struct ComponentFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 420
        let result = positions(in: width, subviews: subviews)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = positions(in: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func positions(
        in width: CGFloat,
        subviews: Subviews
    ) -> (points: [CGPoint], height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, y + rowHeight)
    }
}

private struct ResultCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 0.7)
            }
    }
}

private struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
        }
    }
}

private extension View {
    func resultCard() -> some View {
        modifier(ResultCardModifier())
    }

    func liquidGlass(cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
