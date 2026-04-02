build:
  swift build

test:
  swift test

test-swift60:
  docker run --rm -v "$PWD":/src -w /src --tmpfs /src/.build:exec swift:6.0 swift test

format:
  swiftformat -swift-version 6 .

docs:
  swift package dump-symbol-graph 2>/dev/null || true
  DOCC_JSON_PRETTYPRINT=YES xcrun docc convert \
    Sources/Saga/Saga.docc \
    --additional-symbol-graph-dir .build \
    --output-path ./docs \
    --hosting-base-path Saga

docs-preview:
  swift package dump-symbol-graph 2>/dev/null || true
  xcrun docc preview \
    Sources/Saga/Saga.docc \
    --additional-symbol-graph-dir .build \
    --output-path .build/docc-preview
