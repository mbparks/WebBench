#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo "Run the native suite on macOS 15 or later."; exit 1; fi
mkdir -p build
run="$(mktemp -d "$PWD/build/tests.XXXXXX")"
echo "Test results: $run"
swift test --scratch-path "$run/Storage" 2>&1 | tee "$run/storage.log"
xcodebuild -project WebBench.xcodeproj -scheme WebBench -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$run/DerivedData" -resultBundlePath "$run/WebBench.xcresult" test 2>&1 | tee "$run/native.log"
if command -v node >/dev/null; then
  node --test Tests/*.test.cjs
  node Tests/roundtrip.cjs
fi
