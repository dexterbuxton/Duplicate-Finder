import Foundation

/// A regular file found during a scan.
public struct ScannedFile: Sendable, Hashable, Identifiable {
  public var id: String { url.path }
  public let url: URL
  public let size: Int64
  public let modificationDate: Date
  public let creationDate: Date
  /// Position in the folder list of the folder this file was found through (0 = highest priority).
  public let rootIndex: Int

  public init(url: URL, size: Int64, modificationDate: Date, creationDate: Date, rootIndex: Int) {
    self.url = url
    self.size = size
    self.modificationDate = modificationDate
    self.creationDate = creationDate
    self.rootIndex = rootIndex
  }
}

/// Two or more files with byte-for-byte identical content.
public struct DuplicateGroup: Sendable, Hashable, Identifiable {
  /// SHA-256 of the content, hex encoded.
  public let id: String
  public let size: Int64
  /// Sorted by folder priority, then path.
  public let files: [ScannedFile]

  /// Space freed by keeping just one copy.
  public var reclaimableBytes: Int64 { size * Int64(files.count - 1) }
}

public struct ScanResult: Sendable {
  /// Sorted by reclaimable space, largest first.
  public let groups: [DuplicateGroup]
  /// Files considered (after skipping symlinks, hidden, empty and already-seen files).
  public let filesScanned: Int
  /// Files that had at least part of their content read.
  public let filesHashed: Int
  /// Files or folders that couldn't be read.
  public let unreadable: [URL]
  public let duration: Duration

  public var duplicateCount: Int { groups.reduce(0) { $0 + $1.files.count - 1 } }
  public var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
}

public struct ScanProgress: Sendable, Equatable {
  public enum Phase: Sendable, Equatable {
    case collecting
    case hashing
  }

  public var phase: Phase
  public var filesFound: Int
  public var bytesHashed: Int64
  /// Estimate; shrinks as the prefix pass rules files out.
  public var bytesToHash: Int64

  public init(phase: Phase = .collecting, filesFound: Int = 0, bytesHashed: Int64 = 0, bytesToHash: Int64 = 0) {
    self.phase = phase
    self.filesFound = filesFound
    self.bytesHashed = bytesHashed
    self.bytesToHash = bytesToHash
  }

  /// 0...1 during hashing, nil while still collecting.
  public var fractionComplete: Double? {
    guard phase == .hashing, bytesToHash > 0 else { return nil }
    return min(1, Double(bytesHashed) / Double(bytesToHash))
  }
}

public struct ScanOptions: Sendable {
  public var includeHiddenFiles = false
  /// Files smaller than this are ignored. Default skips empty files.
  public var minimumFileSize: Int64 = 1
  /// Bytes hashed in the first pass to cheaply rule out same-size files.
  public var prefixSize: Int64 = 16 * 1024
  public var maxConcurrentHashes = 4

  public init() {}
}
