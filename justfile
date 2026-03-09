build:
  swift build

test:
  swift test

test-swift510:
  docker run --rm -v "$PWD":/src -w /src --tmpfs /src/.build:exec swift:5.10 swift test

format:
  swiftformat -swift-version 5 .
