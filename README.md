# WebBench

WebBench is Green Shoe Garage’s native macOS WYSIWYG editor for HTML, CSS and JavaScript. Open a single-file Field Instrument or an existing site folder, move an element on the rendered page, inspect the source diff, and save back to the original files.

**Version 0.15.0 · Developer preview · macOS 15 or later**

## Open the included app

Extract the ZIP in Finder, open the **WebBench** folder and double-click **WebBench.app**. The included v0.15.0 developer preview is built for Apple silicon and Intel Macs with macOS 15 or later. Xcode is only needed for building from source. The app is ad-hoc signed. If macOS declines to open the preview, use the local build instructions below.

The repository tracks the full app bundle beside its source. To publish, commit the extracted folder using Git or GitHub Desktop on your Mac so the app's executable permission is recorded.

## Add code and embeds

Open **Insert → Code & embeds** and drag a tile onto the canvas or into a container. **Code snippet** displays copyable code. **Custom HTML** accepts a fragment with multiple elements, CSS and JavaScript. **Iframe embed** accepts a page URL, a relative project path, or pasted provider markup. Double-click the placed item or use its **Edit** button in the Inspector to reopen it.

Design shows selectable iframe placeholders. In-app Preview runs the widget scripts and loads local project frames and inline frames. Choose **File → Preview Website in Browser** to open a temporary snapshot with online embeds enabled by the browser. The included Signal notes page has a code example, a working pulse counter and a self-contained iframe. [Open the example](Fixtures/Snippets-and-embeds.html)

## Build a device interaction

Choose **File → Try Device Workbench**, then **Apply & preview → Connect serial → Send line → Read line**. The readout echoes **PING**. The same example has a USB byte console, camera with snapshot button and a live microphone level meter. Each control opens as an editable workflow. [Standalone Device Workbench](Fixtures/Device-workbench.html)

For your own page, add a button and a suitable output. Select the button, choose **Interactions**, then choose an action under **Serial port**, **USB device**, **Camera** or **Microphone**. Click **Pick** to select a readout, video, image or meter on the canvas. Add a separate Stop or Disconnect button to release the device.

WebBench Preview simulates these devices. To use physical hardware, export the website and open it over HTTPS or localhost. Desktop Chrome supports the serial and USB choosers. Each visitor grants access in their browser. The example guide includes local serving instructions and USB protocol settings. [Device workflow guide](docs/USER-GUIDE.md#device-workflows)

## Try a no-code power meter

Choose **File → Try Power Meter Workflow**. The button checks the form, multiplies the voltage and current, and displays the result in watts. Choose **Apply & preview**, then **Measure power**. At 12 V and 0.25 A the readout shows **3.00 W**. Clear either input and press the button again to exercise the **Otherwise** branch. [Standalone DC Power Meter](Fixtures/Power-meter.html)

On your own page, select a trigger and open **Interactions**. Pick live values from the canvas, set a condition, and add steps to **Then** and **Otherwise**. The 34 actions cover devices, arithmetic, live values, appearance, forms, media, navigation within a page, dialogs and files. The 11 triggers include submission, keyboard, focus and pointer events. Each workflow is saved as ordinary JavaScript.

## Make a button do something

Choose **File → Try Interaction Example** to open a fresh copy of *Signal check*. Its **Test signal** button already has three actions. Choose **Apply & preview** and press the button to see the readout change. The second button downloads a field note from the same HTML file. [Open the standalone example](Fixtures/Signal-check.html)

On your own page, select a button and click **Interactions**. Under **When**, choose the event. Under **Then**, choose **Change text**, click **Pick**, click a result display on the canvas, and enter the new text. **Add action** appends another step. Use a step’s **…** menu to reorder or remove it. **Apply** commits the workflow as one undoable edit. **Apply & preview** also runs it.

Actions can change text and colors, show or hide elements, open a dialog, download a project file or a generated text file, choose a local file and display its name, or upload it. Uploads need a receiving server address and file field name. Preview rehearses transfers locally. A published upload sends a multipart POST after the visitor selects a file and presses **Upload**.

## Build from source

Install full Xcode 16.2 or later. Open [WebBench.xcodeproj](WebBench.xcodeproj), select the **WebBench** scheme and **My Mac**, then press **⌘R**.

To build a locally signed Release app, double-click **Build-WebBench.command** in Finder or run this from the repository root.

```sh
bash Build-WebBench.command
```

The script prints the path to the app and its ZIP, and reveals the app in Finder. Build logs are under `build/local.*/build.log`. If the script cannot find Xcode, select your installed Xcode under **Xcode → Settings → Locations → Command Line Tools**.

## Place a shape

Open **Insert → Layout → Shapes** and drag a silhouette onto the page. Search **Shapes** to show all 24, or type **arrow** to see the four directions. Select the shape, drag a corner to resize it, and use **Element background** in the Inspector to change its fill. The saved shape is ordinary HTML and CSS and works offline.

## At the workbench

Start with a blank sheet and drag a card from **Insert → Parts drawer**. The trays fold, and a search looks through all 80 elements. Double-click placed text to write. Select an object to bring its type, color and size into the Inspector. Open **Page** above the canvas for its background, favicon, title and height.

The screen-size controls sit below the canvas. Choose a screen or click its dimensions to scrub the width. **Preview** runs the page and **Stop preview** brings you back to editing. The bottom status bar opens the source diff.

## Try a source-preserving edit

1. Open a disposable copy of the bundled [sample site](Fixtures/Site) as a folder. WebBench starts in Edit mode with page scripts inactive.
2. In **Insert**, drag **Button** into the flex row. Check the destination label before releasing. For an empty or covered container, select it in **Layers** and choose **Add inside**.
3. Drag the new layer above or below a sibling. Drop in the middle of another compatible container to nest it. Choose **Review changes** in the bottom bar, undo the move, then redo it.
4. Switch between phone and desktop widths. Choose **Preview** to exercise the page scripts in the isolated preview. Save and open the same HTML in a browser.

Visual operations patch mapped source ranges. Opening and saving an untouched page preserves its bytes, including its encoding and line endings. If WebBench cannot map an edit, it directs you to the source. A conflicting external save keeps recovery copies under `~/Library/Application Support/Green Shoe Garage/WebBench/Recovery`.

## Editor features

- **Visual interactions** with ordered actions, canvas target picking and ordinary JavaScript embedded in the page.
- **Design, Code and Split views** with a WebKit canvas, document tree and CSS inspector.
- **80 searchable Insert elements** for free-position pages, semantic sections, Flexbox, Grid, typography, forms, tables and local media.
- **Direct editing** with resize handles, type and color controls, breakpoint-specific placement, nested Layers and native Undo/Redo.
- **Offline assets and export** with photo resizing, crop, filters, borders, a favicon editor, single-file HTML and portable site folders.

## Test

On macOS with full Xcode, run the storage tests and hosted native tests from the repository root. The script also runs the JavaScript and disk round-trip checks when Node is installed.

```sh
bash scripts/test-macos.sh
```

For portable tests, use Swift and Node. The recorded preview checks used Swift 6.0.3 and Node 24.

```sh
swift test
node --test Tests/*.test.cjs
node Tests/roundtrip.cjs
```

In the app, **File → Run Sample Checks…** runs fourteen workflows on disposable files. The v0.15.0 release was cross-built for Apple silicon and Intel. Its recorded browser checks used Chromium on Linux. Native drag gestures and independent Safari verification are pending. [Validation record](docs/VALIDATION.md) · [Mac acceptance checklist](docs/ACCEPTANCE.md)

## Repository guide

| Directory | Contents |
| --- | --- |
| [Sources](Sources) | SwiftUI and AppKit workspace, WKWebView bridge, source storage and native editing tools |
| [Resources](Resources) | Canvas and source-editing JavaScript, starter HTML, app icon and Info.plist |
| [Fixtures](Fixtures) | Standalone Field Instrument and a multi-file test site |
| [Tests](Tests) | Swift, JavaScript, disk round-trip and browser workflow tests |
| [scripts](scripts) | Local build and native test commands |

[First run](START-HERE.txt) · [User guide](docs/USER-GUIDE.md) · [Architecture](docs/ARCHITECTURE.md) · [Roadmap](docs/ROADMAP.md)
