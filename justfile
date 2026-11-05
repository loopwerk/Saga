build:
  swift build

test:
  swift test

format:
  swiftformat -swift-version 6 .

# The symbol graph folder depends on the build system, so use the one that dump-symbol-graph reports.
# All of .build would also pick up stale graphs and other modules' graphs, and DocC needs a single module.
docs:
  #!/usr/bin/env bash
  symbol_graphs=$(swift package dump-symbol-graph 2>/dev/null | sed -n 's/^Files written to //p')
  DOCC_JSON_PRETTYPRINT=YES xcrun docc convert \
    Sources/Saga/Saga.docc \
    --additional-symbol-graph-dir "$symbol_graphs" \
    --output-path ./docs \
    --hosting-base-path Saga

docs-preview:
  #!/usr/bin/env bash
  symbol_graphs=$(swift package dump-symbol-graph 2>/dev/null | sed -n 's/^Files written to //p')
  xcrun docc preview \
    Sources/Saga/Saga.docc \
    --additional-symbol-graph-dir "$symbol_graphs" \
    --output-path .build/docc-preview
