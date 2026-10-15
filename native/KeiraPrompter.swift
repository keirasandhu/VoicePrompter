import AppKit
import SwiftUI
import AVFoundation
import Speech
import Combine

struct SavedScript: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var text: String
}

@MainActor final class PrompterModel: NSObject, ObservableObject {
    @Published var scripts: [SavedScript] = []
    @Published var selectedID: UUID?
    @Published var title = "My script"
    @Published var text = "Paste your script here.\n\n[Pause]\n\nYour words will follow your voice when you start listening."
    @Published var fontSize: Double = 32
    @Published var opacity: Double = 0.90
    @Published var speed: Double = 30
    @Published var listening = false
    @Published var scrolling = false
    @Published var highlight = NSRange(location: 0, length: 0)
    @Published var scrollOffset: CGFloat = 0
    @Published var status = "Ready. Scripts stay on this Mac."
    private var engine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var renewal: Timer?
    private var tokens: [(String, NSRange)] = []
    private var cursor = 0
    private var generation = 0
    private var consecutiveFailures = 0
    private var tapped = false
    private var subscriptions = Set<AnyCancellable>()
    var showEditor: (() -> Void)?
    var showOverlay: (() -> Void)?
    private let file: URL

    init(storage: URL? = nil) {
        file = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keira Prompter/scripts.json")
        super.init()
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([SavedScript].self, from: data) {
            scripts = list
            if let first = list.first { selectedID = first.id; title = first.title; text = first.text }
        }
        fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 32
        opacity = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 0.90
        $fontSize.dropFirst().sink { UserDefaults.standard.set($0, forKey: "fontSize") }.store(in: &subscriptions)
        $opacity.dropFirst().sink { UserDefaults.standard.set($0, forKey: "opacity") }.store(in: &subscriptions)
        Publishers.CombineLatest($text, $title).dropFirst().debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }.store(in: &subscriptions)
        tokenize()
    }
    func save() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = selectedID ?? UUID(); selectedID = id
        let entry = SavedScript(id: id, title: title.isEmpty ? "Untitled" : title, text: text)
        if let i = scripts.firstIndex(where: { $0.id == id }) { scripts[i] = entry } else { scripts.insert(entry, at: 0) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(scripts).write(to: file, options: .atomic)
        } catch { status = "Could not save: \(error.localizedDescription)" }
    }
    func select(_ id: UUID?) {
        guard let entry = scripts.first(where: { $0.id == id }) else { return }
        stopListening(); stopScrolling(); selectedID = id; title = entry.title; text = entry.text; reset()
    }
    func newScript() { save(); stopListening(); stopScrolling(); selectedID = nil; title = "New script"; text = ""; reset() }
    func importText() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .text]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { let value = try String(contentsOf: url, encoding: .utf8); newScript(); title = url.deletingPathExtension().lastPathComponent; text = value; save() }
            catch { status = "Could not import: \(error.localizedDescription)" }
        }
    }
    func tokenize() {
        let string = text as NSString
        let cues = (try? NSRegularExpression(pattern: "\\[[^\\]]*\\]"))?.matches(in: text, range: NSRange(location: 0, length: string.length)).map(\.range) ?? []
        tokens = ((try? NSRegularExpression(pattern: "[\\p{L}\\p{N}'’]+"))?.matches(in: text, range: NSRange(location: 0, length: string.length)) ?? []).filter { match in
            !cues.contains { NSIntersectionRange($0, match.range).length > 0 }
        }.map { (string.substring(with: $0.range).lowercased().replacingOccurrences(of: "’", with: "'"), $0.range) }
    }
    func reset() { cursor = 0; tokenize(); highlight = tokens.first?.1 ?? NSRange(location: 0, length: 0); scrollOffset = 0 }
    func present() { save(); reset(); showOverlay?() }
    func toggleVoice() {
        if listening { stopListening(); return }
        stopScrolling(); save(); tokenize(); consecutiveFailures = 0
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                guard let self else { return }
                guard auth == .authorized else { self.status = "Allow Speech Recognition in System Settings → Privacy & Security."; return }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else { self.status = "Allow Microphone access in System Settings → Privacy & Security."; return }
                        self.beginListening()
                    }
                }
            }
        }
    }
    private func beginListening() {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status = "On-device English recognition is unavailable. Use Auto-scroll, or enable English dictation in macOS settings."; return
        }
        generation += 1; let currentGeneration = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true; req.requiresOnDeviceRecognition = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { status = "No usable microphone. Check the default input in Sound settings."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        tapped = true
        do { engine.prepare(); try engine.start() }
        catch { listening = false; cleanupAudio(); status = "Microphone error: \(error.localizedDescription)"; return }
        listening = true; status = "Listening on this Mac · English (UK)"
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration, self.listening else { return }
                if let result { self.consecutiveFailures = 0; self.follow(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true {
                    if error != nil { self.consecutiveFailures += 1 }
                    if self.consecutiveFailures >= 3 {
                        self.stopListening(); self.status = "Voice recognition stopped. Check English dictation and the microphone, then try again."; return
                    }
                    self.cleanupAudio()
                    self.renewal?.invalidate()
                    self.renewal = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                        Task { @MainActor in if self?.listening == true { self?.beginListening() } }
                    }
                }
            }
        }
        renewal?.invalidate()
        renewal = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.listening else { return }
                self.generation += 1; self.cleanupAudio(); self.beginListening()
            }
        }
    }
    func follow(_ transcript: String) {
        let spokenText = transcript as NSString
        let spokenMatches = (try? NSRegularExpression(pattern: "[\\p{L}\\p{N}'’]+"))?.matches(in: transcript, range: NSRange(location: 0, length: spokenText.length)) ?? []
        let spoken = spokenMatches.map { spokenText.substring(with: $0.range).lowercased().replacingOccurrences(of: "’", with: "'") }
        guard !spoken.isEmpty, !tokens.isEmpty else { return }
        let end = min(tokens.count, cursor + 45), start = max(0, cursor - 4)
        guard start < end else { return }
        var bestIndex: Int?; var bestScore = 0
        for i in start..<end {
            guard tokens[i].0 == spoken.last! else { continue }
            var score = 1
            for distance in 1..<min(6, spoken.count) {
                if i-distance >= 0 && tokens[i-distance].0 == spoken[spoken.count-1-distance] { score += 1 } else { break }
            }
            if score > bestScore || (score == bestScore && bestIndex.map({ abs(i-cursor) < abs($0-cursor) }) == true) { bestScore = score; bestIndex = i }
        }
        if let index = bestIndex, bestScore >= 2 || (bestScore == 1 && abs(index-cursor) <= 2) {
            cursor = min(index + 1, tokens.count - 1); highlight = tokens[cursor].1
        }
    }
    private func cleanupAudio() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
    func stopListening() { listening = false; generation += 1; renewal?.invalidate(); renewal = nil; cleanupAudio(); status = "Paused" }
    func toggleScroll() {
        if scrolling { stopScrolling(); return }
        stopListening(); scrolling = true; status = "Auto-scrolling"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.scrollOffset += self.speed / 30 }
        }
    }
    func stopScrolling() { timer?.invalidate(); timer = nil; if scrolling { status = "Paused" }; scrolling = false }
}

struct ReadingText: NSViewRepresentable {
    @ObservedObject var model: PrompterModel
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 24, height: 32); scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let style = NSMutableParagraphStyle(); style.lineSpacing = 12; style.paragraphSpacing = 22
        let value = NSMutableAttributedString(string: model.text, attributes: [.font: NSFont.systemFont(ofSize: model.fontSize, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: style])
        let range = NSRange(location: 0, length: value.length)
        if let regex = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]") {
            for match in regex.matches(in: model.text, range: range) { value.addAttribute(.foregroundColor, value: NSColor.gray, range: match.range) }
        }
        if NSMaxRange(model.highlight) <= value.length, model.highlight.length > 0 {
            value.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: model.highlight)
        }
        view.textStorage?.setAttributedString(value)
        if model.scrolling {
            let maxY = max(0, view.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(model.scrollOffset, maxY))); scroll.reflectScrolledClipView(scroll.contentView)
        } else if model.listening { view.scrollRangeToVisible(model.highlight) }
        else if model.scrollOffset == 0 && model.highlight.location == 0 { view.scrollRangeToVisible(NSRange(location: 0, length: 0)) }
    }
}

struct OverlayView: View {
    @ObservedObject var model: PrompterModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keira Prompter").font(.system(size: 12, weight: .semibold)); Spacer()
                Button("Editor") { model.showEditor?() }
                Button("Hide") { model.stopListening(); model.stopScrolling(); NSApp.windows.first(where: { $0.title == "Reading window" })?.orderOut(nil) }
            }.padding(12)
            Divider()
            ReadingText(model: model)
            Divider()
            HStack {
                Button(model.listening ? "Pause voice" : "Follow voice") { model.toggleVoice() }
                Button(model.scrolling ? "Pause scroll" : "Auto-scroll") { model.toggleScroll() }
                Button("Restart") { model.reset() }
                Spacer()
                Button("A−") { model.fontSize = max(16, model.fontSize-2) }
                Button("A+") { model.fontSize = min(80, model.fontSize+2) }
            }.padding(12)
            HStack {
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 12).padding(.bottom, 10)
        }.background(Color.black.opacity(model.opacity)).foregroundStyle(.white)
            .preferredColorScheme(.dark)
    }
}

struct EditorView: View {
    @ObservedObject var model: PrompterModel
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR SCRIPTS").font(.caption).foregroundStyle(.secondary)
                List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                    ForEach(model.scripts) { entry in Text(entry.title).tag(entry.id) }
                }
                Button("New script") { model.newScript() }
                Button("Import text file…") { model.importText() }
            }.padding(16).frame(minWidth: 160, idealWidth: 190, maxWidth: 240)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Script title", text: $model.title).font(.title2).textFieldStyle(.plain)
                    Button("Save") { model.save() }.keyboardShortcut("s")
                }
                TextEditor(text: $model.text).font(.system(size: 17)).padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Text("Text size"); Slider(value: $model.fontSize, in: 16...64).frame(maxWidth: 160)
                    Text("\(Int(model.fontSize))").monospacedDigit()
                    Spacer(); Text("Opacity"); Slider(value: $model.opacity, in: 0.35...1).frame(maxWidth: 120)
                }
                HStack {
                    Text("Auto-scroll speed"); Slider(value: $model.speed, in: 5...100).frame(maxWidth: 220)
                    Spacer()
                    Button("Open reading window") { model.present() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                }
                Text("Place the reading window near your camera. [Bracketed cues] are skipped by voice following.").font(.caption).foregroundStyle(.secondary)
                Text("Capture hiding is not guaranteed on modern macOS. Keep the reading window outside a CleanShot region recording until a real capture test passes.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(minWidth: 500)
        }.frame(minWidth: 800, minHeight: 540)
    }
}

final class ReadingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PrompterModel()
    var editor: NSWindow!
    var overlay: NSPanel!
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let appMenu = NSMenu(); let root = NSMenuItem(); root.submenu = appMenu; menu.addItem(root)
        appMenu.addItem(withTitle: "Show editor", action: #selector(showEditor), keyEquivalent: "e").target = self
        appMenu.addItem(withTitle: "Show reading window", action: #selector(showReading), keyEquivalent: "r").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Keira Prompter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit"); let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editRoot.submenu = editMenu; menu.addItem(editRoot)
        for (title, action, key) in [("Undo", "undo:", "z"),("Cut", "cut:", "x"),("Copy", "copy:", "c"),("Paste", "paste:", "v"),("Select All", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
        editor = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1000,height: 680), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        editor.title = "Keira Prompter"; editor.isReleasedWhenClosed = false; editor.center(); editor.delegate = self
        editor.contentView = NSHostingView(rootView: EditorView(model: model))
        overlay = ReadingPanel(contentRect: NSRect(x: 160,y: 180,width: 650,height: 420), styleMask: [.titled,.closable,.resizable,.nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = "Reading window"; overlay.isReleasedWhenClosed = false
        overlay.level = .floating; overlay.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.titlebarAppearsTransparent = true
        overlay.isMovableByWindowBackground = true; overlay.sharingType = .none; overlay.hidesOnDeactivate = false
        overlay.delegate = self; overlay.contentView = NSHostingView(rootView: OverlayView(model: model))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Keira Prompter")
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "Open editor", action: #selector(showEditor), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Open reading window", action: #selector(showReading), keyEquivalent: "").target = self
        statusMenu.addItem(.separator()); statusMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = statusMenu
        model.showEditor = { [weak self] in self?.showEditor() }; model.showOverlay = { [weak self] in self?.overlay.makeKeyAndOrderFront(nil) }
        showEditor()
    }
    @objc func showEditor() { if model.listening { model.stopListening() }; model.stopScrolling(); editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showReading() { model.present() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showEditor(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === overlay { model.stopListening(); model.stopScrolling() }
    }
    func applicationWillTerminate(_ notification: Notification) { model.save(); model.stopListening(); model.stopScrolling() }
}
@main struct KeiraPrompter {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            runSelfTests(); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor func runSelfTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keira-prompter-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("scripts.json")
    let model = PrompterModel(storage: store)
    func current() -> String { (model.text as NSString).substring(with: model.highlight) }
    model.text = "One two [pause] three four five"; model.reset()
    model.follow("one two"); precondition(current() == "three", "Must follow speech across a bracketed cue")
    model.follow("pause"); precondition(current() == "three", "Stage direction must not advance position")
    model.follow("three four"); precondition(current() == "five", "Must continue through a new speech result")
    model.reset(); precondition(current() == "One", "Restart must reset position")
    model.text = "We build systems and we build proof"; model.reset()
    model.follow("we build"); precondition(current() == "systems", "Repeated phrases must select the nearby occurrence")
    model.text = "We don’t waste time today"; model.reset()
    model.follow("we don't"); precondition(current() == "waste", "Apostrophe styles must align")
    model.title = "Test script"; model.save()
    let restored = PrompterModel(storage: store)
    precondition(restored.text == model.text && restored.title == "Test script", "Saved scripts must survive restart")
    print("PASS: cue skipping, partial-result progress, restart, repeated phrases, contractions, script save/reload")
}
