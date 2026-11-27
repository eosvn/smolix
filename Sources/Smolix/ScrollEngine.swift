import AppKit
import CoreGraphics
import OSLog
import QuartzCore
import SmolixCore

enum EngineState: Equatable {
    case starting
    case running
    case needsPermission
    case failed
}

/// What the event tap should do with the incoming event.
private enum TapDecision {
    case pass   // let the (possibly modified in place) event through
    case drop   // swallow it; we will scroll smoothly instead
}

/// Intercepts mouse-wheel events and replays them as smooth pixel scrolling.
///
/// Stability rules (the reasons Smolix exists):
/// - Everything runs on the main thread: event tap, animation, settings. No locks, no races.
/// - The incoming CGEvent and the tap proxy are never stored past the callback. Smooth
///   scrolling posts *fresh* events with `CGEvent.post(tap:)`, never `tapPostEvent` with a
///   stale proxy (a stale proxy/event is the kind of bug that crashes inside SkyLight).
/// - If macOS disables the tap (timeout, user input, sleep/wake, permission changes) a
///   supervisor re-enables or recreates it within seconds.
@MainActor
final class ScrollEngine: NSObject, ObservableObject {
    @Published private(set) var state: EngineState = .starting

    /// Tag stamped on events we post so our own tap ignores them ("SMOLIX").
    static let marker: Int64 = 0x534D_4F4C_4958

    private let settings: AppSettings
    private let appUnderCursor = AppUnderCursor()
    private let log = Logger(subsystem: "dev.smolix.Smolix", category: "engine")

    // Event tap
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var supervisor: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    // Animation
    private var displayLink: CADisplayLink?
    private var displayLinkScreenID: CGDirectDisplayID?
    private var lastFrameTime: CFTimeInterval?
    private var axisY = SmoothAxis()
    private var axisX = SmoothAxis()
    /// 0…1: how fast the wheel was spun during the current animation (drives extra glide).
    private var glideBoost: Double = 0
    /// Stops a glide once the pointer leaves the spot where the wheel was turned.
    private var latch = ScrollLatch()
    private var postFlags: CGEventFlags = []
    private let eventSource: CGEventSource?

    init(settings: AppSettings) {
        self.settings = settings
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
        super.init()
        eventSource?.userData = Self.marker
    }

    // MARK: - Lifecycle

    /// Starts the tap (if permitted) and keeps it healthy for the lifetime of the app.
    func startSupervising() {
        healthCheck()

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.healthCheck() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        supervisor = timer

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { engine in
                engine.log.notice("System woke / session active — recreating event tap")
                engine.restartTap()
            }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { engine in
            engine.dropDisplayLink()
        }
    }

    func shutdown() {
        supervisor?.invalidate()
        supervisor = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        stopTap()
        dropDisplayLink()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (ScrollEngine) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { action(self) }
        }
        observers.append((center, token))
    }

    private func setState(_ new: EngineState) {
        if state != new { state = new }
    }

    /// Runs every 2 s and on demand: makes sure the tap exists, is valid and enabled.
    func healthCheck() {
        guard Accessibility.isTrusted else {
            if tap != nil {
                log.notice("Accessibility permission revoked — removing event tap")
                stopTap()
            }
            setState(.needsPermission)
            return
        }
        guard let tap else {
            startTap()
            return
        }
        if !CFMachPortIsValid(tap) {
            log.error("Event tap port became invalid — recreating")
            restartTap()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            log.notice("Event tap found disabled — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        setState(.running)
    }

    private func startTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: smolixTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("CGEvent.tapCreate failed")
            setState(Accessibility.isTrusted ? .failed : .needsPermission)
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        log.notice("Event tap started")
        setState(.running)
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        tap = nil
        tapSource = nil
        resetAnimation()
    }

    private func restartTap() {
        stopTap()
        healthCheck()
    }

    // MARK: - Event handling (called synchronously from the tap callback, on main)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> TapDecision {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log.notice("macOS disabled the event tap (type \(type.rawValue)) — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .pass
        case .scrollWheel:
            break
        default:
            return .pass
        }

        // Our own synthetic events.
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return .pass }
        // Trackpads and Magic Mouse are already smooth (continuous, with momentum).
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return .pass }

        let flags = event.flags
        // Cmd/Ctrl + wheel is zoom in most apps — keep it exactly as the system sends it.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return .pass }

        var dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if dy == 0 { dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) }
        if dx == 0 { dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) }

        guard dy != 0 || dx != 0 else { return .pass }

        guard settings.smoothEnabled else {
            if settings.reverseEnabled { Self.invertInPlace(event) }
            return .pass
        }

        // iTerm2 + tmux turn every few pixels into another multi-line wheel report, so the same
        // pixel distance scrolls much further in a terminal: scale it down there.
        let terminalSpeed = settings.clampedTerminalSpeed
        let distanceScale = terminalSpeed != 1 && appUnderCursor.isTerminal(at: event.location) ? terminalSpeed : 1

        if settings.debugLogging {
            let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let app = appUnderCursor.bundleID(at: event.location) ?? "?"
            log.debug("""
                wheel lineY=\(lineY) fixedY=\(dy) pointY=\(pointY) dx=\(dx) flags=\(flags.rawValue) \
                app=\(app, privacy: .public) scale=\(distanceScale)
                """)
        }

        // Shift + wheel = horizontal scroll, whether or not macOS already moved it to axis 2.
        if flags.contains(.maskShift), dx == 0 {
            dx = dy
            dy = 0
        }

        // Turned somewhere else: the glide still in flight belongs to the old spot.
        if latch.wheel(at: NSEvent.mouseLocation) {
            axisY.reset()
            axisX.reset()
            glideBoost = 0
        }

        let multiplier: Double = (settings.reverseEnabled ? -1 : 1) * distanceScale
        let parameters = settings.parameters
        if dy != 0 { axisY.add(multiplier * ScrollMath.distance(lines: dy, parameters: parameters)) }
        if dx != 0 { axisX.add(multiplier * ScrollMath.distance(lines: dx, parameters: parameters)) }
        // A fast spin keeps the whole animation gliding longer (until it comes to rest).
        glideBoost = max(glideBoost, ScrollMath.glideBoost(lines: max(abs(dy), abs(dx))))
        postFlags = flags.intersection(.maskAlternate)

        startAnimating()
        return .drop
    }

    /// Reverses a wheel event that is passed through unsmoothed (smooth scrolling off).
    private static func invertInPlace(_ event: CGEvent) {
        let axes: [(line: CGEventField, fixed: CGEventField, point: CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
        ]
        for axis in axes {
            // Read everything first: writing one delta field can make CoreGraphics
            // recompute the others, so read-modify-write per field could flip signs.
            let original = WheelDelta(
                line: event.getIntegerValueField(axis.line),
                fixed: event.getDoubleValueField(axis.fixed),
                point: event.getIntegerValueField(axis.point)
            )
            guard original.line != 0 || original.fixed != 0 || original.point != 0 else { continue }
            let updated = original.negated
            event.setIntegerValueField(axis.line, value: updated.line)
            event.setDoubleValueField(axis.fixed, value: updated.fixed)
            event.setIntegerValueField(axis.point, value: updated.point)
        }
    }

    // MARK: - Animation

    private func startAnimating() {
        let screen = NSScreen.underCursor
        let screenID = screen?.displayID
        if displayLink == nil || screenID != displayLinkScreenID {
            dropDisplayLink()
            guard let screen else {
                flushImmediately()
                return
            }
            let link = screen.displayLink(target: self, selector: #selector(onFrame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            displayLinkScreenID = screenID
        }
        displayLink?.isPaused = false
    }

    @objc private func onFrame(_ link: CADisplayLink) {
        guard settings.smoothEnabled, tap != nil else {
            resetAnimation()
            return
        }
        // The pointer moved on: stop rather than scroll whatever it is over now.
        if latch.hasMoved(to: NSEvent.mouseLocation) {
            if settings.debugLogging { log.debug("Pointer left the scroll spot — glide stopped") }
            resetAnimation()
            return
        }
        let now = link.timestamp
        var dt = lastFrameTime.map { now - $0 } ?? (link.targetTimestamp - link.timestamp)
        if !(dt > 0) { dt = 1.0 / 120 }
        lastFrameTime = now

        let duration = ScrollMath.effectiveDurationMs(settings.parameters, boost: glideBoost)
        let fraction = ScrollMath.frameFraction(dt: dt, durationMs: duration)
        let py = axisY.advance(fraction: fraction)
        let px = axisX.advance(fraction: fraction)
        if py != 0 || px != 0 { post(dy: py, dx: px) }

        if axisY.isIdle && axisX.isIdle {
            link.isPaused = true
            lastFrameTime = nil
            glideBoost = 0
            latch.release()
        }
    }

    /// No screen to sync with (shouldn't happen) — scroll the full distance at once.
    private func flushImmediately() {
        let py = axisY.advance(fraction: 1)
        let px = axisX.advance(fraction: 1)
        if py != 0 || px != 0 { post(dy: py, dx: px) }
        latch.release()
    }

    private func post(dy: Int32, dx: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.flags = postFlags
        event.post(tap: .cgSessionEventTap)
    }

    private func resetAnimation() {
        axisY.reset()
        axisX.reset()
        glideBoost = 0
        latch.release()
        lastFrameTime = nil
        displayLink?.isPaused = true
    }

    private func dropDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkScreenID = nil
        lastFrameTime = nil
    }
}

/// C callback for the event tap. Runs on the main run loop (where the tap source is added).
/// Returns the incoming event unretained (pass) or nil (drop) — it never creates, retains,
/// releases or stores the event, which keeps ownership exactly as CoreGraphics expects.
private func smolixTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
    nonisolated(unsafe) let incoming = event
    let decision = MainActor.assumeIsolated {
        engine.handle(type: type, event: incoming)
    }
    switch decision {
    case .pass: return Unmanaged.passUnretained(event)
    case .drop: return nil
    }
}
