import AppKit
import Foundation
import IOKit.pwr_mgt
import UserNotifications

extension Notification.Name {
    static let sleepBlockerDidChange = Notification.Name("sleepBlockerDidChange")
}

enum AssertionPolicy: Int, CaseIterable {
    case systemIdle = 0
    case displayIdle = 1
    case both = 2

    var title: String {
        switch self {
        case .systemIdle: return "Prevent System Sleep"
        case .displayIdle: return "Prevent Display Sleep"
        case .both: return "Prevent Both"
        }
    }

    var shortTitle: String {
        switch self {
        case .systemIdle: return "System"
        case .displayIdle: return "Display"
        case .both: return "Both"
        }
    }

    var assertionTypes: [CFString] {
        switch self {
        case .systemIdle:
            return [kIOPMAssertionTypePreventUserIdleSystemSleep as CFString]
        case .displayIdle:
            return [kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString]
        case .both:
            return [
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            ]
        }
    }
}

enum StatusBarMode: Int, CaseIterable {
    case iconOnly = 0
    case iconAndRemaining = 1
    case iconAndEndTime = 2

    var title: String {
        switch self {
        case .iconOnly: return "Icon Only"
        case .iconAndRemaining: return "Icon + Remaining"
        case .iconAndEndTime: return "Icon + End Time"
        }
    }
}

enum IconStyle: Int, CaseIterable {
    case cup = 0
    case bolt = 1
    case moon = 2

    var title: String {
        switch self {
        case .cup: return "Cup"
        case .bolt: return "Bolt"
        case .moon: return "Moon"
        }
    }

    var activeSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer.fill"
        case .bolt: return "bolt.fill"
        case .moon: return "moon.fill"
        }
    }

    var inactiveSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer"
        case .bolt: return "bolt"
        case .moon: return "moon"
        }
    }
}

final class DurationPayload: NSObject {
    let title: String
    let seconds: TimeInterval?
    let customMinutes: Int?

    init(title: String, seconds: TimeInterval?, customMinutes: Int? = nil) {
        self.title = title
        self.seconds = seconds
        self.customMinutes = customMinutes
    }
}

final class ProfilePayload: NSObject {
    let menuTitle: String
    let sessionTitle: String
    let seconds: TimeInterval?
    let policy: AssertionPolicy

    init(menuTitle: String, sessionTitle: String, seconds: TimeInterval?, policy: AssertionPolicy) {
        self.menuTitle = menuTitle
        self.sessionTitle = sessionTitle
        self.seconds = seconds
        self.policy = policy
    }
}

final class AppSettings {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let preferredPolicy = "preferredPolicy"
        static let statusBarMode = "statusBarMode"
        static let iconStyle = "iconStyle"
        static let restoreLastSession = "restoreLastSession"
        static let showNotifications = "showNotifications"
        static let playSoundOnExpire = "playSoundOnExpire"
        static let showSecondsInCountdown = "showSecondsInCountdown"
        static let recentCustomMinutes = "recentCustomMinutes"
        static let lastSessionSeconds = "lastSessionSeconds"
        static let lastSessionIsNever = "lastSessionIsNever"
    }

    var preferredPolicy: AssertionPolicy {
        get {
            // If user never selected a policy, default to keeping both system and display awake.
            guard defaults.object(forKey: Key.preferredPolicy) != nil else {
                return .both
            }
            return AssertionPolicy(rawValue: defaults.integer(forKey: Key.preferredPolicy)) ?? .both
        }
        set { defaults.set(newValue.rawValue, forKey: Key.preferredPolicy) }
    }

    var statusBarMode: StatusBarMode {
        get { StatusBarMode(rawValue: defaults.integer(forKey: Key.statusBarMode)) ?? .iconOnly }
        set { defaults.set(newValue.rawValue, forKey: Key.statusBarMode) }
    }

    var iconStyle: IconStyle {
        get { IconStyle(rawValue: defaults.integer(forKey: Key.iconStyle)) ?? .cup }
        set { defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var restoreLastSession: Bool {
        get { defaults.bool(forKey: Key.restoreLastSession) }
        set { defaults.set(newValue, forKey: Key.restoreLastSession) }
    }

    var showNotifications: Bool {
        get { defaults.bool(forKey: Key.showNotifications) }
        set { defaults.set(newValue, forKey: Key.showNotifications) }
    }

    var playSoundOnExpire: Bool {
        get {
            if defaults.object(forKey: Key.playSoundOnExpire) == nil {
                return true
            }
            return defaults.bool(forKey: Key.playSoundOnExpire)
        }
        set { defaults.set(newValue, forKey: Key.playSoundOnExpire) }
    }

    var showSecondsInCountdown: Bool {
        get { defaults.bool(forKey: Key.showSecondsInCountdown) }
        set { defaults.set(newValue, forKey: Key.showSecondsInCountdown) }
    }

    var recentCustomMinutes: [Int] {
        get { defaults.array(forKey: Key.recentCustomMinutes) as? [Int] ?? [] }
        set { defaults.set(Array(newValue.prefix(8)), forKey: Key.recentCustomMinutes) }
    }

    var lastSessionSeconds: TimeInterval? {
        get {
            guard defaults.object(forKey: Key.lastSessionSeconds) != nil else { return nil }
            return defaults.double(forKey: Key.lastSessionSeconds)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastSessionSeconds)
            } else {
                defaults.removeObject(forKey: Key.lastSessionSeconds)
            }
        }
    }

    var lastSessionIsNever: Bool {
        get { defaults.bool(forKey: Key.lastSessionIsNever) }
        set { defaults.set(newValue, forKey: Key.lastSessionIsNever) }
    }

    func addRecentCustom(minutes: Int) {
        guard minutes > 0 else { return }
        var updated = recentCustomMinutes.filter { $0 != minutes }
        updated.insert(minutes, at: 0)
        recentCustomMinutes = updated
    }

    func reset() {
        [
            Key.preferredPolicy,
            Key.statusBarMode,
            Key.iconStyle,
            Key.restoreLastSession,
            Key.showNotifications,
            Key.playSoundOnExpire,
            Key.showSecondsInCountdown,
            Key.recentCustomMinutes,
            Key.lastSessionSeconds,
            Key.lastSessionIsNever
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}

final class SleepBlocker {
    private var assertionIDs: [IOPMAssertionID] = []
    private var expiryTimer: Timer?

    private(set) var isActive = false
    private(set) var currentLabel = "Off"
    private(set) var currentPolicy: AssertionPolicy = .systemIdle
    private(set) var expiresAt: Date?
    private(set) var currentDurationSeconds: TimeInterval?

    func activate(label: String, durationSeconds: TimeInterval?, policy: AssertionPolicy) -> Bool {
        stop(notify: false)

        guard createAssertions(for: policy) else {
            return false
        }

        isActive = true
        currentLabel = label
        currentPolicy = policy
        currentDurationSeconds = durationSeconds

        if let durationSeconds {
            expiresAt = Date().addingTimeInterval(durationSeconds)
            scheduleExpiryTimer()
        } else {
            expiresAt = nil
        }

        postChange(reason: "started")
        return true
    }

    func stop(notify: Bool = true, reason: String = "manual") {
        expiryTimer?.invalidate()
        expiryTimer = nil

        releaseAssertions()

        isActive = false
        currentLabel = "Off"
        currentPolicy = .systemIdle
        expiresAt = nil
        currentDurationSeconds = nil

        if notify {
            postChange(reason: reason)
        }
    }

    func extend(by seconds: TimeInterval) {
        guard isActive, let expiresAt else { return }
        let newExpiry = expiresAt.addingTimeInterval(seconds)
        setExpiry(newExpiry)
    }

    func setExpiry(_ date: Date?) {
        guard isActive else { return }
        expiresAt = date
        currentDurationSeconds = date?.timeIntervalSinceNow
        scheduleExpiryTimer()
        postChange(reason: "extended")
    }

    var remainingSeconds: TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    deinit {
        stop(notify: false)
    }

    private func createAssertions(for policy: AssertionPolicy) -> Bool {
        var createdIDs: [IOPMAssertionID] = []
        let reason = "MacFeine keeps your Mac awake"

        for assertionType in policy.assertionTypes {
            var assertionID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                assertionType,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                createdIDs.forEach { IOPMAssertionRelease($0) }
                NSLog("Failed to create assertion (\(assertionType)): \(result)")
                return false
            }

            createdIDs.append(assertionID)
        }

        assertionIDs = createdIDs
        return true
    }

    private func releaseAssertions() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let expiresAt else { return }
        let interval = max(0.1, expiresAt.timeIntervalSinceNow)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stop(notify: false, reason: "expired")
            self.postChange(reason: "expired")
        }
    }

    private func postChange(reason: String) {
        NotificationCenter.default.post(
            name: .sleepBlockerDidChange,
            object: self,
            userInfo: ["reason": reason]
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = SleepBlocker()
    private let settings = AppSettings()

    private var statusItem: NSStatusItem!
    private var uiRefreshTimer: Timer?

    private var statusMenuItem: NSMenuItem!
    private var recentCustomMenu: NSMenu!

    private var stopNowItem: NSMenuItem!
    private var extend5mItem: NSMenuItem!
    private var extend15mItem: NSMenuItem!
    private var extend1hItem: NSMenuItem!
    private var endNextHourItem: NSMenuItem!
    private var restartLastItem: NSMenuItem!

    private var policyItems: [AssertionPolicy: NSMenuItem] = [:]
    private var statusModeItems: [StatusBarMode: NSMenuItem] = [:]
    private var iconStyleItems: [IconStyle: NSMenuItem] = [:]

    private var restoreLastToggleItem: NSMenuItem!
    private var notificationsToggleItem: NSMenuItem!
    private var soundToggleItem: NSMenuItem!
    private var showSecondsToggleItem: NSMenuItem!

    private var lastKnownStatusLine = "Status: Off"

    private lazy var endTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private let quickPresets: [(String, TimeInterval)] = [
        ("1 Minute", 60),
        ("5 Minutes", 5 * 60),
        ("10 Minutes", 10 * 60),
        ("15 Minutes", 15 * 60),
        ("20 Minutes", 20 * 60),
        ("30 Minutes", 30 * 60)
    ]

    private let longPresets: [(String, TimeInterval)] = [
        ("45 Minutes", 45 * 60),
        ("1 Hour", 60 * 60),
        ("90 Minutes", 90 * 60),
        ("2 Hours", 2 * 60 * 60),
        ("4 Hours", 4 * 60 * 60),
        ("8 Hours", 8 * 60 * 60)
    ]

    private let profiles: [ProfilePayload] = [
        ProfilePayload(
            menuTitle: "Focus Sprint (50m)",
            sessionTitle: "Focus Sprint",
            seconds: 50 * 60,
            policy: .systemIdle
        ),
        ProfilePayload(
            menuTitle: "Deep Work (2h)",
            sessionTitle: "Deep Work",
            seconds: 2 * 60 * 60,
            policy: .systemIdle
        ),
        ProfilePayload(
            menuTitle: "Presentation (Never + Both)",
            sessionTitle: "Presentation",
            seconds: nil,
            policy: .both
        ),
        ProfilePayload(
            menuTitle: "Movie (3h + Display)",
            sessionTitle: "Movie",
            seconds: 3 * 60 * 60,
            policy: .displayIdle
        )
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange(_:)),
            name: .sleepBlockerDidChange,
            object: nil
        )

        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }

        if settings.restoreLastSession {
            restoreLastSessionIfNeeded()
        } else {
            refreshUI()
        }

        if settings.showNotifications {
            requestNotificationPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
        blocker.stop(notify: false)
    }

    @objc
    private func handleStateChange(_ notification: Notification) {
        let reason = notification.userInfo?["reason"] as? String ?? "unknown"

        if reason == "expired" {
            if settings.playSoundOnExpire {
                NSSound.beep()
            }
            sendNotification(title: "MacFeine", body: "Session ended.")
        } else if reason == "started" {
            sendNotification(title: "MacFeine", body: "Awake mode started: \(blocker.currentLabel)")
        } else if reason == "manual" {
            sendNotification(title: "MacFeine", body: "Awake mode stopped.")
        }

        refreshUI()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemVisual(isAwake: false)
    }

    private func setupMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Off", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeStartMenuItem())
        menu.addItem(makeProfilesMenuItem())
        menu.addItem(makeSessionMenuItem())
        menu.addItem(makePolicyMenuItem())
        menu.addItem(makeAppearanceMenuItem())
        menu.addItem(makeBehaviorMenuItem())
        menu.addItem(makeToolsMenuItem())

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeStartMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Start Session", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        addDisabledLabel("Quick Presets", to: submenu)
        for (title, seconds) in quickPresets {
            submenu.addItem(makeDurationItem(title: title, seconds: seconds))
        }

        submenu.addItem(NSMenuItem.separator())
        addDisabledLabel("Long Presets", to: submenu)
        for (title, seconds) in longPresets {
            submenu.addItem(makeDurationItem(title: title, seconds: seconds))
        }

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(makeDurationItem(title: "Never", seconds: nil))

        let customMinutesItem = NSMenuItem(title: "Custom Minutes...", action: #selector(startCustomMinutes), keyEquivalent: "")
        customMinutesItem.target = self
        submenu.addItem(customMinutesItem)

        let untilTimeItem = NSMenuItem(title: "Until Specific Time...", action: #selector(startUntilTime), keyEquivalent: "")
        untilTimeItem.target = self
        submenu.addItem(untilTimeItem)

        let recentItem = NSMenuItem(title: "Recent Custom", action: nil, keyEquivalent: "")
        recentCustomMenu = NSMenu()
        recentItem.submenu = recentCustomMenu
        submenu.addItem(recentItem)

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeProfilesMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for profile in profiles {
            let item = NSMenuItem(title: profile.menuTitle, action: #selector(startProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeSessionMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Current Session", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        extend5mItem = NSMenuItem(title: "+ 5 Minutes", action: #selector(extendCurrentSession(_:)), keyEquivalent: "")
        extend5mItem.target = self
        extend5mItem.representedObject = NSNumber(value: 5 * 60)
        submenu.addItem(extend5mItem)

        extend15mItem = NSMenuItem(title: "+ 15 Minutes", action: #selector(extendCurrentSession(_:)), keyEquivalent: "")
        extend15mItem.target = self
        extend15mItem.representedObject = NSNumber(value: 15 * 60)
        submenu.addItem(extend15mItem)

        extend1hItem = NSMenuItem(title: "+ 1 Hour", action: #selector(extendCurrentSession(_:)), keyEquivalent: "")
        extend1hItem.target = self
        extend1hItem.representedObject = NSNumber(value: 60 * 60)
        submenu.addItem(extend1hItem)

        endNextHourItem = NSMenuItem(title: "End At Next Full Hour", action: #selector(endAtNextHour), keyEquivalent: "")
        endNextHourItem.target = self
        submenu.addItem(endNextHourItem)

        submenu.addItem(NSMenuItem.separator())

        restartLastItem = NSMenuItem(title: "Restart Last Session", action: #selector(restartLastSession), keyEquivalent: "")
        restartLastItem.target = self
        submenu.addItem(restartLastItem)

        stopNowItem = NSMenuItem(title: "Stop Now", action: #selector(stopSession), keyEquivalent: "")
        stopNowItem.target = self
        submenu.addItem(stopNowItem)

        rootItem.submenu = submenu
        return rootItem
    }

    private func makePolicyMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Sleep Policy", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for policy in AssertionPolicy.allCases {
            let item = NSMenuItem(title: policy.title, action: #selector(selectPolicy(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: policy.rawValue)
            policyItems[policy] = item
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeAppearanceMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let statusModeItem = NSMenuItem(title: "Status Bar Text", action: nil, keyEquivalent: "")
        let statusModeMenu = NSMenu()
        for mode in StatusBarMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectStatusBarMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: mode.rawValue)
            statusModeItems[mode] = item
            statusModeMenu.addItem(item)
        }
        statusModeItem.submenu = statusModeMenu
        submenu.addItem(statusModeItem)

        let iconStyleItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        let iconStyleMenu = NSMenu()
        for style in IconStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: style.rawValue)
            iconStyleItems[style] = item
            iconStyleMenu.addItem(item)
        }
        iconStyleItem.submenu = iconStyleMenu
        submenu.addItem(iconStyleItem)

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeBehaviorMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Behavior", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        restoreLastToggleItem = NSMenuItem(title: "Restore Last Session On Launch", action: #selector(toggleRestoreLastSession), keyEquivalent: "")
        restoreLastToggleItem.target = self
        submenu.addItem(restoreLastToggleItem)

        notificationsToggleItem = NSMenuItem(title: "Show Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsToggleItem.target = self
        submenu.addItem(notificationsToggleItem)

        soundToggleItem = NSMenuItem(title: "Play Sound When Session Ends", action: #selector(toggleSoundOnExpire), keyEquivalent: "")
        soundToggleItem.target = self
        submenu.addItem(soundToggleItem)

        showSecondsToggleItem = NSMenuItem(title: "Show Seconds In Countdown", action: #selector(toggleShowSeconds), keyEquivalent: "")
        showSecondsToggleItem.target = self
        submenu.addItem(showSecondsToggleItem)

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeToolsMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let copyStatusItem = NSMenuItem(title: "Copy Current Status", action: #selector(copyStatusToClipboard), keyEquivalent: "")
        copyStatusItem.target = self
        submenu.addItem(copyStatusItem)

        let resetSettingsItem = NSMenuItem(title: "Reset All Preferences", action: #selector(resetPreferences), keyEquivalent: "")
        resetSettingsItem.target = self
        submenu.addItem(resetSettingsItem)

        rootItem.submenu = submenu
        return rootItem
    }

    private func makeDurationItem(title: String, seconds: TimeInterval?, customMinutes: Int? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(startFromDurationItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = DurationPayload(title: title, seconds: seconds, customMinutes: customMinutes)
        return item
    }

    private func addDisabledLabel(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc
    private func startFromDurationItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? DurationPayload else { return }
        startSession(
            title: payload.title,
            durationSeconds: payload.seconds,
            customMinutesToRemember: payload.customMinutes
        )
    }

    @objc
    private func startProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? ProfilePayload else { return }
        settings.preferredPolicy = profile.policy
        startSession(
            title: profile.sessionTitle,
            durationSeconds: profile.seconds,
            customMinutesToRemember: nil
        )
    }

    @objc
    private func startCustomMinutes() {
        let alert = NSAlert()
        alert.messageText = "Custom Minutes"
        alert.informativeText = "Enter how many minutes MacFeine should keep your Mac awake."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "Example: 37"
        input.stringValue = "30"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(text), minutes > 0, minutes <= 7 * 24 * 60 else {
            showSimpleError(title: "Invalid Value", message: "Please enter a number between 1 and 10080.")
            return
        }

        let title = "Custom \(formatMinutesLabel(minutes))"
        startSession(
            title: title,
            durationSeconds: TimeInterval(minutes * 60),
            customMinutesToRemember: minutes
        )
    }

    @objc
    private func startUntilTime() {
        let alert = NSAlert()
        alert.messageText = "Keep Awake Until Time"
        alert.informativeText = "Choose a target time. If it already passed today, MacFeine uses tomorrow."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.dateValue = Date()
        alert.accessoryView = picker

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: picker.dateValue)
        guard let hour = components.hour, let minute = components.minute else { return }

        var match = DateComponents()
        match.hour = hour
        match.minute = minute
        match.second = 0

        guard var target = calendar.nextDate(
            after: now,
            matching: match,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return
        }

        if target <= now {
            target = target.addingTimeInterval(24 * 60 * 60)
        }

        let seconds = target.timeIntervalSince(now)
        let minutes = max(1, Int((seconds / 60).rounded()))
        let title = "Until \(endTimeFormatter.string(from: target))"

        startSession(
            title: title,
            durationSeconds: seconds,
            customMinutesToRemember: minutes
        )
    }

    @objc
    private func extendCurrentSession(_ sender: NSMenuItem) {
        guard blocker.isActive, blocker.expiresAt != nil else { return }
        guard let amount = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        blocker.extend(by: amount)
    }

    @objc
    private func endAtNextHour() {
        guard blocker.isActive, blocker.expiresAt != nil else { return }
        let calendar = Calendar.current
        let now = Date()
        var match = DateComponents()
        match.minute = 0
        match.second = 0
        guard let target = calendar.nextDate(
            after: now,
            matching: match,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return
        }
        blocker.setExpiry(target)
    }

    @objc
    private func restartLastSession() {
        restoreLastSessionIfNeeded()
    }

    @objc
    private func stopSession() {
        blocker.stop(reason: "manual")
    }

    @objc
    private func selectPolicy(_ sender: NSMenuItem) {
        guard let raw = (sender.representedObject as? NSNumber)?.intValue else { return }
        guard let selectedPolicy = AssertionPolicy(rawValue: raw) else { return }

        settings.preferredPolicy = selectedPolicy

        if blocker.isActive {
            let label = blocker.currentLabel
            let remaining = blocker.remainingSeconds
            let duration = blocker.expiresAt == nil ? nil : remaining
            _ = blocker.activate(label: label, durationSeconds: duration, policy: selectedPolicy)
        } else {
            refreshUI()
        }
    }

    @objc
    private func selectStatusBarMode(_ sender: NSMenuItem) {
        guard let raw = (sender.representedObject as? NSNumber)?.intValue else { return }
        guard let mode = StatusBarMode(rawValue: raw) else { return }
        settings.statusBarMode = mode
        refreshUI()
    }

    @objc
    private func selectIconStyle(_ sender: NSMenuItem) {
        guard let raw = (sender.representedObject as? NSNumber)?.intValue else { return }
        guard let style = IconStyle(rawValue: raw) else { return }
        settings.iconStyle = style
        refreshUI()
    }

    @objc
    private func toggleRestoreLastSession() {
        settings.restoreLastSession.toggle()
        refreshUI()
    }

    @objc
    private func toggleNotifications() {
        settings.showNotifications.toggle()
        if settings.showNotifications {
            requestNotificationPermission()
        }
        refreshUI()
    }

    @objc
    private func toggleSoundOnExpire() {
        settings.playSoundOnExpire.toggle()
        refreshUI()
    }

    @objc
    private func toggleShowSeconds() {
        settings.showSecondsInCountdown.toggle()
        refreshUI()
    }

    @objc
    private func copyStatusToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastKnownStatusLine, forType: .string)
    }

    @objc
    private func resetPreferences() {
        let alert = NSAlert()
        alert.messageText = "Reset Preferences"
        alert.informativeText = "This will clear all custom settings, including recent custom timers."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.reset()
        blocker.stop(reason: "manual")
        refreshUI()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    private func startSession(title: String, durationSeconds: TimeInterval?, customMinutesToRemember: Int?) {
        let policy = settings.preferredPolicy
        let success = blocker.activate(label: title, durationSeconds: durationSeconds, policy: policy)

        guard success else {
            showSimpleError(
                title: "Cannot Start",
                message: "MacFeine could not create a power assertion. Try again."
            )
            return
        }

        if let customMinutesToRemember {
            settings.addRecentCustom(minutes: customMinutesToRemember)
        }

        rememberLastSession(durationSeconds: durationSeconds)
        refreshUI()
    }

    private func rememberLastSession(durationSeconds: TimeInterval?) {
        if durationSeconds == nil {
            settings.lastSessionIsNever = true
            settings.lastSessionSeconds = nil
        } else {
            settings.lastSessionIsNever = false
            settings.lastSessionSeconds = durationSeconds
        }
    }

    private func restoreLastSessionIfNeeded() {
        if settings.lastSessionIsNever {
            startSession(title: "Restored Never", durationSeconds: nil, customMinutesToRemember: nil)
            return
        }

        guard let seconds = settings.lastSessionSeconds, seconds > 0 else {
            refreshUI()
            return
        }

        startSession(
            title: "Restored \(formatDuration(seconds))",
            durationSeconds: seconds,
            customMinutesToRemember: nil
        )
    }

    private func refreshUI() {
        updateRecentCustomMenu()
        updateModeStates()
        updateSessionActionStates()

        let statusLine = buildStatusLine()
        lastKnownStatusLine = statusLine
        statusMenuItem.title = statusLine

        updateStatusItemVisual(isAwake: blocker.isActive)
    }

    private func updateRecentCustomMenu() {
        recentCustomMenu.removeAllItems()

        let recents = settings.recentCustomMinutes
        if recents.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Custom Timers", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentCustomMenu.addItem(emptyItem)
            return
        }

        for minutes in recents {
            let title = "Custom \(formatMinutesLabel(minutes))"
            recentCustomMenu.addItem(
                makeDurationItem(
                    title: title,
                    seconds: TimeInterval(minutes * 60),
                    customMinutes: minutes
                )
            )
        }
    }

    private func updateModeStates() {
        for item in policyItems.values { item.state = .off }
        for item in statusModeItems.values { item.state = .off }
        for item in iconStyleItems.values { item.state = .off }

        policyItems[settings.preferredPolicy]?.state = .on
        statusModeItems[settings.statusBarMode]?.state = .on
        iconStyleItems[settings.iconStyle]?.state = .on

        restoreLastToggleItem.state = settings.restoreLastSession ? .on : .off
        notificationsToggleItem.state = settings.showNotifications ? .on : .off
        soundToggleItem.state = settings.playSoundOnExpire ? .on : .off
        showSecondsToggleItem.state = settings.showSecondsInCountdown ? .on : .off
    }

    private func updateSessionActionStates() {
        let isTimedSession = blocker.isActive && blocker.expiresAt != nil
        let hasAnyLastSession = settings.lastSessionIsNever || (settings.lastSessionSeconds ?? 0) > 0

        stopNowItem.isEnabled = blocker.isActive
        extend5mItem.isEnabled = isTimedSession
        extend15mItem.isEnabled = isTimedSession
        extend1hItem.isEnabled = isTimedSession
        endNextHourItem.isEnabled = isTimedSession
        restartLastItem.isEnabled = hasAnyLastSession
    }

    private func updateStatusItemVisual(isAwake: Bool) {
        guard let button = statusItem.button else { return }

        let style = settings.iconStyle
        let symbolName = isAwake ? style.activeSymbol : style.inactiveSymbol
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacFeine")
        button.image?.isTemplate = true

        switch settings.statusBarMode {
        case .iconOnly:
            button.title = ""
        case .iconAndRemaining:
            if !isAwake {
                button.title = ""
            } else if let remaining = blocker.remainingSeconds {
                button.title = " \(formatDuration(remaining))"
            } else {
                button.title = " inf"
            }
        case .iconAndEndTime:
            if !isAwake {
                button.title = ""
            } else if let expiresAt = blocker.expiresAt {
                button.title = " \(endTimeFormatter.string(from: expiresAt))"
            } else {
                button.title = " inf"
            }
        }
    }

    private func buildStatusLine() -> String {
        guard blocker.isActive else {
            return "Status: Off"
        }

        if let remaining = blocker.remainingSeconds, let expiresAt = blocker.expiresAt {
            return "Status: Awake [\(blocker.currentPolicy.shortTitle)] \(blocker.currentLabel) | \(formatDuration(remaining)) left (until \(endTimeFormatter.string(from: expiresAt)))"
        }

        return "Status: Awake [\(blocker.currentPolicy.shortTitle)] \(blocker.currentLabel) | Never"
    }

    private func formatDuration(_ rawSeconds: TimeInterval) -> String {
        let total = max(0, Int(rawSeconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }

        if minutes > 0 {
            if settings.showSecondsInCountdown && seconds > 0 {
                return "\(minutes)m \(seconds)s"
            }
            return "\(minutes)m"
        }

        return "\(seconds)s"
    }

    private func formatMinutesLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 Hour" : "\(hours) Hours"
        }
        return "\(minutes) Minutes"
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        guard settings.showNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if settings.playSoundOnExpire {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func showSimpleError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
