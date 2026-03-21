# Migrating to Saga 3

How to update your project from Saga 2 to Saga 3.


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

saga-cli 2.x unlocks incremental rebuilds and faster dev cycles. Update via Homebrew:

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

The `--watch`, `--output`, and `--ignore` flags have been removed from `saga dev`. Saga now handles file watching and detects the folders from your Swift code. The only remaining option is `--port`.

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


## New: build hooks

Saga 3 adds ``Saga/beforeRead(_:)`` and ``Saga/afterWrite(_:)`` hooks that run before and after each build cycle, including incremental builds during `saga dev`.

These are useful for pre-build steps like CSS compilation and post-build steps like search indexing:

```swift
try await Saga(input: "content", output: "deploy")
  .beforeRead { _ in
    // e.g. compile Tailwind CSS
  }
  .register(/* ... */)
  .afterWrite { _ in
    // e.g. run Pagefind
  }
  .run()
```

See <doc:TailwindCSS> and <doc:AddingSearch> for examples.


## New: incremental dev rebuilds

When running under `saga dev`, Saga 3 stays alive between rebuilds and caches the read phase. Unchanged files are not re-parsed, making content rebuilds significantly faster. This happens automatically; no code changes needed.
