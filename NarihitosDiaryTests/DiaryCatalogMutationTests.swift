import Foundation
import Testing

@testable import NarihitosDiary

@MainActor
struct DiaryCatalogMutationTests {
  private func handle(_ fake: FakeCatalog) -> CatalogItemHandle {
    CatalogItemHandle(
      session: fake.session, resource: UUID(), version: UUID(), kind: DiarySnippetSupportPolicy.kind
    )
  }

  private func page(_ handle: CatalogItemHandle) -> CatalogPage {
    CatalogPage(
      session: handle.session,
      summaries: [
        CatalogSummary(
          handle: handle, assetID: "synthetic", resourceOrder: "synthetic", createdAt: .now,
          title: "Synthetic", favorite: false)
      ],
      recovery: [], continuation: nil, examinedCandidates: 1, isDiscovering: false)
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw DiaryEditIssue.busy }
      await Task.yield()
    }
  }

  @Test func ownPublicationReopensObservedVersionAndOldDetailCannotClearIt() async throws {
    let fake = FakeCatalog()
    let old = handle(fake)
    let updated = handle(fake)
    fake.detailPayload = CatalogRecoveryText(body: "Synthetic")
    fake.queuedPages = [page(old)]
    let model = CatalogModel(catalog: fake)
    defer { model.stop() }
    model.setVisible(true)
    model.activate()
    try await waitUntil { model.state == .end }
    model.open(old)
    try await waitUntil { model.detail != nil }
    model.holdSelectionForMutation(assetID: "synthetic")
    fake.queuedPages = [page(updated)]
    fake.onEvent?(.invalidated)
    #expect(model.selectedItem == old)
    try await waitUntil { model.detail?.handle == updated }
    model.clearDetail(expectedHandle: old)
    #expect(model.selectedItem == updated)
    #expect(model.detail?.handle == updated)
  }

  @Test func formerFolderMutationCannotReopenSameIDInANewFolder() async throws {
    let fake = FakeCatalog()
    let old = handle(fake)
    let other = handle(fake)
    fake.detailPayload = CatalogRecoveryText(body: "Synthetic")
    fake.queuedPages = [page(old)]
    let model = CatalogModel(catalog: fake)
    defer { model.stop() }
    model.setVisible(true)
    model.activate(destinationID: .make())
    try await waitUntil { model.state == .end }
    model.open(old)
    try await waitUntil { model.detail != nil }
    model.holdSelectionForMutation(assetID: "synthetic")
    fake.queuedPages = [page(other)]
    model.changeScope(.make())
    try await waitUntil { model.state == .end }
    #expect(model.selectedItem == nil)
    #expect(model.detail == nil)
  }
}
