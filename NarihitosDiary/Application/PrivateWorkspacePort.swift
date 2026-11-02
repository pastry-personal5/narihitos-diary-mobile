import Foundation

struct WorkspaceID: Hashable, Sendable, CustomStringConvertible {
  let description: String

  init(_ value: String) throws {
    description = try AssetID(value).description
  }

  static func random() throws -> WorkspaceID {
    try WorkspaceID(AssetID.random().description)
  }
}

enum PrivateArtifactRole: String, CaseIterable, Sendable {
  case pendingAudio
  case markdownDraft
  case draftBinding
  case replacement
  case recovery

  var ownedFilename: String {
    switch self {
    case .pendingAudio: "pending-audio.m4a"
    case .markdownDraft: "draft.md"
    case .draftBinding: "draft-binding-v1.json"
    case .replacement: "replacement.data"
    case .recovery: "recovery.data"
    }
  }
}

struct WorkspaceHandle: Hashable, Sendable {
  let adapterID: UUID
  let workspaceID: WorkspaceID
  let nonce: UUID
}

struct ArtifactHandle: Hashable, Sendable {
  let workspace: WorkspaceHandle
  let role: PrivateArtifactRole
}

enum PrivateWorkspaceFailureCode: String, CaseIterable, Error, CustomStringConvertible, Sendable {
  case invalidIdentity
  case invalidHandle
  case resourceTooLarge
  case storageUnavailable
  case unsafeResource
  case resourceMissing
  case atomicWriteFailed
  case verificationFailed
  case backupExclusionFailed
  case protectionPolicyFailed

  var description: String { rawValue }
}

protocol PrivateWorkspacePort {
  func allocate(id: WorkspaceID) throws -> WorkspaceHandle
  func reopen(id: WorkspaceID) throws -> WorkspaceHandle
  func artifact(_ role: PrivateArtifactRole, in workspace: WorkspaceHandle) throws -> ArtifactHandle
  func read(_ artifact: ArtifactHandle) throws -> Data
  func replace(_ artifact: ArtifactHandle, with data: Data) throws
  func remove(_ artifact: ArtifactHandle) throws
  func remove(_ workspace: WorkspaceHandle) throws
}
