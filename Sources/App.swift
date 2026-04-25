import SwiftUI
import WebKit
import AppKit
import Combine
import UniformTypeIdentifiers

extension Notification.Name {
    static let findShow = Notification.Name("MarkdownViewer.findShow")
    static let findShowReplace = Notification.Name("MarkdownViewer.findShowReplace")
    static let findNext = Notification.Name("MarkdownViewer.findNext")
    static let findPrev = Notification.Name("MarkdownViewer.findPrev")
    static let zoomIn = Notification.Name("MarkdownViewer.zoomIn")
    static let zoomOut = Notification.Name("MarkdownViewer.zoomOut")
    static let zoomReset = Notification.Name("MarkdownViewer.zoomReset")
    static let copyRichText = Notification.Name("MarkdownViewer.copyRichText")
}

@main
struct MarkdownViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Section {
                    Button("Find…") {
                        NotificationCenter.default.post(name: .findShow, object: nil)
                    }
                    .keyboardShortcut("f")
                    Button("Find and Replace…") {
                        NotificationCenter.default.post(name: .findShowReplace, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    Button("Find Next") {
                        NotificationCenter.default.post(name: .findNext, object: nil)
                    }
                    .keyboardShortcut("g")
                    Button("Find Previous") {
                        NotificationCenter.default.post(name: .findPrev, object: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                }
            }
            CommandGroup(after: .pasteboard) {
                Section {
                    Button("Copy as Rich Text") {
                        NotificationCenter.default.post(name: .copyRichText, object: nil)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
            CommandGroup(before: .windowArrangement) {
                Section {
                    Button("Zoom In") {
                        NotificationCenter.default.post(name: .zoomIn, object: nil)
                    }
                    .keyboardShortcut("=")
                    Button("Zoom Out") {
                        NotificationCenter.default.post(name: .zoomOut, object: nil)
                    }
                    .keyboardShortcut("-")
                    Button("Actual Size") {
                        NotificationCenter.default.post(name: .zoomReset, object: nil)
                    }
                    .keyboardShortcut("0")
                }
            }
        }
    }
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        if let mdown = UTType(filenameExtension: "markdown") { types.append(mdown) }
        if let mdx = UTType(filenameExtension: "mdx") { types.append(mdx) }
        return types
    }

    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case edit, split, preview
    var id: String { rawValue }
    var label: String {
        switch self {
        case .edit: return "Edit"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
    var symbol: String {
        switch self {
        case .edit: return "square.and.pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "text.alignleft"
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private let documentTabbingID: NSWindow.TabbingIdentifier = "MarkdownViewer.Documents"

private func configureDocumentWindow(_ window: NSWindow) {
    window.tabbingMode = .preferred
    window.tabbingIdentifier = documentTabbingID

    let peer = NSApp.windows.first { other in
        other !== window &&
        other.isVisible &&
        other.tabbingIdentifier == documentTabbingID &&
        (other.tabbedWindows?.contains(window) != true)
    }

    if let peer {
        peer.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    } else {
        snapToRight(window)
    }
}

private func snapToRight(_ window: NSWindow) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let width = min(max(visible.width * 0.5, 640), 1000)
    let frame = NSRect(
        x: visible.maxX - width,
        y: visible.minY,
        width: width,
        height: visible.height
    )
    window.setFrame(frame, display: true)
}

final class ScrollSync {
    var scrollEditorTo: ((Double) -> Void)?
    var scrollPreviewTo: ((Double) -> Void)?
    private var ignoreEditorEcho = false

    func editorDidScroll(to fraction: Double) {
        if ignoreEditorEcho {
            ignoreEditorEcho = false
            return
        }
        scrollPreviewTo?(fraction)
    }

    func previewDidScroll(to fraction: Double) {
        ignoreEditorEcho = true
        scrollEditorTo?(fraction)
        DispatchQueue.main.async { [weak self] in
            self?.ignoreEditorEcho = false
        }
    }
}

struct FindOptions: Equatable {
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var useRegex: Bool = false
}

final class FindState: ObservableObject {
    @Published var isActive = false
    @Published var replaceVisible = false
    @Published var query = ""
    @Published var replacement = ""
    @Published var options = FindOptions()
    @Published var totalMatches = 0
    @Published var currentMatch = 0  // 1-based; 0 means none
    @Published var patternInvalid = false

    var replaceCurrent: () -> Void = {}
    var replaceAll: () -> Void = {}

    func next() {
        guard totalMatches > 0 else { return }
        currentMatch = currentMatch >= totalMatches ? 1 : currentMatch + 1
    }

    func prev() {
        guard totalMatches > 0 else { return }
        currentMatch = currentMatch <= 1 ? totalMatches : currentMatch - 1
    }

    func close() { isActive = false }
}

func buildFindRegex(query: String, options: FindOptions) -> NSRegularExpression? {
    guard !query.isEmpty else { return nil }
    var pattern = options.useRegex ? query : NSRegularExpression.escapedPattern(for: query)
    if options.wholeWord {
        pattern = "(?:\\b)" + pattern + "(?:\\b)"
    }
    var regexOptions: NSRegularExpression.Options = []
    if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }
    return try? NSRegularExpression(pattern: pattern, options: regexOptions)
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var mode: ViewMode = .preview
    @State private var sync = ScrollSync()
    @StateObject private var findState = FindState()

    var body: some View {
        VStack(spacing: 0) {
            if findState.isActive {
                FindBar(state: findState, canReplace: mode != .preview)
                Divider()
            }
            paneContent
        }
        .background(WindowAccessor { window in
            configureDocumentWindow(window)
        })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(ViewMode.allCases) { m in
                        Label(m.label, systemImage: m.symbol).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    NotificationCenter.default.post(name: .copyRichText, object: nil)
                }) {
                    Label("Copy as Rich Text", systemImage: "doc.on.clipboard")
                }
                .help("Copy preview as rich text (⇧⌘C) — paste into Substack, Gmail, Notion, etc.")
                .disabled(mode == .edit)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findShow)) { _ in
            findState.isActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .findShowReplace)) { _ in
            findState.isActive = true
            if mode != .preview { findState.replaceVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
            if findState.isActive { findState.next() } else { findState.isActive = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findPrev)) { _ in
            if findState.isActive { findState.prev() } else { findState.isActive = true }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch mode {
        case .edit:
            MarkdownEditor(text: $document.text, sync: nil, findState: findState)
        case .preview:
            MarkdownView(text: document.text, sync: nil, findState: findState)
        case .split:
            HSplitView {
                MarkdownEditor(text: $document.text, sync: sync, findState: findState)
                    .frame(minWidth: 240)
                MarkdownView(text: document.text, sync: sync, findState: findState)
                    .frame(minWidth: 240)
            }
        }
    }
}

struct FindToggleButton: View {
    @Binding var isOn: Bool
    let label: String
    let help: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 26, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(isOn ? 0 : 0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FindFieldContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
    }
}

struct FindBar: View {
    @ObservedObject var state: FindState
    let canReplace: Bool
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                disclosureButton
                FindFieldContainer {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                        TextField("Find", text: $state.query)
                            .textFieldStyle(.plain)
                            .focused($findFocused)
                            .onSubmit { state.next() }
                    }
                }
                HStack(spacing: 4) {
                    FindToggleButton(isOn: $state.options.caseSensitive, label: "Aa",
                                     help: "Match Case — only matches that share casing")
                    FindToggleButton(isOn: $state.options.wholeWord, label: "W",
                                     help: "Whole Word — match only at word boundaries")
                    FindToggleButton(isOn: $state.options.useRegex, label: ".*",
                                     help: "Regular Expression — treat query as regex")
                }
                Text(countText)
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(state.patternInvalid ? Color.red : .secondary)
                    .frame(minWidth: 88, alignment: .trailing)
                HStack(spacing: 2) {
                    Button(action: { state.prev() }) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.totalMatches == 0)
                    .help("Previous Match (⇧⌘G)")
                    Button(action: { state.next() }) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.totalMatches == 0)
                    .help("Next Match (⌘G)")
                }
                Button(action: { state.close() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close Find (Esc)")
            }
            if canReplace && state.replaceVisible {
                HStack(spacing: 10) {
                    FindFieldContainer {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                            TextField("Replace", text: $state.replacement)
                                .textFieldStyle(.plain)
                        }
                    }
                    Button("Replace") { state.replaceCurrent() }
                        .disabled(state.totalMatches == 0)
                        .help("Replace Current Match")
                    Button("Replace All") { state.replaceAll() }
                        .disabled(state.totalMatches == 0)
                        .help("Replace All Matches")
                }
                .padding(.leading, 26)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .onAppear { findFocused = true }
        .onChange(of: state.isActive) { new in
            if new { findFocused = true }
        }
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if canReplace {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    state.replaceVisible.toggle()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(state.replaceVisible ? 90 : 0))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(state.replaceVisible ? "Hide Replace" : "Show Replace (⌥⌘F)")
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var countText: String {
        if state.patternInvalid { return "Invalid pattern" }
        if state.query.isEmpty { return "" }
        if state.totalMatches == 0 { return "No matches" }
        return "\(state.currentMatch) of \(state.totalMatches)"
    }
}

private func editorFont() -> NSFont {
    let size: CGFloat = 15
    let base = NSFont.systemFont(ofSize: size)
    if let descriptor = base.fontDescriptor.withDesign(.serif),
       let serif = NSFont(descriptor: descriptor, size: size) {
        return serif
    }
    return NSFont(name: "Georgia", size: size) ?? base
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let sync: ScrollSync?
    @ObservedObject var findState: FindState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.smartInsertDeleteEnabled = false
        textView.font = editorFont()
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 28, height: 24)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: textView.font!,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        textView.string = text

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        sync?.scrollEditorTo = { [weak coordinator = context.coordinator] fraction in
            coordinator?.scroll(to: fraction)
        }
        findState.replaceCurrent = { [weak coordinator = context.coordinator] in
            coordinator?.replaceCurrent()
        }
        findState.replaceAll = { [weak coordinator = context.coordinator] in
            coordinator?.replaceAll()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            textView.didChangeText()
            context.coordinator.applyQuery(findState.isActive ? findState.query : "",
                                           options: findState.options)
        }
        context.coordinator.syncFind(query: findState.isActive ? findState.query : "",
                                      options: findState.options,
                                      currentIndex: findState.currentMatch - 1)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        private var matches: [NSRange] = []
        private var lastQuery = ""
        private var lastOptions = FindOptions()
        private var lastIndex = -1

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyQuery(parent.findState.isActive ? parent.findState.query : "",
                       options: parent.findState.options)
        }

        @objc func boundsChanged(_ note: Notification) {
            guard let sync = parent.sync,
                  let scrollView,
                  let textView else { return }
            let clip = scrollView.contentView
            let docHeight = textView.frame.height
            let visible = clip.bounds.height
            let range = docHeight - visible
            guard range > 0 else { return }
            let y = min(range, Swift.max(0, clip.bounds.origin.y))
            sync.editorDidScroll(to: Double(y / range))
        }

        func scroll(to fraction: Double) {
            guard let scrollView, let textView else { return }
            let docHeight = textView.frame.height
            let visible = scrollView.contentView.bounds.height
            let range = docHeight - visible
            guard range > 0 else { return }
            let y = range * CGFloat(fraction)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func syncFind(query: String, options: FindOptions, currentIndex: Int) {
            if query != lastQuery || options != lastOptions {
                applyQuery(query, options: options)
            }
            if currentIndex != lastIndex {
                lastIndex = currentIndex
                scrollToMatch(currentIndex)
                rehighlightActive(currentIndex)
            }
        }

        func applyQuery(_ query: String, options: FindOptions) {
            lastQuery = query
            lastOptions = options
            lastIndex = -1
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            matches.removeAll()

            var patternInvalid = false
            if !query.isEmpty {
                if let regex = buildFindRegex(query: query, options: options) {
                    let text = storage.string
                    let ns = text as NSString
                    let range = NSRange(location: 0, length: ns.length)
                    matches = regex.matches(in: text, range: range).map { $0.range }
                    for range in matches {
                        storage.addAttribute(.backgroundColor,
                                             value: NSColor.systemYellow.withAlphaComponent(0.35),
                                             range: range)
                    }
                } else if options.useRegex {
                    patternInvalid = true
                }
            }
            storage.endEditing()

            let count = matches.count
            let newCurrent = count > 0 ? 1 : 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.findState.patternInvalid != patternInvalid {
                    self.parent.findState.patternInvalid = patternInvalid
                }
                if self.parent.findState.totalMatches != count {
                    self.parent.findState.totalMatches = count
                }
                if self.parent.findState.currentMatch != newCurrent {
                    self.parent.findState.currentMatch = newCurrent
                }
            }
        }

        func rehighlightActive(_ index: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)
            for (i, range) in matches.enumerated() {
                let color = (i == index)
                    ? NSColor.systemOrange.withAlphaComponent(0.6)
                    : NSColor.systemYellow.withAlphaComponent(0.35)
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            storage.endEditing()
        }

        func scrollToMatch(_ index: Int) {
            guard index >= 0, index < matches.count, let textView else { return }
            let range = matches[index]
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        func replaceCurrent() {
            guard let textView, let storage = textView.textStorage else { return }
            let idx = parent.findState.currentMatch - 1
            guard idx >= 0, idx < matches.count else { return }
            let range = matches[idx]
            let replacement = parent.findState.replacement
            if textView.shouldChangeText(in: range, replacementString: replacement) {
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
            }
        }

        func replaceAll() {
            guard let textView, let storage = textView.textStorage else { return }
            guard !matches.isEmpty else { return }
            let replacement = parent.findState.replacement
            let fullRange = NSRange(location: 0, length: storage.length)
            guard textView.shouldChangeText(in: fullRange, replacementString: "") else { return }
            storage.beginEditing()
            for range in matches.reversed() {
                storage.replaceCharacters(in: range, with: replacement)
            }
            storage.endEditing()
            textView.didChangeText()
        }
    }
}

struct MarkdownView: NSViewRepresentable {
    let text: String
    let sync: ScrollSync?
    @ObservedObject var findState: FindState

    func makeCoordinator() -> Coordinator { Coordinator(sync: sync) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "scroll")
        config.userContentController = controller

        let webView = ZoomableWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        context.coordinator.registerZoomObservers()

        sync?.scrollPreviewTo = { [weak coordinator = context.coordinator] fraction in
            coordinator?.scroll(to: fraction)
        }

        if let url = Bundle.main.url(forResource: "viewer", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingMarkdown = text
        context.coordinator.pendingQuery = findState.isActive ? findState.query : ""
        context.coordinator.pendingOptions = findState.options
        context.coordinator.pendingIndex = findState.currentMatch - 1
        context.coordinator.applyPending()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingMarkdown: String?
        var pendingQuery: String = ""
        var pendingOptions = FindOptions()
        var pendingIndex: Int = -1
        var renderedMarkdown: String?
        var renderedQuery: String?
        var renderedOptions = FindOptions()
        var renderedIndex: Int = -1
        var ready = false
        let sync: ScrollSync?

        init(sync: ScrollSync?) { self.sync = sync }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            renderedMarkdown = nil
            renderedQuery = nil
            renderedIndex = -1
            applyPending()
        }

        func applyPending() {
            guard ready, let webView else { return }
            if let md = pendingMarkdown, md != renderedMarkdown {
                renderedMarkdown = md
                let encoded = Data(md.utf8).base64EncodedString()
                webView.evaluateJavaScript("window.renderMarkdown(\"\(encoded)\")", completionHandler: nil)
                renderedQuery = nil
                renderedIndex = -1
            }
            if pendingQuery != renderedQuery || pendingOptions != renderedOptions {
                renderedQuery = pendingQuery
                renderedOptions = pendingOptions
                let encoded = Data(pendingQuery.utf8).base64EncodedString()
                let opts = "{caseSensitive:\(pendingOptions.caseSensitive),wholeWord:\(pendingOptions.wholeWord),useRegex:\(pendingOptions.useRegex)}"
                webView.evaluateJavaScript("window.setFindQuery(\"\(encoded)\", \(opts))", completionHandler: nil)
            }
            if pendingIndex != renderedIndex {
                renderedIndex = pendingIndex
                webView.evaluateJavaScript("window.setFindIndex(\(pendingIndex))", completionHandler: nil)
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scroll",
                  let fraction = message.body as? Double else { return }
            sync?.previewDidScroll(to: fraction)
        }

        func scroll(to fraction: Double) {
            guard ready, let webView else { return }
            webView.evaluateJavaScript("window.scrollToFraction(\(fraction))", completionHandler: nil)
        }

        static let zoomMin: CGFloat = 0.5
        static let zoomMax: CGFloat = 3.0

        func registerZoomObservers() {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(zoomIn), name: .zoomIn, object: nil)
            nc.addObserver(self, selector: #selector(zoomOut), name: .zoomOut, object: nil)
            nc.addObserver(self, selector: #selector(zoomReset), name: .zoomReset, object: nil)
            nc.addObserver(self, selector: #selector(copyRichText), name: .copyRichText, object: nil)
        }

        private func isFrontmost() -> Bool {
            guard let webView, let win = webView.window else { return false }
            return win.isKeyWindow || win.isMainWindow
        }

        private func applyZoom(_ value: CGFloat) {
            guard let webView = webView as? ZoomableWebView else { return }
            let clamped = max(Coordinator.zoomMin, min(Coordinator.zoomMax, value))
            if abs(clamped - webView.currentZoom) < 0.0001 { return }
            webView.currentZoom = clamped
            webView.evaluateJavaScript("window.setZoom(\(clamped))", completionHandler: nil)
        }

        @objc func zoomIn() {
            guard isFrontmost(), let webView = webView as? ZoomableWebView else { return }
            applyZoom(webView.currentZoom + 0.1)
        }

        @objc func zoomOut() {
            guard isFrontmost(), let webView = webView as? ZoomableWebView else { return }
            applyZoom(webView.currentZoom - 0.1)
        }

        @objc func zoomReset() {
            guard isFrontmost() else { return }
            applyZoom(1.0)
        }

        @objc func copyRichText() {
            guard isFrontmost(), ready, let webView else { return }
            webView.evaluateJavaScript("window.getRichContent()") { result, _ in
                guard let dict = result as? [String: Any] else { return }
                let html = dict["html"] as? String ?? ""
                let text = dict["text"] as? String ?? ""
                guard !html.isEmpty || !text.isEmpty else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.declareTypes([.html, .string], owner: nil)
                pb.setString(html, forType: .html)
                pb.setString(text, forType: .string)
            }
        }
    }
}

final class ZoomableWebView: WKWebView {
    var currentZoom: CGFloat = 1.0

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            if delta == 0 {
                return
            }
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.08
            let next = currentZoom * (1.0 + delta * factor)
            let clamped = max(MarkdownView.Coordinator.zoomMin,
                              min(MarkdownView.Coordinator.zoomMax, next))
            if abs(clamped - currentZoom) < 0.0001 {
                return
            }
            currentZoom = clamped
            evaluateJavaScript("window.setZoom(\(clamped))", completionHandler: nil)
            return
        }
        super.scrollWheel(with: event)
    }
}
