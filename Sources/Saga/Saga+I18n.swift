import SagaPathKit

/// A locale identifier string (e.g. `"en"`, `"nl"`, `"de"`).
public typealias SagaLocale = String

extension Saga {
  /// Link items across locales by matching their source paths (after stripping the locale prefix).
  ///
  /// For example, `en/articles/hello.md` and `nl/articles/hello.md` share the translation key
  /// `articles/hello.md`, so they become translations of each other.
  func linkTranslations() {
    // Group items by their translation key (source path without the locale prefix)
    let groups = allItems
      .filter { $0.locale != nil }
      .reduce(into: [String: [AnyItem]]()) { into, item in
        let key = translationKey(for: item.relativeSource, locale: item.locale!)
        into[key, default: []].append(item)
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
  private func translationKey(for path: Path, locale: SagaLocale) -> String {
    let prefix = locale + "/"
    let str = path.string
    if str.hasPrefix(prefix) {
      return String(str.dropFirst(prefix.count))
    }
    return str
  }

  /// Write redirect pages for the default locale.
  ///
  /// When `prefixDefaultLocaleOutputFolder` is false: the default locale's content lives at the
  /// root, so this generates redirects from `/{locale}/...` → `/...` for each generated page.
  ///
  /// When `prefixDefaultLocaleOutputFolder` is true: all locales are prefixed, so this generates
  /// redirects from `/...` → `/{locale}/...` for each generated page.
  func writeDefaultLocaleRedirects() throws {
    guard let config = i18nConfig else { return }

    let locale = config.defaultLocale
    let nonDefaultPrefixes = config.locales.filter { $0 != locale }.map { $0 + "/" }

    for page in generatedPages {
      // Only process pages that belong to the default locale
      let isNonDefault = nonDefaultPrefixes.contains { page.string.hasPrefix($0) }
      if isNonDefault { continue }

      if config.prefixDefaultLocaleOutputFolder {
        // Content is at /{locale}/..., redirect from /... → /{locale}/...
        // The page path already includes the locale prefix
        let unprefixed = Path(String(page.string.dropFirst(locale.count + 1)))
        let destination = outputPath + unprefixed
        try fileIO.mkpath(destination.parent())
        try fileIO.write(destination, Saga.redirectHTML(to: page.url))
      } else {
        // Content is at /..., redirect from /{locale}/... → /...
        let prefixed = Path(locale) + page
        let destination = outputPath + prefixed
        try fileIO.mkpath(destination.parent())
        try fileIO.write(destination, Saga.redirectHTML(to: page.url))
      }
    }
  }

  /// Apply `localizedOutputFolders` mappings to an output path for a given locale.
  func applyLocalizedOutputFolders(to path: Path, locale: SagaLocale) -> Path {
    guard let config = i18nConfig else { return path }
    var str = path.string
    for (contentFolder, localeMap) in config.localizedOutputFolders {
      if let outputFolder = localeMap[locale] {
        if str.hasPrefix(contentFolder + "/") {
          str = outputFolder + "/" + String(str.dropFirst(contentFolder.count + 1))
          break
        } else if str == contentFolder {
          str = outputFolder
          break
        }
      }
    }
    return Path(str)
  }

  /// Rewrite a content-relative path for i18n output.
  ///
  /// Strips the locale prefix, applies `localizedOutputFolders` mappings, and re-prefixes
  /// for non-default locales. For example, `nl/articles/image.png` → `nl/artikelen/image.png`.
  /// Files outside locale folders are copied as-is.
  func i18nOutputPath(for relativePath: Path) -> Path {
    guard let config = i18nConfig else { return relativePath }
    let str = relativePath.string
    for locale in config.locales {
      let prefix = locale + "/"
      if str.hasPrefix(prefix) {
        let stripped = String(str.dropFirst(prefix.count))
        let mapped = applyLocalizedOutputFolders(to: Path(stripped), locale: locale)

        if config.shouldPrefix(locale: locale) {
          return Path(locale) + mapped
        } else {
          return mapped
        }
      }
    }

    return relativePath
  }
}
