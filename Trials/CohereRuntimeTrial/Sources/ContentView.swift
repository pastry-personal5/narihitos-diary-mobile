import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var controller = TrialController()
  @State private var importingModel = false
  @State private var importingAudio = false
  @State private var confirmingDelete = false

  private let ggufType = UTType(filenameExtension: "gguf") ?? .data

  var body: some View {
    NavigationStack {
      Form {
        Section("Inputs") {
          fileRow(
            title: "Model",
            filename: controller.selectedModelURL?.lastPathComponent,
            action: { importingModel = true }
          )
          fileRow(
            title: "Audio",
            filename: controller.selectedAudioURL?.lastPathComponent,
            action: { importingAudio = true }
          )
          Picker("Language", selection: $controller.language) {
            ForEach(TrialLanguage.allCases) { language in
              Text(language.label).tag(language)
            }
          }
          Picker("Run class", selection: $controller.runClass) {
            ForEach(TrialRunClass.allCases) { runClass in
              Text(runClass.label).tag(runClass)
            }
          }
          if controller.isInspecting {
            HStack {
              ProgressView()
              Text("Inspecting model and audio…")
            }
          } else {
            Button("Inspect Inputs") { controller.inspectInputs() }
              .disabled(controller.isRunning)
          }
          if let summary = controller.inputSummary {
            LabeledContent("Quantization", value: summary.model.quantization.rawValue)
            LabeledContent("Model SHA-256", value: shortHash(summary.model.file.sha256))
            LabeledContent("Audio SHA-256", value: shortHash(summary.audioFile.sha256))
            LabeledContent(
              "Audio duration",
              value: summary.audioDurationSeconds.formatted(
                .number.precision(.fractionLength(2))
              ) + " s"
            )
          }
        }

        Section("Controlled conditions") {
          Picker("Network", selection: $controller.networkCondition) {
            ForEach(TrialNetworkCondition.allCases) { condition in
              Text(condition.label).tag(condition)
            }
          }
          TextField(
            "Ambient temperature °C (optional)",
            text: $controller.ambientTemperatureCelsius
          )
          .keyboardType(.decimalPad)
        }

        Section("Run") {
          LabeledContent("Status", value: controller.status)
          if controller.isRunning {
            Button("Cancel", role: .destructive) { controller.cancel() }
              .disabled(controller.isCancelling)
          } else {
            Button("Transcribe") { controller.run() }
              .disabled(controller.inputSummary == nil || controller.isInspecting)
          }
        }

        if let result = controller.lastResult {
          Section("Last result") {
            LabeledContent("Outcome", value: result.outcome.rawValue)
            if let runtimeStatus = result.runtimeStatus {
              let runtimeStatusCode = result.runtimeStatusCode.map { String($0) } ?? "unknown"
              LabeledContent(
                "Runtime status",
                value: "\(runtimeStatus) (\(runtimeStatusCode))"
              )
            }
            if !result.runtimeDiagnostics.isEmpty {
              DisclosureGroup("Runtime diagnostics") {
                ForEach(Array(result.runtimeDiagnostics.enumerated()), id: \.offset) { item in
                  Text(item.element)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                }
              }
            }
            LabeledContent(
              "Total",
              value: result.durations.totalSeconds.formatted(.number.precision(.fractionLength(2)))
                + " s"
            )
            LabeledContent(
              "Peak footprint",
              value: byteCount(result.resources.map(\.physicalFootprintBytes).max() ?? 0)
            )
            LabeledContent(
              "Inference peak",
              value: byteCount(
                result.resources
                  .filter { $0.phase == .inference }
                  .map(\.physicalFootprintBytes)
                  .max() ?? 0
              )
            )
            LabeledContent("Backend", value: result.device.actualBackend)
            LabeledContent(
              "Model input limit",
              value: result.runtimeCapabilities.maxAudioMilliseconds == 0
                ? "Unreported"
                : "\(result.runtimeCapabilities.maxAudioMilliseconds / 1_000) s"
            )
            if !result.transcript.isEmpty {
              Text(result.transcript)
                .textSelection(.enabled)
                .foregroundStyle(result.partialTranscript ? .secondary : .primary)
              if result.partialTranscript {
                Label(
                  "Partial transcript — do not quality-score",
                  systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
              }
            }
            if let resultURL = controller.lastResultURL {
              ShareLink(item: resultURL) {
                Label("Export Result JSON", systemImage: "square.and.arrow.up")
              }
            }
          }
        }

        Section("Stored results") {
          LabeledContent("Count", value: "\(controller.savedResultURLs.count)")
          Button("Delete Results", role: .destructive) { confirmingDelete = true }
            .disabled(controller.savedResultURLs.isEmpty || controller.isRunning)
        }
      }
      .navigationTitle("Cohere Trial")
      .fileImporter(
        isPresented: $importingModel,
        allowedContentTypes: [ggufType],
        allowsMultipleSelection: false
      ) { result in
        do {
          controller.selectModel(try result.get().first)
        } catch {
          controller.errorMessage = error.localizedDescription
        }
      }
      .fileImporter(
        isPresented: $importingAudio,
        allowedContentTypes: [.audio],
        allowsMultipleSelection: false
      ) { result in
        do {
          controller.selectAudio(try result.get().first)
        } catch {
          controller.errorMessage = error.localizedDescription
        }
      }
      .alert("Trial error", isPresented: errorPresented) {
        Button("OK") { controller.errorMessage = nil }
      } message: {
        Text(controller.errorMessage ?? "Unknown error")
      }
      .confirmationDialog(
        "Delete all stored result JSON files?",
        isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete Results", role: .destructive) { controller.deleteAllResults() }
      }
    }
  }

  private var errorPresented: Binding<Bool> {
    Binding(
      get: { controller.errorMessage != nil },
      set: { if !$0 { controller.errorMessage = nil } }
    )
  }

  private func fileRow(
    title: String,
    filename: String?,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(title)
        Spacer()
        Text(filename ?? "Select…")
          .lineLimit(1)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func byteCount(_ count: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
  }

  private func shortHash(_ hash: String) -> String {
    "\(hash.prefix(12))…"
  }
}
