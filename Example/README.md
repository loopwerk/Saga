# Saga example app
This example project contains articles with tags and pagination, an app portfolio, static pages, RSS feeds for all articles and per tag, statically typed HTML templates, and more.

This project follows the official recommendation and makes use of [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) for reading Markdown files using [Parsley](https://github.com/loopwerk/Parsley), and [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to render them using [Swim](https://github.com/robb/Swim), which offers a great HTML DSL using Swift's function builders.

## Usage
Simply open `Package.swift`, wait for the dependencies to be downloaded, and run the project from within Xcode. Or run from the command line: `swift run`.
