# Architecture

**Project.swift** owns original bytes, current bytes, supported text encodings and file saves. The Swift package tests compile that same file. Directory ingestion is bounded and rejects symlink traversal. A site is an ordinary directory with no proprietary manifest.

**Session.swift** owns the active page, distinct active code file, mode, immutable preview snapshots, revision gates and app-wide native UndoManager. Code and visual operations both submit source changes. A single undo group can change the HTML and its external stylesheet together. Opening and Layout saves run off the UI thread. In Write, a command barrier drains earlier input messages before saving the current source synchronously. Closing or replacing a dirty project offers a synchronous save.

**Engine.swift and source.js** run trusted range operations in a dedicated JavaScriptCore context. Project text is passed as string arguments. The tokenizer records UTF-16 ranges for start tags, attributes, text and closing tags without reserializing a DOM. CSS editing locates existing rule bodies and value spans with string, function and comment awareness. Optional end tags are supported in common contexts. Invalid nesting, ambiguous duplicate declarations and unsupported embedded markup fall back to direct source editing.

**Canvas.swift** constructs a fresh WKWebView for each accepted snapshot. A custom URL scheme serves the in-memory file map and explicitly indexed large raster and local media assets, which are read on demand from validated project paths. Edit uses allowsContentJavaScript=false and a trusted user script in an isolated content world. Marker IDs and a per-render token correlate native edits with this exact source revision. DOM mapping checks source tags and parentage against the rendered tree.

**writing.js and document.js** implement Write in the isolated content world. Authoritative HTML is indexed in UTF-16. A DOM selection maps to exact source boundaries, including character references and CRLF. Plain input updates one rendered text node when possible. Structural commands reparse the affected block and update its source markers. Swift verifies the preview token, edit sequence, replaced bytes and resulting index before recording the native change. Typing leaves the active WKWebView mounted. Undo, source changes and switching canvas tools create new snapshots. The writing caret, editable attributes and selection styling exist only in the preview. Paste takes the plain-text clipboard representation.

**canvas.js** handles hit testing, source selections, drop indicators and viewport inspection. For a selected property, it enumerates CSSOM declaration candidates and mirrors their priority into a temporary, unique custom property. The browser cascades that property and the script cleans it up immediately. The inspector shows the computed value independently. Complex logical properties, import access, animation and inheritance can defeat exact attribution. Flex/grid indicators refer to DOM insertion order. Explicit CSS grid placement and arbitrary visual reordering may differ from DOM order.

**arrange.js** calculates CSS-pixel moves and resizes from a measured frame. The Select canvas draws its handles and guides in a closed shadow root. During a drag it previews styles locally. Cancellation restores the exact original style attribute. On release it measures the proposed result against the actual layout, restores the preview, then asks the native session to apply one source patch. Ambiguous inline declarations fail in the source engine. The WKWebView’s page zoom and display frame scale together so the authored viewport width remains independent of magnification.

**DesignInspector.swift** provides element-scoped Style and Arrange panels. Explicit free positioning measures the current frame in its parent and verifies that both remain stable during conversion. The page navigator caches up to 24 in-memory viewport thumbnails of visited pages, invalidating them on relevant source changes. Thumbnails stay out of project files.

**Run** starts with the original page string. Its separate WebKit configuration registers only a bounded console output channel. It has no design message handler, native save callback, or path-based disk service. Local content policies filter remote resources, frames and popups. The run process gets nonpersistent website storage. Applications requiring remote services, service workers or full hosting semantics need their ordinary browser environment.

**CodeEditor.swift** bridges NSTextView to the same source buffer. It disables smart substitutions and native text-view undo in favor of the session history. Selection positions and source coordinates both use UTF-16. **App.swift** supplies menus, native file-open events and close/quit handling. **WorkspaceView.swift** hosts the three-pane editor, native source view and diff/impact sheets.

Apple API references: [page script preference](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript), [content worlds](https://developer.apple.com/documentation/webkit/wkcontentworld), [project URL scheme handler](https://developer.apple.com/documentation/webkit/wkurlschemehandler).


**SampleChecks.swift** hosts an isolated Session and a real WorkspaceView in a separate NSWindow. Each group uses private copies of bundled fixtures. The checker waits for a WebKit view whose coordinator matches the current preview generation. It reads results through the explicit WebKit completion callback, verifies expected source and disk bytes, and records failures per group. The external change group exercises the store and the same resolution method used by the dialog. Reports and the Safari test file are saved outside the active project. The report records Safari only after the user opens the generated file and enters an observation.


## Palette and multi-selection

PaletteTile follows AppKit mouse-down, drag, release and Escape on the originating control. The coordinator converts the pointer through the window and visible WebKit bounds to a viewport fraction. layout-drop.js measures the destination in CSS pixels, removes the previous transient node before hit testing, and inserts a temporary, inert element into the rendered container for the hover preview. Write uses the current writing index to validate destinations and drains pending text changes before native insertion. The native source edit receives the parent, sibling and optional local coordinates. Source serialization never reads the preview node.

Direct flow moves hit-test under the pointer independently of pointer capture. Releasing in the same source slot is a no-op, including across whitespace and comments. Free-position moves keep snapshots of each selected style attribute, trial all proposed offsets simultaneously, measure their border boxes, and restore every attribute before requesting one source edit. The source layer validates the ordered sibling IDs and prepares every patch before emitting the new buffer. Native undo registers the file once per arrangement and can restore the working selection on its original page.

## Free page and publication

New drafts start from canvas-page.html with a positioned body. The default drop mode walks up from the hit element to the nearest mapped, compatible container. Flow, Flexbox and Grid use a sibling insertion point. Positioned design containers can supply local coordinates. On a free page the explicit Page canvas option places overlapping siblings in body. The studio.html starter includes an embedded photograph and responsive CSS.

The Insert catalog in source.js supplies native tile metadata, child-parent rules, preview markup and source insertions. LayerOrder.swift calculates before, inside and after destinations for both the native drop delegate and keyboard commands. The drag carries a local pasteboard type, render token and source identity. The source engine validates containment, verifies the re-indexed destination and moves the authored subtree. A stale drop cannot apply to the next page or revision. Audio and video elements use the project's local URL scheme with byte-range responses for seeking.

StudioControls.swift sets viewport dimensions, magnification, typeface, font size, text color, fill and page settings. WebKit renders the requested CSS viewport at the selected scale. The design overlay sizes its handle hit targets in screen points. North and west handles adjust the origin to keep the opposite edge stationary. An active resize updates preview CSS, then restores the original preview style before a single source commit.

A free page stores scoped geometry in an ordinary embedded style element named webbench-layout. The editor reuses a unique author ID or adds one on the selected layer. Each band writes one media rule per layer. The base geometry is retained. Word formatting maps text selections to an authored span or a targeted block declaration.

Snapshot export captures current source buffers after the writing barrier. The store writes a sibling staging directory then renames it to the requested new folder. Project buffers take precedence over on-disk media. Symlinks, hidden files and dependency folders are excluded from supplemental media traversal. Files retain local relative names. Export does not serialize the preview DOM.


## Photo editing

The Edit canvas reports the mapped element or insertion point along with the original drop. Finder URLs come from the actual drag session. When WebKit supplies a browser File, the native coordinator pulls bounded chunks to a temporary file and releases it on dismissal or failure. For a browser-only transfer above 128 MiB, the app offers a native file picker so ImageIO can open the original directly. Run has no photo-import bridge.

PhotoEditor uses ImageIO to read oriented thumbnails and encode a fresh sRGB JPEG or PNG. The crop uses normalized coordinates on the oriented original. PhotoRecipe applies rotation, mirror, tonal adjustments and borders to premultiplied RGBA pixels. When the encoded bytes exceed the current budget the renderer retries at a smaller edge. The displayed Edited preview is decoded from the output bytes. Rendering can be cancelled as settings change. ImageIO downsamples the source to at most 6144 px for processing, so very tight crops of very large originals can have less detail than a full-resolution crop.

A revision token ties Apply to the source page. Replacing an image patches its src value. New asset bytes and the HTML patch share one undo group. Oversized project originals remain in a path index and can be previewed and exported on demand. Ordinary imports keep their original bytes when conversion is unnecessary.
