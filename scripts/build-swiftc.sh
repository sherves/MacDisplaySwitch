#!/bin/bash
# 备用构建：不依赖 SwiftPM，直接用 swiftc 编译（命令行工具损坏时使用）
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=${SDK:-$(xcrun --show-sdk-path)}
ARCH=$(uname -m)
T="$ARCH-apple-macosx13.0"
O=.build/sw; mkdir -p "$O" .build/release
swiftc -sdk "$SDK" -target "$T" -O -parse-as-library -module-name DisplayCore -emit-module -emit-module-path "$O/DisplayCore.swiftmodule" -emit-library -static -o "$O/libDisplayCore.a" Sources/DisplayCore/*.swift
swiftc -sdk "$SDK" -target "$T" -O -parse-as-library -I "$O" -L "$O" -lDisplayCore Sources/DisplayFocusApp/*.swift -o .build/release/DisplayFocusApp
swiftc -sdk "$SDK" -target "$T" -O -I "$O" -L "$O" -lDisplayCore Sources/displayfocus/main.swift -o .build/release/displayfocus
SKIP_SWIFT_BUILD=1 bash scripts/build.sh
