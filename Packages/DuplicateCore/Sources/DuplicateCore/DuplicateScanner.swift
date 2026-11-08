import Foundation
import CryptoKit

/// Finds files with identical content.
///
/// Pipeline: walk folders -> group by size -> hash first `prefixSize` bytes -> full SHA-256.
/// Each stage only looks at files that still have a potential match.
public enum DuplicateScanner {

  /// Scans `roots` in priority order (index 0 = highest).
  /// Throws `CancellationError` if the surrounding task is cancelled.
  @concurrent
  public static func scan(
    _ roots: [URL],
    options: ScanOptions = ScanOptions(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> ScanResult {
    let clock = ContinuousClock()
    let start = clock.now
    var state = ScanProgress()
    var lastReport = clock.now - .seconds(1)

    func report(force: Bool = false) {
      let now = clock.now
      guard force || now - lastReport >= .milliseconds(100) else { return }
      lastReport = now
      progress(state)
    }

    // 1. Collect
    let collected = try collect(roots, options: options) { count in
      state.filesFound = count
      report()
    }
    var unreadable = collected.unreadable
    report(force: true)

    // 2. Same size
    let sizeCandidates = Dictionary(grouping: collected.files, by: \.size)
      .values.filter { $0.count > 1 }.flatMap { $0 }

    state.phase = .hashing
    state.bytesToHash = sizeCandidates.reduce(0) { $0 + $1.size }
    report(force: true)

    // 3. Prefix hash
    let prefixResults = try await hashAll(sizeCandidates, limit: options.prefixSize,
                                          maxConcurrent: options.maxConcurrentHashes) { bytes in
      state.bytesHashed += bytes
      report()
    }
    unreadable += prefixResults.filter { $0.hash == nil }.map(\.file.url)
    let prefixGroups = groupByHash(prefixResults)

    // Files no bigger than the prefix were hashed in full already.
    var finalGroups = prefixGroups.filter { $0.files[0].size <= options.prefixSize }
    let needFullHash = prefixGroups.filter { $0.files[0].size > options.prefixSize }.flatMap(\.files)

    // Re-estimate: bytes done so far plus full hashes still needed.
    state.bytesToHash = state.bytesHashed + needFullHash.reduce(0) { $0 + $1.size }
    report(force: true)

    // 4. Full hash
    let fullResults = try await hashAll(needFullHash, limit: nil,
                                        maxConcurrent: options.maxConcurrentHashes) { bytes in
      state.bytesHashed += bytes
      report()
    }
    unreadable += fullResults.filter { $0.hash == nil }.map(\.file.url)
    finalGroups += groupByHash(fullResults)

    state.bytesToHash = state.bytesHashed
    report(force: true)

    let groups = finalGroups.sorted {
      $0.reclaimableBytes != $1.reclaimableBytes ? $0.reclaimableBytes > $1.reclaimableBytes : $0.id < $1.id
    }
    return ScanResult(groups: groups,
                      filesScanned: collected.files.count,
                      filesHashed: sizeCandidates.count,
                      unreadable: unreadable,
                      duration: clock.now - start)
  }

  // MARK: - Collecting

  private struct FileKey: Hashable {
    let device: Int32
    let inode: UInt64
  }

  private final class ErrorLog: @unchecked Sendable {
    var urls: [URL] = []
  }

  /// Synchronous because `FileManager.DirectoryEnumerator` can't be iterated in async code.
  private static func collect(
    _ roots: [URL],
    options: ScanOptions,
    onProgress: (Int) -> Void
  ) throws -> (files: [ScannedFile], unreadable: [URL]) {
    var files: [ScannedFile] = []
    var seen = Set<FileKey>()  // dedupes overlapping folders and hard links
    let errors = ErrorLog()

    var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
    if !options.includeHiddenFiles { enumerationOptions.insert(.skipsHiddenFiles) }

    for (rootIndex, root) in roots.enumerated() {
      try Task.checkCancellation()
      guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: nil, options: enumerationOptions,
        errorHandler: { url, _ in errors.urls.append(url); return true }
      ) else {
        errors.urls.append(root)
        continue
      }

      var visited = 0
      for case let url as URL in enumerator {
        visited += 1
        if visited % 256 == 0 { try Task.checkCancellation() }

        var info = stat()
        let ok = url.withUnsafeFileSystemRepresentation { path in
          path.map { lstat($0, &info) == 0 } ?? false
        }
        guard ok else { errors.urls.append(url); continue }
        // Regular files only: skips symlinks, directories, sockets, etc.
        guard info.st_mode & S_IFMT == S_IFREG else { continue }

        let size = Int64(info.st_size)
        guard size >= options.minimumFileSize else { continue }
        guard seen.insert(FileKey(device: info.st_dev, inode: info.st_ino)).inserted else { continue }

        files.append(ScannedFile(url: url,
                                 size: size,
                                 modificationDate: date(info.st_mtimespec),
                                 creationDate: date(info.st_birthtimespec),
                                 rootIndex: rootIndex))
        onProgress(files.count)
      }
    }
    return (files, errors.urls)
  }

  private static func date(_ time: timespec) -> Date {
    Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
  }

  // MARK: - Hashing

  private struct HashResult: Sendable {
    let file: ScannedFile
    let hash: String?   // nil = unreadable
    let bytesRead: Int64
  }

  /// Hashes files concurrently, at most `maxConcurrent` at a time.
  private static func hashAll(
    _ files: [ScannedFile],
    limit: Int64?,
    maxConcurrent: Int,
    onFileHashed: (Int64) -> Void
  ) async throws -> [HashResult] {
    try await withThrowingTaskGroup(of: HashResult.self) { group in
      var results: [HashResult] = []
      results.reserveCapacity(files.count)
      var next = 0

      while next < min(max(1, maxConcurrent), files.count) {
        let file = files[next]
        group.addTask { try hash(file, limit: limit) }
        next += 1
      }
      while let result = try await group.next() {
        results.append(result)
        onFileHashed(result.bytesRead)
        if next < files.count {
          let file = files[next]
          group.addTask { try hash(file, limit: limit) }
          next += 1
        }
      }
      return results
    }
  }

  private static func hash(_ file: ScannedFile, limit: Int64?) throws -> HashResult {
    guard let handle = try? FileHandle(forReadingFrom: file.url) else {
      return HashResult(file: file, hash: nil, bytesRead: 0)
    }
    defer { try? handle.close() }

    var hasher = SHA256()
    var remaining = limit ?? .max
    var total: Int64 = 0
    while remaining > 0 {
      try Task.checkCancellation()
      let chunk: Data
      do {
        guard let data = try handle.read(upToCount: Int(min(remaining, 1 << 20))), !data.isEmpty else { break }
        chunk = data
      } catch {
        return HashResult(file: file, hash: nil, bytesRead: total)
      }
      hasher.update(data: chunk)
      total += Int64(chunk.count)
      remaining -= Int64(chunk.count)
    }
    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return HashResult(file: file, hash: hex, bytesRead: total)
  }

  /// Groups readable results by (size, hash), keeping only groups with 2+ files.
  private static func groupByHash(_ results: [HashResult]) -> [DuplicateGroup] {
    struct Key: Hashable { let size: Int64; let hash: String }
    var buckets: [Key: [ScannedFile]] = [:]
    for result in results {
      guard let hash = result.hash else { continue }
      buckets[Key(size: result.file.size, hash: hash), default: []].append(result.file)
    }
    return buckets.compactMap { key, files in
      guard files.count > 1 else { return nil }
      let sorted = files.sorted {
        $0.rootIndex != $1.rootIndex ? $0.rootIndex < $1.rootIndex : $0.url.path < $1.url.path
      }
      return DuplicateGroup(id: key.hash, size: key.size, files: sorted)
    }
  }
}
