import ArgumentParser
import Foundation

struct Build: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Build the site."
  )

  func run() throws {
    print("Building site...")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
      print(output)
    }

    if process.terminationStatus == 0 {
      print("Build complete.")
    } else {
      throw ExitCode(process.terminationStatus)
    }
  }
}
