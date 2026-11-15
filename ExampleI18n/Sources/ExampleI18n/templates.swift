import Foundation
import HTML
import Saga
import SagaPathKit
import SagaSwimRenderer

// MARK: - Translations

func t(_ key: String, locale: SagaLocale) -> String {
  let strings: [SagaLocale: [String: String]] = [
    "en": [
      "articles": "Articles",
      "projects": "Projects",
      "about": "About",
      "home": "Home",
      "tagged": "Tagged",
      "read_more": "Read more",
      "built_with": "Built with",
      "welcome": "Welcome",
      "latest_article": "Latest article",
    ],
    "nl": [
      "articles": "Artikelen",
      "projects": "Projecten",
      "about": "Over ons",
      "home": "Home",
      "tagged": "Getagd",
      "read_more": "Lees meer",
      "built_with": "Gebouwd met",
      "welcome": "Welkom",
      "latest_article": "Nieuwste artikel",
    ],
  ]
  return strings[locale]?[key] ?? key
}

// MARK: - Language switcher

func languageSwitcher(currentLocale: SagaLocale, translations: [SagaLocale: String]) -> Node {
  div(class: "lang-switcher") {
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

func baseHtml(title pageTitle: String, locale: String, currentUrl: String, translations: [SagaLocale: String], @NodeBuilder children: () -> NodeConvertible) -> Node {
  // URLs are fully localized: Dutch uses /nl/artikelen/ instead of /nl/articles/
  let articlesPath = locale == "en" ? "/articles/" : "/nl/artikelen/"
  let projectsPath = locale == "en" ? "/projects/" : "/nl/projecten/"
  let aboutPath = locale == "en" ? "/about/" : "/nl/over-ons/"
  let homePath = locale == "en" ? "/" : "/nl/"

  // Every URL starts with the home path, so Home is only active on the homepage itself.
  func navLink(_ path: String, _ key: String) -> Node {
    let isActive = path == homePath ? currentUrl == homePath : currentUrl.hasPrefix(path)
    return a(class: isActive ? "active" : nil, href: path) { t(key, locale: locale) }
  }

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
            navLink(homePath, "home")
            navLink(articlesPath, "articles")
            navLink(projectsPath, "projects")
            navLink(aboutPath, "about")

            if !translations.isEmpty {
              languageSwitcher(currentLocale: locale, translations: translations)
            }
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

  return baseHtml(title: context.item.title, locale: locale, currentUrl: context.item.url, translations: context.translations) {
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

  return baseHtml(title: t("articles", locale: locale), locale: locale, currentUrl: context.outputPath.url, translations: context.translations) {
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

  return baseHtml(title: "\(t("tagged", locale: locale)): \(context.key)", locale: locale, currentUrl: context.outputPath.url, translations: context.translations) {
    h1 { "\(t("tagged", locale: locale)): \(context.key)" }
    context.items.map { article in
      div(class: "article-card") {
        a(href: article.url) { article.title }
      }
    }
  }
}

// MARK: - Projects

func renderProjects(context: ItemsRenderingContext<EmptyMetadata>) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: t("projects", locale: locale), locale: locale, currentUrl: context.outputPath.url, translations: context.translations) {
    h1 { t("projects", locale: locale) }
    context.items.map { project in
      div(class: "article-card") {
        h2 { project.title }
        project.resources.map { resource in
          img(alt: project.title, src: resource.url)
        }
        div(class: "article-body") {
          Node.raw(project.body)
        }
      }
    }
  }
}

// MARK: - Home

func renderHome(context: PageRenderingContext) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: t("home", locale: locale), locale: locale, currentUrl: context.outputPath.url, translations: context.translations) {
    h1 { t("welcome", locale: locale) }

    if let latest = context.allItems.compactMap({ $0 as? Item<ArticleMetadata> }).first {
      div(class: "article-card") {
        p { t("latest_article", locale: locale) }
        a(href: latest.url) { latest.title }
      }
    }
  }
}

// MARK: - Generic pages

func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  let locale = context.locale ?? "en"

  return baseHtml(title: context.item.title, locale: locale, currentUrl: context.item.url, translations: context.translations) {
    div(class: "page") {
      h1 { context.item.title }
      div(class: "article-body") {
        Node.raw(context.item.body)
      }
    }
  }
}
