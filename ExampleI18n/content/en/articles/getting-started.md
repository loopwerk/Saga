---
tags: tutorial
date: 2024-07-01
---
# Getting Started with Saga
To create a multilingual site with Saga, start by organizing your content into locale folders. Then configure i18n before your register calls:

```swift
try await Saga(input: "content", output: "deploy")
  .i18n(locales: ["en", "nl"], defaultLocale: "en")
  .register(...)
  .run()
```

Your writers automatically run per-locale, so list pages, tag pages, and feeds are all generated separately for each language.
