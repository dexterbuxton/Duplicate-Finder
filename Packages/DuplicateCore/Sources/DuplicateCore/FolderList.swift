import Foundation

/// Pure logic behind the app's folder list, kept here so it can be unit tested
/// outside the sandbox. Bookmarks and persistence stay in the app.
public enum FolderList {

  public enum Validation: Equatable, Sendable {
    /// OK to add; `path` is the canonical path to store.
    case accepted(path: String)
    case notAFolder
    case alreadyAdded
  }

  /// Decides whether `url` can be added, given the canonical paths already in the list.
  /// A symlink to a folder is accepted as the folder it points to.
  /// Packages (e.g. `.app` bundles) count as files, not folders.
  public static func validate(_ url: URL, existingPaths: some Collection<String>) -> Validation {
    let path = canonicalPath(url)
    // Check the resolved target: resource values on a symlink describe the link itself.
    let values = try? URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    guard values?.isDirectory == true, values?.isPackage != true else { return .notAFolder }
    return existingPaths.contains(path) ? .alreadyAdded : .accepted(path: path)
  }

  /// Absolute path with `.`/`..` and symlinks resolved, so the same folder always compares equal.
  public static func canonicalPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  /// Shows `path` with the home directory replaced by `~`.
  public static func displayPath(_ path: String, home: String = realHomeDirectory) -> String {
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
  }

  /// The user's real home directory. Inside the sandbox `NSHomeDirectory()` returns the
  /// app's container, so look it up from the user database instead.
  public static let realHomeDirectory: String = {
    if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
      return String(cString: dir)
    }
    return NSHomeDirectory()
  }()
}

extension Array {
  /// Returns the array with the elements at `source` moved to `destination`,
  /// using the same index semantics as SwiftUI's `onMove`.
  public func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
    let moving = source.map { self[$0] }
    var remaining = enumerated().filter { !source.contains($0.offset) }.map(\.element)
    let adjusted = destination - source.count(in: 0..<destination)
    remaining.insert(contentsOf: moving, at: adjusted)
    return remaining
  }
}
