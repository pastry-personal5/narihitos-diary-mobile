// swift-format wraps multiline declarations and collections.
// swiftlint:disable opening_brace trailing_comma
import SwiftUI
import Testing
import UIKit

@testable import NarihitosDiary

@MainActor
final class MemoryManualDiaryStore: ManualDiaryStorePort {
  var records: [ManualDiaryRecord] = []
  var submissions: [ManualDiarySubmission] = []
  var failAfterAccept = false
  var permitsPublish = false
  private var bodies: [UUID: DiaryBody] = [:]

  func accept(_ submission: ManualDiarySubmission) async throws -> ManualDiaryRecord {
    submissions.append(submission)
    if let record = records.first(where: { $0.id == submission.id }) { return record }
    let record = ManualDiaryRecord(
      id: submission.id, destinationID: "manual-test", folderName: "Synthetic",
      needsTitle: true, issue: nil)
    records.append(record)
    bodies[record.id] = try DiaryBody(submission.body)
    if failAfterAccept { throw DiaryEditIssue.storage }
    return record
  }

  func inventory() async throws -> [ManualDiaryRecord] { records }
  func body(_ record: ManualDiaryRecord) async throws -> DiaryBody {
    try #require(bodies[record.id])
  }
  func finalize(_ record: ManualDiaryRecord, title: GeneratedDiaryTitle) async throws
    -> ManualDiaryRecord
  {
    var ready = record
    ready.needsTitle = false
    records = records.map { $0.id == ready.id ? ready : $0 }
    return ready
  }
  func publish(_ record: ManualDiaryRecord) async throws -> Bool { permitsPublish }
}

@MainActor
@Suite(.serialized)
struct ManualDiaryEditorTests {
  @Test func blankTextIsRejectedAndUncertainSaveKeepsTheSameSnapshot() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let store = MemoryManualDiaryStore()
    let creation = makeCreation(store)
    creation.activate()
    defer { creation.deactivate() }
    let editor = ManualDiaryEditorModel(creation: creation)
    editor.body = " \n\t"
    #expect(!editor.canSave)
    await editor.save()
    #expect(store.submissions.isEmpty)
    editor.body = "  A manually entered paragraph.\n\n한글.  "
    store.failAfterAccept = true
    await editor.save()
    #expect(editor.message != nil)
    #expect(editor.submission?.body == editor.body)
    let first = try #require(editor.submission)
    store.failAfterAccept = false
    var acknowledged = 0
    editor.onAccepted = { acknowledged += 1 }
    await editor.save()
    #expect(acknowledged == 1)
    #expect(editor.submission == first)
    #expect(store.records.count == 1)
    #expect(store.submissions.allSatisfy { $0 == first })
  }

  @Test func editorHasCompactTopRightBitmapActionsAndCancelDoesNotSubmit() async throws {
    try await HostedUITestSession.acquire()
    defer { HostedUITestSession.release() }
    let store = MemoryManualDiaryStore()
    let creation = makeCreation(store)
    creation.activate()
    defer { creation.deactivate() }
    let editor = ManualDiaryEditorModel(creation: creation)
    var cancelled = 0
    let root = ManualDiaryEditorView(editor: editor, cancel: { cancelled += 1 }, chooseFolder: {})
      .environment(\.scenePhase, .active)
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(rootView: root)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKey()
    }
    let cancel = try await element("manual-diary-cancel", root: host.view, window: window)
    let save = try await element("manual-diary-save", root: host.view, window: window)
    #expect(cancel.accessibilityLabel == "Cancel")
    #expect(save.accessibilityLabel == "Save")
    for button in [cancel, save] {
      #expect(button.accessibilityTraits.contains(.button))
      #expect(button.accessibilityFrame.width >= 44)
      #expect(button.accessibilityFrame.width < window.bounds.width / 2)
      #expect(button.accessibilityFrame.minX > window.bounds.midX)
      #expect(button.accessibilityFrame.minY < window.bounds.height / 3)
    }
    #expect(cancel.accessibilityActivate())
    #expect(cancelled == 1)
    #expect(store.submissions.isEmpty)
    editor.body = "Unsaved words."
    #expect(cancel.accessibilityActivate())
    let discard = try await element("manual-diary-discard", root: host.view, window: window)
    #expect(cancelled == 1)
    #expect(discard.accessibilityActivate())
    #expect(cancelled == 2)
    #expect(store.submissions.isEmpty)
    try await previews(window: window, host: host)
  }

  private func previews<Content: View>(window: UIWindow, host: UIHostingController<Content>)
    async throws
  {
    for (name, size, dark, large) in [
      ("small", CGSize(width: 375, height: 812), false, false),
      ("large", CGSize(width: 430, height: 932), false, false),
      ("landscape", CGSize(width: 812, height: 375), false, false),
      ("dark-large", CGSize(width: 430, height: 932), true, true),
    ] {
      window.frame = CGRect(origin: .zero, size: size)
      host.overrideUserInterfaceStyle = dark ? .dark : .light
      host.traitOverrides.preferredContentSizeCategory =
        large ? .accessibilityExtraExtraExtraLarge : .large
      try await Task.sleep(for: .milliseconds(100))
      window.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
      }
      let path = FileManager.default.temporaryDirectory.appending(path: "manual-editor-\(name).png")
      try image.pngData()?.write(to: path)
      print("Manual editor preview: \(path.path)")
    }
  }

  private func makeCreation(_ store: MemoryManualDiaryStore) -> ManualDiaryCreation {
    ManualDiaryCreation(
      store: store,
      titles: DiaryTitlePolicy(model: EditTitleModel(), languageDetector: EditLanguageDetector()))
  }

  private func element(_ id: String, root: UIView, window: UIWindow) async throws -> NSObject {
    for _ in 0..<150 {
      window.layoutIfNeeded()
      var visited = Set<ObjectIdentifier>()
      if let result = find(id, in: root, visited: &visited) { return result }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw DiaryEditIssue.busy
  }

  private func find(_ id: String, in object: NSObject, visited: inout Set<ObjectIdentifier>)
    -> NSObject?
  {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
    if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
      object.value(forKey: "accessibilityIdentifier") as? String == id
    {
      return object
    }
    var children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
    let count = object.accessibilityElementCount()
    if count > 0 && count < 256 {
      children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }
    children += (object as? UIView)?.subviews ?? []
    for child in children {
      if let result = find(id, in: child, visited: &visited) { return result }
    }
    return nil
  }
}

// swiftlint:enable opening_brace trailing_comma
