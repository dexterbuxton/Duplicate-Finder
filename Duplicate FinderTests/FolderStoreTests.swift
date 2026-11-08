import Foundation
import Testing
@testable import Duplicate_Finder

/// Runs inside the sandboxed app, so bookmarks behave as they do for real.
/// Each test gets its own UserDefaults suite and temp folder.
@MainActor
@Suite(.serialized)
final class FolderStoreTests {
  let suiteName = "FolderStoreTests-\(UUID().uuidString)"
  let defaults: UserDefaults
  let root: URL

  init() throws {
    defaults = UserDefaults(suiteName: suiteName)!
    root = FileManager.default.temporaryDirectory.appending(path: suiteName)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: root)
  }

  func folder(_ name: String) throws -> URL {
    let url = root.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func names(_ store: FolderStore) -> [String] { store.folders.map(\.name) }

  /// A fresh store reading the same saved data, as after a relaunch.
  func relaunch() -> FolderStore { FolderStore(defaults: defaults) }

  // MARK: - Adding

  @Test func addsInOrderAndRestoresAfterRelaunch() throws {
    let store = FolderStore(defaults: defaults)
    store.add([try folder("A"), try folder("B"), try folder("C")])
    #expect(names(store) == ["A", "B", "C"])
    #expect(store.message == nil)

    let restored = relaunch()
    #expect(names(restored) == ["A", "B", "C"])
    #expect(restored.folders.allSatisfy { $0.isAvailable })
    #expect(restored.folders.map(\.id) == store.folders.map(\.id))
  }

  @Test func insertsAtAPosition() throws {
    let store = FolderStore(defaults: defaults)
    store.add([try folder("A"), try folder("C")])
    store.add([try folder("B")], at: 1)
    #expect(names(store) == ["A", "B", "C"])

    store.add([try folder("Y"), try folder("Z")], at: 0)
    #expect(names(store) == ["Y", "Z", "A", "B", "C"])

    store.add([try folder("End")], at: 99)  // out of range clamps to the end
    #expect(names(relaunch()) == ["Y", "Z", "A", "B", "C", "End"])
  }

  @Test func rejectsDuplicatesAndFilesWithAMessage() throws {
    let store = FolderStore(defaults: defaults)
    let a = try folder("A")
    let file = root.appending(path: "notes.txt")
    try Data("hi".utf8).write(to: file)

    store.add([a])
    store.add([a, file, try folder("B")])

    #expect(names(store) == ["A", "B"])
    let message = try #require(store.message)
    #expect(message.contains("“A” is already in the list"))
    #expect(message.contains("“notes.txt” isn’t a folder"))
  }

  @Test func symlinkIsStoredAsItsTarget() throws {
    let store = FolderStore(defaults: defaults)
    let target = try folder("Real")
    let link = root.appending(path: "Link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    store.add([link])
    #expect(names(store) == ["Real"])
    store.add([target])
    #expect(store.folders.count == 1)
  }

  // MARK: - Reordering and removing

  @Test func moveAndMoveToTopPersist() throws {
    let store = FolderStore(defaults: defaults)
    store.add(try ["A", "B", "C", "D"].map(folder))

    store.move(fromOffsets: [0], toOffset: 3)
    #expect(names(store) == ["B", "C", "A", "D"])

    store.moveToTop(store.folders[3].id)
    #expect(names(store) == ["D", "B", "C", "A"])
    #expect(names(relaunch()) == ["D", "B", "C", "A"])
  }

  @Test func removePersists() throws {
    let store = FolderStore(defaults: defaults)
    store.add(try ["A", "B", "C"].map(folder))
    store.remove(ids: [store.folders[0].id, store.folders[2].id])
    #expect(names(store) == ["B"])
    #expect(names(relaunch()) == ["B"])
  }

  // MARK: - Folders that changed on disk

  @Test func deletedFolderShowsAsUnavailable() throws {
    let store = FolderStore(defaults: defaults)
    let a = try folder("A")
    store.add([a])
    let savedPath = try #require(store.folders.first?.lastKnownPath)

    try FileManager.default.removeItem(at: a)
    let restored = relaunch()

    let entry = try #require(restored.folders.first)
    #expect(!entry.isAvailable)
    #expect(entry.name == "A")
    #expect(entry.lastKnownPath == savedPath)
  }

  @Test func renamedFolderIsFollowed() throws {
    let store = FolderStore(defaults: defaults)
    let original = try folder("Before")
    store.add([original])

    try FileManager.default.moveItem(at: original, to: root.appending(path: "After"))
    let restored = relaunch()

    let entry = try #require(restored.folders.first)
    #expect(entry.isAvailable)
    #expect(entry.name == "After")
  }
}
