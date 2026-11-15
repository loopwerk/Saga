# Migrating to Saga 4

Saga 4 adds item resources, and removes the APIs that were deprecated in Saga 3.

## What's new

* Item resources. Files next to an item, such as images, are available as ``Item/resources``. See <doc:AdvancedUsage#Item-resources>.


## Breaking changes

> Important: These changes will require updates to your code.

* `metadata:` is required. Saga's default for this parameter relies on behavior that a future Swift language mode will turn into an error, so every `register` call now needs an explicit `metadata:` argument. Pass `EmptyMetadata.self` where you relied on the default.
* `ItemRenderingContext.resources` is removed. Use `context.item.resources` instead. Each resource is a ``Resource`` rather than a path, so link to it with its ``Resource/url``.
* With i18n, ``Saga/hashed(_:)`` now takes the file's path in the output folder rather than the input folder. For example `/articles/chart.png` rather than `/en/articles/chart.png`, or `/nl/artikelen/chart.png` rather than `/nl/articles/chart.png`. Files outside locale folders, like `/static/style.css`, are unaffected.
* Deprecated APIs are removed:
  * `ignore(_:)`: use ``Saga/ignoreChanges(_:)``.
  * `register(write:)`: use ``Saga/afterRead(_:)`` or ``Saga/afterWrite(_:)``.
  * `sitemap(baseURL:filter:)` with a `(Path) -> Bool` filter: use ``Saga/sitemap(baseURL:filter:)``, whose filter also receives the item, `(Path, AnyItem?) -> Bool`.
  * `atomFeed(…, dateKeyPath:)`: use ``Saga/atomFeed(title:author:baseURL:limit:itemTitle:summary:image:date:)``, which takes a closure or a key path like `\.date`.


## Update your dependencies

In your `Package.swift`, bump the Saga dependency:

```swift
// Before
.package(url: "https://github.com/loopwerk/Saga", from: "3.0.0"),

// After
.package(url: "https://github.com/loopwerk/Saga", from: "4.0.0"),
```
