import SwiftUI

enum InterfaceIconName: String {
  case main, benefits, calendar, plugins, all, record, stop, settings, pending, warning, incomplete,
    conflicts, favorite, play, pause, seekBack, seekForward, write, save, cancel

  var size: CGFloat {
    switch self {
    case .main, .benefits, .calendar, .plugins, .all: 25
    case .record, .stop: 32
    default: 24
    }
  }
}

struct InterfaceIcon: View {
  let name: InterfaceIconName
  let selected: Bool

  init(_ name: InterfaceIconName, selected: Bool = false) {
    self.name = name
    self.selected = selected
  }

  var body: some View {
    Image("ndm-" + name.rawValue + (selected ? "-selected" : ""))
      .renderingMode(.template)
      .resizable()
      .frame(width: name.size, height: name.size)
      .accessibilityHidden(true)
  }
}
