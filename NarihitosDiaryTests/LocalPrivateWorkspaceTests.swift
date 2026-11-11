import Foundation
import Testing

@testable import NarihitosDiary

// swift-format's canonical multiline collections conflict with SwiftLint's trailing-comma rule.
// swiftlint:disable trailing_comma

struct LocalPrivateWorkspaceTests {
  @Test func typedArtifactsStayConfinedAndExcludedFromBackup() throws {
    let root = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let adapter = try LocalPrivateWorkspace(root: root)
    let workspace = try adapter.allocate(id: .random())
    for role in PrivateArtifactRole.allCases {
      let artifact = try adapter.artifact(role, in: workspace)
      let bytes = Data("private-\(role.rawValue)".utf8)
      try adapter.replace(artifact, with: bytes)
      #expect(try adapter.read(artifact) == bytes)
      let file = root.appending(path: workspace.workspaceID.description).appending(
        path: role.ownedFilename)
      #expect(
        try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
    let reopened = try adapter.reopen(id: workspace.workspaceID)
    let reopenedDraft = try adapter.artifact(.markdownDraft, in: reopened)
    #expect(try adapter.read(reopenedDraft) == Data("private-markdownDraft".utf8))
  }

  @Test func handlesFromAnotherAdapterAndMalformedIdentitiesHaveNoAuthority() throws {
    let parent = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let first = try LocalPrivateWorkspace(root: parent.appending(path: "first"))
    let second = try LocalPrivateWorkspace(root: parent.appending(path: "second"))
    let handle = try first.allocate(id: .random())
    #expect(throws: PrivateWorkspaceFailureCode.invalidHandle) {
      try second.artifact(.markdownDraft, in: handle)
    }
    #expect(throws: AssetValueError.invalidAssetID) { try WorkspaceID("../first") }
    #expect(throws: AssetValueError.invalidAssetID) { try WorkspaceID("file:///tmp/x") }
    #expect(throws: AssetValueError.invalidAssetID) { try WorkspaceID("%2e%2e") }
  }

  @Test func aSymlinkedWorkspaceFailsClosed() throws {
    let parent = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "root")
    let outside = parent.appending(path: "outside")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let id = try WorkspaceID.random()
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: id.description), withDestinationURL: outside)
    let adapter = try LocalPrivateWorkspace(root: root)
    #expect(throws: PrivateWorkspaceFailureCode.unsafeResource) { try adapter.reopen(id: id) }
  }

  @Test func workspaceSymlinkSwapFailsWithoutTouchingOutsideResource() throws {
    let parent = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "root")
    let outside = parent.appending(path: "outside")
    let moved = parent.appending(path: "moved")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let sentinel = outside.appending(path: "sentinel")
    try Data("outside".utf8).write(to: sentinel)
    let id = try WorkspaceID.random()
    let workspaceURL = root.appending(path: id.description)
    let adapter = try LocalPrivateWorkspace(
      root: root,
      failureInjector: { point in
        guard point == .afterTemporaryWrite else { return }
        try FileManager.default.moveItem(at: workspaceURL, to: moved)
        try FileManager.default.createSymbolicLink(at: workspaceURL, withDestinationURL: outside)
      })
    let workspace = try adapter.allocate(id: id)
    let artifact = try adapter.artifact(.pendingAudio, in: workspace)
    #expect(throws: PrivateWorkspaceFailureCode.backupExclusionFailed) {
      try adapter.replace(artifact, with: Data("inside".utf8))
    }
    #expect(try Data(contentsOf: sentinel) == Data("outside".utf8))
  }

  @Test func everyInjectedReplacementFailureRetainsPriorBytes() throws {
    let points: [WorkspaceFailurePoint] = [
      .afterTemporaryWrite, .afterAttributes, .afterRecoveryMove, .afterDestinationMove,
    ]
    for failurePoint in points {
      let root = testTemporaryDirectory().appending(path: UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let initialAdapter = try LocalPrivateWorkspace(root: root)
      let initialWorkspace = try initialAdapter.allocate(id: .random())
      let initialArtifact = try initialAdapter.artifact(.markdownDraft, in: initialWorkspace)
      let prior = Data("prior".utf8)
      try initialAdapter.replace(initialArtifact, with: prior)

      let adapter = try LocalPrivateWorkspace(
        root: root,
        failureInjector: { point in
          if point == failurePoint { throw PrivateWorkspaceFailureCode.atomicWriteFailed }
        })
      let workspace = try adapter.reopen(id: initialWorkspace.workspaceID)
      let artifact = try adapter.artifact(.markdownDraft, in: workspace)
      let destination = root.appending(path: workspace.workspaceID.description).appending(
        path: PrivateArtifactRole.markdownDraft.ownedFilename)
      #expect(throws: PrivateWorkspaceFailureCode.atomicWriteFailed) {
        try adapter.replace(artifact, with: Data("replacement".utf8))
      }
      #expect(try Data(contentsOf: destination) == prior)
      #expect(
        try destination.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
          == true)
    }
  }

  @Test func failedFirstWriteRestoresMissingDestination() throws {
    let root = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let adapter = try LocalPrivateWorkspace(
      root: root,
      failureInjector: { point in
        if point == .afterDestinationMove {
          throw PrivateWorkspaceFailureCode.atomicWriteFailed
        }
      })
    let workspace = try adapter.allocate(id: .random())
    let artifact = try adapter.artifact(.markdownDraft, in: workspace)
    #expect(throws: PrivateWorkspaceFailureCode.atomicWriteFailed) {
      try adapter.replace(artifact, with: Data("replacement".utf8))
    }
    #expect(throws: PrivateWorkspaceFailureCode.resourceMissing) {
      try adapter.read(artifact)
    }
  }

  @Test func existingRecoveryArtifactFailsClosed() throws {
    let root = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let adapter = try LocalPrivateWorkspace(root: root)
    let workspace = try adapter.allocate(id: .random())
    let artifact = try adapter.artifact(.markdownDraft, in: workspace)
    let prior = Data("prior".utf8)
    try adapter.replace(artifact, with: prior)
    let workspaceURL = root.appending(path: workspace.workspaceID.description)
    let recovery = workspaceURL.appending(path: ".recovery-markdownDraft")
    let recoveryBytes = Data("recovery".utf8)
    try recoveryBytes.write(to: recovery)

    #expect(throws: PrivateWorkspaceFailureCode.atomicWriteFailed) {
      try adapter.replace(artifact, with: Data("new".utf8))
    }
    #expect(try adapter.read(artifact) == prior)
    #expect(try Data(contentsOf: recovery) == recoveryBytes)
  }

  @Test func artifactSizeLimitFailsBeforeWriting() throws {
    let root = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let adapter = try LocalPrivateWorkspace(root: root)
    let workspace = try adapter.allocate(id: .random())
    let artifact = try adapter.artifact(.pendingAudio, in: workspace)
    let oversized = Data(count: LocalPrivateWorkspace.maximumArtifactBytes + 1)
    #expect(throws: PrivateWorkspaceFailureCode.resourceTooLarge) {
      try adapter.replace(artifact, with: oversized)
    }
    #expect(throws: PrivateWorkspaceFailureCode.resourceMissing) {
      try adapter.read(artifact)
    }
  }

  @Test func protectionPolicyFailureIsSanitizedAndFailsClosed() throws {
    struct FailingPolicy: FileProtectionPolicy {
      func applyAndVerify(to _: URL) throws { throw CocoaError(.fileReadNoPermission) }
    }
    let root = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let adapter = try LocalPrivateWorkspace(root: root, protectionPolicy: FailingPolicy())
    let workspace = try adapter.allocate(id: .random())
    let artifact = try adapter.artifact(.pendingAudio, in: workspace)
    #expect(throws: PrivateWorkspaceFailureCode.protectionPolicyFailed) {
      try adapter.replace(artifact, with: Data("secret diary text".utf8))
    }
    #expect(
      PrivateWorkspaceFailureCode.protectionPolicyFailed.description == "protectionPolicyFailed")
  }

  @Test func removalCannotAffectSiblingResources() throws {
    let parent = testTemporaryDirectory().appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "owned")
    let sibling = parent.appending(path: "owned-sibling")
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    let sentinel = sibling.appending(path: "sentinel")
    try Data("outside".utf8).write(to: sentinel)
    let adapter = try LocalPrivateWorkspace(root: root)
    let workspace = try adapter.allocate(id: .random())
    let artifact = try adapter.artifact(.replacement, in: workspace)
    try adapter.replace(artifact, with: Data("inside".utf8))
    try adapter.remove(artifact)
    #expect(throws: PrivateWorkspaceFailureCode.resourceMissing) { try adapter.read(artifact) }
    try adapter.remove(workspace)
    #expect(try Data(contentsOf: sentinel) == Data("outside".utf8))
  }

  @Test func productionRootUsesApplicationSupport() throws {
    let adapter = try LocalPrivateWorkspace.production()
    let path = adapter.resolvedRoot.path
    #expect(path.contains("Application Support"))
    #expect(!path.contains("/Documents/"))
    #expect(!path.contains("/Caches/"))
    #expect(!path.hasPrefix(FileManager.default.temporaryDirectory.path))
  }

  @Test func publicFailuresContainOnlyStableCodes() {
    let forbiddenFragments = ["/tmp/", "secret diary", "latitude", "bookmark", "NSError"]
    for code in PrivateWorkspaceFailureCode.allCases {
      #expect(code.description == code.rawValue)
      #expect(forbiddenFragments.allSatisfy { !code.description.contains($0) })
    }
    for code in DiarySnippetMalformedCode.allCases {
      #expect(code.description == code.rawValue)
      #expect(forbiddenFragments.allSatisfy { !code.description.contains($0) })
    }
  }

  private func testTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
  }
}

// swiftlint:enable trailing_comma
