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

# Start development server with file watching
swift run watch [input-folders] [output-folder]

# Generate documentation
./generate_docs.sh
```

## Architecture Overview

Saga is a static site generator written in Swift that follows a **Reader → Processor → Writer** pipeline pattern:

1. **Readers** parse content files (Markdown, etc.) into strongly typed `Item<M: Metadata>` objects
2. **Processors** transform items with custom logic and filtering
3. **Writers** generate output files using various rendering contexts

### Core Components

- **Item System**: `Item<M: Metadata>` provides compile-time type safety for content metadata, with `AnyItem` for heterogeneous collections
- **Processing Pipeline**: `Saga` class orchestrates the pipeline with `ProcessingStep` stages and `FileContainer` tracking
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

## Key Directories

- `/Sources/Saga/` - Main library with core architecture
- `/Sources/SagaCLI/` - Command line interface with development server
- `/Tests/SagaTests/` - Unit tests with mock implementations
- `/Example/` - Complete working example demonstrating usage patterns
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
  .staticFiles()
```