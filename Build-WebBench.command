#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash scripts/build-macos.sh WebBench.xcodeproj WebBench WebBench
result=$?
if [ "$result" -ne 0 ]; then
  echo "Build failed. Keep the diagnostic log printed above."
fi
if [ -t 0 ]; then read -r -p "Press Return to close."; fi
exit "$result"
