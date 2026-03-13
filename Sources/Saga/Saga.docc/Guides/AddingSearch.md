# Adding Search

Add client-side search to your Saga site.

## Overview

Since Saga generates static HTML, search needs to happen client-side. There are two main approaches:

**Binary index** — these tools have a CLI that indexes your built site and produces a compact binary index, keeping bandwidth low:

- **[Pagefind](https://pagefind.app)** — indexes your built HTML and provides a fast search UI with no server required.
- **[tinysearch](https://github.com/tinysearch/tinysearch)** — Rust-compiled-to-WebAssembly search with a very small footprint (~50kB for a typical blog), though it only matches complete words.

**JSON index** — these are runtime JS libraries that search a JSON index you load in the browser. You need to build that JSON index yourself (for example by using a Saga writer), and it can grow large on content-heavy sites:

- **[Lunr.js](https://lunrjs.com)** — a lightweight, fully client-side search library.
- **[Fuse.js](https://www.fusejs.io)** — a fuzzy-search library that works well for smaller sites.
- **[MiniSearch](https://github.com/lucaong/minisearch)** — a tiny, zero-dependency JS library with fuzzy matching and auto-suggestions.

This guide walks through integrating **Pagefind**.

## Install Pagefind

Add Pagefind to your project via npm or pnpm:

```shell-session
$ npm init -y
$ npm install pagefind
```

## Run Pagefind after the build

After Saga's `run()` completes, shell out to Pagefind to index the output folder:

```swift
import Foundation

try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderArticle))]
  )
  .run()

// Index the site
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["npx", "pagefind", "--site", "deploy"]
try process.run()
process.waitUntilExit()
```

Pagefind generates its index and UI files into `deploy/pagefind/`.

## Create a search page

Use ``Saga/createPage(_:using:)`` to add a search page:

```swift
try await Saga(input: "content", output: "deploy")
  .register(/* ... */)
  .createPage("search/index.html", using: swim(renderSearch))
  .run()
```

The search template loads Pagefind's UI and wires it up:

```swift
func renderSearch(context: PageRenderingContext) -> Node {
  baseLayout(
    title: "Search",
    extraHead: {
      script(src: "/pagefind/pagefind-modular-ui.js")
      script {
        Node.raw("""
          window.addEventListener('DOMContentLoaded', () => {
            const q = new URLSearchParams(window.location.search).get("q");
            const instance = new PagefindModularUI.Instance();
            instance.add(new PagefindModularUI.Input({ inputElement: "#search" }));
            instance.add(new PagefindModularUI.ResultList({ containerElement: "#results" }));
            if (q) {
              document.getElementById("search").value = q;
              instance.triggerSearch(q);
            }
          });
          """)
      }
    }
  ) {
    h1 { "Search" }
    form(action: "/search/") {
      input(id: "search", name: "q", placeholder: "Search articles", type: "text")
    }
    div(id: "results")
  }
}
```

## Control what gets indexed

Pagefind indexes all HTML by default. Use the `data-pagefind-body` attribute to limit indexing to specific content:

```swift
func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  baseLayout(title: context.item.title) {
    article(customAttributes: ["data-pagefind-body": ""]) {
      h1 { context.item.title }
      Node.raw(context.item.body)
    }
  }
}
```

With `data-pagefind-body` on any element, Pagefind only indexes elements with that attribute, excluding navigation, footers, and other chrome.

> tip: You can check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io) for a complete working search implementation.
