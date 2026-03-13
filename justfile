build:
  swift build

test:
  swift test

test-swift60:
  docker run --rm -v "$PWD":/src -w /src --tmpfs /src/.build:exec swift:6.0 swift test

format:
  swiftformat -swift-version 6 .

[private]
enable-docc-plugin:
  sed -i '' 's|// *\.package(url: "https://github.com/swiftlang/swift-docc-plugin"|.package(url: "https://github.com/swiftlang/swift-docc-plugin"|' Package.swift

[private]
disable-docc-plugin:
  sed -i '' 's|\.package(url: "https://github.com/swiftlang/swift-docc-plugin"|// .package(url: "https://github.com/swiftlang/swift-docc-plugin"|' Package.swift

docs:
  just enable-docc-plugin
  DOCC_JSON_PRETTYPRINT=YES swift package \
    --allow-writing-to-directory ./docs \
    generate-documentation \
    --target Saga \
    --disable-indexing \
    --output-path ./docs \
    --transform-for-static-hosting \
    --hosting-base-path Saga; \
  just disable-docc-plugin

docs-preview:
  just enable-docc-plugin
  swift package --disable-sandbox preview-documentation --target Saga; \
  just disable-docc-plugin
