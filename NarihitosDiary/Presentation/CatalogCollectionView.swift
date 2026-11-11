import SwiftUI
import UIKit

struct CatalogCollectionView: View {
  @ObservedObject var catalog: CatalogModel
  let openAll: () -> Void
  let renderers: CatalogDetailRendererRegistry
  @State private var calendarRevision = 0
  @State private var viewportEvent: UUID?
  @State private var visibleRows: Set<CatalogRowID> = []

  private var sections: [CatalogListSection] {
    _ = calendarRevision
    return CatalogListSection.group(catalog.rows, calendar: .autoupdatingCurrent)
  }

  var body: some View {
    ScrollViewReader { proxy in
      collection
        .onChange(of: catalog.rows.map(\.id)) { previous, current in
          preserveAnchor(previous: previous, current: current, proxy: proxy)
        }
    }
  }

  private var collection: some View {
    List {
      ForEach(sections, id: \.date) { section in
        Section(section.date.formatted(date: .complete, time: .omitted)) {
          ForEach(section.entries) { summary in
            Button {
              catalog.open(summary)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: summary.title).font(.headline).foregroundStyle(.primary)
                Text(summary.createdAt.formatted(date: .omitted, time: .shortened))
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Diary Snippet")
            .accessibilityIdentifier("catalog-row-" + summary.id.rawValue.uuidString)
            .id(summary.id)
            .onScrollVisibilityChange { visible in
              if visible { visibleRows.insert(summary.id) } else { visibleRows.remove(summary.id) }
              if visible, let viewportEvent { catalog.nearEnd(summary.id, event: viewportEvent) }
            }
          }
        }
      }
      if !catalog.rows.isEmpty { footer }
    }
    .overlay { if catalog.rows.isEmpty { emptyState } }
    .refreshable { catalog.refresh() }
    .navigationDestination(item: $catalog.selection) { selection in
      CatalogDetailScreen(catalog: catalog, selection: selection, renderers: renderers)
    }
    .onScrollPhaseChange { previous, current in
      if current == .interacting, previous != .interacting {
        let event = UUID()
        viewportEvent = event
        for id in visibleRows { catalog.nearEnd(id, event: event) }
      } else if current == .idle {
        viewportEvent = nil
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      calendarRevision += 1
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      calendarRevision += 1
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
    ) { _ in calendarRevision += 1 }
    .privacySensitive()
  }

  @ViewBuilder private var footer: some View {
    if catalog.state == .unavailable {
      Button("Retry Loading", action: catalog.refresh).frame(minHeight: 44)
    } else if catalog.isLoadingMore {
      ProgressView("Loading Diary Snippets")
        .accessibilityIdentifier("catalog-loading-more")
        .frame(maxWidth: .infinity, minHeight: 44)
    } else if catalog.canLoadMore {
      Button {
        catalog.requestMore(event: UUID())
      } label: {
        Label("Diary Snippets", systemImage: "chevron.down")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .accessibilityIdentifier("catalog-load-more")
      .accessibilityHint("Loads more Diary Snippets")
    }
  }

  @ViewBuilder private var emptyState: some View {
    switch catalog.state {
    case .idle, .loading, .discovering, .loaded:
      ProgressView(
        catalog.state == .discovering ? "Finding Diary Snippets" : "Loading Diary Snippets")
    case .noFolder:
      ContentUnavailableView {
        Label {
          Text("Choose an iCloud Folder")
        } icon: {
          InterfaceIcon(.incomplete)
        }
      } description: {
        Text("Choose your active folder in All’s Settings to see your diary.")
      } actions: {
        Button("Open All", action: openAll).frame(minHeight: 44)
      }
    case .unavailable:
      ContentUnavailableView {
        Label {
          Text("Folder Unavailable")
        } icon: {
          InterfaceIcon(.warning)
        }
      } description: {
        Text("Restore access to your active folder or try again.")
      } actions: {
        Button("Retry", action: catalog.refresh).frame(minHeight: 44)
        Button("Open All", action: openAll).frame(minHeight: 44)
      }
    case .end:
      ContentUnavailableView {
        Label {
          Text("No Diary Snippets")
        } icon: {
          InterfaceIcon(.main)
        }
      } description: {
        Text(
          catalog.recovery.isEmpty
            ? "Your active folder has no Diary Snippets."
            : "Some items need attention. Open All to review their status.")
      }
    }
  }

  private func preserveAnchor(
    previous: [CatalogRowID], current: [CatalogRowID], proxy: ScrollViewProxy
  ) {
    guard viewportEvent == nil,
      let anchor = previous.first(where: { visibleRows.contains($0) && current.contains($0) }),
      previous.prefix(while: { $0 != anchor }) != current.prefix(while: { $0 != anchor })
    else { return }
    proxy.scrollTo(anchor, anchor: .top)
  }
}

private struct CatalogDetailScreen: View {
  @ObservedObject var catalog: CatalogModel
  let selection: CatalogSelection
  let renderers: CatalogDetailRendererRegistry

  var body: some View {
    Group {
      if let detail = catalog.detail, catalog.selection == selection {
        renderers.render(detail)
      } else if let issue = catalog.detailIssue {
        ContentUnavailableView {
          Label {
            Text("Diary Unavailable")
          } icon: {
            InterfaceIcon(.warning)
          }
        } description: {
          Text(issue.message)
        } actions: {
          Button("Retry") { catalog.open(selection) }.frame(minHeight: 44)
        }
      } else {
        ProgressView("Opening Diary Snippet")
          .accessibilityIdentifier("catalog-opening")
      }
    }
    .navigationTitle("Diary Snippet")
    .navigationBarTitleDisplayMode(.inline)
    .privacySensitive()
  }
}
