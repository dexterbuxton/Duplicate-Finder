import Foundation
import Testing
@testable import DuplicateCore

struct ModelTests {
  func file(_ name: String, size: Int64 = 100) -> ScannedFile {
    ScannedFile(url: URL(filePath: "/tmp/\(name)"), size: size,
                modificationDate: .distantPast, creationDate: .distantPast, rootIndex: 0)
  }

  @Test func groupReclaimsAllButOneCopy() {
    let pair = DuplicateGroup(id: "a", size: 100, files: [file("1"), file("2")])
    let four = DuplicateGroup(id: "b", size: 10, files: (1...4).map { file("\($0)", size: 10) })
    #expect(pair.reclaimableBytes == 100)
    #expect(four.reclaimableBytes == 30)
  }

  @Test func resultTotalsAcrossGroups() {
    let result = ScanResult(
      groups: [
        DuplicateGroup(id: "a", size: 100, files: [file("1"), file("2")]),
        DuplicateGroup(id: "b", size: 10, files: (1...4).map { file("\($0)", size: 10) }),
      ],
      filesScanned: 10, filesHashed: 6, unreadable: [], duration: .zero)
    #expect(result.duplicateCount == 4)
    #expect(result.reclaimableBytes == 130)
  }

  @Test func emptyResultHasNoDuplicates() {
    let result = ScanResult(groups: [], filesScanned: 0, filesHashed: 0, unreadable: [], duration: .zero)
    #expect(result.duplicateCount == 0)
    #expect(result.reclaimableBytes == 0)
  }

  @Test func fractionCompleteOnlyDuringHashing() {
    #expect(ScanProgress(phase: .collecting, bytesHashed: 5, bytesToHash: 10).fractionComplete == nil)
    #expect(ScanProgress(phase: .hashing, bytesHashed: 0, bytesToHash: 0).fractionComplete == nil)
    #expect(ScanProgress(phase: .hashing, bytesHashed: 5, bytesToHash: 10).fractionComplete == 0.5)
    // The estimate can shrink below bytes already hashed; never report over 100%.
    #expect(ScanProgress(phase: .hashing, bytesHashed: 12, bytesToHash: 10).fractionComplete == 1)
  }
}
