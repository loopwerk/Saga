# Architecture

An overview of how Saga works.


## Overview
Saga does its work in multiple stages.

1. First, it finds all the files within the `input` folder.
2. **Read**: For every registered step, it passes those files to a matching ``Reader``. These readers turn text files (such as markdown or reStructuredText files) into `Item` instances.
3. All unhandled files (images, CSS, raw HTML, etc.) are copied as-is to the `output` folder, so that the directory structure exists for the write phase.
4. **Write**: Saga executes all steps sequentially in registration order. Within each step, ``Writer``s run in parallel, turning a rendering context into a `String` using a "renderer" and writing it to disk. Every written file is tracked, so later steps (like ``sitemap(baseURL:filter:)`` via ``Saga/createPage(_:using:)``) can see all pages from earlier steps.

Saga does not come with any readers or renderers out of the box. The official recommendation is to use [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) for reading markdown files using [Parsley](https://github.com/loopwerk/Parsley), and [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to render them using [Swim](https://github.com/robb/Swim), which offers a great HTML DSL using Swift's function builders. 

Please check the <doc:Installation> instructions, or check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) to get an idea of how Saga works with Parsley and Swim.
