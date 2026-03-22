# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Run the example project
swift run

# Generate documentation
./generate_docs.sh
```

## CLI Commands (`saga`)

```bash
# Create a new Saga project
saga init mysite

# Build a site (runs `swift run` in current directory)
saga build

# Start dev server with file watching and auto-reload
saga dev

# Dev server with custom port
saga dev --port 8080
```

The `saga` CLI lives in a [separate repository](https://github.com/loopwerk/saga-cli). Install via Homebrew (`brew install loopwerk/tap/saga`) or Mint (`mint install loopwerk/saga-cli`).

File watching and ignore patterns are handled by Saga itself (not the CLI). Use `.ignore()` in your Swift code to exclude files from triggering rebuilds.

## Architecture Overview

Saga is a static site generator written in Swift that follows a **beforeRead → Reader → Processor → Writer → afterWrite** pipeline pattern:

1. **beforeRead hooks** run pre-build steps (e.g. CSS compilation)
2. **Readers** parse content files (Markdown, etc.) into strongly typed `Item<M: Metadata>` objects
3. **Processors** transform items with custom logic and filtering
4. **Writers** generate output files using various rendering contexts
5. **afterWrite hooks** run post-build steps (e.g. search indexing)

### Core Components

- **Item System**: `Item<M: Metadata>` provides compile-time type safety for content metadata, with `AnyItem` for heterogeneous collections
- **Processing Pipeline**: `Saga` class orchestrates the read → write pipeline with `processSteps` stages
- **I/O Abstraction**: `FileIO` protocol enables mocking for tests, with `Path+Extensions` providing file system utilities
- **Rendering Contexts**: Different contexts for single items, paginated lists, partitioned content (tags/years), and Atom feeds

### Plugin Architecture

Saga is designed for extensibility via external packages:
- **Readers**: SagaParsleyMarkdownReader, SagaInkMarkdownReader, SagaPythonMarkdownReader
- **Renderers**: SagaSwimRenderer (type-safe HTML), SagaStencilRenderer (templates)

### Writer Types

- `itemWriter`: Single item → single file
- `listWriter`: Multiple items → paginated files
- `tagWriter`: Items grouped by tags
- `yearWriter`: Items grouped by publication year

### Build Helpers

- `beforeRead(_:)`: Hook that runs before the read phase of each build cycle (e.g. CSS compilation). Runs on every rebuild under `saga dev`.
- `afterWrite(_:)`: Hook that runs after the write phase of each build cycle (e.g. search indexing). Runs on every rebuild under `saga dev`.
- `Saga.hashed(_:)`: Static method for cache-busting asset URLs (e.g. `Saga.hashed("/static/style.css")` → `/static/style-a1b2c3d4.css`). Skipped in dev mode.
- `postProcess(_:)`: Apply transforms (e.g. HTML minification) to every written file.
- `Saga.sitemap(baseURL:filter:)`: Built-in renderer that generates an XML sitemap from `generatedPages`. Use with `createPage`.
- `Saga.atomFeed(title:author:baseURL:...)`: Built-in renderer that generates an Atom feed from items.
- `Saga.isDev`: `true` when the `SAGA_DEV` environment variable is set. Use to skip expensive work during development.
- `Saga.isCLI`: `true` when launched by saga-cli (checks `SAGA_CLI` env var). Used internally to activate file watching and rebuild loop.
- `ignore(_:)`: Add glob patterns for files that should not trigger a dev rebuild (e.g. generated CSS).
- `i18n(locales:defaultLocale:prefixDefaultLocaleOutputFolder:localizedOutputFolders:)`: Enable multilingual support. Content is organized in locale-prefixed folders (`en/articles/`, `nl/articles/`). Each `register()` call auto-fans into per-locale steps. Use `localizedOutputFolders` to map content folders to different output folder names per locale (e.g. `["articles": ["nl": "artikelen"]]`).
- `Item.locale`: The locale of an item (`nil` without i18n).
- `Item.translations`: Dictionary of locale → `AnyItem` linking translations by matching filenames across locale folders.
- `Item.translation(for:)`: Typed accessor for a specific locale's translation.

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

## Example Usage Pattern

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: customProcessor,
    filter: \.public,
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles), paginate: 20),
      .tagWriter(swim(renderTag), tags: \.metadata.tags)
    ]
  )
  .run()
```