import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
@Suite(.serialized)
struct DiaryDeletionPresentationTests {
  @Test func fullWidthDeleteUsesInlineConfirmationAndCancel() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let fixture = try await DiaryPresentationFixture()
    defer { fixture.close() }
    let deletion = MemoryDiaryDeletion()
    fixture.actions.configureDeletion(deletion) { fixture.state.showDetail = false }
    try await fixture.waitUntil { !fixture.edits.hasActiveWork }
    try await fixture.preview("delete-button", size: CGSize(width: 375, height: 812))
    let button = try #require(fixture.element("diary-delete"))
    #expect(button.accessibilityLabel == "Delete Diary Snippet")
    #expect(button.accessibilityFrame.width >= 295)
    #expect(button.accessibilityFrame.height >= 44)
    try await fixture.activate("diary-delete")
    try await fixture.waitUntil { fixture.element("diary-confirm-delete") != nil }
    #expect(fixture.host.presentedViewController == nil)
    #expect(deletion.calls.isEmpty)
    scrollToBottom(fixture.host.view)
    try await fixture.preview("delete-confirmation-light", size: CGSize(width: 375, height: 812))
    fixture.state.dark = true
    fixture.state.large = true
    try await fixture.preview(
      "delete-confirmation-dark-large", size: CGSize(width: 375, height: 812))
    scrollToBottom(fixture.host.view)
    try await fixture.preview(
      "delete-confirmation-dark-large", size: CGSize(width: 375, height: 812))
    fixture.state.dark = false
    fixture.state.large = false
    try await fixture.activate("diary-cancel-delete")
    try await fixture.waitUntil { fixture.element("diary-delete") != nil }
    #expect(deletion.calls.isEmpty)
    try await fixture.activate("diary-delete")
    fixture.state.phase = .inactive
    try await fixture.waitUntil { fixture.actions.deletionConfirmation == nil }
    #expect(deletion.calls.isEmpty)
    fixture.state.phase = .active
    try await fixture.activate("diary-delete")
    try await fixture.activate("diary-confirm-delete")
    try await fixture.waitUntil { !fixture.state.showDetail }
    #expect(deletion.calls.count == 1)
  }

  private func scrollToBottom(_ view: UIView) {
    view.layoutIfNeeded()
    if let scroll = view as? UIScrollView {
      let bottom = max(
        -scroll.adjustedContentInset.top,
        scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
      scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    } else {
      for child in view.subviews { scrollToBottom(child) }
    }
  }
}
