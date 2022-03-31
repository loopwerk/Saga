#! /bin/bash

# Insert swift-docc-plugin as a dependency, needed to export the docs
cp Package.swift Package.swift.orig
awk 'NR==15{print "    .package(url: \"https://github.com/apple/swift-docc-plugin.git\", from: \"1.0.0\"),"}7' Package.swift.orig > Package.swift

# See https://apple.github.io/swift-docc-plugin/documentation/swiftdoccplugin/publishing-to-github-pages
swift package --allow-writing-to-directory ./docs generate-documentation --target Saga --output-path ./docs --transform-for-static-hosting --hosting-base-path Saga

# Restore the original Package.swift file
mv Package.swift.orig Package.swift
