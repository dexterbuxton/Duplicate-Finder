import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(FolderStore.self) private var store
  @Environment(ScanModel.self) private var scanner
  @State private var isImporterPresented = false
  @State private var isDropTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding()

      Divider()

      if store.folders.isEmpty {
        emptyState
      } else {
        FolderListView()
      }

      Divider()

      ScanBar()
    }
    // Results describe the old folder list, so clear them when it changes.
    .onChange(of: store.folders) { scanner.reset() }
    .dropDestination(for: URL.self) { urls, _ in
      store.add(urls)
      return true
    } isTargeted: {
      isDropTargeted = $0
    }
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.accentColor, lineWidth: 3)
          .padding(4)
          .allowsHitTesting(false)
      }
    }
    .toolbar {
      ToolbarItem {
        Button("Add Folder", systemImage: "plus") {
          isImporterPresented = true
        }
      }
    }
    .fileImporter(isPresented: $isImporterPresented,
                  allowedContentTypes: [.folder],
                  allowsMultipleSelection: true) { result in
      if case .success(let urls) = result {
        store.add(urls)
      }
    }
    .alert("Some items weren’t added",
           isPresented: Binding(get: { store.message != nil },
                                set: { if !$0 { store.message = nil } })) {
      Button("OK") {}
    } message: {
      Text(store.message ?? "")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Folders to Scan")
        .font(.headline)
      Text("Drag to reorder. Files in higher folders are kept; duplicates in lower folders are removed first.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Drop Folders Here", systemImage: "folder.badge.plus")
    } description: {
      Text("Drag folders from Finder, or add them with the button below.")
    } actions: {
      Button("Add Folder…") { isImporterPresented = true }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ContentView()
    .environment(FolderStore(defaults: UserDefaults(suiteName: "preview")!))
    .environment(ScanModel())
}
