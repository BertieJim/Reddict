import AVFoundation
import Foundation
import Speech

enum SpeechLocaleResolver {
  static func localeID(
    interfaceLanguage: InterfaceLanguage,
    existingText: String
  ) -> String {
    let scalars = existingText.unicodeScalars
    if scalars.contains(where: { (0x3040...0x30ff).contains($0.value) }) {
      return "ja-JP"
    }
    if scalars.contains(where: { (0xac00...0xd7af).contains($0.value) }) {
      return "ko-KR"
    }
    if scalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) {
      return "zh-CN"
    }
    return interfaceLanguage == .simplifiedChinese ? "zh-CN" : "en-US"
  }

  static func displayName(
    for localeID: String,
    interfaceLanguage: InterfaceLanguage
  ) -> String {
    switch localeID.lowercased() {
    case let value where value.hasPrefix("zh"):
      return interfaceLanguage.text("中文", "Chinese")
    case let value where value.hasPrefix("ja"):
      return interfaceLanguage.text("日语", "Japanese")
    case let value where value.hasPrefix("ko"):
      return interfaceLanguage.text("韩语", "Korean")
    default:
      return "English"
    }
  }
}

enum VoiceInputPhase: Equatable {
  case idle
  case requestingPermission
  case recording
  case transcribing
}

/// How To Say's tap-to-record pipeline, adapted from audioGo's macOS app:
/// microphone → ordered 16 kHz PCM chunks → Apple Speech partial/final text.
@MainActor
final class VoiceInputTranscriber {
  enum VoiceInputError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable(String)
    case microphone(String)
    case notRecording

    var errorDescription: String? {
      switch self {
      case .microphonePermissionDenied:
        return "麦克风权限被拒绝，请在系统设置 → 隐私与安全性 → 麦克风中允许 Reddict。"
      case .speechPermissionDenied:
        return "语音识别权限被拒绝，请在系统设置 → 隐私与安全性 → 语音识别中允许 Reddict。"
      case .recognizerUnavailable(let locale):
        return "当前无法使用 \(locale) 语音识别。"
      case .microphone(let detail):
        return "麦克风启动失败：\(detail)"
      case .notRecording:
        return "当前没有正在进行的录音。"
      }
    }
  }

  private let microphone = VoiceMicCapture()
  private var recognizer: VoiceAppleRecognizer?
  private var feedTask: Task<Void, Never>?
  private var pcmContinuation: AsyncStream<Data>.Continuation?

  func start(localeID: String, onPartial: @escaping @MainActor (String) -> Void) async throws {
    cancel()
    guard await VoiceMicCapture.requestPermission() else {
      throw VoiceInputError.microphonePermissionDenied
    }
    guard await VoiceAppleRecognizer.requestPermission() else {
      throw VoiceInputError.speechPermissionDenied
    }
    guard let recognizer = VoiceAppleRecognizer(localeID: localeID, onPartial: onPartial) else {
      throw VoiceInputError.recognizerUnavailable(localeID)
    }
    try recognizer.start()
    self.recognizer = recognizer

    // The audio tap is not ordered relative to detached Tasks. One stream and
    // one consumer preserve the exact chunk order before end-of-audio.
    let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
    pcmContinuation = continuation
    feedTask = Task { [weak recognizer] in
      for await chunk in stream {
        recognizer?.send(pcm: chunk)
      }
    }

    do {
      try microphone.start { continuation.yield($0) }
    } catch {
      continuation.finish()
      recognizer.cancel()
      feedTask?.cancel()
      self.recognizer = nil
      pcmContinuation = nil
      feedTask = nil
      throw error
    }
  }

  func stop() async throws -> String {
    guard let recognizer else { throw VoiceInputError.notRecording }
    microphone.stop()
    pcmContinuation?.finish()
    await feedTask?.value

    do {
      let text = try await recognizer.finish()
      clearReferences()
      return text
    } catch {
      recognizer.cancel()
      clearReferences()
      throw error
    }
  }

  func cancel() {
    microphone.stop()
    pcmContinuation?.finish()
    feedTask?.cancel()
    recognizer?.cancel()
    clearReferences()
  }

  private func clearReferences() {
    recognizer = nil
    pcmContinuation = nil
    feedTask = nil
  }
}

private final class VoiceMicCapture {
  static let sampleRate = 16_000.0
  static let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: sampleRate,
    channels: 1,
    interleaved: true
  )!

  private let engine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private var hasTap = false

  static func requestPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  func start(onChunk: @escaping (Data) -> Void) throws {
    let input = engine.inputNode
    let native = input.outputFormat(forBus: 0)
    guard native.sampleRate > 0 else {
      throw VoiceInputTranscriber.VoiceInputError.microphone("没有可用的输入设备")
    }
    guard let converter = AVAudioConverter(from: native, to: Self.outputFormat) else {
      throw VoiceInputTranscriber.VoiceInputError.microphone("无法转换 \(Int(native.sampleRate)) Hz 输入")
    }
    self.converter = converter

    // 64 ms blocks match audioGo's proven macOS capture cadence.
    let frames = AVAudioFrameCount(native.sampleRate * 0.064)
    input.installTap(onBus: 0, bufferSize: frames, format: native) { buffer, _ in
      let ratio = Self.sampleRate / native.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
      guard
        let output = AVAudioPCMBuffer(
          pcmFormat: Self.outputFormat,
          frameCapacity: capacity
        )
      else { return }

      var suppliedInput = false
      var conversionError: NSError?
      converter.convert(to: output, error: &conversionError) { _, status in
        if suppliedInput {
          status.pointee = .noDataNow
          return nil
        }
        suppliedInput = true
        status.pointee = .haveData
        return buffer
      }
      guard conversionError == nil,
        output.frameLength > 0,
        let samples = output.int16ChannelData
      else { return }
      onChunk(Data(bytes: samples[0], count: Int(output.frameLength) * 2))
    }
    hasTap = true

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      hasTap = false
      throw VoiceInputTranscriber.VoiceInputError.microphone(error.localizedDescription)
    }
  }

  func stop() {
    if hasTap {
      engine.inputNode.removeTap(onBus: 0)
      hasTap = false
    }
    engine.stop()
    converter = nil
  }
}

@MainActor
private final class VoiceAppleRecognizer {
  private let recognizer: SFSpeechRecognizer
  private let request = SFSpeechAudioBufferRecognitionRequest()
  private let onPartial: @MainActor (String) -> Void
  private var recognitionTask: SFSpeechRecognitionTask?
  private var finalContinuation: CheckedContinuation<String, Error>?
  private(set) var text = ""
  private var finished = false

  init?(localeID: String, onPartial: @escaping @MainActor (String) -> Void) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
      return nil
    }
    self.recognizer = recognizer
    self.onPartial = onPartial
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
  }

  static func requestPermission() async -> Bool {
    if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  func start() throws {
    guard recognizer.isAvailable else {
      throw VoiceInputTranscriber.VoiceInputError.recognizerUnavailable(
        recognizer.locale.identifier
      )
    }
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        self?.handle(result: result, error: error)
      }
    }
  }

  func send(pcm: Data) {
    let frames = AVAudioFrameCount(pcm.count / 2)
    guard frames > 0,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: VoiceMicCapture.outputFormat,
        frameCapacity: frames
      ),
      let channel = buffer.int16ChannelData
    else { return }
    pcm.withUnsafeBytes { raw in
      guard let source = raw.bindMemory(to: Int16.self).baseAddress else { return }
      channel[0].update(from: source, count: Int(frames))
    }
    buffer.frameLength = frames
    request.append(buffer)
  }

  func finish(timeout: TimeInterval = 10) async throws -> String {
    request.endAudio()
    if finished { return text }

    let timeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(timeout))
      guard let self, !Task.isCancelled else { return }
      // Apple may not mark very short utterances final; the latest partial
      // is still the user's text and is safer than discarding it.
      self.resolve(with: self.text)
    }
    defer { timeoutTask.cancel() }

    return try await withCheckedThrowingContinuation { continuation in
      finalContinuation = continuation
      if finished { resolve(with: text) }
    }
  }

  func cancel() {
    recognitionTask?.cancel()
    recognitionTask = nil
    if let continuation = finalContinuation {
      finalContinuation = nil
      continuation.resume(throwing: CancellationError())
    }
  }

  private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
    if let result {
      text = result.bestTranscription.formattedString
      if !text.isEmpty { onPartial(text) }
      if result.isFinal {
        finished = true
        resolve(with: text)
      }
    }
    if let error {
      finished = true
      if text.isEmpty {
        resolve(throwing: error)
      } else {
        resolve(with: text)
      }
    }
  }

  private func resolve(with text: String) {
    guard let continuation = finalContinuation else { return }
    finalContinuation = nil
    recognitionTask = nil
    continuation.resume(returning: text)
  }

  private func resolve(throwing error: Error) {
    guard let continuation = finalContinuation else { return }
    finalContinuation = nil
    recognitionTask = nil
    continuation.resume(throwing: error)
  }
}
