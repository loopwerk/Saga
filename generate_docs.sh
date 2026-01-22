#! /bin/bash

set -e

PACKAGE_SWIFT="Package.swift"
DOCC_PLUGIN_LINE=".package(url: \"https://github.com/swiftlang/swift-docc-plugin\", from: \"1.1.0\"),"

# Enable the swift-docc-plugin dependency
sed -i '' "s|//\s*$DOCC_PLUGIN_LINE|$DOCC_PLUGIN_LINE|" "$PACKAGE_SWIFT"

# Pretty print DocC JSON output so that it can be consistently diffed between commits
export DOCC_JSON_PRETTYPRINT="YES"

# Generate documentation
swift package \
  --allow-writing-to-directory ./docs \
  generate-documentation \
  --target Saga \
  --disable-indexing \
  --output-path ./docs \
  --transform-for-static-hosting \
  --hosting-base-path Saga

# Restore Package.swift by commenting out the dependency again
if grep -q "$DOCC_PLUGIN_LINE" "$PACKAGE_SWIFT"; then
  sed -i '' "s|$DOCC_PLUGIN_LINE|// $DOCC_PLUGIN_LINE|" "$PACKAGE_SWIFT"
fi

echo "Documentation generated successfully."