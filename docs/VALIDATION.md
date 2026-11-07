# WebBench 0.9.0 validation

**Mac workflows exercised for this release on this host: zero.** This build ran on Linux with an Apple macOS 15.2 SDK, a Swift cross-toolchain and headless Chromium 157.0.8103.38. The macOS target and browser engine matter here. The browser fixtures exercise the actual canvas scripts with a test bridge, and the Layers tests call the production Swift destination planner. AppKit event delivery, SwiftUI row dragging, WKWebView and Safari require a Mac.

## Nested insertion and Layers

| Check executed | Observed result |
|---|---|
| Palette hover, drop and click | A real Chromium layout displayed the insertion preview. A button landed in the nested flex row, a disclosure landed in an empty div, and a card landed in the grid. |
| Layers before, inside and after | Production Swift accepted the three destinations and the source engine moved the corresponding subtrees. After save, export and reopen, the HTML retained its BOM, CRLF and working hyperlink. |
| Insert catalog | All 56 tiles produced a single root with the expected tag in a compatible parent. Chromium parsed each template. |
| Unsafe and redundant changes | Tests covered cycles, incompatible list and table children, nested forms, captions, implicit boundaries, stale slots and a move back to the same slot. A whole-line move kept surrounding indentation and CRLF. |
| Source and storage suites | 89 Node tests and 28 Swift tests passed. They cover the canvas, document editing, source ranges, Layers, byte-range reads, image recipes, encodings, conflicts and portable snapshot export. |

## Original five workflows

| Workflow | Evidence obtained on Linux | Mac step pending |
|---|---|---|
| Open, save, reopen untouched | SHA-256 matched for the standalone instrument and all five original site files. A separate visual text edit, diff, save and reopen produced the expected bytes. | Repeat through native file panels and the packaged app. |
| Flex insertion and mobile CSS | Chromium exercised the drop, source patch, desktop and mobile layouts, winning declaration and affected count. The disk fixture checked the two edited files. | Physical palette drag, native Inspector and Undo/Redo across views. |
| Build a Field Instrument | Generated a click handler, saved a standalone HTML file and opened it via file URL in Chromium. Entering 25 °C produced 77 °F. The voltage-divider template returned 2.500 V and rejected invalid inputs. | Operate it in Run, then open the saved file independently in Safari. |
| Move a workbench object | The disposable page kept its new coordinates, original pointer behavior, local link and ODIN keyboard handler in Chromium. | Use a mouse and trackpad in WebBench and exercise the reopened page in Safari. |
| External stylesheet conflict | The Swift store surfaced the conflict and preserved the draft, baseline and external contents. | Operate the native conflict dialog and inspect the recovered files in Finder. |

## Additional checks

The photo round trip transformed a 23,040,140-byte TIFF into a cropped, rotated and mirrored 360 × 640 PNG with a monochrome filter and instant-print border. The result was 194,352 bytes. The test used the production Swift photo recipe and Pillow codecs. The HTML change was confined to the selected src value and the original file retained its SHA-256. The ICO decoder test independently checked the RGB and alpha channels at 16, 32 and 48 px. Mac ImageIO, Finder drops, playback of local media in WKWebView, and Safari icon and photo display still need native acceptance.

The 16 production Swift files were checked against the macOS SDK with warnings treated as errors. Both arm64 and x86_64 executables were cross-compiled and linked for macOS 15. The Xcode project's source and resource membership, shared scheme and native test source syntax were checked. The bundle is ad-hoc signed. Verification covered both slices' signed code pages and Info.plist and resource-seal digests, archive extraction and executable permissions. Apple codesign, Gatekeeper, native startup and the hosted XCTest suite require a Mac.

## Reproduce the checks

From the extracted WebBench folder, run the portable suites and storage fixtures with Node and Swift installed.

    node --test Tests/*.test.cjs
    swift test
    node Tests/roundtrip.cjs

The browser fixtures require Python with Playwright, a compatible Chromium executable, Node and Swift. Set CHROMIUM to the executable path as needed.

    python3 Tests/layers-browser.py
    python3 Tests/browser_fixtures.py

The icon and photo fixtures also use Pillow. Checksums and byte-comparison results appear in roundtrip-results.txt.

    python3 Tests/icon-roundtrip.py
    python3 Tests/photo-roundtrip.py

On a Mac, choose **File → Run Sample Checks…** to run all thirteen in-app groups against disposable projects. Group 13 inserts a button into nested Flex, moves it into an empty container, checks native Undo and Redo, adds a disclosure and reopens the saved page. Use **Open instrument in Safari** to record the independent browser result. The physical drag, keyboard, playback and export checklist is in **ACCEPTANCE.md**. Run the hosted suite with `bash scripts/test-macos.sh`.
