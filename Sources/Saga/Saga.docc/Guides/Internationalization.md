# Internationalization (i18n)

Build multilingual sites with automatic translation linking, localized URLs, and per-locale output.

## Overview

Saga supports multilingual sites through a global i18n configuration. You define your locales once, and Saga handles locale detection, translation linking, and per-locale output paths automatically. Your `register` calls stay exactly the same as a single-language site — no duplication needed.

Each locale has its own folder under your content directory (`en/articles/hello.md`, `nl/articles/hello.md`).

## Configuration

Call ``Saga/i18n(locales:defaultLocale:defaultLocaleInSubdir:)`` before your `register` calls:

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

Set `defaultLocaleInSubdir: true` to prefix all locales, including the default:

```swift
.i18n(
  locales: ["en", "nl"],
  defaultLocale: "en",
  defaultLocaleInSubdir: true
)
```

This writes `en/index.md` to `deploy/en/index.html`.

## Localized folder names

By default, the output folder name matches the content folder name. Use `localizedOutputFolder` to give locales different URL segments:

```swift
.register(
  folder: "articles",
  localizedOutputFolder: ["nl": "artikelen"],
  metadata: ArticleMetadata.self,
  readers: [.parsleyMarkdownReader],
  writers: [
    .itemWriter(swim(renderArticle)),
    .listWriter(swim(renderArticles)),
  ]
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
// Dictionary of locale → item, excluding the current locale
let dutchVersion = context.item.translation(for: "nl")

// Iterate all translations
for (locale, item) in context.item.translations {
  // locale: "nl", item: the Dutch version
}
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

Combined with `localizedOutputFolder`, you can build fully localized URL structures:

```
/articles/getting-started/         (English)
/nl/artikelen/aan-de-slag/         (Dutch, localized folder + slug)
```

## Writers and i18n

Writers automatically run per-locale when i18n is configured:

- **`itemWriter`** renders each item as usual. Output paths already reflect the locale.
- **`listWriter`** generates a separate list page per locale, containing only that locale's items. For example, `/articles/index.html` lists English articles and `/nl/artikelen/index.html` lists Dutch articles.
- **`tagWriter`** and **`yearWriter`** partition per-locale, so `/articles/tag/swift/` contains only English articles tagged "swift".
- **Atom feeds** are generated per-locale when used as a `listWriter` output.

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
}

try await Saga(input: "content", output: "deploy")
  .i18n(locales: ["en", "nl"], defaultLocale: "en")
  .register(
    folder: "articles",
    localizedOutputFolder: ["nl": "artikelen"],
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
  .createPage("sitemap.xml", using: Saga.sitemap(baseURL: URL(string: "https://example.com")!))
  .run()
```

This single pipeline generates a complete bilingual site with articles, pages, tag archives, and a sitemap — all from one set of `register` calls. See the [ExampleI18n project](https://github.com/loopwerk/Saga/blob/main/ExampleI18n) for a full working site with templates.
