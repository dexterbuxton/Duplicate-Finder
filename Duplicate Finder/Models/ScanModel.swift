import Foundation
import Observation
import DuplicateCore

/// Runs scans and exposes their state to the UI.
@Observable
final class ScanModel {
  enum State {
    case idle
    case scanning(ScanProgress)
    case finished(ScanResult)
    case failed(String)
  }

  private(set) var state: State = .idle
  @ObservationIgnored private var task: Task<Void, Never>?

  var isScanning: Bool {
    if case .scanning = state { return true }
    return false
  }

  /// Scans the available folders in list order (first = highest priority).
  func start(folders: [ScanFolder]) {
    let roots = folders.compactMap(\.url)
    guard !roots.isEmpty else { return }

    task?.cancel()
    state = .scanning(ScanProgress())
    task = Task {
      do {
        let result = try await DuplicateScanner.scan(roots) { progress in
          Task { @MainActor in self.update(progress) }
        }
        state = .finished(result)
      } catch is CancellationError {
        state = .idle
      } catch {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func cancel() {
    task?.cancel()
  }

  /// Clears results, e.g. after the folder list changes.
  func reset() {
    task?.cancel()
    state = .idle
  }

  private func update(_ progress: ScanProgress) {
    guard isScanning else { return }  // ignore late updates after finishing/cancelling
    state = .scanning(progress)
  }
}
