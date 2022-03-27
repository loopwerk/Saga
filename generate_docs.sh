#! /bin/bash

swift build

# See https://apple.github.io/swift-docc-plugin/documentation/swiftdoccplugin/publishing-to-github-pages
swift package --allow-writing-to-directory ./docs generate-documentation --target Saga --output-path ./docs --transform-for-static-hosting --hosting-base-path Saga