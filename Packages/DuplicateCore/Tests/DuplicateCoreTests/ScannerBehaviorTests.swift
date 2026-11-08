import Foundation
import Testing
@testable import DuplicateCore

/// Small, self-contained cases built in a temporary folder.
struct ScannerBehaviorTests {
  let dir: URL

  init() throws {
    dir = FileManager.default.temporaryDirectory.appending(path: "DuplicateCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  func write(_ name: String, _ text: String) throws -> URL {
    let url = dir.appending(path: name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }

  @Test func hardLinksAreNotDuplicates() async throws {
    let original = try write("a.txt", "same content")
    try FileManager.default.linkItem(at: original, to: dir.appending(path: "b.txt"))
    let result = try await DuplicateScanner.scan([dir])
    #expect(result.groups.isEmpty)
    #expect(result.filesScanned == 1)
  }

  @Test func hiddenFilesAreOptIn() async throws {
    _ = try write("visible.txt", "hello")
    _ = try write(".hidden.txt", "hello")

    #expect(try await DuplicateScanner.scan([dir]).groups.isEmpty)

    var options = ScanOptions()
    options.includeHiddenFiles = true
    #expect(try await DuplicateScanner.scan([dir], options: options).groups.count == 1)
  }

  @Test func filesLargerThanPrefixNeedFullMatch() async throws {
    var options = ScanOptions()
    options.prefixSize = 4
    _ = try write("one.txt", "SAME-PREFIX-tail-1")
    _ = try write("two.txt", "SAME-PREFIX-tail-2")
    _ = try write("three.txt", "SAME-PREFIX-tail-1")

    let result = try await DuplicateScanner.scan([dir], options: options)
    #expect(result.groups.count == 1)
    #expect(Set(result.groups[0].files.map(\.url.lastPathComponent)) == ["one.txt", "three.txt"])
  }

  @Test func reportsProgressAndFinishesAtOneHundredPercent() async throws {
    _ = try write("x/1.txt", "dup")
    _ = try write("y/2.txt", "dup")
    let log = ProgressLog()
    _ = try await DuplicateScanner.scan([dir]) { log.append($0) }
    let last = try #require(log.values.last)
    #expect(last.phase == .hashing)
    #expect(last.fractionComplete == 1)
  }

  @Test func cancellationStopsTheScan() async throws {
    for i in 0..<50 { _ = try write("f\(i).txt", "content \(i % 5)") }
    let task = Task { try await DuplicateScanner.scan([dir]) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}

final class ProgressLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [ScanProgress] = []
  func append(_ value: ScanProgress) { lock.withLock { storage.append(value) } }
  var values: [ScanProgress] { lock.withLock { storage } }
}
