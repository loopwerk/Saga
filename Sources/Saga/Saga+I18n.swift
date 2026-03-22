import SagaPathKit

extension Saga {
  /// Link items across locales by matching their source paths (after stripping the locale prefix).
  ///
  /// For example, `en/articles/hello.md` and `nl/articles/hello.md` share the translation key
  /// `articles/hello.md`, so they become translations of each other.
  func linkTranslations() {
    // Group items by their translation key (source path without the locale prefix)
    var groups: [String: [AnyItem]] = [:]
    for item in allItems {
      guard let locale = item.locale else { continue }
      let key = translationKey(for: item.relativeSource, locale: locale)
      groups[key, default: []].append(item)
    }

    // Wire up translations
    for (_, items) in groups where items.count > 1 {
      for item in items {
        for other in items where other !== item {
          if let otherLocale = other.locale {
            item.translations[otherLocale] = other
          }
        }
      }
    }
  }

  /// Strip the locale prefix from a source path to get the translation key.
  private func translationKey(for path: Path, locale: String) -> String {
    let prefix = locale + "/"
    let str = path.string
    if str.hasPrefix(prefix) {
      return String(str.dropFirst(prefix.count))
    }
    return str
  }

  /// Rewrite a relative path for i18n output.
  ///
  /// Files inside a locale folder (e.g. `en/static/style.css`) have the locale prefix
  /// stripped, folder mappings applied (e.g. `articles` → `artikelen`), and optionally
  /// re-prefixed based on whether the locale should be in a subdirectory.
  /// Files outside locale folders are copied as-is.
  func i18nOutputPath(for relativePath: Path) -> Path {
    guard let config = i18nConfig else { return relativePath }
    let str = relativePath.string
    for locale in config.locales {
      let prefix = locale + "/"
      if str.hasPrefix(prefix) {
        var stripped = String(str.dropFirst(prefix.count))

        // Apply folder mappings (e.g. articles/logo.png → artikelen/logo.png)
        if let mappings = folderMappings[locale] {
          for (contentFolder, outputFolder) in mappings {
            let contentPrefix = contentFolder + "/"
            if stripped.hasPrefix(contentPrefix) {
              stripped = outputFolder + "/" + String(stripped.dropFirst(contentPrefix.count))
              break
            }
          }
        }

        if config.shouldPrefix(locale: locale) {
          return Path(locale) + Path(stripped)
        } else {
          return Path(stripped)
        }
      }
    }

    return relativePath
  }
}
