# WebBench 0.15.0 validation

**Mac workflows exercised for this release on this host: zero.** This build ran on Linux with an Apple macOS 15.2 SDK, a Swift cross-toolchain and headless Chromium 157.0.8103.38. The macOS target and browser engine matter here. The browser fixtures exercise the actual canvas scripts with a test bridge, and the Layers tests call the production Swift destination planner. AppKit event delivery, SwiftUI row dragging, WKWebView and Safari require a Mac.

## Snippets and embeds

| Workflow | Observed on Linux |
| --- | --- |
| Add and revise snippets | Literal HTML and JavaScript remained display text. A change to one line retained existing character references. Multi-element HTML fragments preserved scripts, comments and line endings. Malformed or structurally ambiguous input was rejected before mutation. |
| Edit iframe fields or provider code | Changing a URL in an imported iframe preserved quoting, sandbox, title, lazy loading and fullscreen attributes. Pasted markup, inline srcdoc, position and style entities survived save and no-op reapplication. |
| Design selection | Headless Chromium rendered the production annotated HTML with page scripts blocked. A real pointer click selected the placeholder, double-click requested the snippet editor and a corner drag generated the resize operation. Neither the local child nor the simulated provider received a Design request. |
| Run and export | The fixture's pulse button and inline signal slider worked. With a loopback policy mirroring offline Preview, the local frame ran and a second-origin provider was blocked. The exported file opened independently, loaded the local page and successfully interacted with the second-origin test provider. The Swift store preserved BOM, CRLF and saved bytes after runtime interaction. |

The cross-built universal app includes the native editor sheet and stricter subframe navigation checks. Native sheet interaction, text-field undo, AppKit drop, isolated WKWebView navigation and launching the default Mac browser are pending. The provider test used a disposable HTTP origin. Live commercial embeds and their site-specific HTTPS restrictions were not exercised. A hosted XCTest for the native snippet model and Undo/Redo was syntax-checked on this host.

## Layout shapes

The Layout drawer has 24 shapes, including the three original choices. Chromium compared screenshots of all 24 HTML/CSS templates against paths drawn from their native palette geometry descriptors. The rendered fixture canceled a heart drag, dropped a star onto a free canvas, dropped an arrow into Flexbox, selected the star and dragged its corner from 110 × 104 to 170 × 143. The Inspector paint bridge changed only the selected fill. The production Swift store saved, reopened and exported the BOM/CRLF HTML. The independent file-URL render retained the dimensions, color and silhouette. Source tests also inserted, resized, recolored and deleted each shape and compared the surrounding bytes.

The production Swift model decoded the 77 catalog entries in v0.14. The universal app was cross-compiled for macOS 15 with the shape drawer and preview drawing code. The hosted shape catalog and Undo/Redo XCTest was syntax-checked. The native SwiftUI tile appearance, physical Mac drag and independent Safari rendering still need a Mac run.

## Device workflows

The v0.13 portable fixtures exercised the emitted Device Workbench HTML served from localhost. Chromium used its synthetic camera and audio source with the real media-capture, video, canvas and Web Audio APIs. Web Serial and WebUSB used instrumented API doubles. The serial/USB OS chooser and physical transport were not exercised.

| Check | Observed result |
| --- | --- |
| Camera and microphone | Started live video, read frame dimensions and produced a PNG snapshot. The microphone meter reported a nonzero level. Each Stop ended its track and pagehide ended a running microphone. Denied access produced actionable feedback. |
| Serial | UTF-8 split across packets and two buffered lines decoded correctly. Sending from a page field emitted its exact UTF-8 text and LF. Stop released pending reads and locks. Unplug and a late chooser result allowed a fresh connection. |
| USB | Bulk IN and interrupt OUT used the configured endpoints and bytes. A DataView with a nonzero offset produced BE EF. Invalid hex, an interface claim failure, a stalled transfer and a short write produced errors. Closing canceled a pending transfer and unplug released the device. |
| Preview | A Chromium harness selected the same simulation branch used by the WebBench custom scheme. All four device families operated with zero device API requests. The native WKWebView run still needs macOS. |
| Source and export | All 13 example workflows reopened through the production Swift model and regenerated identical bytes. Added, shared, removed and manually modified support blocks were checked. The Swift store saved and exported a UTF-8 BOM/CRLF fixture. Its bytes stayed identical after simulated I/O and synthetic media capture. |
| Mac acceptance | Both architecture builds include the new UI and camera permission delegate. A hosted XCTest for camera target picking, source insertion, native undo/redo and removal was syntax-checked. Native execution and physical devices remain pending. |

## Expanded interactions

| Check | Observed on Linux |
| --- | --- |
| Native model data | The production Swift workflow record and step types decoded both example catalogs. Their outgoing payloads regenerated both HTML files byte-for-byte. |
| v0.11 compatibility | A fixture using all eleven original actions reproduced the exact SHA-256 digest generated by the previous release. The original Signal check example also reopened unchanged. |
| Conditions and arithmetic | Exported HTML ran all eight predicates, all four operations, two live operands, fixed negative operands, precision and units. Blank and nonnumeric operands, division by zero and overflow ran the error path and stopped subsequent steps. |
| Events and targets | Chromium exercised all eight new triggers, focus transfer, scrolling with reduced motion, checkbox state, enable/disable, form reset, CSS classes, disclosure state, copying literal text and actual media playback and pause. |
| Power meter | The standalone HTML displayed 3.00 W for 12 × 0.25. Clearing voltage selected the warning branch. Restoring it to −5 cleared the warning and displayed −1.25 W. |
| Source preservation | The production Swift store saved, reopened and exported the test page. The BOM, CRLF and exact source bytes survived. Runtime actions left both saved files untouched. A missing operand and a modified handler were refused by the authoring engine. |

The new **File → Run Sample Checks…** group 14 is cross-compiled into the app. It exercises the native model, edits precision, checks Undo/Redo, saves and reopens, then runs both branches inside WKWebView. This group, physical canvas picking, the expanded native controls and independent Safari acceptance still require a Mac run.

## Visual interactions

The source tests exercised exact no-op regeneration, targeted ID patches, two separate handlers, multiple same-tag targets, moved and missing elements, hand-edited scripts, literal script terminators and invalid file destinations. A hosted macOS XCTest covers the Session, canvas-target assignment, native Undo/Redo, reopening and removal. Only its syntax was checked on this Linux host.

The browser harness saved and reopened a BOM/CRLF page through the production Swift store and exported it with a PDF. Chromium ran the exported handlers against a disposable loopback server.

| Check | Observed result |
| --- | --- |
| Pick trigger and target | The production canvas script returned both source IDs, intercepted ordinary editing and canceled picking with Escape. Normal selection resumed afterward. |
| Change text and colors, hide, show and toggle | Text remained literal. Both computed colors matched. A flex target recovered its display mode. The existing inline click handler ran once. |
| Run ordered actions | A modal interrupted the sequence until dismissal. An input event also showed its target. |
| Choose a file | The selected filename appeared in the output. |
| Download files | Both the linked PDF and generated UTF-8 text downloaded with the expected names and exact bytes. |
| Upload | The local server received the specified multipart field, filename and bytes. Cancel made no request. A 503 response stayed in the dialog for retry. A subsequent 201 advanced to the next step. |
| Preview transport | Injecting the WebBench scheme into the emitted handler exercised the rehearsal branches without a network request. This was a browser harness simulation. |
| Reopen and run independently | All seven fixture workflows regenerated byte-for-byte after save and export. The bundled Signal check instrument also ran directly from a file URL in Chromium. |

The native Interactions window layout, SwiftUI controls, macOS file picker, WKWebView isolation and independent Safari downloads and uploads still need a Mac run.

## Workspace refresh

The blank-canvas test rendered the production overlay in Chromium. The page body remained the pointer target under the guide. Hover, cancel and click-to-place hid and restored the guide at the expected times. Placing a heading produced its requested coordinates and exported HTML containing just the authored element. A page containing existing text did not display the guide. A Swift test folded nested layers and verified visible sibling order. The Mac acceptance checklist covers the AppKit tile face, panel layout, keyboard focus, popovers and light/dark appearances.

## Nested insertion and Layers

| Check executed | Observed result |
|---|---|
| Palette hover, drop and click | A real Chromium layout displayed the insertion preview. A button landed in the nested flex row, a disclosure landed in an empty div, and a card landed in the grid. |
| Layers before, inside and after | Production Swift accepted the three destinations and the source engine moved the corresponding subtrees. After save, export and reopen, the HTML retained its BOM, CRLF and working hyperlink. |
| Insert catalog | All 56 tiles produced a single root with the expected tag in a compatible parent. Chromium parsed each template. |
| Unsafe and redundant changes | Tests covered cycles, incompatible list and table children, nested forms, captions, implicit boundaries, stale slots and a move back to the same slot. A whole-line move kept surrounding indentation and CRLF. |
| Source and storage suites | 118 Node tests and 29 Swift tests passed. They cover the canvas, document editing, source ranges, Layers, byte-range reads, image recipes, encodings, conflicts and portable snapshot export. |

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

The 19 production Swift files were checked against the macOS SDK with warnings treated as errors. Both arm64 and x86_64 executables were cross-compiled and linked for macOS 15. The Xcode project's source and resource membership, shared scheme and native test source syntax were checked. The bundle is ad-hoc signed. Verification covered both slices' signed code pages and Info.plist and resource-seal digests, archive extraction and executable permissions. Apple codesign, Gatekeeper, native startup and the hosted XCTest suite require a Mac.

## Reproduce the checks

From the extracted WebBench folder, run the portable suites and storage fixtures with Node and Swift installed.

    node --test Tests/*.test.cjs
    swift test
    node Tests/roundtrip.cjs

The browser fixtures require Python with Playwright, a compatible Chromium executable, Node and Swift. Set CHROMIUM to the executable path as needed.

    python3 Tests/devices-browser.py
    python3 Tests/snippets-browser.py
    python3 Tests/shapes-browser.py
    python3 Tests/workflow-values-browser.py
    python3 Tests/interactions-browser.py
    python3 Tests/studio-guide.py
    python3 Tests/layers-browser.py
    python3 Tests/browser_fixtures.py

The shape, icon and photo fixtures also use Pillow. Checksums and byte-comparison results appear in roundtrip-results.txt.

    python3 Tests/icon-roundtrip.py
    python3 Tests/photo-roundtrip.py

On a Mac, choose **File → Run Sample Checks…** to run all fourteen in-app groups against disposable projects. Group 13 inserts a button into nested Flex, moves it into an empty container, checks native Undo and Redo, adds a disclosure and reopens the saved page. Use **Open instrument in Safari** to record the independent browser result. The physical drag, keyboard, playback and export checklist is in **ACCEPTANCE.md**. Run the hosted suite with `bash scripts/test-macos.sh`.
