# ``Saga``
A static site generator, written in Swift, allowing you to supply your own metadata types for your items.


## Overview
Saga uses a system of extendible readers, renderers, and writers, supporting things like Atom feeds, paginating, and strongly typed HTML templates.

Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure.


## Thanks
Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder, which was copied over shamelessly.

You can read [this series of articles](https://www.loopwerk.io/articles/tag/saga/) discussing the inspiration behind the API.


## Topics

### Essentials

- <doc:Installation>
- <doc:GettingStarted>
- <doc:Architecture>
- <doc:ProgrammaticItems>
- ``Reader``
- ``Writer``
