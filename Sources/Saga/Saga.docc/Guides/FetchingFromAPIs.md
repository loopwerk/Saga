# Fetching Items from APIs

Create items programmatically from external data sources like REST APIs.

## Overview

Saga's pipeline is traditionally file-driven, but sometimes your content lives in an API or database. The `register(fetch:writers:)` method lets you supply items from any async data source and feed them into the same writer pipeline as file-based content.

This guide shows how to fetch GitHub repositories and render them as a portfolio page.

## Define your metadata

```swift
import Saga

struct RepoMetadata: Metadata {
  let stars: Int
  let language: String?
  let url: URL
}
```

## Fetch from the API

Write an async function that returns an array of items:

```swift
import Foundation
import SagaPathKit

struct GitHubRepo: Decodable {
  let name: String
  let description: String?
  let html_url: String
  let stargazers_count: Int
  let language: String?
  let pushed_at: String
}

func fetchRepos() async throws -> [Item<RepoMetadata>] {
  let url = URL(string: "https://api.github.com/users/loopwerk/repos?sort=updated&per_page=20")!
  var request = URLRequest(url: url)
  request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

  let (data, _) = try await URLSession.shared.data(for: request)
  let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
  let dateFormatter = ISO8601DateFormatter()

  return repos.map { repo in
    let date = dateFormatter.date(from: repo.pushed_at) ?? Date()
    return Item(
      title: repo.name,
      body: "<p>\(repo.description ?? "No description")</p>",
      date: date,
      relativeDestination: Path("projects") / repo.name.slugified / "index.html",
      metadata: RepoMetadata(
        stars: repo.stargazers_count,
        language: repo.language,
        url: URL(string: repo.html_url)!
      )
    )
  }
}
```

## Register the fetch step

Use `register(fetch:writers:)` just like a file-based registration:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    metadata: RepoMetadata.self,
    fetch: fetchRepos,
    writers: [
      .itemWriter(swim(renderRepo)),
      .listWriter(swim(renderRepoList), output: "projects/index.html"),
    ]
  )
  .run()
```

## Mixing file-based and API content

You can freely mix file-based and fetch-based steps. All items are available via `allItems` in every writer:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
    ]
  )
  .register(
    metadata: RepoMetadata.self,
    fetch: fetchRepos,
    writers: [
      .listWriter(swim(renderRepoList), output: "projects/index.html"),
    ]
  )
  .createPage("index.html", using: swim(renderHome))
  .run()
```

The homepage template can then pull in both articles and repos from `context.allItems`.
