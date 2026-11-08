import Foundation
import DuplicateCore

/// A folder the user added to the scan list.
/// Its position in the list is its priority: index 0 is the most protected.
struct ScanFolder: Identifiable, Equatable {
  let id: UUID
  /// The resolved, security-scoped URL. `nil` when the bookmark couldn't be resolved
  /// (folder deleted, drive unplugged, etc.).
  var url: URL?
  /// Security-scoped bookmark so access survives relaunches.
  var bookmark: Data
  /// Last path we saw, used for display when the folder is unavailable.
  var lastKnownPath: String

  var isAvailable: Bool { url != nil }

  var name: String {
    (lastKnownPath as NSString).lastPathComponent
  }

  /// Path with the user's real home directory shown as `~`.
  var displayPath: String {
    FolderList.displayPath(lastKnownPath)
  }
}
