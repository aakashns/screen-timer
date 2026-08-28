import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let tracker = ScreenTimeTracker()
    private let overlay = OverlayController()
    private var statusItem: NSStatusItem!
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay), keyEquivalent: "")

    private var tickTimer: Timer?
    private var refreshTimer: Timer?

    private var positionItems: [OverlayCorner: NSMenuItem] = [:]

    private let enabledKey = "overlayEnabled"
    private let positionKey = "overlayCorner"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [enabledKey: true])

        setUpStatusItem()
        if let raw = defaults.string(forKey: positionKey), let corner = OverlayCorner(rawValue: raw) {
            overlay.setCorner(corner)
        }
        overlay.setEnabled(defaults.bool(forKey: enabledKey))
        toggleItem.state = overlay.isEnabled ? .on : .off
        syncPositionItems()

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

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for corner in OverlayCorner.allCases {
            let item = NSMenuItem(title: corner.title, action: #selector(setPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = corner.rawValue
            positionMenu.addItem(item)
            positionItems[corner] = item
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        menu.addItem(.separator())

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

    @objc private func setPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = OverlayCorner(rawValue: raw) else { return }
        overlay.setCorner(corner)
        UserDefaults.standard.set(raw, forKey: positionKey)
        syncPositionItems()
    }

    private func syncPositionItems() {
        for (corner, item) in positionItems {
            item.state = corner == overlay.corner ? .on : .off
        }
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
