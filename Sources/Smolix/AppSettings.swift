import Foundation
import SmolixCore

/// Persisted user settings (UserDefaults). Main-thread only.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let smooth = "smoothEnabled"
        static let reverse = "reverseEnabled"
        static let step = "step"
        static let acceleration = "acceleration"
        static let duration = "durationMs"
        static let glide = "glide"
        static let terminalSpeed = "terminalSpeed"
        static let hideIcon = "hideMenuBarIcon"
        static let debug = "debugLogging"
    }

    private let defaults: UserDefaults

    @Published var smoothEnabled: Bool { didSet { defaults.set(smoothEnabled, forKey: Key.smooth) } }
    @Published var reverseEnabled: Bool { didSet { defaults.set(reverseEnabled, forKey: Key.reverse) } }
    @Published var step: Double { didSet { defaults.set(step, forKey: Key.step) } }
    @Published var acceleration: Double { didSet { defaults.set(acceleration, forKey: Key.acceleration) } }
    @Published var durationMs: Double { didSet { defaults.set(durationMs, forKey: Key.duration) } }
    @Published var glide: Double { didSet { defaults.set(glide, forKey: Key.glide) } }
    @Published var hideMenuBarIcon: Bool { didSet { defaults.set(hideMenuBarIcon, forKey: Key.hideIcon) } }
    /// Smooth-scroll distance multiplier when the cursor is over a terminal (1 = same as other apps).
    /// iTerm2/tmux turn every few pixels into a multi-line wheel report, so terminals need less.
    @Published var terminalSpeed: Double { didSet { defaults.set(terminalSpeed, forKey: Key.terminalSpeed) } }

    static let terminalSpeedRange: ClosedRange<Double> = 0.3...1.5
    static let defaultTerminalSpeed = 0.7

    /// `defaults write dev.smolix.Smolix debugLogging -bool true` logs raw wheel events.
    let debugLogging: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = ScrollParameters.default
        defaults.register(defaults: [
            Key.smooth: true,
            Key.reverse: false,
            Key.step: d.step,
            Key.acceleration: d.acceleration,
            Key.duration: d.durationMs,
            Key.glide: d.glide,
            Key.terminalSpeed: Self.defaultTerminalSpeed,
            Key.hideIcon: false,
            Key.debug: false,
        ])
        smoothEnabled = defaults.bool(forKey: Key.smooth)
        reverseEnabled = defaults.bool(forKey: Key.reverse)
        step = defaults.double(forKey: Key.step)
        acceleration = defaults.double(forKey: Key.acceleration)
        durationMs = defaults.double(forKey: Key.duration)
        glide = defaults.double(forKey: Key.glide)
        terminalSpeed = defaults.double(forKey: Key.terminalSpeed)
        hideMenuBarIcon = defaults.bool(forKey: Key.hideIcon)
        debugLogging = defaults.bool(forKey: Key.debug)
    }

    var clampedTerminalSpeed: Double {
        guard terminalSpeed.isFinite else { return Self.defaultTerminalSpeed }
        return min(max(terminalSpeed, Self.terminalSpeedRange.lowerBound), Self.terminalSpeedRange.upperBound)
    }

    var parameters: ScrollParameters {
        ScrollParameters(step: step, acceleration: acceleration, durationMs: durationMs, glide: glide).clamped()
    }

    func resetScrollFeel() {
        let d = ScrollParameters.default
        step = d.step
        acceleration = d.acceleration
        durationMs = d.durationMs
        glide = d.glide
        terminalSpeed = Self.defaultTerminalSpeed
    }
}
