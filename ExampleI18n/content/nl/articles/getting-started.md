---
tags: handleiding
date: 2024-07-01
---
# Aan de slag met Saga
Om een meertalige site te maken met Saga, begin je met het organiseren van je content in taalmappen. Configureer daarna i18n voor je register-aanroepen:

```swift
try await Saga(input: "content", output: "deploy")
  .i18n(locales: ["en", "nl"], defaultLocale: "en")
  .register(
    folder: "articles",
    localizedOutputFolder: ["nl": "artikelen"],
    ...
  )
  .run()
```

Je writers draaien automatisch per taal, dus lijstpagina's, tagpagina's en feeds worden allemaal apart gegenereerd voor elke taal.
