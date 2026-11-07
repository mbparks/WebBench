#!/bin/bash
# Simple single-target app template. Adapt for helpers, extensions, or embedded code.
# Usage from the project root:
# bash scripts/build-macos.sh Project.xcodeproj Scheme AppName [Entitlements.plist]
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 Project.xcodeproj Scheme AppName [Entitlements.plist]" >&2
  exit 2
fi
project="$1"
scheme="$2"
product="$3"
entitlements="${4:-}"
case "$product" in
  ""|.|..|*/*) echo "AppName must be a simple product basename." >&2; exit 2 ;;
esac
if [ ! -d "$project" ]; then echo "Xcode project not found: $project" >&2; exit 2; fi
if [ -n "$entitlements" ] && [ ! -f "$entitlements" ]; then
  echo "Entitlements not found: $entitlements" >&2
  exit 2
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Run this build script on a Mac with the Xcode version documented in START-HERE." >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Install/open Xcode, finish its setup, and select Xcode in Settings > Locations > Command Line Tools." >&2
  exit 1
fi
mkdir -p build
build_run="$(mktemp -d "$PWD/build/local.XXXXXX")"
log="$build_run/build.log"
echo "Build log: $log"
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "Build failed. Diagnostic log: $log" >&2; fi' EXIT
xcodebuild -project "$project" -scheme "$scheme" -configuration Release \
  -derivedDataPath "$build_run/DerivedData" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$log"
app="$build_run/DerivedData/Build/Products/Release/$product.app"
if [ ! -d "$app" ]; then
  echo "Expected product not found: $app. Check the product name and build settings." >&2
  exit 1
fi
nested="$(find "$app/Contents" -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.bundle' \) -print)"
dylibs="$(find "$app/Contents" -type f -name '*.dylib' -print)"
if [ -n "$nested" ] || [ -n "$dylibs" ]; then
  echo "Embedded code/resources require an app-specific signing workflow. Adapt this template before packaging." >&2
  exit 1
fi
if [ -d "$app/Contents/Library" ]; then
  echo "Contents/Library may contain helpers. Use an app-specific signing workflow." >&2
  exit 1
fi
sign_args=(--force --sign - --options runtime)
if [ -n "$entitlements" ]; then sign_args+=(--entitlements "$entitlements"); fi
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
archive="$build_run/$product-local-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
echo "Built: $app"
echo "Packaged: $archive"
echo "Ad-hoc local build; not Developer ID signed or notarized."
if [ -z "${CI:-}" ]; then
  open -R "$app" || echo "Reveal the printed app path in Finder."
fi
