import SwiftUI

@main
struct DuplicateFinderApp: App {
  @State private var folderStore = FolderStore()
  @State private var scanModel = ScanModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(folderStore)
        .environment(scanModel)
        .frame(minWidth: 700, minHeight: 450)
    }
  }
}
