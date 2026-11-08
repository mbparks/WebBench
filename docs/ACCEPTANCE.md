# Mac acceptance workflows

## Canvas placement in 0.15.2

1. Check both Command-N and File → New Site Folder. Each should show the first-element artwork. At Fit zoom, drag a star from Insert onto the page. With the star selected, click the Button tile, then click the center of the star. The button should appear over the star. Both should be direct children of the body in Layers.
2. Drag the button away from the star, undo and redo. Scroll down, switch to 50% zoom and place a heading. Compare the ghost and final position, review the source diff, save and reopen in Safari.
3. Choose **Container**. Drag a button into a flex row, then place another over an iframe inside a section. Check the target label before releasing and the resulting parent in Layers.
4. On an existing page, select a positioned panel, then drag a positioned child inside a static wrapper in that panel. Check that only the child’s coordinates change.

## Snippets and embeds on macOS

1. Open a disposable site folder with two HTML pages. Drag **Code snippet** into a section, enter `<button>A & B</button>` and insert. Confirm it displays literally, Undo restores the original bytes and Redo restores the snippet.
2. Drag **Custom HTML** onto a free page. Paste an HTML button and script. Check that Design stays idle, Preview runs the script and edit/reopen preserves the original markup around the widget. An unfinished tag should keep the draft available for correction.
3. Drop **Iframe embed**, pick the second page, set its title, and resize it by dragging a corner. Double-click to revise the URL. Check that Preview can use the second page and that switching back restores the editable placeholder.
4. Paste provider iframe code with custom attributes. Cancel once and verify the source diff stays empty. Insert it, save and reopen. Use **Preview Website in Browser**, verify the default browser opens the selected page, and test the embed on an HTTPS host accepted by the provider. Check the relative local frame independently in Safari.

## Layout shapes on macOS

1. Open a blank canvas and expand **Insert → Layout**. Search **Shapes** and check that 24 silhouettes are available. Search **arrow**, then drag a left arrow onto the canvas. Check that the hover outline and saved direction agree.
2. Choose **Container** for nesting on a free page. Drag a star into a section and a heart into a flex row. Select each by clicking its filled area. Resize and recolor one, check the diff, then Undo and Redo. Verify the names in Layers.
3. Save and reopen, export the page, and open the export in Safari. Check the silhouettes and fills at desktop and phone widths. Confirm an untouched save has the same hash.

## Device Workbench on macOS

1. Open **File → Try Device Workbench**, change the Connect serial baud rate, Apply, review the diff, Undo, Redo, save and reopen. The device support script should occur exactly once, and existing separate handlers should survive unchanged.
2. Choose **Apply & preview**. Send and read PING. Send and read `01 0A FF`. Start the test camera, take a snapshot and stop. Start and stop the meter. Check for the simulated-device status. Stop Preview and check that readouts and snapshot pixels did not enter the source.
3. Export a disposable website folder. Serve it at localhost following the User Guide. In desktop Chrome, connect a serial board running known echo firmware with matching baud and LF framing. Send a harmless known string. Confirm the line in the chosen readout. Unplug during a read, reconnect and repeat.
4. Connect a WebUSB-compatible test peripheral with a documented harmless command. Set its VID/PID, configuration, alternate, interface and endpoint numbers. Cancel the chooser once. Reopen it, send the known command and compare returned bytes with the device specification. Disconnect with a pending transfer and reconnect.
5. In a capture-capable browser, deny the camera or microphone request once and verify the status. Grant the permission, take two different stills, and watch the meter respond to sound. Press each Stop control and check the browser’s camera and microphone indicators. Repeat camera and microphone acceptance in Safari. Reopen the source and compare its bytes with the exported original.


For the packaged app, start with **File → Run Sample Checks…**. Each invocation creates a separate editor session and fresh files. It records hash comparisons, a real WKWebView synthetic flex drop, computed spacing at two widths, native Undo/Redo, a single-file conversion, a meter nudge, the original link and ODIN behavior, recovery after a separate disk write, writing on the rendered page, arranging a box on a free-position board, dragging from a native tile into flex, arranging several selected objects, and the whole-page free canvas with device-specific export, favicon and photo editing, and nested insertion with Layers reordering. A failed group records its error and allows subsequent groups to run.

At the end, use **Open instrument in Safari**, enter 25, click Convert, and record the observed result in the checks window. **Show report in Finder** opens the run folder. The report identifies synthetic-event checks and the separate user-observed Safari result. For physical pointer input, native dialogs and file picker coverage, use the steps below.

Run these on a disposable copy. Record the macOS version, CPU architecture, app build, and each actual outcome. In Terminal, change to the extracted WebBench folder first.

## 1. Open, save, reopen

Copy both fixtures and make a hash list.

    mkdir -p "$TMPDIR/WebBenchAcceptance"
    cp -R Fixtures/. "$TMPDIR/WebBenchAcceptance/"
    cd "$TMPDIR/WebBenchAcceptance"
    find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort > ../WebBench-before.txt

Open Field-Instrument.html in WebBench. Save, reopen and save. Repeat with the **Site folder**. Run the same find command with output redirected to ../WebBench-after.txt and compare the lists with diff. Expect identical hashes for all original fixture files. Next change only the Site heading in Write, or using Set text under the inspector’s Inspect tab, inspect Diff, save and reopen. Expect only its text to change.

## 2. Flex insertion, breakpoint and undo

Open the copied Site folder in Split. Finish typing if needed and open Insert in the sidebar. Drag Button over the right side of the .actions flex container. Verify its destination label, then drop. Select the inserted button. In Inspect, set margin-top to 19px, choose This element, Breakpoint, 600px and css/bench.css as the output. Apply. Check the computed margin at 380px and 900px. At the smaller width expect 19px, and at the larger width expect the original desktop margin.

Inspect the two-file diff. Undo twice and check the canvas and source after each step. Redo twice, save and reopen. Then select one of the original .control buttons at 380px. The margin-top rule in css/bench.css should identify its max-width context and match two controls. Choose Winning rule to edit that existing declaration.

## 3. Build and run a single-file instrument

Open the WebBench project menu and choose New blank page…, finish typing, and select section.layout. From the element palette, add Number input, Button and Output. In Inspect, set their IDs to reading, convert and result. Select the button and choose Find or create click handler. Replace the selected comment with this code.

    const c = document.getElementById('reading').valueAsNumber;
    document.getElementById('result').textContent = String(c * 9 / 5 + 32);

Set the input to 25 in Run, click the button and expect 77. Stop, save, and open the saved HTML directly in Safari. Repeat the calculation. Reopen it in WebBench and verify the button selects in Edit. The included voltage-divider template provides a second independent check of numeric inputs, validation and console output.

## 4. Move a workbench object

For a fresh copy, choose **File → Open Sample Workbench…**. Open the disposable Site in Select and select the meter in Layers. Option-drag it 35px right and 18px down or use the Layout shortcuts. Diff should show changes to left and top. Save, reopen, and confirm the new location. In Run, drag the meter, click its link to open notes, then go back to the bench via the notes link. Give the page focus and type ODIN. Expect the Mjölnir output and lightning badge. Stop and check Diff. The runtime move and badge should have no saved source changes.

## 5. External change and recovery

Open the copied Site, choose css/bench.css in Files and add a local comment in Code. Before saving, open the same CSS file in another editor, append a different comment and save there. Save in WebBench. Expect a conflict. Choose Show recovery copies and compare WebBench-bench.css, External-bench.css and Baseline-bench.css. Confirm the project stylesheet still contains the external version. Save again, choose Use external version, and reapply the intended local change from the recovered copy. Save, reopen and verify the merged result.

## 6. Write like a document

1. Open the WebBench project menu and choose New blank page…. Type in the empty paragraph, split it with Return, then insert a soft break with Shift-Return. With a Japanese or Chinese input source, commit a composition and cancel a second one. Inspect Diff for dropped or duplicated characters.
2. Select a word and use Command-B. Use the italic toolbar button, then Command-K. Give the words a relative link. Paste two lines from another app. Inspect the paragraphs and selected text in Split.
3. From inside a paragraph, use Insert to add a button. Type its label. Add a table, replace the selected first cell, and use Tab to reach the next one. Import an SVG at a caret. In a folder project, check the relative path and the staged image in the canvas before saving. In a single file, check the embedded image.
4. Undo and redo. Save immediately after typing. Repeat after switching to Code, Run and Select. Close with unsaved text and verify the save prompt. Open the saved HTML independently in Safari.
5. Open a page with comments, quoted attributes, entities, accented text and CRLF. Change one word. Compare the original and saved bytes. Try a selection spanning separate blocks and verify that the reason and source remain available in Code.

## 7. Arrange a board

1. Create a Design Canvas. Select Box, preview the destination, then click. Choose a fill in Style and apply it. Add an image that overlaps it, then change their order with Arrange.
2. Move the box past a sibling and observe the guide. Compare normal dragging, Shift-constrained dragging, and Option with snapping bypassed. Cancel a drag with Escape. The cancelled gesture should produce no source diff.
3. Resize with the right, bottom and corner handles, including Shift on the corner. Check the CSS dimensions in Arrange. Enter two new dimensions and verify that one Undo restores both values. Redo, Save and reopen.
4. Double-click existing text, type, press Escape and verify the same text layer can be moved. Switch among device widths and zoom choices and check that previewing alone creates no edits.
5. Open the sample site. Insert a button into the flex row with Free placement off. Inspect the source to confirm ordinary flow. Place a design area elsewhere on the page and insert a text box inside it. Check the page in Safari.

## 8. Palette to page with a mouse and trackpad

Open the practice canvas. Press Button in Insert and drag it over the board. Check the visible button preview under the pointer. Leave the page, re-enter, then press Escape. Check that Diff is empty. Repeat, drop, then double-click the button and type “Measure”. Press Escape. Drag the button to another location. Open Diff, undo the move, redo, save, and reopen the file in Safari. Repeat at Fit and 100% zoom.

Use the disposable site next. Drop Button between two siblings in a flex row. Drag the rendered button before the first sibling. Drop artwork from Finder. Check the preview location against the resulting layout and confirm the intended source order and portable image path.

## 9. Arrange several workbench objects

Command-click three positioned siblings of different sizes. Align their top edges to the first. Apply horizontal equal gaps and inspect the result. Option-drag a selected member to move the group freely. Repeat with snapping, then cancel a second drag with Escape. Test ordinary and Shift-arrow nudges, resize a single layer, and select an obscured object from Layers. Undo and redo each change, inspect the source, save, and compare the reopened page. Repeat with one object constrained by an important CSS declaration and check that a rejected move changes no source.

## 10. Design a page from blank paper and publish a snapshot

1. Launch with no file or press Command-N. The page should contain no authored objects. Drag a heading onto the paper. In Insert choose Page canvas and drop a circle over the heading. In Layers verify both are siblings directly under body. Move each independently.
2. Select a part and drag each edge and corner. Check the rendered part changes while the mouse is held. With the northwest grip dragged, the opposite corner should stay anchored. Shift-drag a corner on a photo. Try the Resize sliders and a precise width. Escape during a drag should restore the original frame. Check one undo and redo per released gesture.
3. Double-click the heading and type. Change the typeface and Text color of one word. Press Escape. Change a button's typeface, Fill and size. In Diff confirm the remaining text and elements keep their existing source.
4. Switch among Phone (390 × 844), Tablet (820 × 1180), Desktop (1280 × 800), rotated and custom sizes. Preview alone should leave Diff unchanged. At Phone choose Only this breakpoint and move or resize the button. Switch to Desktop and verify its original position, then return to Phone and check the new one.
5. Export → Website folder with unsaved changes. Open its index.html in Safari and compare all three viewport widths. Test text, links and controls. Reopen the exported folder in WebBench. Compare the working original and confirm the export left it untouched.
6. Open File → New Studio Portfolio. Move the photo, replace it with local artwork, change the heading, export Current HTML file and reopen it in Safari offline. Repeat the physical drag and resize with a trackpad at Fit and 100%.

## 11. Inspector, page colors and browser icons

1. Start a free canvas. Check the Inspector appears on the right. Add a button and select it. Switch among Style, Arrange and Inspect. Double-click text and check the sidebar follows the active block. Choose Inspect block layout. Toggle the sidebar with Option-Command-I. Reopen the app and verify your deliberate visibility choice persists. From Code use the shortcut to open Split with the Inspector.
2. Set Page background to forest green. Set the button's Element background to gold and then Transparent. Inspect the source and undo each change. Repeat on a short body with margins, an inline shorthand, an important rule and a gradient. Compare the solid-color and Keep background image choices.
3. Open Favicon. Draw a diagonal stroke, create initials, erase pixels, flood-fill a connected patch and undo. Import a known asymmetric, transparent PNG and confirm it is upright. Edit an existing multi-size ICO. Export PNG and ICO and check them in Preview. Cancel the sheet and verify Diff is unchanged. Reopen it and apply the edit.
4. For a single-file page, check the embedded PNG and colors after export and reopen. For a nested page in a folder project, edit one of two icon links and check the relative PNG, its reported size, other icon links and pages sharing the original artwork. Serve the exported folder locally and verify the tab icon in Safari in a fresh tab or browsing session. Test Undo/Redo and Save independently.


## 12. Oversized photo, crop, filters and borders

1. Start a blank single-file page. Drop a JPEG or HEIC larger than 2 MiB from Finder. Check the proposed output size. Cancel and confirm Diff is empty. Repeat via the Image palette tile, then import at a known location. In Write, drop in a paragraph and verify the insertion point.
2. Try a portrait phone photo with EXIF rotation and a transparent PNG. Drag a free crop near a recognizable corner. Try clockwise rotation, mirror, a 1280 px longest edge, Black & white and Instant print. Set a distinct border color. Compare Original, Crop and Edited, then apply. Verify orientation, transparency in PNG and the wide bottom border. Repeat with JPEG and check its white backdrop.
3. Open a site folder with two images pointing to the same file and an original larger than 12 MiB. Select just one photo. Choose Edit photo, apply a border, then check Diff, Undo and Redo. Save and reopen. Verify the original file hash, second image, alt text, links, CSS dimensions and surrounding comments. Export the folder and check its relative link and image in Safari.
4. Repeat on a standalone page with an embedded photo. Reload the saved HTML in Safari offline. Check the image, then reopen in WebBench and edit it again. Test a phone photo dropped onto a free canvas at both Fit and 100%, using the mouse and trackpad.

## 13. Add inside an existing section and rearrange it in Layers

1. Open an existing HTML page with a section, a nested Flex or Grid container, and siblings. In Design, drag Button from Insert into the containing layout. Check the parent and its insertion point before release. In Split, verify exactly where the new child appears.
2. In Layers, select an empty or covered container. Choose Add inside → Text & lists → Disclosure. Select it again, switch to Insert, search for `range` and click Range slider. Confirm both are children of that container.
3. Use the top edge, center highlight and bottom edge of target rows to move a layer before, inside and after. Move a whole section with its descendants. Repeat with Option-Command-Up, Down, Right and Left. Verify both the native tree and the source. Cancel a drag and check the diff.
4. Move an absolutely positioned layer into a flex row. Use Arrange → Use normal flow to see the parent place it. On the free canvas, choose Page canvas for an overlapping object, then switch back to Container. Undo and redo each change. Save, reopen and compare the hierarchy and links in Safari.
5. Add a table row to a table body and a cell to a row, a list item to an ordered list and an option to a dropdown. Add a local audio or video file in the Inspector. Test playback and seeking in Run and in the exported site. Repeat the Layers drops with a mouse and a trackpad at Fit and 100%.

## Workspace refresh on macOS

1. In light and dark appearance, open a new free canvas at the minimum window size, then expand the window. Confirm the Parts drawer, Inspector and device dock remain usable. Make a fresh draft and ensure a save without edits contains no guide or editor decoration.
2. Collapse Layout, search for Grid and drag the card into a section. Clear search and check the tray returns to its previous state. Try Tab and Space on a palette card. Drag a card with a mouse and trackpad and press Escape before releasing.
3. Select an image, edit its photo or size, then select text and change its typeface. Try editing text with the Inspector open and closed. Fold a parent layer and select a child on the page to reveal its row. Use Option-Command arrows with Layers active and inspect the source diff.
4. Open Code, edit a project file, return to Design, switch device or rotate and open the width popover. Preview the page, produce a console error, stop preview and check the working source. Save, reopen and compare the result in Safari.


## Visual interaction authoring

Choose **File → Try Interaction Example**. Change the readout text, add **Open a dialog**, and choose **Apply & preview**. Press **Test signal**, dismiss the dialog, then try the download button. Stop, inspect the diff, undo the complete edit, redo, save and reopen. Check the saved page in Safari.

In a separate disposable site, select a button, open **Interactions**, use **Pick** on the canvas and add an upload step followed by a text change. In Preview, cancel once and verify the readout stays put. Repeat with a disposable file and **Test upload**. Open an exported copy against a local HTTP test receiver, confirm the field name and bytes, and try one failed request followed by a retry. Record both the in-app and independent Safari outcomes.


## Conditional calculation on macOS

Choose **File → Try Power Meter Workflow**. Pick the voltage and current inputs on the canvas. Change the precision to three decimal places. Apply, undo, redo, save and reopen. Measure 12 V at 0.25 A and verify 3.000 W. Clear an input and repeat to reach the warning branch. Restore it and verify the warning clears. Export the HTML and repeat in Safari. Run group 14 in **File → Run Sample Checks…** for the automated native counterpart.
