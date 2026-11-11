import Foundation

/// Keeps the envelope inside the recording's own private workspace, so protection, backup
/// exclusion, confinement and cleanup are the workspace's existing guarantees.
final class WorkspaceContextEnvelopeStore: ContextEnvelopeStore {
  private let workspace: any PrivateWorkspacePort

  init(workspace: any PrivateWorkspacePort) { self.workspace = workspace }

  func load(ownerID: String) throws -> ContextEnvelope? {
    let handle: WorkspaceHandle
    do { handle = try workspace.reopen(id: WorkspaceID(ownerID)) } catch { return nil }
    let data: Data
    do { data = try workspace.read(try workspace.artifact(.context, in: handle)) } catch {
      return nil
    }
    guard data.count <= ContextEnvelope.maximumBytes,
      let envelope = try? JSONDecoder().decode(ContextEnvelope.self, from: data)
    else { throw PrivateWorkspaceFailureCode.verificationFailed }
    return envelope
  }

  func save(_ envelope: ContextEnvelope) throws {
    let data = try JSONEncoder().encode(envelope)
    guard data.count <= ContextEnvelope.maximumBytes else {
      throw PrivateWorkspaceFailureCode.resourceTooLarge
    }
    let handle = try workspace.reopen(id: WorkspaceID(envelope.ownerID))
    try workspace.replace(try workspace.artifact(.context, in: handle), with: data)
  }

  func delete(ownerID: String) throws {
    let handle = try workspace.reopen(id: WorkspaceID(ownerID))
    try workspace.remove(try workspace.artifact(.context, in: handle))
  }
}
