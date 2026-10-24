import Cocoa
import WebKit

// MARK: - 锁屏

enum ScreenLocker {
    /// 优先用系统登录框架的 SACLockScreenImmediate（等同菜单栏“锁定屏幕” ⌃⌘Q），失败时让显示器休眠。
    static func lock() {
        typealias LockFn = @convention(c) () -> Int32
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let sym = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(sym, to: LockFn.self)()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }
}

// MARK: - 计时器

final class CountdownTimer {
    static let warnLead: TimeInterval = 60

    private(set) var endDate: Date?
    private(set) var total: TimeInterval = 0
    private var warned = false
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    var onChange: (() -> Void)?
    var onWarn: (() -> Void)?
    var onFire: (() -> Void)?

    var isRunning: Bool { endDate != nil }
    var remaining: TimeInterval { max(0, endDate?.timeIntervalSinceNow ?? 0) }

    func start(seconds: TimeInterval) {
        stopTimer()
        total = seconds
        endDate = Date().addingTimeInterval(seconds)
        warned = seconds <= Self.warnLead
        // 防止 App Nap 拖慢计时
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "定时锁屏倒计时")
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        onChange?()
    }

    func extend(by seconds: TimeInterval) {
        guard let end = endDate else { return }
        endDate = end.addingTimeInterval(seconds)
        total += seconds
        if remaining > Self.warnLead { warned = false }
        onChange?()
    }

    func cancel() {
        stopTimer()
        onChange?()
    }

    func tick() {
        guard isRunning else { return }
        let left = remaining
        if left <= 0 {
            stopTimer()
            onChange?()
            onFire?()
        } else if left <= Self.warnLead && !warned {
            warned = true
            onWarn?()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
    }
}

// MARK: - 偏好

enum Prefs {
    private static let d = UserDefaults.standard
    static var value: String {
        get { d.string(forKey: "value") ?? "25" }
        set { d.set(newValue, forKey: "value") }
    }
    static var unit: String {
        get { d.string(forKey: "unit") ?? "min" }
        set { d.set(newValue, forKey: "unit") }
    }
    static var warn: Bool {
        get { d.object(forKey: "warn") as? Bool ?? true }
        set { d.set(newValue, forKey: "warn") }
    }
}

// MARK: - 窗口

/// 标题栏区域的拖动条（网页铺满窗口，需要它来拖动窗口）
final class DragStrip: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

final class MainWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    let timer: CountdownTimer
    private var webView: WKWebView!

    init(timer: CountdownTimer) {
        self.timer = timer
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "定时锁屏"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x13 / 255, green: 0x14 / 255, blue: 0x1C / 255, alpha: 1)
                : .white
        }
        window.center()
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)

        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptHandler(self), name: "app")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self

        let content = NSView()
        window.contentView = content
        let drag = DragStrip()
        for v in [webView!, drag] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            drag.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 80),
            drag.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            drag.topAnchor.constraint(equalTo: content.topAnchor),
            drag.heightAnchor.constraint(equalToConstant: 34),
        ])

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(activate: Bool = true) {
        if activate {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window?.orderFrontRegardless()
        }
    }

    func pushState(warning: Bool = false) {
        let state: [String: Any] = [
            "running": timer.isRunning,
            "endMs": (timer.endDate?.timeIntervalSince1970 ?? 0) * 1000,
            "totalSec": timer.total,
            "value": Prefs.value,
            "unit": Prefs.unit,
            "warn": Prefs.warn,
            "warning": warning,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.appState && window.appState(\(json))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { pushState() }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "start":
            guard let seconds = body["seconds"] as? Double, seconds >= 1 else { return }
            if let v = body["value"] as? String { Prefs.value = v }
            if let u = body["unit"] as? String { Prefs.unit = u }
            timer.start(seconds: seconds)
        case "extend":
            if let seconds = body["seconds"] as? Double { timer.extend(by: seconds) }
        case "cancel":
            timer.cancel()
        case "lockNow":
            timer.cancel()
            ScreenLocker.lock()
        case "setWarn":
            Prefs.warn = body["on"] as? Bool ?? true
        default:
            break
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let timer = CountdownTimer()
    var windowController: MainWindowController!
    var statusItem: NSStatusItem!
    var statusTick: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMainMenu()
        windowController = MainWindowController(timer: timer)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        timer.onChange = { [weak self] in self?.timerChanged() }
        timer.onWarn = { [weak self] in self?.timerWarn() }
        timer.onFire = { ScreenLocker.lock() }

        // 睡眠唤醒后立即检查是否已过点
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.timer.tick() }

        updateStatusItem()
        windowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard timer.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "定时锁屏正在进行"
        alert.informativeText = "退出后将取消本次定时，不会自动锁屏。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "继续定时")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: 计时回调

    private func timerChanged() {
        windowController.pushState()
        updateStatusItem()
        statusTick?.invalidate()
        statusTick = nil
        if timer.isRunning {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatusItem() }
            RunLoop.main.add(t, forMode: .common)
            statusTick = t
        }
    }

    private func timerWarn() {
        NSSound(named: "Tink")?.play()
        windowController.pushState(warning: true)
        if Prefs.warn {
            // 不抢键盘焦点，只把窗口浮到最前
            windowController.show(activate: false)
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    // MARK: 菜单栏

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol = timer.isRunning ? "lock.fill" : "lock.open"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "定时锁屏")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        if timer.isRunning {
            button.attributedTitle = NSAttributedString(
                string: " " + Self.format(timer.remaining),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)])
        } else {
            button.title = ""
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if timer.isRunning {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            let info = NSMenuItem(title: "将于 \(f.string(from: timer.endDate!)) 锁屏 · 剩余 \(Self.format(timer.remaining))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            menu.addItem(item("延长 5 分钟", #selector(extend(_:)), tag: 5 * 60))
            menu.addItem(item("延长 15 分钟", #selector(extend(_:)), tag: 15 * 60))
            menu.addItem(item("取消定时", #selector(cancelTimer)))
        } else {
            for (title, sec) in [("15 分钟后锁屏", 15 * 60), ("30 分钟后锁屏", 30 * 60),
                                 ("1 小时后锁屏", 3600), ("2 小时后锁屏", 7200)] {
                menu.addItem(item(title, #selector(startPreset(_:)), tag: sec))
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("立即锁屏", #selector(lockNow)))
        menu.addItem(item("打开定时锁屏…", #selector(showWindow)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.tag = tag
        return i
    }

    @objc private func startPreset(_ sender: NSMenuItem) { timer.start(seconds: TimeInterval(sender.tag)) }
    @objc private func extend(_ sender: NSMenuItem) { timer.extend(by: TimeInterval(sender.tag)) }
    @objc private func cancelTimer() { timer.cancel() }
    @objc private func lockNow() { timer.cancel(); ScreenLocker.lock() }
    @objc private func showWindow() { windowController.show() }

    // MARK: 主菜单（提供 ⌘Q / ⌘W / 复制粘贴等快捷键）

    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于定时锁屏", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏定时锁屏", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出定时锁屏", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for sub in [appMenu, editMenu, windowMenu] {
            let holder = NSMenuItem()
            holder.submenu = sub
            main.addItem(holder)
        }
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
