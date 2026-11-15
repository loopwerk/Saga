# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
# Build the project
just build

# Run tests
just test

# Format the code
just format

# Generate documentation
just docs

# Preview documentation
just docs-preview
```

The example sites (`Example/`, `ExampleI18n/`) have their own `justfile`: `just run` starts `saga dev`, `just build` runs `saga build`.

The `saga` CLI (`init`, `dev`, `build`) lives in a [separate repository](https://github.com/loopwerk/saga-cli). File watching is handled by Saga itself, not the CLI.

## Documentation

Saga's features are documented in DocC, in `Sources/Saga/Saga.docc/`. Start with `Architecture.md` for the pipeline, `AdvancedUsage.md` for hooks, processors and other features, and `Guides/` for specific use cases. The API reference comes from the doc comments in `Sources/Saga/`. Plugins are listed on [getsaga.dev](https://getsaga.dev).

## Internals

- **Processing Pipeline**: `Saga` (a `StepBuilder` subclass) turns each `register`/`createPage` call into a `PipelineStep`, and `build()` runs the read and write phases over all steps
- **I/O Abstraction**: `FileIO` is a struct of closures, so tests swap in `FileIO.mock`, with `Path+Extensions` providing file system utilities
- **Item System**: `Item<M: Metadata>` provides compile-time type safety for content metadata, with `AnyItem` for heterogeneous collections

## Key Directories

- `/Sources/Saga/` - Main library with core architecture
- `/Tests/SagaTests/` - Unit tests with mock implementations
- `/Example/` - Complete working example demonstrating usage patterns
- `/ExampleI18n/` - Multilingual example with localized folder names
- `/Sources/Saga/Saga.docc/` - DocC documentation source

## Design Principles

- **Code over Configuration**: Explicit, no hidden behavior
- **Strong Typing**: Compile-time safety for metadata and content processing
- **Testable Architecture**: Dependency injection with mock file I/O support
- **Extensibility**: Plugin-based readers and renderers
