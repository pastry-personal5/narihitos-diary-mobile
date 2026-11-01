import SwiftUI

@main
struct NarihitosDiaryApp: App {
  var body: some Scene {
    WindowGroup {
      if LaunchVersionPolicy.isSupported(ProcessInfo.processInfo.operatingSystemVersion) {
        ContentView()
      } else {
        ContentUnavailableView(
          "Update iOS",
          systemImage: "iphone.gen3",
          description: Text("Narihito's Diary requires iOS 27.0.1 or later.")
        )
      }
    }
  }
}
