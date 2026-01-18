import ArgumentParser
import Foundation
import PathKit

#if os(macOS)
  import CoreServices

  class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    private let ignoredPatterns: [String]
    private let basePath: String
    private var lastModificationTimes: [String: Date] = [:]

    init(paths: [String], ignoredPatterns: [String] = [], folderDidChange: @escaping () -> Void) {
      self.callback = folderDidChange
      self.ignoredPatterns = ignoredPatterns
      self.basePath = Path.current.string

      var context = FSEventStreamContext()
      context.info = Unmanaged.passUnretained(self).toOpaque()

      let flags = UInt32(
        kFSEventStreamCreateFlagUseCFTypes |
        kFSEventStreamCreateFlagFileEvents |
        kFSEventStreamCreateFlagNoDefer
      )

      stream = FSEventStreamCreate(
        nil,
        { (_, info, numEvents, eventPaths, eventFlags, _) in
          guard let info = info else { return }
          let monitor = Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue()

          guard numEvents > 0,
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            return
          }

          // Only respond to actual content changes
          let contentChangeFlags: UInt32 =
            UInt32(kFSEventStreamEventFlagItemCreated) |
            UInt32(kFSEventStreamEventFlagItemRemoved) |
            UInt32(kFSEventStreamEventFlagItemRenamed) |
            UInt32(kFSEventStreamEventFlagItemModified)

          var hasRelevantChange = false
          for i in 0..<numEvents {
            let flags = eventFlags[i]
            if (flags & contentChangeFlags) != 0 {
              let path = paths[i]

              // Check if this path matches any ignored patterns
              if monitor.shouldIgnore(path: path) {
                continue
              }

              // Only trigger if the file's modification time actually changed
              if !monitor.hasFileActuallyChanged(path: path) {
                continue
              }

              hasRelevantChange = true
            }
          }

          if hasRelevantChange {
            monitor.callback()
          }
        },
        &context,
        paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.3, // debounce delay in seconds
        flags
      )

      if let stream = stream {
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "FolderMonitorQueue"))
        FSEventStreamStart(stream)
      }
    }

    private func hasFileActuallyChanged(path: String) -> Bool {
      let fileManager = FileManager.default

      guard let attributes = try? fileManager.attributesOfItem(atPath: path),
            let modDate = attributes[.modificationDate] as? Date else {
        // File doesn't exist or can't read - might be deleted, treat as changed
        lastModificationTimes.removeValue(forKey: path)
        return true
      }

      if let lastMod = lastModificationTimes[path] {
        if modDate <= lastMod {
          // Modification time hasn't changed - not a real modification
          return false
        }
      }

      lastModificationTimes[path] = modDate
      return true
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
      if let stream = stream {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
      }
    }
  }

  private func runCommand(_ cmd: String, process: Process = Process()) -> String? {
    let pipe = Pipe()
    process.launchPath = "/bin/sh"
    process.arguments = ["-c", String(format: "%@", cmd)]
    process.standardOutput = pipe
    let fileHandle = pipe.fileHandleForReading
    process.launch()
    return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
  }

  struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Watch folders for changes and rebuild the site.",
      discussion: """
        Monitors the specified folders for file changes and automatically rebuilds the site.
        Starts a local development server using browser-sync.

        Legacy usage:
          watch <folders...> <output>

        New usage:
          watch --watch content --watch Sources --output deploy --ignore "*.tmp"
        """
    )

    private static let defaultIgnorePatterns = [".DS_Store"]

    @Option(name: .shortAndLong, help: "Folder to watch for changes. Can be specified multiple times.")
    var watch: [String] = []

    @Option(name: .shortAndLong, help: "Output folder for the built site (also used by browser-sync).")
    var output: String?

    @Option(name: .shortAndLong, help: "Glob pattern for files/folders to ignore. Can be specified multiple times.")
    var ignore: [String] = []

    @Argument(help: "Legacy positional arguments: <folders...> <output>")
    var legacyArgs: [String] = []

    mutating func run() throws {
      let watchFolders: [String]
      let outputFolder: String

      // Determine if we're using new-style or legacy arguments
      if !watch.isEmpty, let out = output {
        // New style: --watch and --output specified
        watchFolders = watch
        outputFolder = out
      } else if !legacyArgs.isEmpty {
        // Legacy style: positional arguments
        if legacyArgs.count < 2 {
          throw ValidationError("Legacy usage requires at least 2 arguments: <folders...> <output>")
        }
        var args = legacyArgs
        outputFolder = args.removeLast()
        watchFolders = args
      } else {
        throw ValidationError("Either use --watch and --output options, or provide legacy positional arguments.")
      }

      print("Building website, please wait...")
      _ = runCommand("swift run")

      // Turn the folders into full paths
      let paths = watchFolders.map { folder in
        (Path.current + folder).string
      }

      // Start monitoring!
      print("Monitoring for changes!")
      if !ignore.isEmpty {
        print("Ignoring patterns: \(ignore.joined(separator: ", "))")
      }

      let folderMonitor = FolderMonitor(paths: paths, ignoredPatterns: Self.defaultIgnorePatterns + ignore) {
        print("Detected change, rebuilding website...")
        _ = runCommand("swift run")
      }

      let serverQueue = DispatchQueue(label: "Saga.WebServer")
      let serverProcess = Process()

      // Handle Ctrl+C shutdown
      let signalsQueue = DispatchQueue(label: "Saga.Signals")
      let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalsQueue)
      sigintSrc.setEventHandler {
        serverProcess.terminate()
        Darwin.exit(0)
      }
      sigintSrc.resume()
      signal(SIGINT, SIG_IGN) // Make sure the signal does not terminate the application.

      // Start web server using browser-sync
      serverQueue.async {
        _ = runCommand("browser-sync \"\(outputFolder)\" -w --no-notify", process: serverProcess)
        serverProcess.terminate()
        Darwin.exit(1)
      }

      // Keep server running
      _ = readLine()

      // Prevent folderMonitor from being deallocated
      _ = folderMonitor

      serverProcess.terminate()
    }
  }

  Watch.main()
#endif
