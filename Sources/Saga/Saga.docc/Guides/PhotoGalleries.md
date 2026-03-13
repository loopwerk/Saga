# Building Photo Galleries

Use nested subfolder processing to create photo galleries with per-album navigation.

## Overview

Photo galleries typically have a two-level structure: albums containing photos. Saga's `/**` folder suffix creates a separate processing step per subfolder, giving each album its own scoped `items` array and `previous`/`next` navigation.

## Content structure

Organize your content with one markdown file per album (for album metadata) and images alongside it:

```
content/
  photos/
    vacation/
      index.md
      beach.jpg
      sunset.jpg
    birthday/
      index.md
      cake.jpg
      group.jpg
```

Each `index.md` contains album-level frontmatter:

```text
---
date: 2024-06-15
---
# Summer Vacation
Photos from our trip to the coast.
```

## Define metadata types

```swift
struct AlbumMetadata: Metadata {
  // Add fields as needed, e.g. coverImage, location
}

struct PhotoMetadata: Metadata {
  // Metadata per photo, if any
}
```

## Register two steps

The key is registering two steps: one for albums (flat) and one for photos (nested):

```swift
try await Saga(input: "content", output: "deploy")
  // Step 1: Album pages from markdown files
  .register(
    folder: "photos",
    metadata: AlbumMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .listWriter(swim(renderAlbums)),
      .itemWriter(swim(renderAlbum)),
    ]
  )
  // Step 2: Individual photo pages, scoped per subfolder
  .register(
    folder: "photos/**",
    metadata: PhotoMetadata.self,
    readers: [.imageReader()],
    writers: [
      .itemWriter(swim(renderPhoto)),
    ]
  )
  .run()
```

The `/**` suffix means `photos/vacation` and `photos/birthday` each become their own step with their photos. Within each step, `previous`/`next` navigation links stay within the album.

## Linking albums to their photos

In your album template, find the photos that belong to this album by matching folder paths:

```swift
func photosForAlbum(_ album: AnyItem, allItems: [AnyItem]) -> [AnyItem] {
  allItems.filter {
    $0 is Item<PhotoMetadata>
      && $0.relativeSource.parent() == album.relativeSource.parent()
  }
}

func renderAlbum(context: ItemRenderingContext<AlbumMetadata>) -> Node {
  let photos = photosForAlbum(context.item, allItems: context.allItems)

  return baseLayout(title: context.item.title) {
    h1 { context.item.title }
    div(class: "photo-grid") {
      photos.map { photo in
        a(href: photo.url) {
          img(alt: photo.title, loading: "lazy", src: photo.relativeSource.lastComponent)
        }
      }
    }
  }
}
```

## Photo detail pages with navigation

Each photo page gets `previous`/`next` links scoped to its album:

```swift
func renderPhoto(context: ItemRenderingContext<PhotoMetadata>) -> Node {
  let album = context.allItems.first {
    $0 is Item<AlbumMetadata>
      && $0.relativeSource.parent() == context.item.relativeSource.parent()
  }

  return baseLayout(title: context.item.title) {
    div(class: "photo-nav") {
      if let previous = context.previous {
        a(href: previous.url) { "Previous" }
      }
      if let album {
        a(href: album.url) { "Back to album" }
      }
      if let next = context.next {
        a(href: next.url) { "Next" }
      }
    }
    img(alt: context.item.title, src: "../\(context.item.relativeSource.lastComponent)")
  }
}
```

> tip: Check the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a complete, runnable version of this pattern.
