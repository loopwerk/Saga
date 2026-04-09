# Building Photo Galleries

Use nested processing steps to create photo galleries.

## Overview

Photo galleries typically have a two-level structure: albums containing photos. The `register` step's `nested:` parameter creates a separate processing scope per subfolder, giving each album its own `items` array and `previous`/`next` navigation.

## Simple gallery (images only)

When albums are just folders of images with no metadata file:

```
content/
  photos/
    vacation/
      beach.jpg
      sunset.jpg
    birthday/
      cake.jpg
      group.jpg
```

Then set up your nested Saga pipeline like so:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "photos",
    writers: [
      .listWriter(swim(renderAlbums)),
    ],
    nested: { nested in
      nested.register(
        metadata: ImageMetadata.self,
        readers: [.imageReader],
        writers: [
          .listWriter(swim(renderAlbum)),
          .itemWriter(swim(renderPhoto)),
        ]
      )
    }
  )
  .run()
```

> Note: `Reader.imageReader` and `ImageMetadata` are coming from [SagaImageReader](https://github.com/loopwerk/SagaImageReader).

In the outer `renderAlbums` template, `context.items` is the list of albums. For each album you can use ``Item/children(as:)`` to access the nested items:

```swift
func renderAlbums(context: ItemsRenderingContext<EmptyMetadata>) -> Node {
  context.items.map { album in
    let photos = album.children(as: ImageMetadata.self)
    return a(href: album.url) {
      h2 { album.title }
      p { "\(photos.count) photos" }
    }
  }
}
```

## Gallery with album metadata

For albums with an `index.md` containing metadata, use different readers for the outer and nested registrations:

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

Your pipeline looks like this:

```swift
struct AlbumMetadata: Metadata {
  // Add fields as needed, e.g. coverImage, location
}

try await Saga(input: "content", output: "deploy")
  .register(
    folder: "photos",
    metadata: AlbumMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .listWriter(swim(renderAlbums)),
      .itemWriter(swim(renderAlbum)),
    ],
    nested: { nested in
      nested.register(
        metadata: ImageMetadata.self,
        readers: [.imageReader],
        writers: [
          .itemWriter(swim(renderPhoto)),
        ]
      )
    }
  )
  .run()
```

Parent/child relationships are wired automatically. Access them with typed accessors:

```swift
func renderAlbum(context: ItemRenderingContext<AlbumMetadata>) -> Node {
  let photos = context.item.children(as: ImageMetadata.self)

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

Each photo page gets `previous`/`next` links scoped within its album, and can navigate back to its parent:

```swift
func renderPhoto(context: ItemRenderingContext<ImageMetadata>) -> Node {
  let album = context.item.parent(as: AlbumMetadata.self)

  return baseLayout(title: context.item.title) {
    div(class: "photo-nav") {
      if let previous = context.previous {
        a(href: previous.url) { "Previous" }
      }
      a(href: album.url) { "Back to album" }
      if let next = context.next {
        a(href: next.url) { "Next" }
      }
    }
    img(alt: context.item.title, src: context.item.relativeSource.lastComponent)
  }
}
```

> Tip: Check the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a complete, runnable version of this pattern.
