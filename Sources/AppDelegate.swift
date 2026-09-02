import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let tracker = ScreenTimeTracker()
    private let overlay = OverlayController()
    private var statusItem: NSStatusItem!
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay), keyEquivalent: "")

    private var tickTimer: Timer?
    private var refreshTimer: Timer?

    /// Submenu items keyed by the raw value they select, per submenu.
    private var positionItems: [String: NSMenuItem] = [:]
    private var sizeItems: [String: NSMenuItem] = [:]
    private var transparencyItems: [String: NSMenuItem] = [:]

    private let enabledKey = "overlayEnabled"
    private let positionKey = "overlayCorner"
    private let sizeKey = "overlaySize"
    /// Deliberately not "overlayTransparency". The scale was relabelled after
    /// that key shipped: the old `low` (0.45) is now `medium`, and `low` is a new
    /// more opaque step. Reading under a new key drops the stale value so an
    /// existing install keeps the appearance it already had.
    private let transparencyKey = "overlayTransparencyLevel"
    private let legacyTransparencyKey = "overlayTransparency"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [enabledKey: true])
        defaults.removeObject(forKey: legacyTransparencyKey)

        setUpStatusItem()
        if let raw = defaults.string(forKey: positionKey), let corner = OverlayCorner(rawValue: raw) {
            overlay.setCorner(corner)
        }
        if let raw = defaults.string(forKey: sizeKey), let size = OverlaySize(rawValue: raw) {
            overlay.setSize(size)
        }
        if let raw = defaults.string(forKey: transparencyKey), let value = OverlayTransparency(rawValue: raw) {
            overlay.setTransparency(value)
        }
        overlay.setEnabled(defaults.bool(forKey: enabledKey))
        toggleItem.state = overlay.isEnabled ? .on : .off
        syncOptionItems()

        tracker.refresh()
        update()

        tickTimer = schedule(every: 1) { [weak self] in
            self?.tracker.tick()
            self?.update()
        }
        // Re-read pmset periodically so we stay correct across display sleep.
        refreshTimer = schedule(every: 60) { [weak self] in self?.tracker.refresh() }

        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.didWakeNotification,
                                          NSWorkspace.screensDidWakeNotification,
                                          NSWorkspace.screensDidSleepNotification,
                                          NSWorkspace.willSleepNotification] {
            workspace.addObserver(self, selector: #selector(powerStateChanged), name: name, object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.save()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen time today")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        menu.delegate = self

        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        toggleItem.target = self
        menu.addItem(toggleItem)

        positionItems = addSubmenu(to: menu, title: "Position",
                                   options: OverlayCorner.allCases.map { ($0.rawValue, $0.title) },
                                   action: #selector(setPosition(_:)))
        sizeItems = addSubmenu(to: menu, title: "Size",
                               options: OverlaySize.allCases.map { ($0.rawValue, $0.title) },
                               action: #selector(setSize(_:)))
        transparencyItems = addSubmenu(to: menu, title: "Transparency",
                                       options: OverlayTransparency.allCases.map { ($0.rawValue, $0.title) },
                                       action: #selector(setTransparency(_:)))
        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Timer", action: #selector(resetTimer), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)

        let quit = NSMenuItem(title: "Quit Screen Timer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        update()
    }

    // MARK: - Actions

    @objc private func toggleOverlay() {
        let enabled = !overlay.isEnabled
        overlay.setEnabled(enabled)
        toggleItem.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        update()
    }

    /// - Returns: the created items, keyed by the raw value each one selects.
    private func addSubmenu(to menu: NSMenu,
                            title: String,
                            options: [(raw: String, title: String)],
                            action: Selector) -> [String: NSMenuItem] {
        let submenu = NSMenu()
        var items: [String: NSMenuItem] = [:]
        for option in options {
            let item = NSMenuItem(title: option.title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = option.raw
            submenu.addItem(item)
            items[option.raw] = item
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
        return items
    }

    @objc private func setPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = OverlayCorner(rawValue: raw) else { return }
        overlay.setCorner(corner)
        UserDefaults.standard.set(raw, forKey: positionKey)
        syncOptionItems()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = OverlaySize(rawValue: raw) else { return }
        overlay.setSize(size)
        UserDefaults.standard.set(raw, forKey: sizeKey)
        syncOptionItems()
    }

    @objc private func setTransparency(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let value = OverlayTransparency(rawValue: raw) else { return }
        overlay.setTransparency(value)
        UserDefaults.standard.set(raw, forKey: transparencyKey)
        syncOptionItems()
    }

    @objc private func resetTimer() {
        tracker.reset()
        update()
    }

    private func syncOptionItems() {
        for (raw, item) in positionItems { item.state = raw == overlay.corner.rawValue ? .on : .off }
        for (raw, item) in sizeItems { item.state = raw == overlay.size.rawValue ? .on : .off }
        for (raw, item) in transparencyItems { item.state = raw == overlay.transparency.rawValue ? .on : .off }
    }

    @objc private func powerStateChanged() {
        tracker.save()
        tracker.refresh()
        update()
    }

    // MARK: - Refresh

    private func update() {
        let text = tracker.formattedToday
        overlay.setText(text)
        // The overlay already shows the time; only duplicate it in the menu bar
        // when the overlay is switched off.
        statusItem.button?.attributedTitle = NSAttributedString(
            string: overlay.isEnabled ? "" : " " + text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
        headerItem.title = "Screen on today: \(text)"
    }

    private func schedule(every interval: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in body() }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
