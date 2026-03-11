build:
  swift build

test:
  swift test

test-swift60:
  docker run --rm -v "$PWD":/src -w /src --tmpfs /src/.build:exec swift:6.0 swift test

format:
  swiftformat -swift-version 6 .
