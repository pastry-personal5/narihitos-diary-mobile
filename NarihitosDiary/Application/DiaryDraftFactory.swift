import Foundation

enum DiaryDraftFactoryFailure: Error, Equatable {
  case mismatchedClaim
  case invalidAudioEvidence
  case invalidProvenance
}

/// Builds only typed metadata. The draft store owns serialization and verification.
struct DiaryDraftFactory {
  // swiftlint:disable:next function_parameter_count
  func make(
    job: QueueJob, receipt: QueueReceipt, candidate: TranscriptionPayload,
    assetID: AssetID, updatedAt: Date, title: GeneratedDiaryTitle
  ) throws -> DiarySnippetV1 {
    guard job.state == .resultReady, job.draftAssetID == assetID.description,
      job.matches(receipt), job.attemptID != nil,
      let method = job.selectedMethodID, let settings = job.effectiveSettings,
      candidate.resolvedLocale == job.language.rawValue,
      candidate.conversion == job.conversionIdentity
    else { throw DiaryDraftFactoryFailure.mismatchedClaim }
    let inspection = receipt.inspection
    guard inspection.isAccepted, let sampleRate = inspection.sampleRate,
      let channels = inspection.channelCount, let bitRate = inspection.approximateBitRate,
      inspection.isMonoAAC, sampleRate.isFinite,
      sampleRate >= 1, sampleRate <= 384_000, channels == 1,
      (1...1_000_000).contains(bitRate)
    else { throw DiaryDraftFactoryFailure.invalidAudioEvidence }
    let provenance = try transcriptionProvenance(
      method: method, settings: settings, candidate: candidate, job: job)
    let created = try SchemaInstant.from(date: job.startedAt)
    let updated = try SchemaInstant.from(date: updatedAt)
    let layout = DiarySnippetLayout(id: assetID, createdAt: created)
    return DiarySnippetV1(
      id: assetID, createdAt: created, updatedAt: updated, title: title.text,
      titleProvenance: title.provenance, favorite: false,
      language: job.language.rawValue, audioFilename: layout.audioFilename,
      audioSHA256: candidate.sourceDigest,
      recordingDurationMilliseconds: Int64((inspection.duration * 1_000).rounded()),
      audioCodec: "aac", audioSampleRateHertz: Int64(sampleRate.rounded()),
      audioChannels: Int64(channels), audioBitrateBPS: Int64(bitRate),
      transcription: provenance, location: nil, weather: nil,
      body: try DiaryBody(candidate.text), preservedScalars: [])
  }

  private func transcriptionProvenance(
    method: String, settings: [String: String], candidate: TranscriptionPayload,
    job: QueueJob
  ) throws -> TranscriptionProvenance {
    guard settings["settingsRevision"] == "1" || settings["settingsRevision"] == "2",
      settings["requestedLocale"] == job.language.rawValue,
      settings["resolvedLocale"] == candidate.resolvedLocale,
      settings["runtime"] == candidate.runtime,
      !candidate.runtime.isEmpty, !candidate.conversion.isEmpty
    else { throw DiaryDraftFactoryFailure.invalidProvenance }
    switch method {
    case TranscriptionMethodIdentifiers.apple:
      guard job.modelIdentity == nil, settings["preset"] == "transcription",
        settings["resultPolicy"] == "final-only"
      else { throw DiaryDraftFactoryFailure.invalidProvenance }
      return TranscriptionProvenance(
        methodID: try TranscriptionMethodID(method),
        languageHint: job.language.rawValue, settingsRevision: 1,
        modelID: nil, modelVersion: nil, runtimeID: candidate.runtime,
        conversionID: candidate.conversion)
    case TranscriptionMethodIdentifiers.cohere:
      guard job.modelIdentity != nil, settings["backend"] == "metal",
        let modelID = settings["modelID"], !modelID.isEmpty,
        let version = settings["modelRevision"], !version.isEmpty,
        settings["runtime"] == CohereRuntimeProvenance.identity,
        settings["runtimeCommit"] == CohereRuntimeProvenance.commit,
        settings["chunkingRevision"] == CohereChunkPlanner.identity,
        settings["installedIdentity"] == job.modelIdentity
      else { throw DiaryDraftFactoryFailure.invalidProvenance }
      let revision = settings["settingsRevision"] == "2" ? 2 : 1
      let quantization = settings["quantization"]
      let modelVersion =
        revision == 2 && quantization != nil ? "\(version):\(quantization!)" : version
      guard revision == 1 || (quantization == "Q4_K_M" || quantization == "Q5_K_M")
      else { throw DiaryDraftFactoryFailure.invalidProvenance }
      let descriptor =
        quantization == "Q5_K_M"
        ? CohereTrustedModel.productionQ5
        : CohereTrustedModel.productionQ4
      guard revision == 2 || quantization == "Q4_K_M",
        modelID == descriptor.modelID,
        version == descriptor.repositoryRevision,
        job.modelIdentity == descriptor.installationIdentity,
        settings["installedIdentity"] == descriptor.installationIdentity
      else { throw DiaryDraftFactoryFailure.invalidProvenance }
      return TranscriptionProvenance(
        methodID: try TranscriptionMethodID(method),
        languageHint: job.language.rawValue, settingsRevision: Int64(revision),
        modelID: modelID, modelVersion: modelVersion,
        runtimeID: candidate.runtime, conversionID: candidate.conversion)
    default:
      throw DiaryDraftFactoryFailure.invalidProvenance
    }
  }

}
