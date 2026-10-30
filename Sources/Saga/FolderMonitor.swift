import Foundation
import SagaPathKit
#if canImport(CoreServices)
  import CoreServices
#endif

class FolderMonitor {
  private let callback: (Set<Path>) -> Void
  private let ignoredPatterns: [String]
  private let basePath: Path
  private let paths: [Path]
  private let queue = DispatchQueue(label: "Saga.FolderMonitor")
  private var knownFiles: [Path: Date] = [:]
  private var timer: DispatchSourceTimer?
  #if canImport(CoreServices)
    private var stream: FSEventStreamRef?
  #endif

  init(paths: [Path], ignoredPatterns: [String] = [], folderDidChange: @escaping (Set<Path>) -> Void) {
    self.paths = paths
    callback = folderDidChange
    self.ignoredPatterns = ignoredPatterns
    basePath = Path.current

    // Take initial snapshot
    knownFiles = scanFiles()

    // FSEvents only says that something changed; the snapshot diff decides what.
    // The timer catches anything FSEvents drops.
    #if canImport(CoreServices)
      startEventStream()
      let pollInterval = 10.0
    #else
      let pollInterval = 1.0
    #endif

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
    timer.setEventHandler { [weak self] in
      self?.checkForChanges()
    }
    timer.resume()
    self.timer = timer
  }

  #if canImport(CoreServices)
    private func startEventStream() {
      var context = FSEventStreamContext()
      context.info = Unmanaged.passUnretained(self).toOpaque()

      let flags = UInt32(kFSEventStreamCreateFlagFileEvents)

      guard let stream = FSEventStreamCreate(
        nil,
        { _, info, _, _, _, _ in
          guard let info else { return }
          Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue().checkForChanges()
        },
        &context,
        paths.map { $0.absolute().string } as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.2,
        flags
      ) else { return }

      FSEventStreamSetDispatchQueue(stream, queue)
      FSEventStreamStart(stream)
      self.stream = stream
    }
  #endif

  private func checkForChanges() {
    let currentFiles = scanFiles()

    var changedPaths: Set<Path> = []

    // Check for new or modified files
    for (path, modDate) in currentFiles {
      if let previousDate = knownFiles[path] {
        if modDate != previousDate {
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
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]

    for watchPath in paths {
      guard let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: watchPath.string),
        includingPropertiesForKeys: Array(keys)
      ) else { continue }

      for case let url as URL in enumerator {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              let modDate = values.contentModificationDate
        else { continue }

        let fullPath = Path(url.path)
        let relativePath = (try? fullPath.relativePath(from: basePath)) ?? fullPath
        if Self.matchesGlobPattern(relativePath, patterns: ignoredPatterns) {
          continue
        }

        result[fullPath] = modDate
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
    #if canImport(CoreServices)
      if let stream {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
      }
    #endif
  }
}
