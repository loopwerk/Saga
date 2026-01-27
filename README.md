<p align="center">
  <img src="logo.png" width="200" alt="Saga" />
</p>

A static site generator written in Swift.

Build websites using plain Swift code — no configuration files, no implicit behavior, no magic conventions. Start with a minimal setup that turns Markdown into HTML, then grow it into a structured site as your needs evolve.


## Quick start

Create a new Swift package:

```bash
$ mkdir MySite && cd MySite
$ swift package init --type executable
```

Saga is modular: you pick a **reader** to parse your content and a **renderer** to generate HTML. For this guide, we'll use the recommended defaults: [Parsley](https://github.com/loopwerk/Parsley) for Markdown and [Swim](https://github.com/robb/Swim) for type-safe HTML. 

Add them as dependencies in `Package.swift`:

```swift
// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "MySite",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/Saga.git", from: "2.0.0"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader.git", from: "1.0.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer.git", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "MySite",
      dependencies: [
        "Saga",
        "SagaParsleyMarkdownReader",
        "SagaSwimRenderer",
      ]
    ),
  ]
)
```

Create a `content/` folder with a Markdown file:

```bash
$ mkdir content
$ echo "# Hello world" > content/index.md
```

Replace the contents of `Sources/MySite/MySite.swift` with:

```swift
import Saga
import SagaParsleyMarkdownReader
import SagaSwimRenderer
import HTML

func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  html(lang: "en-US") {
    body {
      h1 { context.item.title }
      Node.raw(context.item.body)
    }
  }
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      .register(
        readers: [.parsleyMarkdownReader()],
        writers: [.itemWriter(swim(renderPage))]
      )
      .run()
      .staticFiles()
  }
}
```

Build your site:

```bash
$ swift run
```

Your site is now in `deploy/`. Open `deploy/index.html` in a browser to see it.

### Development server

For a better workflow, use the built-in dev server with live reload. First install [browser-sync](https://github.com/BrowserSync/browser-sync):

```bash
$ pnpm install -g browser-sync
```

Then start the development server:

```bash
$ swift run watch --watch content --watch Sources --output deploy
```

This rebuilds your site whenever you change content or code, and automatically refreshes your browser.


## Code over configuration

Saga avoids hidden behavior entirely.

There are no default values to override, no magic conventions you have to learn, and no configuration files that quietly change how your site is built. Everything is strongly typed, from top to bottom, and you describe exactly how your site is generated using Swift code.

If something happens during a build, you can always point to the code that made it happen.


## Growing beyond a simple site

The quick start shows the simplest case: one type of content, one template. But Saga scales to handle complex sites with multiple content types.

Saga allows you to:

- Add strongly typed metadata to your content
- Define multiple content types with different metadata
- Build archive pages, tag pages, feeds, and indexes
- Swap in different readers and renderers
- Keep everything enforced by the compiler

### Typed metadata (when you need it)

Saga's metadata system lets you define multiple content types, each with their own strongly typed metadata.

For example, a single site might include:

- Blog articles with tags and publication dates
- A project portfolio with App Store links and screenshots
- Movie reviews with ratings, actors, genres, and release years

Each content type can be indexed, paginated, or grouped independently.

Few static site generators can model diverse content like this while keeping everything type-safe. Saga can.

See the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a complete site with articles, tags, pagination, an app portfolio, and RSS feeds.


## Documentation

Full documentation covering installation, getting started, metadata modeling, and advanced usage is available:

- In Xcode via Product → Build Documentation
- Online at [loopwerk.github.io/Saga/documentation/saga/](https://loopwerk.github.io/Saga/documentation/saga/)


## Plugins

Saga is modular. You compose it with readers and renderers that fit your needs.

**Markdown readers**

- [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) — uses [Parsley](https://github.com/loopwerk/Parsley)
- [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) — uses [Ink](https://github.com/JohnSundell/Ink) and [Splash](https://github.com/JohnSundell/Splash)
- [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader) — uses [Python-Markdown](https://github.com/Python-Markdown/markdown) and [Pygments](https://pygments.org)

**Renderers**

- [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) — type-safe HTML using [Swim](https://github.com/robb/Swim)
- [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer) — templates using [Stencil](https://github.com/stencilproject/Stencil)


## Requirements

Saga requires Swift 5.5+ and runs on macOS 12+ and Linux. The development server requires [browser-sync](https://github.com/BrowserSync/browser-sync) and only works on macOS.


## Websites using Saga

- [loopwerk.io](https://loopwerk.io) ([source](https://github.com/loopwerk/loopwerk.io))
- [mhoush.com](https://mhoush.com) ([source](https://github.com/m-housh/mhoush.com))
- [spamusement.cc](https://www.spamusement.cc) ([source](https://github.com/kevinrenskers/spamusement.cc))

Is your website built with Saga? Send a pull request to add it to the list!