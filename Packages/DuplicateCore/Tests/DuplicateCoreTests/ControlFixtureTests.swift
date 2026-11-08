import Foundation
import Testing
@testable import DuplicateCore

/// Runs the scanner against the generated control set and compares with Fixtures/manifest.json.
/// Regenerates the fixtures (python3 Scripts/make_fixtures.py) if they're missing.
@Suite(.serialized)
struct ControlFixtureTests {
  static let repoRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()  // DuplicateCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // DuplicateCore
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repo
  static let fixtures = repoRoot.appending(path: "Fixtures")
  static let control = fixtures.appending(path: "Control")
  static let priorityOrder = ["Primary", "Backup", "Downloads", "Archive", "EdgeCases"]

  struct Manifest: Decodable {
    struct Copy: Decodable { let path: String }
    struct Group: Decodable {
      let sha256: String
      let size: Int64
      let original: String
      let copies: [Copy]
      var paths: Set<String> { Set([original] + copies.map(\.path)) }
    }
    let groups: [Group]
  }

  init() throws {
    if !FileManager.default.fileExists(atPath: Self.control.path) {
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/env")
      process.arguments = ["python3", Self.repoRoot.appending(path: "Scripts/make_fixtures.py").path]
      try process.run()
      process.waitUntilExit()
      #expect(process.terminationStatus == 0, "Fixture generation failed")
    }
  }

  func manifest() throws -> Manifest {
    try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.fixtures.appending(path: "manifest.json")))
  }

  func relative(_ url: URL) -> String {
    String(url.standardizedFileURL.path.dropFirst(Self.fixtures.standardizedFileURL.path.count + 1))
  }

  func pathSets(_ result: ScanResult) -> Set<Set<String>> {
    Set(result.groups.map { Set($0.files.map { relative($0.url) }) })
  }

  @Test func findsExactlyTheManifestGroups() async throws {
    let roots = Self.priorityOrder.map { Self.control.appending(path: $0) }
    let result = try await DuplicateScanner.scan(roots)
    let expected = try manifest()

    #expect(pathSets(result) == Set(expected.groups.map(\.paths)))
    #expect(Set(result.groups.map(\.id)) == Set(expected.groups.map(\.sha256)))
    #expect(result.groups.count == 18)
    #expect(result.duplicateCount == 30)
    #expect(result.unreadable.isEmpty)
  }

  @Test func filesAreSortedByFolderPriority() async throws {
    let roots = Self.priorityOrder.map { Self.control.appending(path: $0) }
    let result = try await DuplicateScanner.scan(roots)
    for group in result.groups {
      let indexes = group.files.map(\.rootIndex)
      #expect(indexes == indexes.sorted())
      #expect(relative(group.files[0].url).hasPrefix("Control/Primary/"))
    }
  }

  @Test func edgeCasesProduceNoGroups() async throws {
    let result = try await DuplicateScanner.scan([Self.control.appending(path: "EdgeCases")])
    #expect(result.groups.isEmpty)
    // Empty files and the symlink are skipped: 6 real files remain.
    #expect(result.filesScanned == 6)
  }

  @Test func overlappingFoldersCountEachFileOnce() async throws {
    let separate = try await DuplicateScanner.scan(Self.priorityOrder.map { Self.control.appending(path: $0) })
    let overlapping = try await DuplicateScanner.scan([Self.control, Self.control.appending(path: "Primary")])

    #expect(pathSets(overlapping) == pathSets(separate))
    #expect(overlapping.filesScanned == separate.filesScanned)
    for group in overlapping.groups {
      #expect(Set(group.files.map(\.url.path)).count == group.files.count)
    }
  }
}
