import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Narihito's Diary",
        systemImage: "book.closed",
        description: Text("Your diary is coming soon.")
      )
      .navigationTitle("Diary")
    }
  }
}
