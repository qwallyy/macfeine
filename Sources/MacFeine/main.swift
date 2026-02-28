import AppKit
import Foundation
import IOKit.pwr_mgt

final class SleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private(set) var isActive = false
    private(set) var currentSelection: DurationOption?
    private(set) var expiresAt: Date?

    func activate(_ option: DurationOption) {
        stop()

        if option == .off {
            return
        }

        var newAssertionID: IOPMAssertionID = 0
        let reason = "MacFeine keeps your Mac awake"
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            NSLog("Failed to create sleep assertion: \(result)")
            return
        }

        assertionID = newAssertionID
        isActive = true
        currentSelection = option

        if let seconds = option.seconds {
            let expiry = Date().addingTimeInterval(seconds)
            expiresAt = expiry
            timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.stop()
                NotificationCenter.default.post(name: .sleepBlockerDidChange, object: nil)
            }
        } else {
            expiresAt = nil
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if isActive {
            IOPMAssertionRelease(assertionID)
        }

        assertionID = 0
        isActive = false
        currentSelection = .off
        expiresAt = nil
    }

    deinit {
        stop()
    }
}

enum DurationOption: String, CaseIterable {
    case off
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case never

    var title: String {
        switch self {
        case .off: return "Turn Off"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        case .never: return "Never"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: return 0
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .never: return nil
        }
    }
}

extension Notification.Name {
    static let sleepBlockerDidChange = Notification.Name("sleepBlockerDidChange")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = SleepBlocker()
    private var statusItem: NSStatusItem!
    private var menuItems: [DurationOption: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupMenu()
        blocker.activate(.off)
        refreshUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .sleepBlockerDidChange,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.stop()
    }

    @objc
    private func handleStateChange() {
        refreshUI()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(isAwake: false)
    }

    private func updateStatusIcon(isAwake: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = isAwake ? "cup.and.saucer.fill" : "cup.and.saucer"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacFeine")
        button.image?.isTemplate = true
    }

    private func setupMenu() {
        let menu = NSMenu()

        let stateItem = NSMenuItem(title: "Status: Off", action: nil, keyEquivalent: "")
        stateItem.tag = 999
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())

        let orderedOptions: [DurationOption] = [.fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .never]
        for option in orderedOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            menuItems[option] = item
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let turnOffItem = NSMenuItem(title: DurationOption.off.title, action: #selector(selectDuration(_:)), keyEquivalent: "")
        turnOffItem.target = self
        turnOffItem.representedObject = DurationOption.off
        menuItems[.off] = turnOffItem
        menu.addItem(turnOffItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func selectDuration(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? DurationOption else {
            return
        }
        blocker.activate(option)
        refreshUI()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private func refreshUI() {
        for item in menuItems.values {
            item.state = .off
        }

        guard let menu = statusItem.menu else { return }
        let statusTitle: String
        let isAwake: Bool

        if blocker.isActive, let selection = blocker.currentSelection {
            isAwake = true
            menuItems[selection]?.state = .on
            if selection == .never {
                statusTitle = "Status: Awake (Never)"
            } else if let expiry = blocker.expiresAt {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                statusTitle = "Status: Awake until \(formatter.string(from: expiry))"
            } else {
                statusTitle = "Status: Awake"
            }
        } else {
            isAwake = false
            menuItems[.off]?.state = .on
            statusTitle = "Status: Off"
        }

        updateStatusIcon(isAwake: isAwake)

        if let stateItem = menu.item(withTag: 999) {
            stateItem.title = statusTitle
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
