import Foundation
import NaturalLanguage

struct SourceSegment: Codable, Identifiable, Sendable {
  let id: String
  let text: String
  let difficultyScore: Int
  let paragraphIndex: Int

  enum CodingKeys: String, CodingKey {
    case id
    case text
    case difficultyScore = "difficulty_score"
    case paragraphIndex = "paragraph_index"
  }

  init(
    id: String,
    text: String,
    difficultyScore: Int = 0,
    paragraphIndex: Int = 0
  ) {
    self.id = id
    self.text = text
    self.difficultyScore = max(0, min(100, difficultyScore))
    self.paragraphIndex = max(0, paragraphIndex)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    difficultyScore = max(
      0,
      min(100, try container.decodeIfPresent(Int.self, forKey: .difficultyScore) ?? 0)
    )
    paragraphIndex = max(
      0,
      try container.decodeIfPresent(Int.self, forKey: .paragraphIndex) ?? 0
    )
  }
}

struct SegmentationPlan: Sendable {
  let segments: [SourceSegment]
  let requiresAISegmentation: Bool
  let normalizedText: String
}

enum TextSegmenter {
  private static let maximumSegmentLength = 4_000
  private static let preferredBatchLength = 1_500
  private static let maximumSegmentsPerBatch = 1

  static func plan(_ source: String) -> SegmentationPlan {
    let lineNormalized =
      source
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lineNormalized.isEmpty else {
      return SegmentationPlan(
        segments: [],
        requiresAISegmentation: false,
        normalizedText: ""
      )
    }

    let paragraphs = normalizedParagraphs(from: lineNormalized)
    let normalized = paragraphs.joined(separator: "\n\n")
    var candidates: [(text: String, paragraphIndex: Int)] = []
    for (paragraphIndex, paragraph) in paragraphs.enumerated() {
      let tokenizer = NLTokenizer(unit: .sentence)
      tokenizer.string = paragraph
      var paragraphSentences: [String] = []
      tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
        let sentence = clean(String(paragraph[range]))
        if !sentence.isEmpty {
          paragraphSentences.append(sentence)
        }
        return true
      }
      if paragraphSentences.isEmpty, !paragraph.isEmpty {
        paragraphSentences = [paragraph]
      }
      candidates.append(contentsOf: paragraphSentences.map { ($0, paragraphIndex) })
    }

    let tokenizerFoundSingleBlock = candidates.count == 1
    let refined = candidates.flatMap { candidate in
      splitOversized(candidate.text).map { ($0, candidate.paragraphIndex) }
    }
    let segments = refined.enumerated().map {
      SourceSegment(
        id: "s\($0.offset + 1)",
        text: $0.element.0,
        difficultyScore: localDifficultyScore($0.element.0),
        paragraphIndex: $0.element.1
      )
    }
    let punctuationCount = normalized.filter { ".!?。！？；;".contains($0) }.count
    let hasFinalTerminator = normalized.last.map { ".!?。！？".contains($0) } ?? false
    let lacksClearBoundary =
      tokenizerFoundSingleBlock
      && normalized.count >= 220
      && punctuationCount == (hasFinalTerminator ? 1 : 0)
    return SegmentationPlan(
      segments: segments,
      requiresAISegmentation: lacksClearBoundary,
      normalizedText: normalized
    )
  }

  static func segment(_ source: String) -> [SourceSegment] {
    plan(source).segments
  }

  static func shouldAnalyzeAutomatically(
    _ segment: SourceSegment,
    totalTextLength: Int,
    usedAISegmentation: Bool
  ) -> Bool {
    if totalTextLength < 520 {
      return !usedAISegmentation || segment.difficultyScore >= 48
    }
    return segment.text.count >= 72 || segment.difficultyScore >= 60
  }

  static func batches(from segments: [SourceSegment]) -> [[SourceSegment]] {
    var result: [[SourceSegment]] = []
    var current: [SourceSegment] = []
    var currentLength = 0

    for segment in segments {
      let wouldOverflow =
        !current.isEmpty
        && (current.count >= maximumSegmentsPerBatch
          || currentLength + segment.text.count > preferredBatchLength)
      if wouldOverflow {
        result.append(current)
        current = []
        currentLength = 0
      }
      current.append(segment)
      currentLength += segment.text.count
    }

    if !current.isEmpty {
      result.append(current)
    }
    return result
  }

  /// Splits an existing complete translation into contiguous pieces aligned with
  /// the source segments. This is deliberately local: selecting a sentence must
  /// never trigger another translation request or replace the complete translation.
  static func alignedTranslations(
    from completeTranslation: String,
    to sourceSegments: [SourceSegment]
  ) -> [String: String] {
    guard !sourceSegments.isEmpty else { return [:] }
    let translation = completeTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !translation.isEmpty else { return [:] }
    guard sourceSegments.count > 1 else {
      return [sourceSegments[0].id: translation]
    }

    var units = translationUnits(in: translation)
    while units.count < sourceSegments.count {
      guard
        let index = units.indices.max(by: {
          units[$0].count < units[$1].count
        }), let split = splitTranslationUnit(units[index])
      else {
        break
      }
      units.replaceSubrange(index...index, with: split)
    }

    guard units.count >= sourceSegments.count else {
      return proportionalCharacterSlices(translation, sourceSegments: sourceSegments)
    }

    let sourceLengths = sourceSegments.map { max(1, $0.text.count) }
    let totalSourceLength = max(1, sourceLengths.reduce(0, +))
    let unitLengths = units.map { max(1, $0.count) }
    let totalTranslationLength = unitLengths.reduce(0, +)
    var sourceLengthSoFar = 0
    var unitStart = 0
    var result: [String: String] = [:]

    for sourceIndex in sourceSegments.indices {
      let isLastSource = sourceIndex == sourceSegments.index(before: sourceSegments.endIndex)
      let unitEnd: Int
      if isLastSource {
        unitEnd = units.count
      } else {
        sourceLengthSoFar += sourceLengths[sourceIndex]
        let desiredBoundary =
          Double(sourceLengthSoFar)
          / Double(totalSourceLength)
          * Double(totalTranslationLength)
        let remainingSources = sourceSegments.count - sourceIndex - 1
        let maximumBoundary = units.count - remainingSources
        var cumulativeLength = unitLengths[..<unitStart].reduce(0, +)
        var bestBoundary = unitStart + 1
        var bestDistance = Double.greatestFiniteMagnitude
        for boundary in (unitStart + 1)...maximumBoundary {
          cumulativeLength += unitLengths[boundary - 1]
          let distance = abs(Double(cumulativeLength) - desiredBoundary)
          if distance < bestDistance {
            bestDistance = distance
            bestBoundary = boundary
          }
        }
        unitEnd = bestBoundary
      }

      result[sourceSegments[sourceIndex].id] = units[unitStart..<unitEnd]
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
      unitStart = unitEnd
    }
    return result
  }

  static func containsOrphanListMarker(_ segments: [SourceSegment]) -> Bool {
    segments.contains { isStandaloneListMarker($0.text) }
  }

  private enum ParagraphKind {
    case prose
    case listItem
    case quote
  }

  /// Copying from PDFs, terminals, and narrow web columns often inserts a
  /// newline at the visual wrap point. Blank lines and structural list/quote
  /// markers remain paragraph boundaries; ordinary single newlines become spaces.
  private static func normalizedParagraphs(from text: String) -> [String] {
    var paragraphs: [String] = []
    var currentLines: [String] = []
    var currentKind: ParagraphKind = .prose

    func flushCurrent() {
      let paragraph = currentLines.joined(separator: " ")
        .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !paragraph.isEmpty {
        paragraphs.append(paragraph)
      }
      currentLines.removeAll(keepingCapacity: true)
      currentKind = .prose
    }

    for rawLine in text.components(separatedBy: "\n") {
      let line = clean(rawLine)
      guard !line.isEmpty else {
        flushCurrent()
        continue
      }

      if isHeading(line) {
        flushCurrent()
        paragraphs.append(line)
      } else if isListItemStart(line) {
        flushCurrent()
        currentLines = [line]
        currentKind = .listItem
      } else if isQuoteStart(line) {
        if currentKind != .quote {
          flushCurrent()
          currentKind = .quote
        }
        currentLines.append(line)
      } else {
        currentLines.append(line)
      }
    }
    flushCurrent()
    return paragraphs
  }

  private static func isHeading(_ text: String) -> Bool {
    text.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil
  }

  private static func isQuoteStart(_ text: String) -> Bool {
    text.range(of: #"^>\s*\S"#, options: .regularExpression) != nil
  }

  private static func isListItemStart(_ text: String) -> Bool {
    if isStandaloneListMarker(text) { return true }
    let patterns = [
      #"^[-*•‣◦▪▫]\s+\S"#,
      #"^\d{1,3}[.)、:]\s+\S"#,
      #"^\(\d{1,3}\)\s+\S"#,
      #"^[A-Ha-h][.)]\s+\S"#,
      #"^[一二三四五六七八九十百]+[、.)]\s*\S"#,
      #"^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳]\s*\S"#,
    ]
    return patterns.contains {
      text.range(of: $0, options: .regularExpression) != nil
    }
  }

  private static func splitOversized(_ text: String) -> [String] {
    guard text.count > maximumSegmentLength else { return [text] }
    return hardWrap(text)
  }

  private static func translationUnits(in text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var upperBounds: [String.Index] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      upperBounds.append(range.upperBound)
      return true
    }
    guard !upperBounds.isEmpty else { return [text] }

    var units: [String] = []
    var lowerBound = text.startIndex
    for upperBound in upperBounds where lowerBound < upperBound {
      units.append(String(text[lowerBound..<upperBound]))
      lowerBound = upperBound
    }
    if lowerBound < text.endIndex {
      if units.isEmpty {
        units.append(String(text[lowerBound...]))
      } else {
        units[units.index(before: units.endIndex)] += String(text[lowerBound...])
      }
    }
    return units.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private static func splitTranslationUnit(_ unit: String) -> [String]? {
    guard unit.count >= 2 else { return nil }
    let midpoint = unit.index(unit.startIndex, offsetBy: unit.count / 2)
    let boundaryCharacters = CharacterSet(charactersIn: "\n，,；;：:、—–- ")
    let candidates = unit.indices.filter { index in
      guard index > unit.startIndex else { return false }
      let scalar = unit[index].unicodeScalars.first
      return scalar.map(boundaryCharacters.contains) ?? false
    }
    let splitIndex: String.Index
    if let closest = candidates.min(by: {
      unit.distance(from: $0, to: midpoint).magnitude
        < unit.distance(from: $1, to: midpoint).magnitude
    }) {
      splitIndex = unit.index(after: closest)
    } else {
      splitIndex = midpoint
    }
    guard splitIndex > unit.startIndex, splitIndex < unit.endIndex else { return nil }
    return [String(unit[..<splitIndex]), String(unit[splitIndex...])]
  }

  private static func proportionalCharacterSlices(
    _ translation: String,
    sourceSegments: [SourceSegment]
  ) -> [String: String] {
    let sourceLengths = sourceSegments.map { max(1, $0.text.count) }
    let totalSourceLength = max(1, sourceLengths.reduce(0, +))
    var sourceLengthSoFar = 0
    var lowerBound = translation.startIndex
    var result: [String: String] = [:]

    for index in sourceSegments.indices {
      let upperBound: String.Index
      if index == sourceSegments.index(before: sourceSegments.endIndex) {
        upperBound = translation.endIndex
      } else {
        sourceLengthSoFar += sourceLengths[index]
        let offset = Int(
          (Double(sourceLengthSoFar) / Double(totalSourceLength)
            * Double(translation.count)).rounded()
        )
        upperBound = translation.index(
          translation.startIndex,
          offsetBy: max(0, min(translation.count, offset))
        )
      }
      result[sourceSegments[index].id] = String(translation[lowerBound..<upperBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      lowerBound = upperBound
    }
    return result
  }

  private static func hardWrap(_ text: String) -> [String] {
    var remainder = text[...]
    var chunks: [String] = []

    while remainder.count > maximumSegmentLength {
      let limit = remainder.index(remainder.startIndex, offsetBy: maximumSegmentLength)
      let prefix = remainder[remainder.startIndex..<limit]
      let preferredBreak = prefix.lastIndex(where: {
        $0.isWhitespace || "，,、—–-".contains($0)
      })
      let split = preferredBreak.map { remainder.index(after: $0) } ?? limit
      let chunk = clean(String(remainder[..<split]))
      if !chunk.isEmpty { chunks.append(chunk) }
      remainder = remainder[split...]
    }

    let tail = clean(String(remainder))
    if !tail.isEmpty { chunks.append(tail) }
    return chunks
  }

  private static func clean(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isStandaloneListMarker(_ text: String) -> Bool {
    let patterns = [
      #"^\d{1,3}[.)、:]$"#,
      #"^\(\d{1,3}\)$"#,
      #"^[A-Ha-h][.)]$"#,
      #"^[一二三四五六七八九十百]+[、.)]$"#,
      #"^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳]$"#,
      #"^[-*•‣◦▪▫]$"#,
    ]
    return patterns.contains {
      text.range(of: $0, options: .regularExpression) != nil
    }
  }

  private static func localDifficultyScore(_ text: String) -> Int {
    var score = min(55, text.count / 2)
    score += min(18, text.filter { ",，、;；:：()（）".contains($0) }.count * 3)
    let lower = text.lowercased()
    let complexityMarkers = [
      "although", "whereas", "which", "that", "unless", "despite",
      "ことに", "わけ", "ものの", "にもかかわらず", "にすぎない",
    ]
    score += complexityMarkers.filter { lower.contains($0) }.count * 8
    return max(10, min(100, score))
  }
}
