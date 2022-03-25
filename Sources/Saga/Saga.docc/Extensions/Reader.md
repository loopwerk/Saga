# ``Saga/Reader``

Readers are responsible for turning text files into ``Item`` instances.


## Overview
Readers are responsible for turning text files into ``Item`` instances. Every Reader can declare what kind of text files it supports, for example Markdown or RestructuredText. Readers are expected to support the parsing of metadata contained within a document, such as this example for Markdown files:

```text
---
tags: article, news
summary: This is the summary
---
# Hello world
Hello there.
```

Saga does not come bundled with any readers out of the box, instead you'll have to install one such as [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader), [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader), or [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader).
