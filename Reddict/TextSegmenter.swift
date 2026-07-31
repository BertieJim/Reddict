import Foundation
import NaturalLanguage

struct SourceSegment: Codable, Identifiable, Sendable {
    let id: String
    let text: String
    let difficultyScore: Int

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case difficultyScore = "difficulty_score"
    }

    init(id: String, text: String, difficultyScore: Int = 0) {
        self.id = id
        self.text = text
        self.difficultyScore = max(0, min(100, difficultyScore))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        difficultyScore = max(
            0,
            min(100, try container.decodeIfPresent(Int.self, forKey: .difficultyScore) ?? 0)
        )
    }
}

struct SegmentationPlan: Sendable {
    let segments: [SourceSegment]
    let requiresAISegmentation: Bool
}

enum TextSegmenter {
    private static let preferredSegmentLength = 900
    private static let preferredBatchLength = 1_500
    private static let maximumSegmentsPerBatch = 1

    static func plan(_ source: String) -> SegmentationPlan {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return SegmentationPlan(segments: [], requiresAISegmentation: false)
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized
        var candidates: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let sentence = clean(String(normalized[range]))
            if !sentence.isEmpty {
                candidates.append(sentence)
            }
            return true
        }

        if candidates.isEmpty {
            candidates = [normalized]
        }

        candidates = candidates.flatMap { candidate in
            let lines = candidate
                .components(separatedBy: .newlines)
                .map(clean)
                .filter { !$0.isEmpty }
            return lines.isEmpty ? [candidate] : lines
        }
        candidates = mergeStandaloneListMarkers(candidates)
        let tokenizerFoundSingleBlock = candidates.count == 1
        let refined = candidates.flatMap(splitOversized)
        let segments = refined.enumerated().map {
            SourceSegment(
                id: "s\($0.offset + 1)",
                text: $0.element,
                difficultyScore: localDifficultyScore($0.element)
            )
        }
        let punctuationCount = normalized.filter { ".!?。！？；;\n".contains($0) }.count
        let hasFinalTerminator = normalized.last.map { ".!?。！？".contains($0) } ?? false
        let lacksClearBoundary = tokenizerFoundSingleBlock
            && normalized.count >= 220
            && punctuationCount == (hasFinalTerminator ? 1 : 0)
        return SegmentationPlan(
            segments: segments,
            requiresAISegmentation: lacksClearBoundary
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
            let wouldOverflow = !current.isEmpty
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

    static func containsOrphanListMarker(_ segments: [SourceSegment]) -> Bool {
        segments.contains { isStandaloneListMarker($0.text) }
    }

    private static func splitOversized(_ text: String) -> [String] {
        guard text.count > preferredSegmentLength else { return [text] }

        let boundaries = CharacterSet(charactersIn: "\n；;：:")
        var chunks = text
            .components(separatedBy: boundaries)
            .map(clean)
            .filter { !$0.isEmpty }

        if chunks.count <= 1 {
            chunks = hardWrap(text)
        } else {
            chunks = chunks.flatMap { $0.count > preferredSegmentLength ? hardWrap($0) : [$0] }
        }
        return chunks
    }

    private static func hardWrap(_ text: String) -> [String] {
        var remainder = text[...]
        var chunks: [String] = []

        while remainder.count > preferredSegmentLength {
            let limit = remainder.index(remainder.startIndex, offsetBy: preferredSegmentLength)
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

    private static func mergeStandaloneListMarkers(_ candidates: [String]) -> [String] {
        var merged: [String] = []
        var pendingMarkers: [String] = []

        for candidate in candidates {
            if isStandaloneListMarker(candidate) {
                pendingMarkers.append(candidate)
                continue
            }

            if pendingMarkers.isEmpty {
                merged.append(candidate)
            } else {
                merged.append((pendingMarkers + [candidate]).joined(separator: " "))
                pendingMarkers.removeAll(keepingCapacity: true)
            }
        }

        merged.append(contentsOf: pendingMarkers)
        return merged
    }

    private static func isStandaloneListMarker(_ text: String) -> Bool {
        let patterns = [
            #"^\d{1,3}[.)、:]$"#,
            #"^\(\d{1,3}\)$"#,
            #"^[A-Ha-h][.)]$"#,
            #"^[一二三四五六七八九十百]+[、.)]$"#,
            #"^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳]$"#,
            #"^[-*•‣◦▪▫]$"#
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
            "ことに", "わけ", "ものの", "にもかかわらず", "にすぎない"
        ]
        score += complexityMarkers.filter { lower.contains($0) }.count * 8
        return max(10, min(100, score))
    }
}
