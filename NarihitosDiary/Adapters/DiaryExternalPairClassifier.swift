import CryptoKit
import Foundation

/// Classifies one exact canonical layout. A catalog may enumerate layouts, but
/// it need not interpret provider bytes or infer missing components itself.
struct DiaryExternalPairClassifier {
  private let codec = DiarySnippetMarkdownCodec()

  func classify(
    layout: DiarySnippetLayout, assetID: AssetID,
    markdown: DiaryObservedMarkdown?, audio: DiaryObservedAudio?
  ) -> DiaryExternalPairStatus {
    guard markdown != nil || audio != nil else { return .absent }
    let snippet: DiarySnippetV1?
    if let markdown {
      guard Int64(markdown.bytes.count) == markdown.version.byteCount,
        Self.digest(markdown.bytes) == markdown.version.digest,
        case .supported(let decoded) = codec.decode(markdown.bytes),
        decoded.id == assetID, decoded.audioFilename == layout.audioFilename,
        layout.validates(audioReference: decoded.audioFilename),
        DiarySnippetLayout(id: decoded.id, createdAt: decoded.createdAt) == layout
      else { return .blocked("The Markdown needs review.") }
      snippet = decoded
    } else {
      snippet = nil
    }
    if let audio, !audio.playable {
      return .blocked("The audio needs review.")
    }
    switch (markdown, audio) {
    case (let markdown?, let audio?):
      guard let snippet else { return .blocked("The pair needs review.") }
      guard snippet.audioSHA256 == nil || snippet.audioSHA256 == audio.version.digest else {
        return .blocked("The audio does not match the diary text.")
      }
      return .complete(
        DiaryVerifiedExternalPair(
          snippet: snippet,
          version: DiaryPairVersion(
            markdownIdentity: markdown.version.identity,
            audioIdentity: audio.version.identity,
            markdownDigest: markdown.version.digest,
            audioDigest: audio.version.digest),
          modifiedAt: DiaryPairModificationTimes(
            markdown: markdown.modifiedAt, audio: audio.modifiedAt)))
    case (let markdown?, nil):
      return .incomplete(
        DiaryIncompletePairRecovery(
          assetID: assetID.description, missing: .audio,
          survivingMarkdown: snippet, hasPlayableAudio: false,
          survivingVersion: markdown.version,
          reason: "The audio file is missing."))
    case (nil, let audio?):
      return .incomplete(
        DiaryIncompletePairRecovery(
          assetID: assetID.description, missing: .markdown,
          survivingMarkdown: nil, hasPlayableAudio: true,
          survivingVersion: audio.version,
          reason: "The diary text file is missing."))
    case (nil, nil): return .absent
    }
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
