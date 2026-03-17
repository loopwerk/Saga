# Internationalization (i18n)

Build multilingual sites with automatic translation linking and per-locale output.

## Overview

Saga supports multilingual sites through a global i18n configuration. You define your locales once, and Saga handles locale detection, translation linking, and per-locale output paths automatically. Your `register` calls stay exactly the same as a single-language site — no duplication needed.

Two content organization styles are supported:

- **Directory-based:** each locale has its own folder (`en/articles/hello.md`, `nl/articles/hello.md`)
- **Filename-based:** locale is encoded in the filename (`articles/hello.en.md`, `articles/hello.nl.md`)

## Configuration

Call ``Saga/i18n(locales:defaultLocale:style:defaultLocaleInSubdir:)`` before your `register` calls:

```swift
try await Saga(input: "content", output: "deploy")
  .i18n(
    locales: ["en", "nl"],
    defaultLocale: "en",
    style: .directory
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

### Directory-based (`.directory`)

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

### Filename-based (`.filename`)

All content lives in a single folder structure, with locale suffixes on filenames:

```
content/
  articles/
    getting-started.en.md
    getting-started.nl.md
    concurrency.en.md
    concurrency.nl.md
  index.en.md
  index.nl.md
  about.en.md
  about.nl.md
  static/
    style.css
```

Files without a locale suffix (like `style.css`) are locale-independent.

## Output paths

By default, the default locale's content is written to the root, and other locales are written to a subfolder:

| Source | Output |
|---|---|
| `en/articles/getting-started.md` | `deploy/articles/getting-started/index.html` |
| `nl/articles/getting-started.md` | `deploy/nl/articles/getting-started/index.html` |
| `en/index.md` | `deploy/index.html` |
| `nl/index.md` | `deploy/nl/index.html` |

Saga generates an HTML redirect from `/en/` to `/` so that locale-prefixed URLs still work.

Set `defaultLocaleInSubdir: true` to prefix all locales, including the default:

```swift
.i18n(
  locales: ["en", "nl"],
  defaultLocale: "en",
  style: .directory,
  defaultLocaleInSubdir: true
)
```

This writes `en/index.md` to `deploy/en/index.html` and generates a redirect from `/` to `/en/`.

## Translation linking

Saga links translations automatically by matching source filenames. In directory mode, `en/articles/getting-started.md` and `nl/articles/getting-started.md` are translations of each other because they share the path `articles/getting-started.md` relative to their locale folder. In filename mode, `articles/getting-started.en.md` and `articles/getting-started.nl.md` are translations because they share the base name `getting-started`.

Access translations via the `translations` property on any item:

```swift
// Dictionary of locale → item, excluding the current locale
let dutchVersion = context.item.translation(for: "nl")

// Iterate all translations
for (locale, item) in context.item.translations {
  // locale: "nl", item: the Dutch version
}
```

## Localized URLs

Translation matching is based on source filenames, not output paths. This means you can have different URL slugs per locale while keeping translations linked. Use the `slug` frontmatter field to override the output path:

```yaml
---
slug: over-ons
---
# Over ons
```

With this frontmatter, `nl/about.md` is written to `deploy/nl/over-ons/index.html` but still links to `en/about.md` as its English translation.

## Writers and i18n

Writers automatically run per-locale when i18n is configured:

- **`itemWriter`** renders each item as usual. Output paths already reflect the locale.
- **`listWriter`** generates a separate list page per locale, containing only that locale's items. For example, `/articles/index.html` lists English articles and `/nl/articles/index.html` lists Dutch articles.
- **`tagWriter`** and **`yearWriter`** partition per-locale, so `/articles/tag/swift/` contains only English articles tagged "swift".
- **Atom feeds** are generated per-locale.

## Rendering context

All rendering contexts include a `locale` property:

```swift
func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  let locale = context.locale ?? "en"

  html(lang: locale) {
    // ...
  }
}
```

## Building a language switcher

Use `context.item.translations` to build a language switcher that links to the same content in other locales:

```swift
func languageSwitcher(currentLocale: String, item: AnyItem) -> Node {
  nav(class: "lang-switcher") {
    // Current locale (not a link)
    span(class: "active") { currentLocale.uppercased() }

    // Other locales
    item.translations.sorted(by: { $0.key < $1.key }).map { (locale, translated) in
      a(href: translated.url) { locale.uppercased() }
    }
  }
}
```

For list pages (which aren't tied to a single item), swap the locale prefix manually:

```swift
func listLanguageSwitcher(currentLocale: String, locales: [String]) -> Node {
  nav(class: "lang-switcher") {
    locales.map { locale in
      if locale == currentLocale {
        span(class: "active") { locale.uppercased() }
      } else {
        a(href: "/\(locale)/articles/") { locale.uppercased() }
      }
    }
  }
}
```

## String translation

Saga does not provide a built-in UI string translation system. For localized labels ("Articles", "Read more", etc.), define your own lookup:

```swift
func t(_ key: String, locale: String) -> String {
  let strings: [String: [String: String]] = [
    "en": ["articles": "Articles", "about": "About", "read_more": "Read more"],
    "nl": ["articles": "Artikelen", "about": "Over ons", "read_more": "Lees meer"],
  ]
  return strings[locale]?[key] ?? key
}
```

## Complete example

```swift
struct ArticleMetadata: Metadata {
  let tags: [String]
  var summary: String?
}

try await Saga(input: "content", output: "deploy")
  .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
      .listWriter(
        atomFeed(
          title: "My Site",
          author: "Author",
          baseURL: URL(string: "https://example.com")!,
          summary: \.metadata.summary
        ),
        output: "feed.xml"
      ),
    ]
  )
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )
  .createPage("sitemap.xml", using: sitemap(baseURL: URL(string: "https://example.com")!))
  .run()
```

This single pipeline generates a complete bilingual site with articles, pages, tag archives, feeds, and a sitemap — all from one set of `register` calls.
