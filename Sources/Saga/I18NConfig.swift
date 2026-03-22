/// Configuration for internationalization (i18n) support.
///
/// When i18n is configured, Saga expects content to be organized in locale-prefixed folders:
/// ```
/// content/
///   en/articles/hello.md
///   nl/articles/hello.md
/// ```
///
/// Each `register()` call automatically fans out into per-locale processing steps.
public struct I18NConfig: Sendable {
  /// The supported locales (e.g. `["en", "nl", "de"]`).
  public let locales: [String]

  /// The default locale (e.g. `"en"`).
  public let defaultLocale: String

  /// Whether the default locale should be placed in a subdirectory.
  ///
  /// When `false` (the default), the default locale's content is written to the root:
  /// - `en/articles/hello.md` → `articles/hello/index.html`
  /// - `nl/articles/hello.md` → `nl/articles/hello/index.html`
  ///
  /// When `true`, all locales get a subdirectory prefix:
  /// - `en/articles/hello.md` → `en/articles/hello/index.html`
  /// - `nl/articles/hello.md` → `nl/articles/hello/index.html`
  public let prefixDefaultLocaleOutputFolder: Bool

  /// Whether the given locale should be prefixed in output paths.
  func shouldPrefix(locale: String) -> Bool {
    prefixDefaultLocaleOutputFolder || locale != defaultLocale
  }
}
