import Foundation
import Observation
import DuplicateCore

/// Owns the ordered list of folders to scan and persists it as security-scoped bookmarks.
@Observable
final class FolderStore {
  private(set) var folders: [ScanFolder] = []

  /// A user-facing message about items that couldn't be added. Cleared by the UI.
  var message: String?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let storageKey = "scanFolders"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  // MARK: - Editing

  /// Adds folders at `index` (end of list when nil). Skips non-folders and folders already in the list.
  func add(_ urls: [URL], at index: Int? = nil) {
    var insertIndex = min(index ?? folders.count, folders.count)
    var problems: [String] = []

    for url in urls {
      // Needed for URLs from the open panel; harmless (returns false) for dropped URLs.
      let didStart = url.startAccessingSecurityScopedResource()
      defer { if didStart { url.stopAccessingSecurityScopedResource() } }

      let path: String
      switch FolderList.validate(url, existingPaths: folders.map(\.lastKnownPath)) {
      case .accepted(let canonical):
        path = canonical
      case .notAFolder:
        problems.append("“\(url.lastPathComponent)” isn’t a folder.")
        continue
      case .alreadyAdded:
        problems.append("“\(url.lastPathComponent)” is already in the list.")
        continue
      }

      do {
        let target = URL(filePath: path, directoryHint: .isDirectory)
        let bookmark = try target.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
        // Resolve right away so we hold the same long-lived access we'd get after a relaunch.
        let folder = Self.resolve(id: UUID(), bookmark: bookmark, lastKnownPath: path)
        folders.insert(folder, at: insertIndex)
        insertIndex += 1
      } catch {
        problems.append("Couldn’t add “\(url.lastPathComponent)”: \(error.localizedDescription)")
      }
    }

    if !problems.isEmpty { message = problems.joined(separator: "\n") }
    save()
  }

  func remove(ids: Set<ScanFolder.ID>) {
    for folder in folders where ids.contains(folder.id) {
      folder.url?.stopAccessingSecurityScopedResource()
    }
    folders.removeAll { ids.contains($0.id) }
    save()
  }

  /// Same semantics as SwiftUI's `onMove`.
  func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    folders = folders.moving(fromOffsets: source, toOffset: destination)
    save()
  }

  func moveToTop(_ id: ScanFolder.ID) {
    guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
    move(fromOffsets: [index], toOffset: 0)
  }

  // MARK: - Persistence

  private struct Stored: Codable {
    let id: UUID
    let bookmark: Data
    let path: String
  }

  private func save() {
    let stored = folders.map { Stored(id: $0.id, bookmark: $0.bookmark, path: $0.lastKnownPath) }
    if let data = try? JSONEncoder().encode(stored) {
      defaults.set(data, forKey: storageKey)
    }
  }

  private func load() {
    guard let data = defaults.data(forKey: storageKey),
          let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return }
    folders = stored.map { Self.resolve(id: $0.id, bookmark: $0.bookmark, lastKnownPath: $0.path) }
    save() // persist any refreshed (previously stale) bookmarks
  }

  /// Resolves a bookmark and starts security-scoped access, which is held while the folder is in the list.
  private static func resolve(id: UUID, bookmark: Data, lastKnownPath: String) -> ScanFolder {
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: bookmark,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale) else {
      return ScanFolder(id: id, url: nil, bookmark: bookmark, lastKnownPath: lastKnownPath)
    }
    _ = url.startAccessingSecurityScopedResource()

    var bookmark = bookmark
    if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil) {
      bookmark = fresh
    }
    // Bookmarks follow moves/renames, so refresh the path we display.
    return ScanFolder(id: id, url: url, bookmark: bookmark, lastKnownPath: FolderList.canonicalPath(url))
  }
}
