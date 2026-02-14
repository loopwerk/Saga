import ArgumentParser

@main
struct SagaCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "saga",
    abstract: "A code-first static site generator written in Swift.",
    subcommands: [Init.self, Dev.self, Build.self]
  )
}
