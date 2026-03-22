import Foundation
import HTML
import Saga
import SagaPathKit
import SagaSwimRenderer

// MARK: - Translations

func t(_ key: String, locale: String) -> String {
  let strings: [String: [String: String]] = [
    "en": [
      "articles": "Articles",
      "about": "About",
      "home": "Home",
      "tagged": "Tagged",
      "read_more": "Read more",
      "built_with": "Built with",
    ],
    "nl": [
      "articles": "Artikelen",
      "about": "Over ons",
      "home": "Home",
      "tagged": "Getagd",
      "read_more": "Lees meer",
      "built_with": "Gebouwd met",
    ],
  ]
  return strings[locale]?[key] ?? key
}

// MARK: - Language switcher

func languageSwitcher(currentLocale: String, translations: [String: String]) -> Node {
  nav(class: "lang-switcher") {
    translations.sorted(by: { $0.key < $1.key }).map { locale, url in
      if locale == currentLocale {
        span(class: "active") { locale.uppercased() }
      } else {
        a(href: url) { locale.uppercased() }
      }
    }
  }
}

// MARK: - Base layout

func baseHtml(title pageTitle: String, locale: String, @NodeBuilder children: () -> NodeConvertible) -> Node {
  // URLs are fully localized: Dutch uses /nl/artikelen/ instead of /nl/articles/
  let articlesPath = locale == "en" ? "/articles/" : "/nl/artikelen/"
  let aboutPath = locale == "en" ? "/about/" : "/nl/over-ons/"
  let homePath = locale == "en" ? "/" : "/nl/"

  return html(lang: locale) {
    head {
      meta(charset: "utf-8")
      meta(content: "width=device-width, initial-scale=1", name: "viewport")
      title { SiteMetadata.name + ": " + pageTitle }
      link(href: "/static/style.css", rel: "stylesheet")
    }
    body {
      header {
        nav {
          a(class: "site-title", href: homePath) { SiteMetadata.name }
          div(class: "nav-links") {
            a(href: homePath) { t("home", locale: locale) }
            a(href: articlesPath) { t("articles", locale: locale) }
            a(href: aboutPath) { t("about", locale: locale) }
          }
        }
      }
      main {
        children()
      }
      footer {
        p {
          t("built_with", locale: locale)
          " "
          a(href: "https://github.com/loopwerk/Saga") { "Saga" }
        }
      }
    }
  }
}

// MARK: - Articles

func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  let locale = context.locale ?? "en"
  let tagBase = locale == "en" ? "/articles/tag" : "/nl/artikelen/tag"

  return baseHtml(title: context.item.title, locale: locale) {
    languageSwitcher(currentLocale: locale, translations: context.translations)

    h1 { context.item.title }
    ul(class: "tags") {
      context.item.metadata.tags.map { tag in
        li {
          a(href: "\(tagBase)/\(tag.slugified)/") { tag }
        }
      }
    }
    div(class: "article-body") {
      Node.raw(context.item.body)
    }
  }
}

func renderArticles(context: ItemsRenderingContext<ArticleMetadata>) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: t("articles", locale: locale), locale: locale) {
    languageSwitcher(currentLocale: locale, translations: context.translations)

    h1 { t("articles", locale: locale) }
    context.items.map { article in
      div(class: "article-card") {
        a(href: article.url) { article.title }
      }
    }
  }
}

func renderTag(context: PartitionedRenderingContext<String, ArticleMetadata>) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: "\(t("tagged", locale: locale)): \(context.key)", locale: locale) {
    h1 { "\(t("tagged", locale: locale)): \(context.key)" }
    context.items.map { article in
      div(class: "article-card") {
        a(href: article.url) { article.title }
      }
    }
  }
}

// MARK: - Generic pages

func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: context.item.title, locale: locale) {
    languageSwitcher(currentLocale: locale, translations: context.translations)

    div(class: "page") {
      h1 { context.item.title }
      div(class: "article-body") {
        Node.raw(context.item.body)
      }
    }
  }
}
