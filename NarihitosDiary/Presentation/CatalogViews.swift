import SwiftUI
import UIKit

@MainActor
struct CatalogDetailRendererRegistry {
  private var renderers: [String: (CatalogDetail) -> AnyView] = [:]

  mutating func register(_ kind: String, renderer: @escaping (CatalogDetail) -> AnyView) {
    renderers[kind] = renderer
  }

  func render(_ detail: CatalogDetail) -> AnyView {
    renderers[detail.handle.kind]?(detail) ?? AnyView(Text("This format isn’t supported."))
  }

  static func production(
    attributionSource: any WeatherAttributionPort,
    actions: DiaryActionsModel = DiaryActionsModel()
  ) -> CatalogDetailRendererRegistry {
    var registry = CatalogDetailRendererRegistry()
    registry.register(DiarySnippetSupportPolicy.kind) { detail in
      if let recovery = detail.payload as? CatalogRecoveryText {
        return AnyView(ScrollView { Text(verbatim: recovery.body).padding(20) })
      }
      guard let diary = detail.payload as? DiaryCatalogDetail else {
        return AnyView(Text("This format isn’t supported."))
      }
      return AnyView(
        DiaryCatalogDetailView(
          diary: diary, handle: detail.handle, actions: actions,
          attributionSource: attributionSource))
    }
    return registry
  }
}

private struct DiaryCatalogDetailView: View {
  let diary: DiaryCatalogDetail
  let handle: CatalogItemHandle
  @ObservedObject var actions: DiaryActionsModel
  @StateObject private var attribution: WeatherAttributionModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.scenePhase) private var scenePhase
  @AccessibilityFocusState private var deletionFocused: Bool

  init(
    diary: DiaryCatalogDetail, handle: CatalogItemHandle, actions: DiaryActionsModel,
    attributionSource: any WeatherAttributionPort
  ) {
    self.diary = diary
    self.handle = handle
    self.actions = actions
    _attribution = StateObject(wrappedValue: WeatherAttributionModel(source: attributionSource))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
              title
              favorite
            }
            VStack(alignment: .leading, spacing: 8) {
              title
              favorite
            }
          }
          Text(verbatim: diary.body)
            .font(.body).frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
          if !diary.isLegacy {
            Button {
              Task { await actions.openEditor(handle) }
            } label: {
              Text("Edit Diary").font(.headline).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("diary-edit")
            .disabled(
              actions.edits == nil || actions.isOpening || actions.isDeleting || pending != nil)
          }
          deletion
          if let pending {
            Text(pending.issue?.message ?? "Saving changes.").foregroundStyle(.secondary)
          }
          if let message = actions.message { Text(message).foregroundStyle(.secondary) }
        }
        if !diary.isManual {
          Divider()
          audio
          Divider()
          metadata
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { if diary.weather != nil { await attribution.load() } }
    .onAppear { actions.showDetail(handle) }
    .onDisappear { actions.hideDetail(handle) }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { actions.cancelDeletion() }
    }
    .onChange(of: handle) { _, _ in actions.cancelDeletion() }
    .onChange(of: actions.deletionConfirmation) { _, selected in
      deletionFocused = selected == handle
    }
  }

  private var pending: DiaryEditRecord? {
    diary.assetID.flatMap { actions.pending(assetID: $0) }
  }

  private var weatherMark: UIImage? {
    colorScheme == .dark ? attribution.darkMark : attribution.lightMark
  }

  private var title: some View {
    Text(verbatim: diary.title).font(.title2.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var favorite: some View {
    if let favorite = diary.favorite {
      Button {
        Task { await actions.setFavorite(!favorite, handle: handle) }
      } label: {
        InterfaceIcon(.favorite, selected: favorite).frame(minWidth: 44, minHeight: 44)
      }
      .disabled(
        actions.edits == nil || actions.isOpening || actions.isDeleting || actions.editor != nil
          || pending != nil
      )
      .accessibilityLabel("Favorite").accessibilityValue(favorite ? "On" : "Off")
      .accessibilityIdentifier("diary-favorite")
      .accessibilityAddTraits(favorite ? .isSelected : [])
    }
  }

  @ViewBuilder private var audio: some View {
    if diary.audioAvailable {
      DiaryReplayControls(actions: actions, handle: handle)
    } else {
      field("Audio", value: "Unavailable")
    }
  }

  private var metadata: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Metadata").font(.headline).accessibilityAddTraits(.isHeader)
      if let date = diary.recordedAt {
        field("Recorded", value: date.formatted(date: .complete, time: .shortened))
      }
      if let duration = diary.duration {
        field(
          "Duration", value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
      }
      if let language = diary.language {
        field(
          "Recording language",
          value: Locale.current.localizedString(forIdentifier: language) ?? language)
      }
      if let location = diary.location {
        field("Place", value: location.placeName ?? "\(location.latitude), \(location.longitude)")
      }
      if let weather = diary.weather {
        if attribution.ready {
          field("Weather", value: weather.summary)
          field(
            "Temperature",
            value: Measurement(
              value: NSDecimalNumber(decimal: weather.temperatureCelsius).doubleValue,
              unit: UnitTemperature.celsius
            ).formatted(.measurement(width: .abbreviated, usage: .weather)))
          if let mark = weatherMark, let legalPage = attribution.legalPage {
            Link(destination: legalPage) {
              Image(uiImage: mark).resizable().scaledToFit().frame(height: 20)
                .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel("Apple Weather attribution")
          }
        } else if attribution.failed {
          Text("Weather attribution is unavailable.").foregroundStyle(.secondary)
          Button("Retry Weather Attribution") { Task { await attribution.load() } }.frame(
            minHeight: 44)
        } else {
          ProgressView("Loading weather attribution")
        }
      }
      if diary.isLegacy {
        Text("Read-only legacy diary").font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private var deletion: some View {
    VStack(alignment: .leading, spacing: 12) {
      if actions.isDeleting {
        ProgressView("Deleting Diary Snippet")
          .frame(maxWidth: .infinity, minHeight: 52)
      } else if actions.deletionConfirmation == handle {
        Text("Delete this Diary Snippet?").font(.headline).accessibilityAddTraits(.isHeader)
          .accessibilityFocused($deletionFocused)
        Text(
          "This permanently deletes the diary text and its recorded audio from iCloud. This cannot be undone."
        )
        Button(role: .destructive) {
          Task { await actions.confirmDeletion(handle) }
        } label: {
          deletionLabel("Delete Diary Snippet")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("diary-confirm-delete")
        Button {
          actions.cancelDeletion()
        } label: {
          deletionLabel("Cancel")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("diary-cancel-delete")
      } else {
        Button(role: .destructive) {
          actions.requestDeletion(handle)
        } label: {
          deletionLabel("Delete Diary Snippet")
        }
        .buttonStyle(.bordered)
        .disabled(!actions.canDelete)
        .accessibilityIdentifier("diary-delete")
      }
      if let message = actions.deletionMessage {
        Text(message).foregroundStyle(.secondary).accessibilityIdentifier("diary-delete-message")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func deletionLabel(_ text: String) -> some View {
    Text(text).font(.headline).multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 52)
      .contentShape(Rectangle())
  }

  private func field(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.subheadline).foregroundStyle(.secondary)
      Text(verbatim: value).frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}
