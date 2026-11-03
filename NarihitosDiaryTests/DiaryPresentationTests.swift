import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct DiaryPresentationTests {
  @Test func editorPreservesFailedInputAndConfirmsDiscard() async throws {
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    try await fixture.activate("diary-edit")
    try await fixture.waitUntil { fixture.actions.editor != nil }
    let editor = try #require(fixture.actions.editor)
    editor.body = "Synthetic unsaved text. 한국어 입력."
    fixture.state.showDetail = false
    #expect(fixture.actions.editor?.body == editor.body)
    fixture.store.failAcceptance = true
    try await fixture.activate("diary-save-body")
    try await fixture.waitUntil { editor.issue != nil }
    #expect(editor.body == "Synthetic unsaved text. 한국어 입력.")
    #expect(!editor.locksBody)
    #expect(fixture.store.records.isEmpty)
    try await fixture.activate("diary-cancel-edit")
    try await fixture.waitUntil { fixture.element("diary-keep-editing") != nil }
    try await fixture.activate("diary-keep-editing")
    #expect(fixture.actions.editor?.id == editor.id)
    try await fixture.activate("diary-cancel-edit")
    try await fixture.activate("diary-discard-edit")
    try await fixture.waitUntil { fixture.host.presentedViewController == nil }
    #expect(fixture.actions.editor == nil)
  }

  @Test func favoriteControlSubmitsDesiredStateWithoutRegeneratingTitle() async throws {
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    try await fixture.activate("diary-favorite")
    try await fixture.waitUntil {
      !fixture.store.candidates.isEmpty && !fixture.edits.hasActiveWork
    }
    let candidate = try #require(fixture.store.candidates.values.first)
    #expect(candidate.favorite)
    #expect(candidate.body.text == "Original diary.")
    #expect(candidate.title == "Original diary")
    #expect(fixture.titleModel.calls == 0)
  }

  @Test func uncertainSaveKeepsTheSubmittedIdentityUntilAcknowledgmentIsReadable() async throws {
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    try await fixture.activate("diary-edit")
    try await fixture.waitUntil { fixture.actions.editor != nil }
    let editor = try #require(fixture.actions.editor)
    editor.body = "Synthetic submitted text."
    fixture.store.failAfterAcceptance = true
    fixture.store.failLookupAfterAcceptance = true
    await editor.save()
    #expect(editor.issue != nil)
    #expect(editor.locksBody)
    #expect(fixture.actions.editor?.id == editor.id)
    let submittedID = try #require(fixture.store.records.keys.first)
    fixture.store.failLookup = false
    fixture.edits.prerequisiteChanged()
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    await editor.save()
    #expect(fixture.actions.editor == nil)
    #expect(fixture.store.records.keys.sorted() == [submittedID])
    #expect(fixture.store.acceptCount == 1)
    #expect(fixture.store.candidates[submittedID]?.body.text == "Synthetic submitted text.")
  }

  @Test func bodySaveFavoriteAndReplayUseAccessibleControlsAndLegacyHasNoMutations() async throws {
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    let favorite = try #require(fixture.element("diary-favorite"))
    #expect(favorite.accessibilityLabel == "Favorite")
    #expect(favorite.accessibilityValue == "Off")
    #expect(favorite.accessibilityFrame.width >= 44)
    #expect(favorite.accessibilityFrame.height >= 44)
    try await fixture.activate("diary-edit")
    try await fixture.waitUntil { fixture.actions.editor != nil }
    fixture.actions.editor?.body = ""
    try await fixture.activate("diary-save-body")
    try await fixture.waitUntil { fixture.actions.editor == nil && !fixture.edits.hasActiveWork }
    let saved = try #require(fixture.store.candidates.values.first)
    #expect(saved.body.text.isEmpty)
    #expect(saved.title == "Untitled")
    try await fixture.activate("diary-audio-play-pause")
    try await fixture.waitUntil { fixture.replay.state == .playing }
    #expect(fixture.element("diary-audio-play-pause")?.accessibilityLabel == "Pause audio")
    try await fixture.waitUntil {
      fixture.element("diary-audio-position")?.accessibilityTraits.contains(.notEnabled) == false
    }
    let position = try #require(fixture.element("diary-audio-position"))
    #expect(position.accessibilityLabel == "Audio position")
    position.accessibilityIncrement()
    try await fixture.waitUntil { fixture.replay.elapsed == 15 }
    #expect(fixture.replay.elapsed == 15)
    position.accessibilityDecrement()
    try await fixture.waitUntil { fixture.replay.elapsed == 0 }
    #expect(fixture.replay.elapsed == 0)
    await fixture.replay.stop()
    fixture.close()
    let legacy = try await DiaryPresentationFixture(legacy: true)
    defer { legacy.close() }
    try await legacy.waitUntil { legacy.element("diary-audio-play-pause") != nil }
    #expect(legacy.element("diary-edit") == nil)
    #expect(legacy.element("diary-favorite") == nil)
  }

  @Test func syntheticDetailEditorAndPrivacyLayoutsAreRenderableAcrossSizes() async throws {
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    try await fixture.preview("detail-light", size: CGSize(width: 375, height: 812))
    fixture.state.dark = true
    fixture.state.large = true
    try await fixture.preview("detail-dark-large", size: CGSize(width: 375, height: 812))
    fixture.state.dark = false
    fixture.state.large = false
    try await fixture.preview("detail-landscape", size: CGSize(width: 812, height: 375))
    try await fixture.activate("diary-edit")
    try await fixture.waitUntil { fixture.actions.editor != nil }
    try await fixture.preview("editor-light", size: CGSize(width: 375, height: 812))
    fixture.state.dark = true
    fixture.state.large = true
    try await fixture.preview("editor-dark-large", size: CGSize(width: 375, height: 812))
    fixture.state.phase = .inactive
    try await fixture.preview("editor-inactive", size: CGSize(width: 375, height: 812))
    #expect(fixture.actions.editor?.body == "Original diary.")
  }
}
