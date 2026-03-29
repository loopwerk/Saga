# ``Saga``
A code-first static site generator in Swift. No config files, no implicit behavior, no magic conventions.

Your entire site pipeline is plain Swift code:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles), paginate: 20),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )
  .run()
```

Typed metadata, pluggable readers, multiple writer types, pagination, tags — all defined in Swift, readable top to bottom, and enforced by the compiler. No hidden defaults. No template logic you can't debug.


## Overview
Saga uses a system of extendible readers, renderers, and writers, supporting things like Atom feeds, sitemaps, paginating, and strongly typed HTML templates.

Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure.


## Who this is for

**Saga is for you if:**
- You want your site generation logic in Swift, not YAML/TOML config files
- You want compile-time safety for your HTML templates and content metadata
- You've outgrown convention-based SSGs and want full control

**Saga is not for you if:**
- You need a large ecosystem of themes and templates
- You're not comfortable with Swift


## Thanks
Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder, which was copied over shamelessly.

You can read [this series of articles](https://www.loopwerk.io/articles/tag/saga/) discussing the inspiration behind the API.


## Topics

### Essentials

- <doc:Installation>
- <doc:GettingStarted>
- <doc:Architecture>
- <doc:AdvancedUsage>
- <doc:Migrate>

### Guides

- <doc:AddingSearch>
- <doc:PhotoGalleries>
- <doc:TailwindCSS>
- <doc:CustomFeedFormats>
- <doc:FetchingFromAPIs>
- <doc:GeneratingSitemaps>
- <doc:HTMLMinification>
- <doc:Internationalization>
- <doc:Shortcodes>
- <doc:ReusableHTMLLayouts>
