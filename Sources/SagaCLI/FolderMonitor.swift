import Foundation

class FolderMonitor {
  private let callback: () -> Void
  private let ignoredPatterns: [String]
  private let basePath: String
  private let paths: [String]
  private var knownFiles: [String: Date] = [:]
  private var timer: DispatchSourceTimer?

  init(paths: [String], ignoredPatterns: [String] = [], folderDidChange: @escaping () -> Void) {
    self.paths = paths
    self.callback = folderDidChange
    self.ignoredPatterns = ignoredPatterns
    self.basePath = FileManager.default.currentDirectoryPath

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

    var changed = false

    // Check for new or modified files
    for (path, modDate) in currentFiles {
      if let previousDate = knownFiles[path] {
        if modDate > previousDate {
          changed = true
          break
        }
      } else {
        // New file
        changed = true
        break
      }
    }

    // Check for deleted files
    if !changed {
      for path in knownFiles.keys {
        if currentFiles[path] == nil {
          changed = true
          break
        }
      }
    }

    if changed {
      knownFiles = currentFiles
      callback()
    }
  }

  private func scanFiles() -> [String: Date] {
    let fileManager = FileManager.default
    var result: [String: Date] = [:]

    for watchPath in paths {
      guard let enumerator = fileManager.enumerator(atPath: watchPath) else { continue }

      while let relativePath = enumerator.nextObject() as? String {
        let fullPath = watchPath + "/" + relativePath

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else {
          continue
        }

        if shouldIgnore(path: fullPath) {
          continue
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
           let modDate = attributes[.modificationDate] as? Date {
          result[fullPath] = modDate
        }
      }
    }

    return result
  }

  private func shouldIgnore(path: String) -> Bool {
    guard !ignoredPatterns.isEmpty else { return false }

    let relativePath: String
    if path.hasPrefix(basePath) {
      relativePath = String(path.dropFirst(basePath.count + 1))
    } else {
      relativePath = path
    }

    for pattern in ignoredPatterns {
      if fnmatch(pattern, relativePath, FNM_PATHNAME) == 0 {
        return true
      }
      if let filename = relativePath.split(separator: "/").last {
        if fnmatch(pattern, String(filename), 0) == 0 {
          return true
        }
      }
    }

    return false
  }

  deinit {
    timer?.cancel()
  }
}
