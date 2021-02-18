import PathKit
import Foundation

#if os(macOS)
class FolderMonitor {
  private let folderMonitorQueue = DispatchQueue(label: "FolderMonitorQueue", attributes: .concurrent)
  private var folderMonitorSources: [URL: DispatchSourceFileSystemObject] = [:]

  /// Listen for changes to the paths
  init(urls: [URL], folderDidChange: @escaping () -> Void) {
    for url in urls {
      let monitoredFolderFileDescriptor = open(url.path, O_EVTONLY)
      let folderMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: monitoredFolderFileDescriptor, eventMask: .write, queue: folderMonitorQueue)
      folderMonitorSource.setEventHandler {
        folderDidChange()
      }

      folderMonitorSources[url] = folderMonitorSource

      // Start monitoring the directory via the source.
      folderMonitorSource.resume()
    }
  }

  deinit {
    for folderMonitorSource in folderMonitorSources.values {
      folderMonitorSource.cancel()
    }
  }
}

enum WatcherError: Error {
  case invalidArguments
}

private func runCommand(_ cmd: String, process: Process = Process()) -> String? {
  let pipe = Pipe()
  process.launchPath = "/bin/sh"
  process.arguments = ["-c", String(format:"%@", cmd)]
  process.standardOutput = pipe
  let fileHandle = pipe.fileHandleForReading
  process.launch()
  return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
}

class Watcher {
  let folderMonitor: FolderMonitor

  init() throws {
    if CommandLine.arguments.count < 3 {
      throw WatcherError.invalidArguments
    }

    print("Building website, please wait...")
    _ = runCommand("swift run")

    var folders = CommandLine.arguments.dropFirst()
    let output = folders.removeLast()

    // Turn the urls that were given as CLI arguments into full paths
    var urls = folders
      .map { folder in
        return Path.current + folder
      }

    // Add all their subfolders too
    let subUrls = try urls
      .flatMap { folder -> [Path] in
        return try folder.recursiveChildren().filter { $0.isDirectory }
      }
    urls.append(contentsOf: subUrls)

    let allUrls = urls
      .compactMap { URL(string: $0.string) }

    // Start monitoring!
    print("Monitoring for changes!")
    folderMonitor = FolderMonitor(urls: allUrls) {
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
      exit(0)
    }
    sigintSrc.resume()
    signal(SIGINT, SIG_IGN) // Make sure the signal does not terminate the application.

    // Start web server, using lite-server (we just assume it's globally installed!)
    serverQueue.async {
      _ = runCommand("browser-sync \"\(output)\" -w --no-notify", process: serverProcess)
      serverProcess.terminate()
      exit(1)
    }

    // Keep server running
    _ = readLine()

    serverProcess.terminate()
  }
}

_ = try Watcher()
#endif
