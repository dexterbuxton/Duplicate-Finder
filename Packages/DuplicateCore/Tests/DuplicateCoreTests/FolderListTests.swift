import Foundation
import Testing
@testable import DuplicateCore

struct FolderListMoveTests {
  /// Expected results follow SwiftUI's `onMove` semantics:
  /// `destination` is an index in the *original* array, before removal.
  @Test(arguments: [
    ([0], 2, "bacd"),     // down one
    ([0], 4, "bcda"),     // to the end
    ([3], 0, "dabc"),     // to the top
    ([2], 1, "acbd"),     // up one
    ([1], 1, "abcd"),     // onto itself
    ([1], 2, "abcd"),     // just below itself (no-op)
    ([1, 3], 0, "bdac"),  // non-adjacent group to top
    ([0, 2], 4, "bdac"),  // non-adjacent group to end
    ([0, 1], 3, "cabd"),  // adjacent group down
  ])
  func moving(source: [Int], destination: Int, expected: String) {
    let result = Array("abcd").moving(fromOffsets: IndexSet(source), toOffset: destination)
    #expect(String(result) == expected)
  }
}

struct FolderListValidationTests {
  let dir: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "FolderListTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    dir = base
  }

  func makeFolder(_ name: String) throws -> URL {
    let url = dir.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func acceptsAFolderWithItsCanonicalPath() throws {
    let folder = try makeFolder("Photos")
    #expect(FolderList.validate(folder, existingPaths: []) == .accepted(path: FolderList.canonicalPath(folder)))
  }

  @Test func rejectsFilesPackagesAndMissingPaths() throws {
    let file = dir.appending(path: "note.txt")
    try Data("hi".utf8).write(to: file)
    let app = try makeFolder("Tool.app")

    #expect(FolderList.validate(file, existingPaths: []) == .notAFolder)
    #expect(FolderList.validate(app, existingPaths: []) == .notAFolder)
    #expect(FolderList.validate(dir.appending(path: "missing"), existingPaths: []) == .notAFolder)
  }

  @Test func detectsTheSameFolderReachedDifferentWays() throws {
    let folder = try makeFolder("Photos")
    let existing = [FolderList.canonicalPath(folder)]

    let link = dir.appending(path: "PhotosLink")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
    let dotted = dir.appending(path: "Photos/../Photos")

    #expect(FolderList.validate(folder, existingPaths: existing) == .alreadyAdded)
    #expect(FolderList.validate(link, existingPaths: existing) == .alreadyAdded)
    #expect(FolderList.validate(dotted, existingPaths: existing) == .alreadyAdded)
  }

  @Test func symlinkToAFolderIsAcceptedAsItsTarget() throws {
    let folder = try makeFolder("Photos")
    let link = dir.appending(path: "PhotosLink")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
    #expect(FolderList.validate(link, existingPaths: []) == .accepted(path: FolderList.canonicalPath(folder)))
  }

  @Test func subfolderOfAListedFolderIsAllowed() throws {
    let parent = try makeFolder("Photos")
    let child = try makeFolder("Photos/Favorites")
    let result = FolderList.validate(child, existingPaths: [FolderList.canonicalPath(parent)])
    #expect(result == .accepted(path: FolderList.canonicalPath(child)))
  }
}

struct FolderListDisplayPathTests {
  @Test(arguments: [
    ("/Users/sam", "~"),
    ("/Users/sam/Documents", "~/Documents"),
    ("/Users/sam/Documents/a b", "~/Documents/a b"),
    ("/Users/samantha/Documents", "/Users/samantha/Documents"),  // shares a prefix, not inside home
    ("/Volumes/Backup", "/Volumes/Backup"),
  ])
  func abbreviatesHome(path: String, expected: String) {
    #expect(FolderList.displayPath(path, home: "/Users/sam") == expected)
  }

  @Test func realHomeIsNotTheSandboxContainer() {
    #expect(!FolderList.realHomeDirectory.contains("/Library/Containers/"))
  }
}
