<p align="center">
  <img src="logo.png" width="200" alt="Saga" />
</p>

> [!TIP]
> **Saga 3 is here!** i18n, incremental builds, and more. See the [migration guide](https://getsaga.dev/docs/migrate/) for what's new.

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
```

Typed metadata, pluggable readers, multiple writer types, pagination, tags — all defined in Swift, readable top to bottom, and enforced by the compiler. No hidden defaults. No template logic you can't debug.


## Who this is for

**Saga is for you if:**
- You want your site generation logic in Swift, not YAML/TOML config files
- You want compile-time safety for your HTML templates and content metadata
- You've outgrown convention-based SSGs and want full control

**Saga is not for you if:**
- You need a large ecosystem of themes and templates
- You're not comfortable with Swift


## Feature comparison

| Feature | Saga | Hugo | Eleventy | Jekyll | Pelican | Astro | Publish | Ignite | Toucan |
|---|---|---|---|---|---|---|---|---|---|
| Language | Swift | Go | JS | Ruby | Python | TS | Swift | Swift | Swift |
| In development since | 2021 | 2013 | 2017 | 2008 | 2010 | 2021 | 2019 | 2024 | 2023 |
| CLI (init, dev, build) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| Live reload | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Incremental builds | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Code over configuration | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| Multiple typed content types | ✓ | ✗ | ✗ | ✗ | ✗ | ✓¹ | ✗ | ✗ | ✗ |
| Type-safe HTML templates | ✓ | ✗ | ✗ | ✗ | ✗ | ✓² | ✓ | ✓ | ✗ |
| Pagination | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ |
| Tags / taxonomies | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ |
| i18n | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Sitemap generation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| RSS / Atom feeds | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Syntax highlighting | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| Markdown attributes | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Programmatic content | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✓⁴ | ✗ |
| Asset hashing | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Pre/Post build hooks | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Shortcodes | ✓³ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Image processing | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Asset bundling | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Themes ecosystem | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| Good documentation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |

¹ With Zod  
² With JSX  
³ With item processors  
⁴ Via `prepare()` hook


## Installing the CLI

**Via [Homebrew](https://brew.sh):**
```
$ brew install loopwerk/tap/saga
```

**Via [Mint](https://github.com/yonaskolb/Mint):**
```
$ mint install loopwerk/saga-cli
```

**From source:**

```shell-session
$ git clone https://github.com/loopwerk/saga-cli.git
$ cd saga-cli
$ swift package experimental-install
```

This installs the `saga` binary to `~/.swiftpm/bin`. Make sure that directory is in your `PATH`.


## Getting started

The fastest way to start a new site:

```
$ saga init mysite
$ cd mysite
$ saga dev
```

This scaffolds a complete project with articles, tags, templates, and a stylesheet — ready to build and serve.

For manual setup or more detail, see the [installation guide](https://getsaga.dev/docs/installation/).


## Code over configuration

Saga avoids hidden behavior entirely.

There are no default values to override, no magic conventions you have to learn, and no configuration files that quietly change how your site is built. Everything is strongly typed, from top to bottom, and you describe exactly how your site is generated using Swift code.

If something happens during a build, you can always point to the code that made it happen.


## Growing beyond a simple site

The example above shows a single content type, but Saga scales to handle complex sites with multiple content types.

Saga allows you to:

- Add strongly typed metadata to your content.
- Define multiple content types with different metadata.
- Build archive pages, tag pages, feeds, and indexes.
- Swap in different readers and renderers.
- Load content programmatically and/or from disk.
- Build multilingual sites with automatic translation linking and fully localized URLs.
- Register custom pipeline steps for logic outside the standard pipeline: generate images, build a search index, or run any custom logic as part of your build.
- Process the generated HTML content right before it's written to disk. For example to [minify it](https://github.com/loopwerk/Bonsai).
- Easily created cache-busting hashed filenames for static assets.
- Create a sitemap with one line of code.
- Keep everything enforced by the compiler.

### Typed metadata (when you need it)

Saga's metadata system lets you define multiple content types, each with their own strongly typed metadata.

For example, a single site might include:

- Blog articles with tags and publication dates
- A project portfolio with App Store links and screenshots
- Movie reviews with ratings, actors, genres, and release years

Each content type can be indexed, paginated, or grouped independently.

Few static site generators can model diverse content like this while keeping everything type-safe. Saga can.

See the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a complete site with articles, server-side syntax highlighting of code blocks, tags, pagination, an app portfolio, and RSS feeds.

### Multilingual sites

Saga has built-in i18n support with fully localized URLs, automatic translation linking, and per-locale writers. See the [i18n guide](https://getsaga.dev/docs/guides/internationalization/) and the [ExampleI18n project](https://github.com/loopwerk/Saga/blob/main/ExampleI18n).


## Documentation

Full documentation covering installation, getting started, metadata modeling, and advanced usage is available:

- In Xcode via Product → Build Documentation
- Online at [getsaga.dev/docs/](https://getsaga.dev/docs/)


## Plugins

Saga is modular. You compose it with readers and renderers that fit your needs.

**Markdown readers**

- [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) — uses [Parsley](https://github.com/loopwerk/Parsley)
- [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) — uses [Ink](https://github.com/JohnSundell/Ink) and [Splash](https://github.com/JohnSundell/Splash)
- [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader) — uses [Python-Markdown](https://github.com/Python-Markdown/markdown) and [Pygments](https://pygments.org)

**Renderers**

- [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) — type-safe HTML using [Swim](https://github.com/robb/Swim)
- [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer) — templates using [Stencil](https://github.com/stencilproject/Stencil)

**Utilities**

- [SagaUtils](https://github.com/loopwerk/SagaUtils) — composable HTML transformations (via [SwiftSoup](https://github.com/scinfu/SwiftSoup)) and useful String extensions
- [SagaImageReader](https://github.com/loopwerk/SagaImageReader) — turn image files into items

## Requirements

Saga requires Swift 6.0+ and runs on macOS 14+ and Linux.


## Websites using Saga

- [loopwerk.io](https://loopwerk.io) ([source](https://github.com/loopwerk/loopwerk.io))
- [mhoush.com](https://mhoush.com) ([source](https://github.com/m-housh/mhoush.com))
- [spamusement.cc](https://www.spamusement.cc) ([source](https://github.com/kevinrenskers/spamusement.cc))
- [getsaga.dev](https://getsaga.dev) ([source](https://github.com/loopwerk/getsaga.dev))

Is your website built with Saga? Send a pull request to add it to the list!

## Support

Commercial support is available via [Loopwerk](https://www.loopwerk.io/open-source/support/).
