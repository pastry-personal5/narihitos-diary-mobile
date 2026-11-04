import Foundation
import Testing

@testable import NarihitosDiary

// swiftlint:disable trailing_comma

@MainActor
private final class StubTitleModel: DiaryTitleModelPort {
  var isAvailable = true
  var modelIdentifier: String?
  var chunkResponses: [[String]?] = []
  var replies: [TitleModelReply] = []
  var requestedLimits: [Int] = []
  var requests: [String] = []
  var requestedLanguages: [String] = []
  var requestedChunkTokens: [Int] = []
  var requestedChunkCounts: [Int] = []

  // swiftlint:disable opening_brace
  func chunks(for text: String, maximumTokens: Int, maximumChunks: Int) async throws
    -> [String]?
  {
    requestedChunkTokens.append(maximumTokens)
    requestedChunkCounts.append(maximumChunks)
    return chunkResponses.isEmpty ? [text] : (chunkResponses.removeFirst() ?? [])
  }

  func summarize(_ text: String, language: String, maximumOutputTokens: Int) async throws
    -> TitleModelReply
  {
    requests.append(text)
    requestedLanguages.append(language)
    requestedLimits.append(maximumOutputTokens)
    return replies.removeFirst()
  }
  // swiftlint:enable opening_brace
}

@MainActor
private final class SuspendedTitleModel: DiaryTitleModelPort {
  let isAvailable = true
  var modelIdentifier: String? { nil }
  var pending: CheckedContinuation<TitleModelReply, Never>?
  var calls = 0

  // swiftlint:disable opening_brace
  func chunks(for text: String, maximumTokens _: Int, maximumChunks _: Int) async throws
    -> [String]?
  { [text] }

  func summarize(_ text: String, language _: String, maximumOutputTokens _: Int) async throws
    -> TitleModelReply
  {
    calls += 1
    return await withCheckedContinuation { pending = $0 }
  }
  // swiftlint:enable opening_brace
}

@MainActor
private struct StubTitleLanguageDetector: DiaryTitleLanguageDetector {
  var confidence = 1.0

  func assess(_ text: String) -> TitleLanguageAssessment? {
    let korean = text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    return TitleLanguageAssessment(language: korean ? "ko" : "en", confidence: confidence)
  }
}

@MainActor
struct DiaryTitlePolicyTests {
  private func policy(
    _ model: any DiaryTitleModelPort, confidence: Double = 1.0,
    timeout: Duration = .seconds(30)
  ) -> DiaryTitlePolicy {
    DiaryTitlePolicy(
      model: model, languageDetector: StubTitleLanguageDetector(confidence: confidence),
      timeout: timeout)
  }

  @Test func fallbackUsesNativeSentenceAndCapsGraphemes() {
    let title = DiaryTitlePolicy.fallback("  First sentence. Second sentence.")
    #expect(title.text == "First sentence.")
    #expect(title.provenance.originID.description == "first-sentence")
    let unicode = DiaryTitlePolicy.fallback(String(repeating: "👩🏽‍💻", count: 35))
    #expect(unicode.text.count == 30)
    #expect(unicode.text.last == "…")
    #expect(DiaryTitlePolicy.fallback(" \n ").text == "Untitled")
  }

  @Test func unavailableModelKeepsFallback() async throws {
    let model = StubTitleModel()
    model.isAvailable = false
    let title = await policy(model).title(
      for: try DiaryBody("A complete diary sentence. Another one."))
    #expect(title.text == "A complete diary sentence.")
    #expect(model.requests.isEmpty)
  }

  @Test func uncertainBodyLanguageUsesFallbackWithoutModelCall() async throws {
    let model = StubTitleModel()
    let title = await policy(model, confidence: 0.79).title(
      for: try DiaryBody("I wrote about my day in the park."))
    #expect(title.provenance.originID.description == "first-sentence")
    #expect(model.requests.isEmpty)
  }

  @Test func modelOutputIsCappedAndRecordsOrigin() async throws {
    let model = StubTitleModel()
    model.modelIdentifier = "local-model-fixture"
    model.replies = [TitleModelReply(text: String(repeating: "Diary ", count: 8), outputTokens: 20)]
    let title = await policy(model).title(
      for: try DiaryBody(String(repeating: "A thoughtful day at home. ", count: 12)))
    #expect(title.text.count == 30)
    #expect(title.text.last == "…")
    #expect(title.provenance.originID.description == "apple-ai")
    #expect(title.provenance.promptRevision == "title-v1")
    #expect(title.provenance.osVersion?.contains(".") == true)
    #expect(title.provenance.modelID == "local-model-fixture")
    #expect(model.requestedLimits == [64])
  }

  @Test func skippedBodyPartFallsBackWithoutModelCall() async throws {
    let model = StubTitleModel()
    model.chunkResponses = [["Only a fragment"]]
    let title = await policy(model).title(
      for: try DiaryBody("Only a fragment. Then more text."))
    #expect(title.provenance.originID.description == "first-sentence")
    #expect(model.requests.isEmpty)
  }

  @Test func moreThanEightChunksFallsBackBeforeInference() async throws {
    let model = StubTitleModel()
    let body = String(repeating: "A thoughtful day at home. ", count: 9)
    model.chunkResponses = [Array(repeating: "A thoughtful day at home. ", count: 9)]
    let title = await policy(model).title(for: try DiaryBody(body))
    #expect(title.provenance.originID.description == "first-sentence")
    #expect(model.requests.isEmpty)
  }

  @Test func overlongIntermediateSummaryFallsBack() async throws {
    let model = StubTitleModel()
    let first = String(repeating: "I walked outside. ", count: 8)
    let second = String(repeating: "I cooked dinner. ", count: 8)
    model.chunkResponses = [[first, second]]
    model.replies = [TitleModelReply(text: String(repeating: "A", count: 81), outputTokens: 50)]
    let title = await policy(model).title(for: try DiaryBody(first + second))
    #expect(title.provenance.originID.description == "first-sentence")
    #expect(model.requestedLimits == [128])
    let tooManyTokens = StubTitleModel()
    tooManyTokens.chunkResponses = [[first, second]]
    tooManyTokens.replies = [TitleModelReply(text: "A walk in the park", outputTokens: 129)]
    let tokenOverflow = await policy(tooManyTokens).title(for: try DiaryBody(first + second))
    #expect(tokenOverflow.provenance.originID.description == "first-sentence")
  }

  @Test func emptyEditedBodyUsesUntitledWithoutModelCall() async throws {
    let model = StubTitleModel()
    let title = await policy(model).title(for: try DiaryBody(""))
    #expect(title.text == "Untitled")
    #expect(title.provenance.originID.description == "empty-body")
    #expect(model.requests.isEmpty)
  }

  @Test func aiTitleCapsExtendedGraphemeClusters() async throws {
    let model = StubTitleModel()
    let grapheme = "e\u{301}"
    model.replies = [
      TitleModelReply(text: String(repeating: grapheme, count: 35), outputTokens: 20)
    ]
    let body = try DiaryBody(String(repeating: "I wrote about my day. ", count: 12))
    let title = await policy(model).title(for: body)
    #expect(title.provenance.originID.description == "apple-ai")
    #expect(title.text.count == 30)
    #expect(title.text.last == "…")
    #expect(String(title.text.dropLast()) == String(repeating: grapheme, count: 29))
  }

  @Test func longBodyUsesEveryChunkBeforeFinalTitle() async throws {
    let model = StubTitleModel()
    let first = String(repeating: "I walked in the park. ", count: 12)
    let second = String(repeating: "I made dinner at home. ", count: 12)
    model.chunkResponses = [[first, second]]
    model.replies = [
      TitleModelReply(text: "A walk in the park", outputTokens: 12),
      TitleModelReply(text: "Dinner at home", outputTokens: 10),
      TitleModelReply(text: "A walk and dinner", outputTokens: 15),
    ]
    let title = await policy(model).title(for: try DiaryBody(first + second))
    #expect(title.text == "A walk and dinner")
    #expect(model.requests == [first, second, "A walk in the park\nDinner at home"])
    #expect(model.requestedLimits == [128, 128, 64])
    #expect(model.requestedChunkTokens == [2_000, 2_000])
    #expect(model.requestedChunkCounts == [8, 1])
  }

  @Test func wrongLanguageAndExcessTokensFallBack() async throws {
    let body = try DiaryBody(String(repeating: "I wrote about my day. ", count: 12))
    let wrongLanguage = StubTitleModel()
    wrongLanguage.replies = [TitleModelReply(text: "오늘의 일기", outputTokens: 12)]
    let first = await policy(wrongLanguage).title(for: body)
    #expect(first.provenance.originID.description == "first-sentence")

    let excess = StubTitleModel()
    excess.replies = [TitleModelReply(text: "A day of writing", outputTokens: 65)]
    let second = await policy(excess).title(for: body)
    #expect(second.provenance.originID.description == "first-sentence")
  }

  @Test func visiblyUnsafeModelFormatsFallBack() async throws {
    let body = try DiaryBody(String(repeating: "I wrote about my day. ", count: 12))
    for unsafe in ["Title: A day of writing", "A day of writing 🎉", "\"A day of writing\""] {
      let model = StubTitleModel()
      model.replies = [TitleModelReply(text: unsafe, outputTokens: 12)]
      let title = await policy(model).title(for: body)
      #expect(title.provenance.originID.description == "first-sentence")
    }
  }

  @Test func koreanBodyUsesKoreanModelLanguage() async throws {
    let model = StubTitleModel()
    model.replies = [
      TitleModelReply(text: "집에서 일기를 쓴 하루", outputTokens: 14)
    ]
    let body = try DiaryBody(String(repeating: "오늘은 집에서 하루를 보내고 일기를 썼다. ", count: 12))
    let title = await policy(model).title(for: body)
    #expect(title.provenance.originID.description == "apple-ai")
    #expect(model.requestedLanguages == ["ko"])
  }

  @Test func deadlineReturnsFallbackAndFencesUnsettledModel() async throws {
    let model = SuspendedTitleModel()
    let policy = policy(model, timeout: .milliseconds(300))
    let body = try DiaryBody(String(repeating: "I wrote about my day. ", count: 12))
    let operation = Task { await policy.title(for: body) }
    for _ in 0..<100 where model.pending == nil { await Task.yield() }
    #expect(model.pending != nil)
    let timedOut = await operation.value
    #expect(timedOut.provenance.originID.description == "first-sentence")
    #expect(model.calls == 1)
    let stillBusy = await policy.title(for: body)
    #expect(stillBusy.provenance.originID.description == "first-sentence")
    #expect(model.calls == 1)
    model.pending?.resume(returning: TitleModelReply(text: "Late title", outputTokens: 2))
  }

  @Test func completedTitleReportsGeneratingThenIdle() async throws {
    let model = StubTitleModel()
    model.replies = [TitleModelReply(text: "A day of writing", outputTokens: 5)]
    let policy = policy(model)
    let owner = DiaryTitleWorkOwner.edit(submissionID: UUID())
    var changes: [DiaryTitleWorkSnapshot?] = []
    policy.onWorkChange = { changes.append($0) }
    #expect(policy.workSnapshot == nil)
    let result = await policy.title(for: try DiaryBody("I wrote about my day."), owner: owner)
    #expect(result.text == "A day of writing")
    #expect(changes.count == 2)
    #expect(changes.first??.owner == owner)
    #expect(changes.first??.phase == .generating)
    #expect(changes.last! == nil)
    #expect(policy.workSnapshot == nil)
    #expect(!policy.hasActiveWork)
  }

  @Test(arguments: [true, false])
  func timeoutKeepsOriginalOwnerUntilSettlement(recordingFirst: Bool) async throws {
    let model = SuspendedTitleModel()
    let policy = policy(model, timeout: .milliseconds(300))
    let recording = DiaryTitleWorkOwner.recording(
      jobID: UUID().uuidString.lowercased(), attemptID: UUID(), attemptGeneration: 3,
      destinationRevision: 2, bodyRevision: 1)
    let edit = DiaryTitleWorkOwner.edit(submissionID: UUID())
    let owner = recordingFirst ? recording : edit
    let competitor = recordingFirst ? edit : recording
    var changes: [DiaryTitleWorkSnapshot?] = []
    policy.onWorkChange = { changes.append($0) }
    let body = try DiaryBody("I wrote about my day. Another sentence.")
    let operation = Task { await policy.title(for: body, owner: owner) }
    for _ in 0..<1_000 where model.pending == nil { await Task.yield() }
    let pending = try #require(model.pending)
    let started = try #require(policy.workSnapshot)
    #expect(started.owner == owner)
    #expect(started.phase == .generating)
    let fallback = await operation.value
    #expect(fallback.provenance.originID.description == "first-sentence")
    let settling = try #require(policy.workSnapshot)
    #expect(settling.operationID == started.operationID)
    #expect(settling.owner == owner)
    #expect(settling.phase == .settling)
    #expect(policy.hasActiveWork)

    let competing = await policy.title(for: body, owner: competitor)
    #expect(competing == fallback)
    #expect(policy.workSnapshot == settling)
    #expect(model.calls == 1)
    #expect(changes.count == 2)
    model.pending = nil
    pending.resume(returning: TitleModelReply(text: "Late model title", outputTokens: 3))
    for _ in 0..<1_000 where policy.hasActiveWork { await Task.yield() }
    #expect(policy.workSnapshot == nil)
    #expect(changes.count == 3)
    #expect(changes.last! == nil)
    #expect(fallback.text == "I wrote about my day.")

    let next = Task { await policy.title(for: body, owner: competitor) }
    for _ in 0..<1_000 where model.pending == nil { await Task.yield() }
    let nextPending = try #require(model.pending)
    #expect(policy.workSnapshot?.operationID != started.operationID)
    #expect(policy.workSnapshot?.owner == competitor)
    #expect(policy.workSnapshot?.phase == .generating)
    nextPending.resume(returning: TitleModelReply(text: "A day of writing", outputTokens: 5))
    #expect(await next.value.text == "A day of writing")
    #expect(policy.workSnapshot == nil)
    #expect(changes.count == 5)
  }
}

// swiftlint:enable trailing_comma
