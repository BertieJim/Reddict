import Foundation

@main
struct TextSegmenterSmoke {
  static func main() {
    let sources = [
      SourceSegment(id: "s1", text: "First sentence."),
      SourceSegment(id: "s2", text: "Second sentence!"),
      SourceSegment(id: "s3", text: "Third sentence?"),
    ]
    let completeTranslation = "第一句。第二句！第三句？"
    let aligned = TextSegmenter.alignedTranslations(
      from: completeTranslation,
      to: sources
    )

    precondition(aligned["s1"] == "第一句。")
    precondition(aligned["s2"] == "第二句！")
    precondition(aligned["s3"] == "第三句？")
    precondition(sources.allSatisfy { aligned[$0.id]?.isEmpty == false })

    let clauseSources = [
      SourceSegment(id: "s1", text: "One"),
      SourceSegment(id: "s2", text: "Two"),
    ]
    let singleSentence = "第一部分，第二部分。"
    let clauseAligned = TextSegmenter.alignedTranslations(
      from: singleSentence,
      to: clauseSources
    )
    precondition(clauseAligned["s1"] == "第一部分，")
    precondition(clauseAligned["s2"] == "第二部分。")

    let wrappedCopy = """
      Each prompt file follows the family format: style anchor into the French guide's own templates, the
           exact operating prompt, the styled/chrome distribution, a five-line showcase, and a reflection on what
           converted well and what resisted. The merged file's meta.style_prompts now has an fr entry, every
           entry's fr block gained styles + styled (same shape as es), and the pre-merge original is backed up at
           kotkit-all-styles.json.bak.
      """
    let wrappedPlan = TextSegmenter.plan(wrappedCopy)
    precondition(wrappedPlan.segments.count == 2)
    precondition(wrappedPlan.segments.allSatisfy { !$0.text.contains("\n") })
    precondition(wrappedPlan.segments.allSatisfy { $0.paragraphIndex == 0 })
    precondition(
      wrappedPlan.segments[0].text.hasSuffix("what resisted.")
    )
    precondition(
      wrappedPlan.segments[1].text.hasSuffix("kotkit-all-styles.json.bak.")
    )

    let paragraphs = TextSegmenter.plan(
      "First sentence. Second sentence.\n\nThird paragraph sentence."
    )
    precondition(paragraphs.segments.count == 3)
    precondition(paragraphs.segments.map(\.paragraphIndex) == [0, 0, 1])
    precondition(
      paragraphs.normalizedText
        == "First sentence. Second sentence.\n\nThird paragraph sentence."
    )

    print("TEXT_SEGMENTER_SMOKE_OK")
  }
}
