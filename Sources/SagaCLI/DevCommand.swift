import ArgumentParser
import Foundation

struct Dev: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Build, watch for changes, and serve the site with auto-reload."
  )

  @Option(name: .shortAndLong, help: "Folder to watch for changes. Can be specified multiple times.")
  var watch: [String] = ["content", "Sources"]

  @Option(name: .shortAndLong, help: "Output folder for the built site.")
  var output: String = "deploy"

  @Option(name: .shortAndLong, help: "Port for the development server.")
  var port: Int = 3000

  @Option(name: .shortAndLong, help: "Glob pattern for files to ignore. Can be specified multiple times.")
  var ignore: [String] = []

  func run() throws {
    print("Building site...")
    let buildResult = runBuild()
    if !buildResult {
      print("Initial build failed, starting server anyway...")
    }

    // Start the dev server
    let server = DevServer(outputPath: output, port: port)

    let serverQueue = DispatchQueue(label: "Saga.DevServer")
    serverQueue.async {
      do {
        try server.start()
      } catch {
        print("Failed to start server: \(error)")
        Foundation.exit(1)
      }
    }

    // Give the server a moment to start
    Thread.sleep(forTimeInterval: 0.5)
    print("Development server running at http://localhost:\(port)/")

    // Open the browser
    openBrowser(url: "http://localhost:\(port)/")

    // Turn watch folders into full paths
    let currentPath = FileManager.default.currentDirectoryPath
    let paths = watch.map { folder -> String in
      if folder.hasPrefix("/") {
        return folder
      }
      return currentPath + "/" + folder
    }

    let defaultIgnorePatterns = [".DS_Store"]

    // Start monitoring
    if !ignore.isEmpty {
      print("Ignoring patterns: \(ignore.joined(separator: ", "))")
    }

    var isRebuilding = false
    let rebuildLock = NSLock()

    let folderMonitor = FolderMonitor(paths: paths, ignoredPatterns: defaultIgnorePatterns + ignore) {
      rebuildLock.lock()
      guard !isRebuilding else {
        rebuildLock.unlock()
        return
      }
      isRebuilding = true
      rebuildLock.unlock()

      print("Change detected, rebuilding...")
      let success = runBuild()
      if success {
        print("Rebuild complete.")
        server.sendReload()
      } else {
        print("Rebuild failed.")
      }

      rebuildLock.lock()
      isRebuilding = false
      rebuildLock.unlock()
    }

    // Handle Ctrl+C shutdown
    let signalsQueue = DispatchQueue(label: "Saga.Signals")
    let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalsQueue)
    sigintSrc.setEventHandler {
      print("\nShutting down...")
      server.stop()
      Foundation.exit(0)
    }
    sigintSrc.resume()
    signal(SIGINT, SIG_IGN)

    print("Watching for changes in: \(watch.joined(separator: ", "))")

    // Prevent folderMonitor from being deallocated
    withExtendedLifetime(folderMonitor) {
      // Keep running
      dispatchMain()
    }
  }

  private func runBuild() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run"]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        print(output, terminator: "")
      }

      return process.terminationStatus == 0
    } catch {
      print("Build error: \(error)")
      return false
    }
  }

  private func openBrowser(url: String) {
    #if os(macOS)
      Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [url])
    #elseif os(Linux)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["xdg-open", url]
      try? process.run()
    #endif
  }
}
