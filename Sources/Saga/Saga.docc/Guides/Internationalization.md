# Internationalization (i18n)

Build multilingual sites with automatic translation linking, localized URLs, and per-locale output.

## Overview

Saga supports multilingual sites through a global i18n configuration. You define your locales once, and Saga handles locale detection, translation linking, and per-locale output paths automatically. Your `register` calls stay exactly the same as a single-language site — no duplication needed.

Each locale has its own folder under your content directory (`en/articles/hello.md`, `nl/articles/hello.md`).

## Configuration

Call ``Saga/i18n(locales:defaultLocale:prefixDefaultLocaleOutputFolder:localizedOutputFolders:)`` before your `register` calls:

```swift
try await Saga(input: "content", output: "deploy")
  .i18n(
    locales: ["en", "nl"],
    defaultLocale: "en"
  )
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )
  .run()
```

With this configuration, `.register(folder: "articles")` automatically processes both `en/articles/` and `nl/articles/`. Each item gets a `locale` property, and translations are linked by matching source filenames across locale directories.

## Content organization

Each locale gets its own top-level folder under your content directory:

```
content/
  en/
    articles/
      getting-started.md
      concurrency.md
    index.md
    about.md
  nl/
    articles/
      getting-started.md
      concurrency.md
    index.md
    about.md
  static/
    style.css
```

Files outside locale folders (like `static/`) are locale-independent and handled normally.

## Output paths

By default, the default locale's content is written to the root, and other locales are written to a subfolder:

| Source | Output |
|---|---|
| `en/articles/getting-started.md` | `deploy/articles/getting-started/index.html` |
| `nl/articles/getting-started.md` | `deploy/nl/articles/getting-started/index.html` |
| `en/index.md` | `deploy/index.html` |
| `nl/index.md` | `deploy/nl/index.html` |

Set `prefixDefaultLocaleOutputFolder: true` to prefix all locales, including the default:

```swift
.i18n(
  locales: ["en", "nl"],
  defaultLocale: "en",
  prefixDefaultLocaleOutputFolder: true
)
```

This writes `en/index.md` to `deploy/en/index.html`.

## Localized folder names

By default, the output folder name matches the content folder name. Use `localizedOutputFolders` on the `i18n()` call to give locales different URL segments:

```swift
.i18n(
  locales: ["en", "nl"],
  defaultLocale: "en",
  localizedOutputFolders: ["articles": ["nl": "artikelen"]]
)
```

This produces:

| Source | Output |
|---|---|
| `en/articles/hello.md` | `deploy/articles/hello/index.html` |
| `nl/articles/hello.md` | `deploy/nl/artikelen/hello/index.html` |

Locales not in the map use the original folder name. You only need to specify the ones that differ.

## Translation linking

Saga links translations automatically by matching source filenames. `en/articles/getting-started.md` and `nl/articles/getting-started.md` are translations of each other because they share the path `articles/getting-started.md` relative to their locale folder.

Access translations via the `translations` property on any item:

```swift
// Iterate all translations
for (locale, item) in context.item.translations {
  // locale: "nl", item: the Dutch version
}

// Grab a specific translation
let dutchVersion = context.item.translation(for: "nl")
```

## Localized slugs

Translation matching is based on source filenames, not output paths. This means you can have different URL slugs per locale while keeping translations linked. Use the `slug` frontmatter field to override the output path:

```yaml
---
slug: over-ons
---
# Over ons
```

With this frontmatter, `nl/about.md` is written to `deploy/nl/over-ons/index.html` but still links to `en/about.md` as its English translation.

Combined with `localizedOutputFolders`, you can build fully localized URL structures:

| Source | Output |
|---|---|
| `en/articles/getting-started.md` | `deploy/articles/getting-started/index.html` |
| `nl/articles/getting-started.md` | `deploy/nl/artikelen/aan-de-slag/index.html` |

## Template-driven pages

Use ``StepBuilder/createPage(_:forEachLocale:)`` to create pages that run once per locale, like a homepage:

```swift
.createPage("index.html", forEachLocale: swim(renderHome))
```

This writes `index.html` for the default locale and `nl/index.html` for Dutch (etc.). The renderer receives a `PageRenderingContext` with `locale` set and `allItems` filtered to that locale.

For pages that don't need per-locale variants (sitemaps, 404 pages), use the regular ``StepBuilder/createPage(_:using:)``.

## Rendering context

All rendering contexts include `locale` and `translations` properties. When i18n is configured, `allItems` is automatically filtered to the current locale.

```swift
func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  let locale = context.locale ?? "en"

  html(lang: locale) {
    // context.allItems only contains items for this locale
    // context.translations has URLs for all locales
  }
}
```

## Building a language switcher

All rendering contexts provide a `translations` dictionary mapping locale to URL.

```swift
func languageSwitcher(currentLocale: String, translations: [String: String]) -> Node {
  nav(class: "lang-switcher") {
    translations.sorted(by: { $0.key < $1.key }).map { (locale, url) in
      if locale == currentLocale {
        span(class: "active") { locale.uppercased() }
      } else {
        a(href: url) { locale.uppercased() }
      }
    }
  }
}

// Use it from any rendering context:
languageSwitcher(currentLocale: context.locale ?? "en", translations: context.translations)
```

> Tip: See the [ExampleI18n project](https://github.com/loopwerk/Saga/blob/main/ExampleI18n) for a full working site with templates.


## Complete example

```swift
struct ArticleMetadata: Metadata {
  let tags: [String]
}

try await Saga(input: "content", output: "deploy")
  .i18n(
    locales: ["en", "nl"],
    defaultLocale: "en",
    localizedOutputFolders: ["articles": ["nl": "artikelen"]]
  )
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )
  .createPage("index.html", forEachLocale: swim(renderHome))
  .createPage("sitemap.xml", using: Saga.sitemap(baseURL: URL(string: "https://example.com")!))
  .run()
```

This single pipeline generates a complete bilingual site with articles, pages, per-locale homepages, and a sitemap — all from one set of `register` calls. 

> Tip: See the [ExampleI18n project](https://github.com/loopwerk/Saga/blob/main/ExampleI18n) for a full working site with templates.
