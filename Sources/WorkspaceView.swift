import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let pine = Color(red: 0.12, green: 0.33, blue: 0.25)
private let properties = [
  "margin-top", "margin-right", "margin-bottom", "margin-left", "padding-top", "padding-right",
  "padding-bottom", "padding-left", "gap", "row-gap", "column-gap", "color", "background-color",
  "font-family", "font-size", "font-weight", "line-height", "text-align", "width", "height",
  "min-width", "max-width", "display", "position", "left", "top", "align-items", "justify-content",
  "flex-direction", "flex-wrap", "grid-template-columns", "grid-template-rows", "border-radius",
  "opacity",
]
struct WorkspaceView: View {
  @State private var paletteSearch = ""
  @State private var layerDrag: LayerDrag?
  @State private var dropMark: LayerDropMark?
  @ObservedObject var m: Session
  var body: some View {
    VStack(spacing: 0) {
      if m.site == nil {
        welcome
      } else {
        toolbar
        if m.mode != .code { StudioControls(model: m) }
        if m.writing && !m.running && m.mode != .code { writingBar }
        Divider()
        HSplitView {
          if !m.running {
            sidebar.frame(minWidth: 165, idealWidth: 200, maxWidth: 300)
          }
          editor.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
          if !m.running && m.mode != .code && m.showInspector {
            Inspector(m: m).frame(minWidth: 215, idealWidth: 248, maxWidth: 330)
          }
        }
      }
      Divider()
      HStack(spacing: 8) {
        if m.busy {
          ProgressView().controlSize(.small)
        } else {
          Circle().fill(m.changed ? Color.orange : Color.green).frame(width: 7, height: 7)
        }
        Text(m.status).lineLimit(2).textSelection(.enabled)
        Spacer()
        if let site = m.site {
          Text(m.changed ? "\(site.dirtyPaths.count) unsaved" : "Saved").foregroundStyle(.secondary)
        }
      }.font(.caption).padding(.horizontal, 12).frame(minHeight: 27)
    }.disabled(m.busy)
      .sheet(item: $m.photoEditor) { job in PhotoEditor(model: m, job: job) }
      .sheet(item: $m.iconEditor) { edit in FaviconEditor(model: m, edit: edit) }
      .sheet(isPresented: Binding(get: { m.diffText != nil }, set: { if !$0 { m.diffText = nil } }))
    {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(m.reviewTitle).font(.title2.bold())
          Spacer()
          Button("Done") { m.diffText = nil }.keyboardShortcut(.defaultAction)
        }
        ScrollView([.vertical, .horizontal]) {
          Text(m.diffText ?? "").font(.system(size: 12, design: .monospaced)).textSelection(
            .enabled
          ).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(22).frame(minWidth: 700, minHeight: 430)
    }
  }
  var welcome: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .bottomLeading) {
        pine
        VStack(alignment: .leading, spacing: 18) {
          Image(systemName: "square.stack.3d.up.fill").font(.system(size: 54, weight: .light))
            .foregroundStyle(Color(red: 0.87, green: 0.74, blue: 0.43))
          Spacer()
          Text("GREEN SHOE GARAGE").font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(2)
          Text("WebBench").font(.system(size: 52, weight: .medium, design: .serif))
          Text("Visual HTML, CSS & JavaScript editor").font(.title3)
        }.foregroundStyle(.white).padding(34)
      }.frame(maxWidth: 420)
      VStack(alignment: .leading, spacing: 18) {
        Text("Open your workbench").font(.largeTitle.bold())
        Text(
          "Choose an HTML file for a single-file app, or a site folder to load linked styles, scripts and artwork."
        ).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Button("Open file or folder…") { m.openPanel() }.buttonStyle(.borderedProminent).tint(pine)
          .controlSize(.large)
        Button("Start a free canvas") { m.newStudioDraft() }.controlSize(.large)
        Text("Drag in a button, move it, then double-click its label to type.")
          .font(.callout).foregroundStyle(.secondary)
        Divider().padding(.vertical, 8)
        Text("Create a page").font(.headline)
        HStack {
          Button("Blank page…") { m.new("blank") }
          Button("Field Instrument…") { m.new("instrument") }
          Button("Studio portfolio") { m.newStudioDraft("studio") }
        }
      }.frame(maxWidth: 445, alignment: .leading).padding(40)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  var toolbar: some View {
    HStack(spacing: 9) {
      Menu {
        Button("Open file or folder…") { m.afterWriting { m.openPanel() } }
        Button("Start a free canvas") { m.afterWriting { m.newStudioDraft() } }
        Button("Studio portfolio template") { m.afterWriting { m.newStudioDraft("studio") } }
        Button("New blank page…") { m.afterWriting { m.new("blank") } }
      } label: {
        Label("Project", systemImage: "folder")
      }.fixedSize().accessibilityLabel("Project")
      Picker(
        "View",
        selection: Binding(get: { m.mode }, set: { mode in m.afterWriting { m.mode = mode } })
      ) {
        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden().frame(width: 164)
      if !m.running && m.mode != .code {
        Button {
          m.afterWriting {
            if !m.writing, let i = m.inspection, i.textEditable {
              m.startText(i.id, offset: 0)
            } else {
              m.setWriting(!m.writing)
            }
          }
        } label: {
          Label(
            m.writing ? "Done typing" : "Edit text",
            systemImage: m.writing ? "checkmark" : "text.cursor")
        }.help("Double-click text on the page to type. Escape returns to layout.")
      }
      Button {
        m.afterWriting { m.setRun(!m.running) }
      } label: {
        Label(m.running ? "Stop" : "Run", systemImage: m.running ? "stop.fill" : "play.fill")
      }.help("Run the current source in a separate preview")
      Spacer()
      if !m.running {
        Button {
          m.toggleInspector()
        } label: {
          Label("Inspector", systemImage: "sidebar.right")
        }
        .accessibilityLabel(
          m.showInspector && m.mode != .code ? "Hide inspector" : "Show inspector"
        ).help("Show or hide the Inspector (⌥⌘I)")
      }
      Divider().frame(height: 19)
      Button {
        m.afterWriting { m.diff() }
      } label: {
        Label("Diff", systemImage: "plus.forwardslash.minus")
      }
      Button("Save") { m.afterWriting { m.save() } }
      Menu {
        Button("Website folder…") { m.afterWriting { m.exportSnapshot(folder: true) } }
        Button("Current HTML file…") { m.afterWriting { m.exportSnapshot(folder: false) } }
      } label: {
        Label("Export snapshot", systemImage: "square.and.arrow.up")
      }.fixedSize()
        .help("Export the current source and assets as a site you can upload")
    }.padding(.horizontal, 12).frame(height: 44)
  }
  var writingBar: some View {
    HStack(spacing: 10) {
      Menu(m.writingFormat.title) {
        Button("Paragraph") { m.writeCommand("block", "p") }
        ForEach(1...6, id: \.self) { level in
          Button("Heading \(level)") { m.writeCommand("block", "h" + String(level)) }
        }
      }.fixedSize()
      Divider().frame(height: 18)
      Button {
        m.writeCommand("bold")
      } label: {
        Image(systemName: "bold")
      }
      .tint(m.writingFormat.bold ? Color.accentColor : Color.primary)
      .accessibilityValue(m.writingFormat.bold ? "On" : "Off")
      .accessibilityLabel("Bold").help("Bold (⌘B)")
      Button {
        m.writeCommand("italic")
      } label: {
        Image(systemName: "italic")
      }
      .tint(m.writingFormat.italic ? Color.accentColor : Color.primary)
      .accessibilityValue(m.writingFormat.italic ? "On" : "Off")
      .accessibilityLabel("Italic").help("Italic (⌘I)")
      Button {
        m.writeCommand("list", "ul")
      } label: {
        Image(systemName: "list.bullet")
      }
      .tint(m.writingFormat.list == "ul" ? Color.accentColor : Color.primary)
      .accessibilityValue(m.writingFormat.list == "ul" ? "On" : "Off")
      .accessibilityLabel("Bulleted list").help("Bulleted list")
      Button {
        m.writeCommand("list", "ol")
      } label: {
        Image(systemName: "list.number")
      }
      .tint(m.writingFormat.list == "ol" ? Color.accentColor : Color.primary)
      .accessibilityValue(m.writingFormat.list == "ol" ? "On" : "Off")
      .accessibilityLabel("Numbered list").help("Numbered list")
      Button {
        m.writingLink()
      } label: {
        Image(systemName: "link")
      }
      .accessibilityLabel("Link").help("Insert or edit link (⌘K)")
      Divider().frame(height: 18)
      Menu("Insert") {
        Button("Paragraph") { m.writeCommand("paragraph") }
        Button("Line break") { m.writeCommand("break") }
        Button("Link…") { m.writingLink() }
        Button("Image…") { m.pickImage() }
        Button("Button") { m.writeCommand("element", "button") }
        Button("Table") { m.writeCommand("element", "table") }
        Button("Horizontal rule") { m.writeCommand("element", "hr") }
      }.fixedSize()
      Spacer()
      if let pages = m.site?.pages, pages.count > 1 {
        Menu(m.page) {
          ForEach(pages, id: \.self) { page in
            Button(page) { m.afterWriting { m.choosePage(page) } }
          }
        }.fixedSize()
      }
    }.padding(.horizontal, 12).frame(height: 36).background(Color(nsColor: .controlBackgroundColor))
  }
  var sidebar: some View {
    VStack(alignment: .leading, spacing: 9) {
      Picker("Project panel", selection: $m.sidebarTab) {
        Text("Insert").tag("Insert")
        Text("Layers").tag("Tree")
        Text("Pages").tag("Pages")
        if m.sidebarTab == "Files" { Text("Files").tag("Files") }
      }.pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 8)
      if m.sidebarTab == "Pages" {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(m.site?.pages ?? [], id: \.self) { page in
              Button {
                m.choosePage(page)
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  if let image = m.pageImages[page] {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                      .background(.white).clipShape(RoundedRectangle(cornerRadius: 4))
                  }
                  HStack(spacing: 6) {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                    Text(page).lineLimit(2).font(.callout)
                    Spacer()
                    if m.page == page { Image(systemName: "checkmark").font(.caption) }
                  }
                }.padding(8).background(
                  m.page == page ? pine.opacity(0.12) : .clear,
                  in: RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain)
            }
          }.padding(.horizontal, 6)
        }
      } else if m.sidebarTab == "Tree" {
        layerTools
        Text("Drag between rows to reorder, or onto a container to nest.").font(.caption)
          .foregroundStyle(.secondary).padding(.horizontal, 10)
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
              ForEach(m.layers) { row in
                layerRow(row)

              }
            }
          }
          .onChange(of: m.selected) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
        }.disabled(m.running)
          .onChange(of: m.preview?.token) { _, _ in
            layerDrag = nil
            dropMark = nil
          }
          .onDisappear {
            layerDrag = nil
            dropMark = nil
          }
      } else if m.sidebarTab == "Files" {
        Text("Project files").font(.headline).padding(.horizontal, 10)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(m.site?.workspacePaths ?? [], id: \.self) { path in
              let ext = (path as NSString).pathExtension.lowercased()
              let art = Site.images.contains(ext) || Site.rasterPhotos.contains(ext)
              let row = Button {
                m.chooseFile(path)
              } label: {
                HStack {
                  Image(systemName: art ? "photo" : "doc.plaintext")
                  Text(path).lineLimit(2)
                  Spacer()
                  if m.site?.files[path]?.dirty == true {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                  }
                }.font(.caption).padding(5).background(
                  m.file == path ? Color.accentColor.opacity(0.18) : .clear)
              }.buttonStyle(.plain)
              if art {
                row.onDrag { NSItemProvider(object: ("WebBench:Asset/" + path) as NSString) }
              } else {
                row
              }
            }
          }.padding(.horizontal, 5)
        }
      } else {
        TextField("Search elements", text: $paletteSearch).textFieldStyle(.roundedBorder).padding(
          .horizontal, 10)
        if m.hasFreePage {
          Picker("Drop into", selection: $m.dropOnPage) {
            Text("Container").tag(false)
            Text("Page canvas").tag(true)
          }.pickerStyle(.segmented).padding(.horizontal, 10).help(
            "Container targets the nearest compatible layout. Page canvas places overlapping objects on the page."
          )
        }
        if let parent = m.selectedContainer, parent.tag != "body", !m.dropOnPage {
          Text("Click to add inside " + parent.label + ", or drag to place.").font(.caption)
            .padding(.horizontal, 10)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(m.paletteGroups, id: \.self) { group in
              let entries = matchingElements.filter { $0.group == group }
              if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                  Text(group).font(.caption.bold()).foregroundStyle(.secondary)
                  ForEach(entries) { item in
                    PaletteTile(item: item.id, title: item.title, symbol: item.symbol, model: m)
                      .frame(maxWidth: .infinity).frame(height: 29)
                  }
                }
              }
            }
            if matchingElements.isEmpty { Text("No matching elements").font(.callout) }
          }.padding(.horizontal, 10).padding(.vertical, 4)
        }.disabled(m.mode == .code)
      }
      Spacer(minLength: 0)
      Divider()
      HStack {
        Button {
          m.sidebarTab = m.sidebarTab == "Files" ? "Insert" : "Files"
        } label: {
          Label("Files", systemImage: "folder")
        }.buttonStyle(.plain)
        Spacer()
        Menu {
          Toggle("Show canvas grid", isOn: $m.gridVisible)
          Toggle("Snap to guides and grid", isOn: $m.snap)
          Toggle("Free placement in positioned containers", isOn: $m.freePlacement)
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Placement options")
      }.padding(.horizontal, 11).padding(.bottom, 8)
    }.background(Color(nsColor: .controlBackgroundColor))
  }
  private var matchingElements: [InsertElement] {
    let term = paletteSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    return m.elements.filter {
      term.isEmpty
        || [$0.id, $0.title, $0.tag, $0.group].contains(where: {
          $0.localizedCaseInsensitiveContains(term)
        })
    }
  }
  @ViewBuilder private func addInside(_ row: ElementRow) -> some View {
    Menu("Add inside") {
      ForEach(m.paletteGroups, id: \.self) { group in
        let options = m.elements.filter { $0.group == group && m.accepts($0.tag, in: row) }
        if !options.isEmpty {
          Menu(group) {
            ForEach(options) { item in Button(item.title) { m.insertChild(item, in: row.id) } }
          }
        }
      }
    }
  }
  private var layerTools: some View {
    HStack(spacing: 4) {
      if let row = m.selectedContainer { addInside(row).menuStyle(.borderlessButton).fixedSize() }
      Spacer(minLength: 0)
      ForEach(
        Array(
          zip(LayerStep.allCases, ["arrow.up", "arrow.down", "increase.indent", "decrease.indent"])),
        id: \.0
      ) { step, symbol in
        let slot = m.selected.flatMap { m.slot(for: $0, step: step) }
        Button {
          if let id = m.selected, let slot { m.moveLayer(id, to: slot) }
        } label: {
          Image(systemName: symbol).frame(width: 14)
        }
        .buttonStyle(.borderless).disabled(slot == nil || !m.groupIDs.isEmpty).help(step.rawValue)
        .accessibilityLabel(step.rawValue)
        .keyboardShortcut(
          step == .up
            ? .upArrow : step == .down ? .downArrow : step == .indent ? .rightArrow : .leftArrow,
          modifiers: [.command, .option])
      }
    }.padding(.horizontal, 8)
  }
  private func layerRow(_ row: ElementRow) -> some View {
    let zone = dropMark?.row == row.id ? dropMark?.zone : nil
    return Button {
      if !m.writing && m.mode != .code
        && (NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false)
      {
        m.designer?.toggle(row.id)
      } else {
        m.select(row.id)
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: layerIcon(row.tag)).foregroundStyle(.secondary).frame(width: 15)
        Text(row.name).lineLimit(1).font(.callout)
        Spacer(minLength: 0)
        if zone == .inside { Image(systemName: "arrow.turn.down.right") }
      }.padding(.leading, CGFloat(min(10, max(0, row.depth - 1))) * 9 + 5).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        .background(
          zone == .inside
            ? Color.accentColor.opacity(0.25)
            : m.selectedIDs.contains(row.id) ? pine.opacity(0.16) : .clear
        )
        .contentShape(Rectangle())
    }.buttonStyle(.plain).id(row.id).help(row.label)
      .overlay(alignment: zone == .after ? .bottom : .top) {
        if zone == .before || zone == .after {
          Rectangle().fill(Color.accentColor).frame(height: 2).allowsHitTesting(false)
        }
      }
      .contextMenu {
        if m.elements.contains(where: { m.accepts($0.tag, in: row) }) { addInside(row) }
        ForEach(LayerStep.allCases, id: \.self) { step in
          let slot = m.slot(for: row.id, step: step)
          Button(step.rawValue) { if let slot { m.moveLayer(row.id, to: slot) } }.disabled(
            slot == nil)
        }
        Divider()
        Button(m.selectedIDs.contains(row.id) ? "Remove from selection" : "Add to selection") {
          m.designer?.toggle(row.id)
        }.disabled(m.writing || m.mode == .code)
      }
      .onDrag {
        guard m.canEditLayers, m.movableLayer(row.id), m.groupIDs.isEmpty,
          let token = m.preview?.token
        else { return NSItemProvider() }
        let drag = LayerDrag(id: row.id, token: token, source: m.site?.files[m.page]?.bytes)
        layerDrag = drag
        let provider = NSItemProvider(object: drag.payload as NSString)
        let payload = Data(drag.payload.utf8)
        provider.registerDataRepresentation(
          forTypeIdentifier: LayerDrag.type.identifier, visibility: .ownProcess
        ) { done in
          DispatchQueue.main.async { done(payload, nil) }
          return nil
        }
        return provider
      }
      .onDrop(
        of: [LayerDrag.type],
        delegate: LayerRowDrop(
          model: m, target: row.id, drag: $layerDrag, mark: $dropMark, height: 28))
  }
  private func layerIcon(_ tag: String) -> String {
    switch tag {
    case "img", "svg", "picture": return "photo"
    case "h1", "h2", "h3", "h4", "h5", "h6", "p", "span", "label": return "textformat"
    case "button", "input", "output": return "switch.2"
    case "a": return "link"
    case "main", "section", "article", "body": return "rectangle.3.group"
    default: return "square"
    }
  }
  var editor: some View {
    GeometryReader { geo in
      VStack(spacing: 0) {
        if m.mode != .code {
          HStack {
            Image(systemName: m.running ? "play.circle" : "doc.richtext").foregroundStyle(
              .secondary)
            Text(m.page).lineLimit(1).font(.caption.bold())
            Spacer()
            if !m.insertTool.isEmpty && !m.running {
              Text("Click to place " + m.insertTool.lowercased()).font(.caption)
              Button {
                m.insertTool = ""
              } label: {
                Image(systemName: "xmark.circle")
              }.buttonStyle(.plain).accessibilityLabel("Cancel placement")
            }
            if !m.running && !m.writing && m.canDeleteSelection {
              Button {
                m.deleteLayers()
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.plain).accessibilityLabel("Delete selected layers").help(
                "Delete selected layers")
            }
            if !m.running {
              BackgroundControl(model: m, pageWide: true)
              Button {
                m.openFavicon()
              } label: {
                Label("Favicon", systemImage: "square.grid.3x3")
              }.controlSize(.small)
              if !m.writing { PageControls(model: m) }
            }
          }.padding(.horizontal, 10).frame(height: 26)
          Divider()
          if let p = m.preview {
            GeometryReader { available in
              let fit = min(
                1, (available.size.width - 20) / m.width,
                (available.size.height - 20) / m.deviceHeight)
              let scale =
                m.zoom == "Fit" ? max(0.05, fit) : (Double(m.zoom.dropLast()) ?? 100) / 100
              ScrollView([.horizontal, .vertical]) {
                Canvas(model: m, state: p, zoom: CGFloat(scale)).id(p.token)
                  .frame(width: m.width * scale, height: m.deviceHeight * scale)
                  .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                  .padding(9)
                  .frame(minWidth: available.size.width, alignment: .top)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(nsColor: .underPageBackgroundColor))
            }.frame(minHeight: 90, maxHeight: .infinity)
          } else {
            VStack(spacing: 8) {
              Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title2)
              Text(m.sourceIssue.isEmpty ? "Preparing preview…" : m.sourceIssue).font(.headline)
              Button("Open source") { m.mode = .code }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        if m.running {
          Divider()
          HStack {
            Text("Run console").font(.caption.bold())
            Spacer()
            Button("Clear") { m.logs = [] }.controlSize(.small)
          }.padding(.horizontal, 8)
          ScrollView {
            Text(m.logs.isEmpty ? "No console output." : m.logs.joined(separator: "\n")).font(
              .system(size: 11, design: .monospaced)
            ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6)
          }.frame(height: 70)
        }
        if m.mode != .design {
          Divider()
          HStack {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
            Text(m.file).font(.caption.monospaced())
            Spacer()
            if !m.sourceIssue.isEmpty {
              Image(systemName: "exclamationmark.triangle").help(m.sourceIssue)
            }
          }.padding(.horizontal, 10).frame(height: 26)
          CodeEditor(model: m).frame(minHeight: 90, maxHeight: .infinity)
        }
      }
    }
  }
}

private struct Inspector: View {
  @ObservedObject var m: Session
  @State private var text = ""
  @State private var attr = "title"
  @State private var attributeValue = ""
  @State private var value = ""
  @State private var target = "Element"
  @State private var scope = "Global"
  @State private var breakpoint = 600
  @State private var external = "Page"
  func reset(_ i: Inspection?) {
    guard let i else { return }
    if target == "Winning rule" && !i.rules.indices.contains(i.winner) { target = "Element" }
    text = i.text
    attributeValue = i.attributes[attr] ?? ""
    value = i.computed
    if target.hasPrefix(".") && !i.classes.contains(where: { "." + $0.name == target }) {
      target = "Element"
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Inspector").font(.headline)
        if m.writing {
          Text(m.writingFormat.title).font(.subheadline).foregroundStyle(.secondary)
          Divider()
          FontControl(current: m.writingFormat.fontFamily) { m.styleSelection("font-family", $0) }
          FontSizeControl(current: m.writingFormat.fontSize) { m.styleSelection("font-size", $0) }
          PaintControl(title: "Text color", symbol: "textformat", current: m.writingFormat.ink) {
            m.styleSelection("color", $0)
          }
          BackgroundControl(model: m, pageWide: false)
          Button("Inspect block layout") { m.afterWriting { m.setWriting(false) } }
        } else if !m.groupIDs.isEmpty {
          GroupInspector(model: m)
        } else {
          Picker("Inspector", selection: $m.inspectorTab) {
            ForEach(["Style", "Arrange", "Inspect"], id: \.self) { Text($0).tag($0) }
          }.pickerStyle(.segmented).labelsHidden()
          if let i = m.inspection {
            Text(i.label).font(.system(.body, design: .monospaced).bold()).textSelection(.enabled)
            Text(i.display + " layout").font(.caption).foregroundStyle(.secondary)
            Divider()
            if m.inspectorTab != "Inspect" {
              DesignInspector(model: m, selection: i)
            } else {
              Text("Element").font(.headline)
              if i.textEditable {
                TextField("Text content", text: $text)
                Button("Set text") {
                  m.mutate(["kind": "text", "value": text], name: "Change element text")
                }
              } else {
                Button("Edit contents in Code") {
                  m.codeFallback(
                    "This content is nested or exceeds the inspector text limit.", id: i.id)
                }
              }
              Picker("Attribute", selection: $attr) {
                ForEach(
                  [
                    "title", "id", "class", "href", "src", "alt", "value", "type", "for",
                    "aria-label",
                  ],
                  id: \.self
                ) { Text($0).tag($0) }
              }.onChange(of: attr) { _, a in attributeValue = i.attributes[a] ?? "" }
              HStack {
                TextField("Value", text: $attributeValue)
                Button("Set") {
                  m.mutate(
                    ["kind": "attr", "key": attr, "value": attributeValue], name: "Set " + attr)
                }
              }
              Divider()
              Text("CSS").font(.headline)
              Picker("Property", selection: $m.property) {
                ForEach(properties, id: \.self) { Text($0).tag($0) }
              }.labelsHidden()
              Text("Computed  " + i.computed).font(.caption.monospaced()).textSelection(.enabled)
              if i.rules.indices.contains(i.winner) {
                rule(i.rules[i.winner], title: "Winning declaration")
              } else {
                Text(
                  i.limited
                    ? "Complex cascade · inspect matched rules in Code."
                    : "Inherited, initial, shorthand, or browser default."
                ).font(.caption).foregroundStyle(.secondary)
              }
              if i.rules.count > 0 {
                DisclosureGroup("Matched rules (\(i.rules.count))") {
                  ForEach(i.rules.indices, id: \.self) { idx in
                    rule(i.rules[idx], title: i.rules[idx].value)
                  }
                }
              }
              Picker("Change", selection: $target) {
                Text("This element").tag("Element")
                if i.rules.indices.contains(i.winner) { Text("Winning rule").tag("Winning rule") }
                ForEach(i.classes, id: \.name) { c in Text("." + c.name).tag("." + c.name) }
              }
              if target == "Winning rule", i.rules.indices.contains(i.winner) {
                let r = i.rules[i.winner]
                if r.styleIndex != -2 {
                  Button("Show affected elements") { m.impactRequest = r.selector }
                }
                Text("Affects \(r.count) on this page · " + r.examples).font(.caption)
                Text(r.media.isEmpty ? "Global rule" : r.media).font(.caption)
              } else {
                if let c = i.classes.first(where: { "." + $0.name == target }) {
                  Button("Show affected elements") { m.impactRequest = target }
                  Text("Affects \(c.count) on this page · " + c.examples).font(.caption)
                }
                Picker("Scope", selection: $scope) {
                  Text("Global").tag("Global")
                  Text("Breakpoint").tag("Breakpoint")
                }
                if scope == "Breakpoint" {
                  HStack {
                    Text("Max width")
                    TextField("px", value: $breakpoint, formatter: NumberFormatter())
                    Text("px")
                  }.font(.caption)
                }
                if target != "Element" || scope == "Breakpoint" {
                  Picker("Write to", selection: $external) {
                    Text("Page style").tag("Page")
                    ForEach(linkedSheets(i), id: \.self) { Text($0).tag($0) }
                  }
                }
              }
              HStack {
                TextField("CSS value", text: $value)
                Button("Apply") {
                  m.applyStyle(
                    value: value, target: target, scope: scope, breakpoint: breakpoint,
                    external: linkedSheets(i).contains(external) ? external : "Page")
                }
              }
              Divider()
              Text("Layout").font(.headline)
              HStack {
                Button("Earlier") {
                  m.mutate(["kind": "reorder", "step": -1], name: "Move earlier")
                }
                Button("Later") { m.mutate(["kind": "reorder", "step": 1], name: "Move later") }
              }
              if i.canMove {
                Text("Drag to position, or use Move in the Layout menu.").font(.caption)
                HStack {
                  ForEach(["←", "↑", "↓", "→"], id: \.self) { a in
                    Button(a) {
                      m.nudge(a == "←" ? -1 : a == "→" ? 1 : 0, a == "↑" ? -1 : a == "↓" ? 1 : 0)
                    }
                  }
                }
              }
              Divider()
              Button("Find or create click handler") { m.handler() }
            }
          } else {
            Text("Select an object on the page to inspect its style, size and CSS.")
              .foregroundStyle(.secondary)
            BackgroundControl(model: m, pageWide: true)
            Button("Edit favicon…") { m.openFavicon() }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }.background(Color(nsColor: .controlBackgroundColor))
      .onReceive(m.$inspection) { reset($0) }
  }
  func linkedSheets(_ i: Inspection) -> [String] {
    Array(Set(i.sheets.compactMap { m.localPath($0) })).sorted()
  }
  func rule(_ r: RuleInfo, title: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Button(title) { m.showRule(r) }.buttonStyle(.link).font(.caption.bold())
      Text(r.selector + "  " + r.value + (r.priority.isEmpty ? "" : " !" + r.priority)).font(
        .caption.monospaced())
      Text((m.localPath(r.source) ?? r.source) + (r.media.isEmpty ? "" : " · " + r.media)).font(
        .caption
      ).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
  }
}

private struct LayerDrag {
  static let type = UTType(exportedAs: "com.greenshoegarage.webbench.layer")
  let id: Int, token: String, source: Data?
  var payload: String { "WebBench:Node/" + token + "/" + String(id) }
}
private struct LayerDropMark: Equatable {
  let row: Int, zone: LayerZone
}
private struct LayerRowDrop: DropDelegate {
  let model: Session, target: Int
  @Binding var drag: LayerDrag?
  @Binding var mark: LayerDropMark?
  let height: CGFloat
  private func placement(_ info: DropInfo) -> (LayerZone, LayerSlot)? {
    guard let drag, drag.token == model.preview?.token, model.nodes.indices.contains(drag.id),
      model.nodes.indices.contains(target)
    else { return nil }
    let y = info.location.y
    let canNest = model.accepts(model.nodes[drag.id].tag, in: model.nodes[target])
    let zone: LayerZone =
      canNest && y >= height * 0.25 && y <= height * 0.75
      ? .inside : y < height / 2 ? .before : .after
    return model.slot(for: drag.id, at: target, zone: zone).map { (zone, $0) }
  }
  func validateDrop(info: DropInfo) -> Bool {
    guard let drag, model.canEditLayers, model.nodes.indices.contains(drag.id),
      drag.token == model.preview?.token
    else { return false }
    return info.hasItemsConforming(to: [LayerDrag.type])
  }
  func dropUpdated(info: DropInfo) -> DropProposal? {
    if let (zone, _) = placement(info) {
      mark = LayerDropMark(row: target, zone: zone)
      return DropProposal(operation: .move)
    }
    mark = nil
    return DropProposal(operation: .forbidden)
  }
  func dropExited(info: DropInfo) { if mark?.row == target { mark = nil } }
  func performDrop(info: DropInfo) -> Bool {
    defer { mark = nil }
    guard let drag, let (_, slot) = placement(info),
      let provider = info.itemProviders(for: [LayerDrag.type]).first
    else { return false }
    provider.loadDataRepresentation(forTypeIdentifier: LayerDrag.type.identifier) { bytes, _ in
      guard bytes == Data(drag.payload.utf8) else { return }
      DispatchQueue.main.async {
        guard self.model.preview?.token == drag.token,
          self.model.site?.files[self.model.page]?.bytes == drag.source
        else { return }
        self.model.moveLayer(drag.id, to: slot)
      }
    }
    return true
  }
}
