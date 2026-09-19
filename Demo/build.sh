#!/bin/zsh
# Builds CableKit as a module, then the demo into a simulator .app — no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/CableDemo.app
MOD=build/modules
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TARGET=arm64-apple-ios17.0-simulator
mkdir -p "$OUT" "$MOD"

# SwiftPM generates `Bundle.module` for the package's resources; a plain swiftc build needs its own.
# Strings then resolve from the app bundle, falling back to the English keys.
cat > "$MOD/resource_bundle_accessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static let module = Bundle.main
}
SWIFT

xcrun -sdk iphonesimulator swiftc -target $TARGET -sdk "$SDK" -swift-version 6 -O \
  -emit-module -emit-library -module-name CableKit \
  -emit-module-path "$MOD/CableKit.swiftmodule" -o "$MOD/libCableKit.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libCableKit.dylib \
  Sources/CableKit/*.swift "$MOD/resource_bundle_accessor.swift"


xcrun -sdk iphonesimulator swiftc -target $TARGET -sdk "$SDK" -swift-version 6 -O -parse-as-library \
  -module-name CableDemo -I "$MOD" -L "$MOD" -lCableKit -Xlinker -rpath -Xlinker @executable_path \
  Demo/*.swift -o "$OUT/CableDemo"


cp "$MOD/libCableKit.dylib" "$OUT/"
cp Demo/Info.plist "$OUT/Info.plist"
echo "Built $OUT"
