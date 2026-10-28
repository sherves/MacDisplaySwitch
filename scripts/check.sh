#!/bin/bash
# Fixture checks work with Command Line Tools alone (no XCTest/Xcode installation required).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun swiftc -D DISPLAYFOCUS_FIXTURES -swift-version 5 -parse-as-library -module-name DisplayCore Sources/DisplayCore/*.swift Tests/DisplayCoreTests/*.swift -o .build/checks/display-safety-checks
.build/checks/display-safety-checks
