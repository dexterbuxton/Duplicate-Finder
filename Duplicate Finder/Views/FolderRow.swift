import SwiftUI

struct FolderRow: View {
  let folder: ScanFolder
  let priority: Int
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("\(priority)")
        .font(.title3.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 28, alignment: .trailing)

      Image(systemName: folder.isAvailable ? "folder.fill" : "exclamationmark.triangle.fill")
        .font(.title2)
        .foregroundStyle(folder.isAvailable ? Color.accentColor : Color.orange)

      VStack(alignment: .leading, spacing: 2) {
        Text(folder.name)
          .font(.body.weight(.medium))
        Text(folder.isAvailable ? folder.displayPath : "Not found: \(folder.displayPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      if priority == 1 {
        Text("Highest priority")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button("Remove", systemImage: "minus.circle", action: onRemove)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Remove from list")
    }
    .padding(.vertical, 4)
  }
}
