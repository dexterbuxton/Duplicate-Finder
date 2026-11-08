import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The prioritized folder list. Drag rows to reorder; drop folders from Finder between rows to insert.
struct FolderListView: View {
  @Environment(FolderStore.self) private var store
  @State private var selection: Set<ScanFolder.ID> = []

  var body: some View {
    List(selection: $selection) {
      ForEach(Array(store.folders.enumerated()), id: \.element.id) { index, folder in
        FolderRow(folder: folder, priority: index + 1) {
          store.remove(ids: [folder.id])
        }
        .contextMenu { contextMenu(for: folder) }
      }
      .onMove { store.move(fromOffsets: $0, toOffset: $1) }
      .onInsert(of: [.fileURL]) { index, providers in
        Task {
          let urls = await Self.loadFileURLs(from: providers)
          store.add(urls, at: index)
        }
      }
    }
    .onDeleteCommand {
      store.remove(ids: selection)
      selection = []
    }
  }

  @ViewBuilder
  private func contextMenu(for folder: ScanFolder) -> some View {
    if let url = folder.url {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      }
    }
    Button("Move to Top") { store.moveToTop(folder.id) }
      .disabled(store.folders.first?.id == folder.id)
    Divider()
    Button("Remove", role: .destructive) {
      store.remove(ids: [folder.id])
    }
  }

  private static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
    var urls: [URL] = []
    for provider in providers {
      let url: URL? = await withCheckedContinuation { continuation in
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          continuation.resume(returning: url)
        }
      }
      if let url { urls.append(url) }
    }
    return urls
  }
}
