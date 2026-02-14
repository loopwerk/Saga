import ArgumentParser
import PathKit

struct Init: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a new Saga project."
  )

  @Argument(help: "The name of the project to create.")
  var name: String

  func run() throws {
    let projectPath = Path.current + name

    guard !projectPath.exists else {
      throw ValidationError("Directory '\(name)' already exists.")
    }

    let capitalizedName = name.prefix(1).uppercased() + name.dropFirst()

    // Create directory structure
    try (projectPath + "Sources" + capitalizedName).mkpath()
    try (projectPath + "content" + "articles").mkpath()
    try (projectPath + "content" + "static").mkpath()

    // Write files
    let files: [(Path, String)] = [
      (projectPath + "Package.swift", ProjectTemplate.packageSwift(name: capitalizedName)),
      (projectPath + "Sources" + capitalizedName + "run.swift", ProjectTemplate.runSwift(name: capitalizedName)),
      (projectPath + "Sources" + capitalizedName + "templates.swift", ProjectTemplate.templatesSwift()),
      (projectPath + "content" + "index.md", ProjectTemplate.indexMarkdown()),
      (projectPath + "content" + "articles" + "hello-world.md", ProjectTemplate.helloWorldMarkdown()),
      (projectPath + "content" + "static" + "style.css", ProjectTemplate.styleCss()),
    ]

    for (path, content) in files {
      try path.write(content)
    }

    print("Created new Saga project in '\(name)/'")
    print("")
    print("Next steps:")
    print("  cd \(name)")
    print("  saga dev")
  }
}
