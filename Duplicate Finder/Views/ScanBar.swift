import SwiftUI
import DuplicateCore

/// Bottom bar: Scan / Cancel button plus status, progress, or a results summary.
struct ScanBar: View {
  @Environment(FolderStore.self) private var store
  @Environment(ScanModel.self) private var scanner

  private var availableFolders: [ScanFolder] { store.folders.filter(\.isAvailable) }

  var body: some View {
    HStack(spacing: 12) {
      status
      Spacer()
      if scanner.isScanning {
        Button("Cancel") { scanner.cancel() }
          .keyboardShortcut(.cancelAction)
      } else {
        Button("Scan") { scanner.start(folders: store.folders) }
          .keyboardShortcut(.defaultAction)
          .disabled(availableFolders.isEmpty)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var status: some View {
    switch scanner.state {
    case .idle:
      Text(availableFolders.isEmpty
           ? "Add folders to scan."
           : "\(availableFolders.count) \(availableFolders.count == 1 ? "folder" : "folders") ready to scan.")
        .foregroundStyle(.secondary)

    case .scanning(let progress):
      HStack(spacing: 8) {
        if let fraction = progress.fractionComplete {
          ProgressView(value: fraction)
            .frame(width: 160)
          Text("Comparing files… \(fraction, format: .percent.precision(.fractionLength(0)))")
        } else {
          ProgressView()
            .controlSize(.small)
          Text("Finding files… \(progress.filesFound, format: .number)")
        }
      }
      .foregroundStyle(.secondary)

    case .finished(let result):
      VStack(alignment: .leading, spacing: 2) {
        Text(result.groups.isEmpty
             ? "No duplicates found."
             : "\(result.duplicateCount, format: .number) duplicates in \(result.groups.count, format: .number) groups · \(Self.bytes(result.reclaimableBytes)) can be freed")
          .font(.body.weight(.medium))
        Text(details(result))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private func details(_ result: ScanResult) -> String {
    var parts = ["\(result.filesScanned.formatted()) files scanned in \(result.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated, maximumUnitCount: 1)))"]
    if !result.unreadable.isEmpty {
      parts.append("\(result.unreadable.count.formatted()) couldn’t be read")
    }
    return parts.joined(separator: " · ")
  }

  private static func bytes(_ count: Int64) -> String {
    count.formatted(.byteCount(style: .file))
  }
}
