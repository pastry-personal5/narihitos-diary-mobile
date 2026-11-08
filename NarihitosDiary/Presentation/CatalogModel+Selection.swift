import Foundation

extension CatalogModel {
  func open(_ row: CatalogListRow) {
    if remembered?.isActive == true {
      open(.remembered(row.id))
    } else if let handle = row.currentHandle {
      open(handle)
    }
  }

  func open(_ selected: CatalogSelection) {
    switch selected {
    case .current(let handle): open(handle)
    case .remembered(let id): openRemembered(id)
    }
  }

  private func openRemembered(_ id: CatalogRowID) {
    guard let remembered, remembered.isActive else { return }
    selection = .remembered(id)
    clearDetail()
    let epoch = generation
    detailOperation = Task { [weak self] in
      guard let self else { return }
      do {
        let value = try await remembered.catalog.resolve(id)
        guard epoch == generation, !Task.isCancelled, selection == .remembered(id) else { return }
        detail = value
      } catch {
        guard epoch == generation, !Task.isCancelled, selection == .remembered(id) else { return }
        detailIssue = (error as? CatalogIssue) ?? .unavailable
      }
    }
  }

  func clearDetail(expectedSelection: CatalogSelection) {
    guard selection == expectedSelection else { return }
    clearDetail()
  }

  func open(_ handle: CatalogItemHandle) {
    selectedItem = handle
    clearDetail()
    if collection.recovery[handle.id]?.issue == .duplicateID {
      detailIssue = .duplicateID
      return
    }
    let epoch = generation
    detailOperation = Task { [weak self] in
      guard let self else { return }
      do {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while loading {
          guard ContinuousClock.now < deadline else { throw CatalogIssue.unavailable }
          try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        let value = try await catalog.detail(handle)
        guard epoch == generation, !Task.isCancelled, selectedItem == handle else { return }
        detail = value
      } catch {
        guard epoch == generation, !Task.isCancelled else { return }
        let issue = (error as? CatalogIssue) ?? .unavailable
        if issue == .changed { refresh() } else { detailIssue = issue }
      }
    }
  }

  func clearDetail(expectedHandle: CatalogItemHandle? = nil) {
    guard expectedHandle == nil || selectedItem == expectedHandle else { return }
    detailOperation?.cancel()
    detailOperation = nil
    detail = nil
    detailIssue = nil
  }

}
