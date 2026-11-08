# WebBench user guide

## Code snippets and embeds

Open **Insert → Code & embeds**. Drag the tile to its destination. You can also select a container in Layers and use **Add inside → Code & embeds**. The sheet opens before anything changes in the page. **Insert** commits one undoable edit. Cancel discards the draft. Double-click the resulting element or use **Edit** in the Inspector to revise it.

| Tile | What to enter | What visitors get |
| --- | --- | --- |
| Code snippet | The text of an HTML, CSS, JavaScript or other code example | A selectable, copyable preformatted code block. Indentation, line breaks, angle brackets and ampersands appear as text. |
| Custom HTML | A body fragment. Include CSS inside `<style>` and JavaScript inside `<script>`. A provider widget with several tags and a loader script belongs here. | The fragment renders inside a movable HTML container. Its scripts can run in Preview and in the browser. |
| Iframe embed | Choose **Embed URL** and enter an address and accessible title, choose another HTML page in the project, or choose **Paste embed code** for a complete `<iframe>…</iframe>`. | A frame that retains authored dimensions and provider attributes such as `allow`, `sandbox`, `loading`, `referrerpolicy` and `srcdoc`. |

For example, open the standalone [Signal notes fixture](../Fixtures/Snippets-and-embeds.html). The top block displays button markup verbatim. In Preview, **Send pulse** increments the counter. The lower slider updates a percentage inside a sandboxed inline frame. Stop Preview, double-click the frame and edit its embed code. For an existing URL-based iframe, the **URL and title** view updates only the fields you change. Apply edits in one view before switching to the other.

**Design** keeps page scripts inactive and replaces each frame’s live document with a selectable placeholder. Drag the frame or select it in Layers. Use its resize handles or Inspector size controls. **Preview** can load an inline `srcdoc` document or another local page. Open the enclosing site folder to make linked pages available. Remote widget scripts and frames stay offline inside the app.

**File → Preview Website in Browser** writes a temporary copy of the current page and site files and opens it in your default browser. Use this to test a provider’s embed URL. A provider can restrict which sites may frame its content, or require an HTTPS origin. Use its official embed code and test on the intended host when needed. Choose **Export Website Folder…** to keep a publishable copy.

Plain preformatted blocks and existing iframes can be reopened through the same Inspector. A code block with syntax-highlighting spans or character references that WebBench cannot safely map opens in Code. An invalid fragment stays in its editor with an explanation.

## Interactions

Select a button, link or input, then choose **Interactions** in the toolbar or Inspector. **File → Try Interaction Example** opens an editable Signal check instrument with two working workflows. The example uses its own draft folder on each opening.

1. Under **When**, pick the trigger on the canvas or use the searchable element list. Choose click/tap, double-click, input as you type, committed value, form submission, focus gained or lost, pointer entry or exit, or the Enter or Escape key. For form submission select the form. **Handle submission in this workflow** keeps the visitor on the page. Browser form validation normally runs before a submit event. To show custom feedback for invalid input, use the button’s click trigger as in the power meter.
2. Under **Then**, click the action name to choose its behavior. For an action that changes another element, click **Pick** and click that element on the canvas. Escape cancels the pick. The searchable list also includes hidden elements.
3. Use **Add action** to chain steps. Each **…** menu moves a step earlier or later or removes it. A message waits for dismissal. A file step waits for the visitor. Canceling file selection ends that run.
4. **Apply** updates the page. **Apply & preview** commits the same edit and starts Preview. Use **Stop preview** to return to the editor. **Review changes**, Undo, Redo and Save use the same working source as Code view. A draft can be canceled before applying.
5. Reopen **Interactions** on the trigger to revise it. **Page workflows** lists existing handlers and starts a new one. Each element can have one workflow per event. **Remove workflow…** removes that handler. Existing element IDs remain available to CSS and other scripts.

### Device workflows

**File → Try Device Workbench** opens an editable page with all thirteen device actions. **Apply & preview** starts the local simulation. To build a camera tool from a blank page, insert a **Video**, an **Image** and three **Buttons**. Give the buttons the labels **Start**, **Snapshot** and **Stop**. Select Start, open **Interactions**, choose **Camera → Show live camera**, then **Pick** the video. Give Snapshot the **Take a snapshot** action and pick the image. Give Stop the **Stop camera** action. Click **Apply** after each workflow. Preview the page and press the three controls in order.

| Action family | What you can build | Settings and outputs |
| --- | --- | --- |
| Serial port | Connect, send text, read one line, disconnect | Set the firmware’s baud rate. The connection uses 8 data bits, no parity and one stop bit. Send fixed text or the current value of a page element. Choose LF, CRLF or no line ending. Incoming UTF-8 lines end with LF or CRLF and appear in the selected readout. |
| USB device | Connect, send a packet, read a packet, disconnect | Optionally filter by four-digit hex vendor and product IDs. Select configuration, interface and alternate setting in the Connect action. For each transfer, set a bulk or interrupt endpoint number (1–15). Reads accept up to 4096 bytes and display hex pairs. Writes accept hex pairs from a fixed value or page element. |
| Camera | Start live video, take a still, stop | Pick a Video element for the muted feed and an Image element for each snapshot. A snapshot is a PNG in the running page. The visitor can save the displayed image using browser image controls. |
| Microphone | Start a level meter, stop | Pick a Meter, Progress or text readout. The meter tracks RMS amplitude as a percentage of full scale and resets on Stop. This action measures level locally. It produces no recording. |

Use a dedicated button for each Start or Connect action and put that step first. The exported page opens the browser’s permission or device chooser after the visitor acts. Other buttons on the page can share the connection. Each device family supports one active connection. A denied request, unavailable API, incompatible endpoint or failed transfer displays a status message and ends that branch. Stop or Disconnect cancels a pending read. The page releases its devices when it is left.

**Testing physical devices.** Choose **File → Export Website Folder…**. Serve that folder over HTTPS, or run the following command in the folder with Python 3 installed.

```sh
python3 -m http.server 8000 --bind 127.0.0.1
```

Open `http://127.0.0.1:8000/` in desktop Chrome and press the page’s Start or Connect button. Close any serial monitor that already owns the port. For a board that exposes a serial console, choose **Serial port**. For a vendor-specific USB protocol, use the interface, endpoints and command bytes documented for that device. The Device Workbench defaults are editable examples. Chrome’s USB picker may exclude protected interfaces or interfaces claimed by an OS driver. Camera and microphone capture also require browser and OS permission. Stop the local server with Control-C when finished.

Preview uses a simulated serial port, USB loopback, color-bar camera and changing microphone meter. Simulation helps wire the page before a device is available. The published HTML contains its own support code. A captured frame, a received reading or an active permission exists only in the running page.

[Chrome Web Serial guide](https://developer.chrome.com/docs/capabilities/serial/) · [Chrome WebUSB guide](https://developer.chrome.com/docs/capabilities/usb) · [W3C Media Capture and Streams](https://www.w3.org/TR/mediacapture-streams/)

### Calculations and conditions

Choose **File → Try Power Meter Workflow** for a self-contained working example. In a new workflow, choose **Values and math → Calculate a result**. Pick a result display and a first value. Choose Add, Subtract, Multiply or Divide. For the second value, pick another element or enter a fixed number. Choose the decimal places and an optional suffix, such as a space followed by W. A blank input, nonnumeric reading, division by zero or nonfinite result displays your invalid-result message and ends that branch. Use an Output or text element for formatted results. Keep intermediate numeric results free of suffixes when another step reads them.

Enable **Check a condition** and pick an element. Text tests cover empty, filled, equality and containment. Numeric tests compare a reading with a threshold. A checkbox or radio can be tested for its checked state, and a form or field can be tested for browser validity. Each event evaluates the condition once and runs the chosen branch in order. **Otherwise** may be left empty. Turning off the condition keeps the alternate steps in the current draft until you apply.

| Action | Visitor experience |
| --- | --- |
| Copy a live value | Reads the selected field, output or text element when the event occurs, adds an optional prefix and suffix, then writes to the destination. |
| Calculate a result | Reads live operands, performs arithmetic and writes a formatted result. |
| Change a CSS class | Adds, removes or toggles one class. Choose a class already used on the page or enter a class name from your stylesheet. |
| Enable or disable a control | Changes the disabled state of a field, select, fieldset or button. |
| Set a checkbox or radio | Checks, unchecks or toggles the control. |
| Reset a form | Restores the form’s original field values. |
| Focus an element | Moves keyboard focus to the chosen focusable element. |
| Scroll to an element | Scrolls the target into view and respects the visitor’s reduced-motion setting. |
| Open or close details | Opens, closes or toggles an HTML disclosure element. |
| Play or pause media | Controls a selected audio or video element. Use a click trigger for playback in browsers that require a user gesture. |
| Change text | Replaces the target’s text, or sets the value of a text field or output. Markup entered here displays as plain text. |
| Text or background color | Applies the chosen color to the target. |
| Show, hide or toggle | Changes the target’s visibility. A previously visible flex or grid element recovers its layout when shown again. |
| Open a dialog | Opens a keyboard-accessible modal with a title, message and Close button. |
| Download a site file | Offers the selected relative file with an optional download name. Keep the file beside your page or export the site folder with its assets. |
| Download a text file | Creates the download from the name and contents in this workflow. It works in a standalone HTML file. |
| Choose a file and show its name | Displays the chosen filename in a target. The file stays on the visitor’s device. |
| Upload a file | Shows the destination and asks the visitor to select a file and press Upload. A successful HTTP response advances the workflow. An error stays in the dialog for retry or cancellation. |

Enter the URL supplied by your upload service and its multipart field name (commonly `file`). A relative endpoint such as `/uploads` resolves against the published site. An endpoint on another origin must allow the page’s origin. WebBench’s isolated Preview simulates the transfer. Export and use your test endpoint in a browser to exercise the server. A static site needs an upload service to receive files.

WebBench writes a short configuration comment and JavaScript into one ordinary script per workflow. Elements get a stable ID only when referenced. If you edit a generated script by hand, WebBench takes you to the changed block in Code view. Other authored scripts can be maintained alongside it.


## Find your way around

**Insert** opens the Parts drawer. Expand a tray to browse, or type a name or tag to search across all trays. Clearing the search restores your expanded and collapsed trays. **Layers**, **Pages** and **Files** sit alongside Insert. Layers can fold a section or reveal the ancestors of an object selected on the canvas. Code opens Files, and returning to Design restores the previous panel when Files is still active.

**Preview** runs the page. Select **Console** below the device controls to see messages. A JavaScript error or unhandled rejection opens the console. **Stop preview** returns to editing. The status bar shows **View diff** on a saved page and **Review changes** after edits.

## Work on the page

| To | On the canvas |
|---|---|
| Add an object | Drag a tile from Insert. Read the destination label, then release. Select a container and click a compatible tile to append a child. On a free page, choose Page canvas to place overlapping siblings. |
| Move and size it | Drag the object. Drag an edge to resize one dimension or a corner to resize both. Shift-drag a corner to keep proportions. Option bypasses snapping. Inspector → Resize also provides a live slider and exact pixel input for each dimension. |
| Write and style | Double-click words to type. Select words for a typeface, size or text-color change. With an object selected, open Inspector → Style for its typeface, size and colors. Element background changes its fill. Page → Page background works with no selection. Press Escape or choose Done typing to return to layout. |
| Arrange layers | Select a covered object in Layers. Command-click positioned siblings to move them together. Align to the first selection or distribute three or more with equal gaps. Arrow keys nudge, Shift-arrow moves 10 px, and Delete removes the selection. |
| Preview a screen | Choose Phone, Tablet or Desktop below the canvas. At narrow widths, open the device menu. Rotate or click the dimensions for a custom size. Fit shows the device area in the available workspace, while 100% supports panning. The page can scroll inside the viewport. |
| Adapt placement | On a free page, the scope control defaults to All widths. Choose Only this breakpoint for a phone, tablet or desktop position or size. The bands are up to 600 CSS px, 601–1024 px and 1025 px or wider. Switching preview sizes alone leaves the source intact. |
| Test and publish | Click Preview to use the site. Choose Export → Website folder to write the current project into a fresh directory containing index.html. Try it in Safari, then upload its contents. Choose Current HTML file for a single-file app with embedded assets. |

**Page** sets the tab title and minimum height. The object inspector includes exact dimensions, typography, corner radius, layout, stacking and CSS inspection. Source and Diff remain available for precise edits. On a free canvas, dimensions and positions are explicit. Place or resize parts at smaller breakpoints when a desktop composition needs a different arrangement. Installed fonts use CSS fallback families on other machines. A folder project can carry its own linked fonts.

## Build inside containers and rearrange Layers

Drag **Button** into the middle of an existing section or div. The label identifies its parent and the insertion point before you release. Flex rows and grids keep their layout. For an empty, covered or zero-height container, select its **Layers** row and choose **Add inside → Essentials → Button**. You can also select the container, switch to Insert, and click a compatible tile. On a free page, **Container** is the default drop mode. Choose **Page canvas** when you want an independent object over an existing section.

In Layers, drag a row to the top or bottom edge of another row to move it before or after that element. Drop on the highlighted middle of a compatible row to nest it. A moved section carries its contents. With a single layer selected, **Option-Command-Up/Down** changes sibling order. **Option-Command-Right** nests it in the preceding compatible sibling, and **Option-Command-Left** moves it out one level. The same actions are available from the buttons above the tree and its context menu.

Layers changes HTML source order. An existing absolute position, explicit CSS Grid placement, Flex order or z-index can affect where a moved part appears. To let a positioned part participate in its new layout, select it and choose **Inspector → Arrange → Use normal flow**. Check **Diff**, then try Undo and Redo before saving.

Open **Insert → Layout → Shapes** for rectangles, rounded shapes, polygons, four directional arrows, a chevron, star, heart, plus, speech bubble and line. Search **Shapes** to see every silhouette together. Drag one onto the free canvas, into a section, or between Flexbox and Grid children. In Layers, select a container and choose **Add inside → Layout → Shapes** to insert by name. Click the filled area to select it. The resize handles sit on the rectangular selection bounds, including corners outside a clipped silhouette. Hold Shift while dragging a corner to keep its proportions. Change **Element background** in the Inspector to recolor it. The new shapes have named classes in HTML and readable names in Layers.

**Insert** has 80 searchable choices across Essentials, Layout, Landmarks, Text & lists, Media & data, Forms, and Code & embeds. Try a responsive grid, navigation, disclosure, table, captioned figure, audio or video player, dropdown, date field, range slider or progress bar. Search by display name or HTML tag. List items belong in lists, table cells in rows, and options in dropdowns. Select an audio or video element and choose **Choose media file…** in the Inspector. Open a site folder to link large media files by relative path.

## Import and edit photos

Drop a photo from Finder onto the canvas, or place **Image** from Insert and choose a file. In Write, drop it in a paragraph or use **Image…** at the caret. When a photo exceeds the current page’s budget, **Resize photo for this page** opens with a proposed web-sized copy. Compare **Original** and **Edited**, check the resulting dimensions and encoded size, then choose **Resize and insert**. Cancel leaves the page as it was. A web-ready photo that fits can be inserted with its original bytes.

Select an image on the canvas and click **Edit photo…** in **Inspector → Style**. In **Crop**, drag a rectangle or choose a preset. Rotate left or right, mirror, choose a longest edge, and adjust brightness, contrast and saturation. Try Black & white, Sepia, Warm, Cool or Vivid. Borders include Solid, Double line, Mat and Instant print. Set the border color and thickness, then return to **Edited** to preview the finished image. Borders are drawn inside the image so the output dimensions stay predictable.

**Apply to photo** updates the selected image. A site folder gains a portable copy under assets. A single-file page, or a page that sets its own base URL, embeds the result. Other references to the same original keep their image. Use **Diff**, **Undo**, and **Redo** as with other visual changes.

The editor creates a still JPEG or PNG, with a maximum requested longest edge of 4096 px. Automatic format can retain transparency as PNG. JPEG uses white behind transparency. Animated or multi-page inputs use their first frame when edited. WebBench fits the encoded copy to the available room, up to 2 MiB for embedding or 12 MiB for a linked copy. The preview reports the actual dimensions after fitting. The original keeps its metadata and full resolution. For a responsive picture or srcset, WebBench takes you to Code to select the intended source.

## Inspector, backgrounds and favicons

**Inspector** is the right sidebar. It starts open, stays visible while typing, and remembers an explicit show/hide choice across launches. Click **Inspector** or press **Option-Command-I**. From Code the same command opens Split with the Inspector visible. Select a page object for Style, Arrange and Inspect. While typing the panel follows the current text block. Choose **Inspect block layout** to see its geometry and CSS.

**Page → Page background** above the canvas colors the whole document, including the area outside a short body. **Element background** in the Inspector colors the selected object. Choose a swatch, enter six or eight hex digits, or choose Transparent. If the target has a background image or gradient, the picker offers **Keep background image or gradient**. Applying a solid color overrides the image on that target when this option is off. The editor preserves authored image URLs and gradients in source. An ordinary page or element color change is one document undo.

Use **Page → Edit favicon…** above the canvas or **File → Edit Favicon…**. Draw with Pencil, Erase, Fill and Sample. Create initials in the current ink or import artwork and touch up the pixels. The checkerboard shows transparency. Compare the previews at 16, 32 and 48 pixels. A page with several declared browser icons offers a link selector. Local icons can be opened when their files are in the project. A folder's conventional favicon.ico is also recognized if no icon link is present.

**Apply to page** stages one change for the current HTML page. A single-file project embeds a PNG. Folder projects store a portable PNG under assets and preserve other pages that use the original icon. A page with an explicit base URL uses an embedded PNG so its icon resolves reliably. Touch icons, pinned-tab masks and unselected favicon variants keep their original declarations. **Export → PNG** saves the working grid. **Export → ICO** writes a file with 16, 32 and 48 px images. Imported artwork is rasterized onto the chosen grid. Favicon edits stay in the sheet until applied.

## Projects and source

Command-N creates a writable HTML draft. Command-S saves it and **File → Show Project in Finder** reveals its location. To work on an existing site, open its folder. Linked assets keep their relative paths. Use the single HTML option for a self-contained page. Local dependencies of a standalone file are included in a folder export when you open the enclosing site folder as the project.

Opened sites retain their authored flow, flexbox, grid and positioned containers. Supported visual edits patch source ranges. Conflicting external changes produce recovery copies. Unsupported mappings and incomplete markup can be edited in Code. Edit keeps page scripts inactive. Run loads the working source in a separate WebKit configuration. Preview-only selection handles, grid and interaction state never enter exported markup.

The folder snapshot writes the project's HTML, CSS, scripts, fonts and artwork, plus common public media from the opened site including PDFs, audio, video, captions and feeds. A site with its own index.html keeps that entry. A project without one gains a landing page pointing to the selected page or a byte-identical root entry. Export does not publish to a host.
