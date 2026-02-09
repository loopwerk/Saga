<p align="center">
  <img src="logo.png" width="200" alt="Saga" />
</p>

A code-first static site generator in Swift. No config files, no implicit behavior, no magic conventions.

Your entire site pipeline is plain Swift code:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles), paginate: 20),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )
  .run()
  .staticFiles()
```

Typed metadata, pluggable readers, multiple writer types, pagination, tags — all defined in Swift, readable top to bottom, and enforced by the compiler. No hidden defaults. No template logic you can't debug.


## Who this is for

**Saga is for you if:**
- You want your site generation logic in Swift, not YAML/TOML config files
- You want compile-time safety for your content metadata
- You've outgrown convention-based SSGs and want full control

**Saga is not for you if:**
- You want a CLI that scaffolds everything with zero code
- You need a large ecosystem of themes and templates
- You're not comfortable with Swift


## Getting started

Getting started takes a few minutes if you're comfortable with Swift and SwiftPM. Follow the [installation guide](https://loopwerk.github.io/Saga/documentation/saga/installation) to set up your first site.


## Code over configuration

Saga avoids hidden behavior entirely.

There are no default values to override, no magic conventions you have to learn, and no configuration files that quietly change how your site is built. Everything is strongly typed, from top to bottom, and you describe exactly how your site is generated using Swift code.

If something happens during a build, you can always point to the code that made it happen.


## Growing beyond a simple site

The example above shows a single content type, but Saga scales to handle complex sites with multiple content types.

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

See the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a complete site with articles, server-side syntax highlighting of code blocks, tags, pagination, an app portfolio, and RSS feeds.


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