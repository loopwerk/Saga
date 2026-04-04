import Foundation
import SagaPathKit

class FolderMonitor {
  private let callback: (Set<Path>) -> Void
  private let ignoredPatterns: [String]
  private let basePath: Path
  private let paths: [Path]
  private var knownFiles: [Path: Date] = [:]
  private var timer: DispatchSourceTimer?

  init(paths: [Path], ignoredPatterns: [String] = [], folderDidChange: @escaping (Set<Path>) -> Void) {
    self.paths = paths
    callback = folderDidChange
    self.ignoredPatterns = ignoredPatterns
    basePath = Path.current

    // Take initial snapshot
    knownFiles = scanFiles()

    // Poll for changes every second
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "Saga.FolderMonitor"))
    timer.schedule(deadline: .now() + 1, repeating: 1.0)
    timer.setEventHandler { [weak self] in
      self?.checkForChanges()
    }
    timer.resume()
    self.timer = timer
  }

  private func checkForChanges() {
    let currentFiles = scanFiles()

    var changedPaths: Set<Path> = []

    // Check for new or modified files
    for (path, modDate) in currentFiles {
      if let previousDate = knownFiles[path] {
        if modDate > previousDate {
          changedPaths.insert(path)
        }
      } else {
        // New file
        changedPaths.insert(path)
      }
    }

    // Check for deleted files
    for path in knownFiles.keys {
      if currentFiles[path] == nil {
        changedPaths.insert(path)
      }
    }

    if !changedPaths.isEmpty {
      knownFiles = currentFiles
      callback(changedPaths)
    }
  }

  private func scanFiles() -> [Path: Date] {
    var result: [Path: Date] = [:]

    for watchPath in paths {
      guard let children = try? watchPath.recursiveChildren() else { continue }

      for fullPath in children {
        guard fullPath.isFile else { continue }

        let relativePath = (try? fullPath.relativePath(from: basePath)) ?? fullPath
        if Self.matchesGlobPattern(relativePath, patterns: ignoredPatterns) {
          continue
        }

        if let modDate = fullPath.modificationDate {
          result[fullPath] = modDate
        }
      }
    }

    return result
  }

  static func matchesGlobPattern(_ relativePath: Path, patterns: [String]) -> Bool {
    for pattern in patterns {
      if fnmatch(pattern, relativePath.string, FNM_PATHNAME) == 0 {
        return true
      }
      let filename = relativePath.lastComponent
      if fnmatch(pattern, filename, 0) == 0 {
        return true
      }
    }
    return false
  }

  deinit {
    timer?.cancel()
  }
}
