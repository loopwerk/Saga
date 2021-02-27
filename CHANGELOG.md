# 0.19.0 - 2021-02-18
- Switched the dev server from [lite-server](https://github.com/johnpapa/lite-server) to [browser-sync](https://browsersync.io)

# 0.18.5 - 2021-02-17
- Clear output folder right before writing the new files, this greatly improves the dev server reload reliability

# 0.18.4 - 2021-02-17
- Greatly improved the slugified function on String, which now also comes with unit tests

# 0.18.3 - 2021-02-15
- Added more unit tests
- The watch server executable is now only available on macOS, as it doesn't compile on Linux.

# 0.18.2 - 2021-02-14
- Made sure files are written in a fixed order, so unit tests don't randomly fail.

# 0.18.1 - 2021-02-14
- Added first unit tests
- Fixed slugification of tagWriter's `[key]`, if you have tags with spaces

# 0.18.0 - 2021-02-13
- Added paginator support (#8)
- Renamed Page to Item, pageWriter to itemWriter, and all other Page related things to Item. This so that the Paginator's `itemsPerPage` and numberOfPages` don't cause confusion.

# 0.17.0 - 2021-02-12
- tagWriter and yearWriter are now generalized into a partitionedWriter. (They are still available as convenience functions that use partitionedWriter under the hood).

# 0.16.0 - 2021-02-12
- Added a watch mode that rebuilds your website and reloads the browser as well. This functionality does depend on a globally installed lite-server, https://github.com/johnpapa/lite-server.

# 0.15.0 - 2021-02-11
- The Slugify dependency has been removed and replaced with my own very basic slugified computed property on String. This makes quite a big speed difference!

# 0.14.0 - 2021-02-10
- Saga no longer comes bundled with a default markdown reader - you install one yourself:
  - https://github.com/loopwerk/SagaParsleyMarkdownReader
  - https://github.com/loopwerk/SagaPythonMarkdownReader
  - https://github.com/loopwerk/SagaInkMarkdownReader
- The writers now have a different function signature. They no longer simply take a templatePath,
  Instead they expect a function that is given a RenderingContext and must return a String.
  This should make it possible to use any kind of renderer you want, whether you want to use swift-html,
  Plot, Swim or Stencil. As long as you can turn a RenderingContext into a String, it'll work.
  One renderer that is available is https://github.com/loopwerk/SagaSwimRenderer.

# 0.13.0 - 2021-02-09
- Switched away from SwiftMarkdown to Parsley, which is a LOT faster, see https://github.com/loopwerk/Saga/pull/5. Sadly it doesn't do syntax highlighting, so a client side solution such as prism.js is very handy.
  If you want to keep using SwiftMarkdown, check out https://github.com/loopwerk/SagaPythonMarkdownReader.

# 0.12.0 - 2021-02-07
- Updated to latest version of SwiftMarkdown and now using its `urlize` extension

# 0.11.0 - 2021-02-07
- Fixed Stencil filters when compiling your site under Linux

# 0.10.0 - 2021-02-07
- Refactored the `keepExactPath` parameter of the writer into a better documented `PageWriteMode` enum that's part of the `register` function. This is because we need those destination paths for all pages before the first writer even starts its thing.

# 0.9.0 - 2021-02-07
- Changed the `numberOfWords` filter, the old version didn't work on Linux
  (`error: 'byWords' is unavailable: Enumeration by words isn't supported in swift-corelibs-foundation`)

# 0.8.0 - 2021-02-07
- Replaced Ink and Stencil with SwiftMarkdown, see https://github.com/loopwerk/Saga/pull/3.
  If you want to keep using Ink and Stencil, check out https://github.com/loopwerk/SagaInkMarkdownReader.
- Added a way to supply custom `SiteMetadata`, which will be given to every template
- Added `striptags`, `wordcount`, `slugify`, `escape` and `truncate` filters for Stencil
- Made some previously `internal` things `public`

# 0.7.0 - 2021-02-03
- Complete API redesign, see https://github.com/loopwerk/Saga/pull/1

# 0.6.0 - 2021-02-02
- Pages can set their own custom template

# 0.5.0 - 2021-02-02
- The `read` function's `metadata` parameter now defaults to `EmptyMetadata.self`

# 0.4.0 - 2021-01-31
- `Saga.rootPath`, `Saga.inputPath`, and `Saga.outputPath` are now public

# 0.3.0 - 2021-01-30
- Added `lastModified` to `Page`

# 0.4.0 - 2021-01-30
- `Saga.fileStorage` is now public

# 0.1.0 - 2021-01-29
- Initial release