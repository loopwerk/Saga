/// The content organization style for multilingual sites.
public enum I18NStyle: Sendable {
  /// Each locale has its own folder: `en/articles/hello.md`, `nl/articles/hello.md`
  case directory

  /// Locale is encoded in the filename: `articles/hello.en.md`, `articles/hello.nl.md`
  case filename
}

/// Configuration for internationalization (i18n).
///
/// Pass this to ``Saga/i18n(locales:defaultLocale:style:defaultLocaleInSubdir:)``
/// to enable automatic locale detection, translation linking, and per-locale output.
struct I18NConfig {
  /// The supported locales, e.g. `["en", "nl"]`.
  let locales: [String]

  /// The default locale, e.g. `"en"`. Must be one of `locales`.
  let defaultLocale: String

  /// The content organization style.
  let style: I18NStyle

  /// Whether the default locale's content should be written to a subdirectory.
  ///
  /// When `false` (the default), the default locale's content is written to the root
  /// (e.g. `deploy/articles/`) and other locales are prefixed (e.g. `deploy/nl/articles/`).
  ///
  /// When `true`, all locales are prefixed (e.g. `deploy/en/articles/`, `deploy/nl/articles/`)
  /// and a redirect is generated from `/` to `/{defaultLocale}/`.
  let defaultLocaleInSubdir: Bool

  /// Whether the given locale's output should be prefixed with the locale path.
  func shouldPrefix(locale: String) -> Bool {
    if locale == defaultLocale, !defaultLocaleInSubdir {
      return false
    }
    return true
  }
}
