import Foundation
import SagaPathKit

extension Saga {
  /// Run the build pipeline once.
  func build() async throws {
    let totalStart = DispatchTime.now()
    fileIO.log("Starting run")

    if !beforeReadHooks.isEmpty {
      let start = DispatchTime.now()
      for hook in beforeReadHooks {
        try await hook(self)
      }

      fileIO.log("Finished beforeRead hooks in \(elapsed(from: start))")
    }

    // Run all the readers for all the steps sequentially to ensure proper order,
    // which turns raw content into Items, and stores them within the step.
    let readStart = DispatchTime.now()
    for step in steps {
      let items = try await step.read(self)
      allItems.append(contentsOf: items)
    }

    fileIO.log("Finished read phase in \(elapsed(from: readStart))")

    // Link translations across locales
    if i18nConfig != nil {
      linkTranslations()
    }

    // Sort all items by date descending
    allItems.sort { $0.date > $1.date }

    // Clean the output folder
    try fileIO.deletePath(outputPath)

    // Copy all unhandled files as-is to the output folder first,
    // so that the directory structure exists for the write phase.
    let copyStart = DispatchTime.now()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for file in unhandledFiles {
        group.addTask {
          let output = self.outputPath + self.i18nOutputPath(for: file.relativePath)
          try self.fileIO.mkpath(output.parent())
          try self.fileIO.copy(file.path, output)
        }
      }
      try await group.waitForAll()
    }

    fileIO.log("Finished copying static files in \(elapsed(from: copyStart))")

    // Make Saga.hashed() work
    setupHashFunction()

    // Run all writers sequentially
    // processedWrite tracks generated paths automatically.
    let writeStart = DispatchTime.now()
    for step in steps {
      try await step.write(self)
    }

    fileIO.log("Finished write phase in \(elapsed(from: writeStart))")

    // Copy hashed versions of files that were referenced via Saga.hashed()
    try copyHashedFiles()

    // Generate redirect pages for the default locale
    try writeDefaultLocaleRedirects()

    if !afterWriteHooks.isEmpty {
      let start = DispatchTime.now()
      for hook in afterWriteHooks {
        try await hook(self)
      }

      fileIO.log("Finished afterWrite hooks in \(elapsed(from: start))")
    }

    fileIO.log("All done in \(elapsed(from: totalStart))")
  }
  
  var recompileReasonPath: Path {
    rootPath + ".build/saga-recompile-reason"
  }

  /// Read `.build/saga-recompile-reason` to determine if this launch was triggered by a Swift file change.
  /// If the file exists, sets ``buildReason`` to `.recompile` and deletes it.
  func readRecompileReason() {
    let path = recompileReasonPath
    guard path.exists, let contents: String = try? path.read(), !contents.isEmpty else { return }
    buildReason = .recompile(Path(contents))
    try? path.delete()
  }

  /// Write `.build/saga-recompile-reason` so the next launch knows which Swift file triggered it.
  func writeRecompileReason(_ changedPath: String) {
    try? recompileReasonPath.write(changedPath)
  }

  /// Watch for file changes and rebuild when content changes.
  /// Signals saga-cli via SIGUSR1 if Swift source files change (so it can recompile and relaunch).
  func watchAndRebuild() async throws {
    let watchPaths = [inputPath.string, (rootPath + "Sources").string]
    let monitor = FolderMonitor(paths: watchPaths, ignoredPatterns: ignoredPatterns) { [weak self] changedPaths in
      guard let self else { return }

      if let swiftFile = changedPaths.first(where: { $0.hasSuffix(".swift") }) {
        // Swift source changed — write the reason file and signal saga-cli to recompile and relaunch
        self.writeRecompileReason(swiftFile)
        self.signalParent(SIGUSR1)
        return
      }

      Task {
        do {
          try self.reset()
          if let changedPath = changedPaths.first {
            self.buildReason = .fileChange(Path(changedPath))
          }
          try await self.build()
          self.signalParent(SIGUSR2)
        } catch {
          self.fileIO.log("💥 Rebuild failed: \(error)")
        }
      }
    }

    // Keep the monitor alive and block forever (dev mode runs until killed)
    withExtendedLifetime(monitor) {
      while true {
        Thread.sleep(forTimeInterval: .greatestFiniteMagnitude)
      }
    }
  }
}
