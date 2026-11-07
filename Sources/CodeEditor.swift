import AppKit
import SwiftUI

struct CodeEditor: NSViewRepresentable {
  @ObservedObject var model: Session
  func makeCoordinator() -> Coordinator { Coordinator(model) }
  func makeNSView(context: Context) -> NSScrollView {
    let sv = NSScrollView()
    let text = NSTextView()
    sv.hasVerticalScroller = true
    sv.hasHorizontalScroller = true
    text.isRichText = false
    text.importsGraphics = false
    text.allowsUndo = false
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false
    text.isContinuousSpellCheckingEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticLinkDetectionEnabled = false
    text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    text.textContainerInset = NSSize(width: 12, height: 12)
    text.minSize = .zero
    text.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.delegate = context.coordinator
    text.setAccessibilityLabel("Source code")
    sv.documentView = text
    return sv
  }
  func updateNSView(_ sv: NSScrollView, context: Context) {
    guard let text = sv.documentView as? NSTextView else { return }
    let c = context.coordinator
    let value = model.currentText
    text.isEditable = !model.running && !model.busy && model.site?.files[model.file]?.text != nil
    let changedFile = c.path != model.file
    if changedFile || !text.string.utf8.elementsEqual(value.utf8) {
      c.programmatic = true
      let old = text.selectedRange()
      text.string = value
      text.setSelectedRange(
        NSRange(
          location: changedFile ? 0 : min(old.location, (value as NSString).length), length: 0))
      c.programmatic = false
      c.path = model.file
    }
    if c.reveal != model.revealID || changedFile {
      c.reveal = model.revealID
      let r = model.codeRange
      if NSMaxRange(r) <= (value as NSString).length {
        text.setSelectedRange(r)
        text.scrollRangeToVisible(r)
      }
    }
  }
  final class Coordinator: NSObject, NSTextViewDelegate {
    let model: Session
    var programmatic = false, path = "", reveal: UUID?
    init(_ model: Session) { self.model = model }
    func textDidChange(_ notification: Notification) {
      guard !programmatic, let text = notification.object as? NSTextView, path == model.file else {
        return
      }
      model.editSource(text.string)
    }
    func textView(
      _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
    ) -> Bool {
      if replacementString == "\n", model.currentText.contains("\r\n") {
        textView.insertText("\r\n", replacementRange: range)
        return false
      }
      return true
    }
  }
}
