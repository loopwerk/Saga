# Architecture

An overview of how Saga works.


## Overview
Saga does its work in multiple stages.

1. Any registered ``Saga/beforeRead(_:)`` hooks run first — use these for pre-build steps like CSS compilation.
2. For every registered step, Saga passes the input files to a matching ``Reader``. These readers turn text files (such as markdown files) into `Item` instances.
3. Saga runs all the registered steps again, now executing the ``Writer``s. These writers turn a rendering context (which holds the ``Item`` among other things) into a `String` using a "renderer", which it'll then write to disk, to the `output` folder.
4. Any registered ``Saga/afterWrite(_:)`` hooks run last — use these for post-build steps like search indexing.
5. Finally, all unhandled files (images, CSS, raw HTML, etc.) are copied as-is to the `output` folder.

Saga does not come with any readers or renderers out of the box. The official recommendation is to use [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) for reading markdown files using [Parsley](https://github.com/loopwerk/Parsley), and [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to render them using [Swim](https://github.com/robb/Swim), which offers a great HTML DSL using Swift's result builders. 

Please check the <doc:Installation> instructions, or check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) to get an idea of how Saga works with Parsley and Swim.
