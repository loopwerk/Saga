# Migrating to Saga 3

Saga 3 brings faster builds, a smarter dev server, and first-class internationalization support.

## What's new

* **Dramatically faster rebuilds**. Saga caches the read phase between builds, so only changed files are re-parsed.
* **Build hooks**. Run code before or after each build with `beforeRead` and `afterWrite`.
* **Dev server configuration**. Configure the dev server directly from your pipeline.
* **Internationalization**. Fully localized URLs, automatic translation linking, and locale-aware sitemaps. See the [internationalization guide](doc:Internationalization).


## Breaking changes

> Important: These changes will require updates to your code.

* **CLI flags removed**. The `--watch`, `--output`, and `--ignore` flags are gone from `saga dev`. Use ``Saga/ignore(_:)`` in code instead.
* **Pre/post pipeline code must move to hooks**. Code that ran before or after your pipeline must be wrapped in ``Saga/beforeRead(_:)`` and ``Saga/afterWrite(_:)``, since the pipeline now runs multiple times during `saga dev`.


## Update your dependencies

In your `Package.swift`, bump the Saga dependency:

```swift
// Before
.package(url: "https://github.com/loopwerk/Saga", from: "2.0.0"),

// After
.package(url: "https://github.com/loopwerk/Saga", from: "3.0.0"),
```

Saga 3 requires Swift 6.0 and macOS 14 or Linux.


## Update saga-cli

saga-cli 2 unlocks incremental rebuilds and faster dev cycles, and requires Saga 3 to work. Update via Homebrew:

```shell-session
$ brew upgrade loopwerk/tap/saga
```

Or via Mint:

```shell-session
$ mint install loopwerk/saga-cli
```

If you installed from source, pull the latest and reinstall:

```shell-session
$ cd path/to/saga-cli
$ git pull
$ swift package experimental-install
```

### Removed CLI flags

The `--watch`, `--output`, and `--ignore` flags have been removed from `saga dev`. Saga itself now handles file watching and uses the input and output folders automatically.

If you were using `--ignore`, use ``Saga/ignore(_:)`` in your Swift code instead:

```swift
// Before (saga-cli 1.x)
// $ saga dev --ignore output.css

// After (Saga 3)
try await Saga(input: "content", output: "deploy")
  .ignore("output.css")
  .register(/* ... */)
  .run()
```


## Migrate to use build hooks

Since the pipeline now runs multiple times during `saga dev`, the old way of running code before and after your pipeline no longer works, and has to be migrated to Saga 3's new ``Saga/beforeRead(_:)`` and ``Saga/afterWrite(_:)`` hooks.

Before:

```swift
// Run Tailwind CSS
let tailwind = SwiftTailwind(version: "4.2.1")
try await tailwind.run(
  input: "content/static/input.css",
  output: "content/static/output.css",
  options: .minify
)

try await Saga(input: "content", output: "deploy")
  .register(/* ... */)
  .run()

// Index the site
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["pnpm", "pagefind", "--site", "deploy"]
try process.run()
process.waitUntilExit()
```

After:

```swift
let tailwind = SwiftTailwind(version: "4.2.1")

try await Saga(input: "content", output: "deploy")
  .beforeRead { _ in
    // Run Tailwind CSS
    try await tailwind.run(
      input: "content/static/input.css",
      output: "content/static/output.css",
      options: .minify
    )
  }
  .ignore("output.css") // no more `$ saga dev --ignore output.css`
  .register(/* ... */)
  .afterWrite { _ in
    // Index the site
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pnpm", "pagefind", "--site", "deploy"]
    try process.run()
    process.waitUntilExit()
  }
  .run()
```
