# Architecture

An overview of how Saga works.


## Overview
Saga does its work in multiple stages.

1. First, it finds all the files within the `input` folder.
2. **Read**: For every registered step, it passes those files to a matching ``Reader``. These readers turn text files (such as markdown or reStructuredText files) into `Item` instances.
3. All unhandled files (images, CSS, raw HTML, etc.) are copied as-is to the `output` folder, so that the directory structure exists for the write phase.
4. **Write**: Saga executes the ``Writer``s in parallel. These writers turn a rendering context (which holds the ``Item`` among other things) into a `String` using a "renderer", which it'll then write to disk, to the `output` folder. Every written file is tracked in ``Saga/generatedPages``.
5. **Pages**: Steps registered with ``Saga/createPage(_:using:)`` run after all writers, so renderers like ``sitemap(baseURL:filter:)`` can access the complete list of generated pages.

Saga does not come with any readers or renderers out of the box. The official recommendation is to use [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) for reading markdown files using [Parsley](https://github.com/loopwerk/Parsley), and [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to render them using [Swim](https://github.com/robb/Swim), which offers a great HTML DSL using Swift's function builders. 

Please check the <doc:Installation> instructions, or check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) to get an idea of how Saga works with Parsley and Swim.
