import Foundation

public enum PetDaylightPeriod: CaseIterable, Sendable {
    case dawn, day, sunset, night
    public init(hour: Int) {
        switch hour {
        case 7: self = .dawn
        case 8...16: self = .day
        case 17: self = .sunset
        default: self = .night
        }
    }
    public init(date: Date, calendar: Calendar = .current) { self.init(hour: calendar.component(.hour, from: date)) }
    public var backgroundImageName: String {
        switch self {
        case .dawn: "stepmate_background_dawn"
        case .day: "stepmate_background_day"
        case .sunset: "stepmate_background_sunset"
        case .night: "stepmate_background_night"
        }
    }
    public var usesLightText: Bool { self == .night }
}

/// Fixed-canvas greeting frames keep the same character pose between updates.
public struct PetSpriteAnimation: Sendable {
    public static let greetingFrameCount = 16
    public static let greetingFrameInterval: TimeInterval = 1.0 / 15
    public static let greetingDuration: TimeInterval = 16.0 / 15
    public let activity: CharacterActivity
    public init(_ activity: CharacterActivity) { self.activity = activity }
    public var frameInterval: TimeInterval { Self.greetingFrameInterval }
    public var frameNames: [String] {
        let mode = activity == .running ? "running" : "greeting"
        let count = isAnimated ? 16 : 1
        return (0..<count).map { String(format: "stepmate_fox_\(mode)_v3_%02d", $0) }
    }
    public var cycleDuration: TimeInterval { Double(frameNames.count) * frameInterval }
    public var isAnimated: Bool { activity == .running || activity == .touching }
    public var posterImageName: String { frameNames[activity == .touching ? 8 : 0] }
    public func imageName(elapsed: TimeInterval) -> String {
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        switch activity {
        case .running:
            let frame = Int((elapsed.truncatingRemainder(dividingBy: cycleDuration) / frameInterval + 1e-9).rounded(.down))
            return frameNames[min(frame, 15)]
        case .touching:
            let frame = min(Int(min(elapsed / Self.greetingFrameInterval + 1e-9, Double(Self.greetingFrameCount - 1)).rounded(.down)), Self.greetingFrameCount - 1)
            return frameNames[frame]
        case .idle, .stopped: return frameNames[0]
        }
    }
}

/// A step update may extend expiry without restarting an already playing clip.
public struct PetPlaybackRequest: Equatable, Sendable {
    public let activity: CharacterActivity
    public let startedAt: Date
    public let isPlaying: Bool
    public init(state: PetAnimationState, suppressed: Bool) {
        activity = state.activity; startedAt = state.startedAt
        isPlaying = state.isActive && PetSpriteAnimation(state.activity).isAnimated && !suppressed
    }
}

/// Ephemeral presentation only. Never changes step, affection, or reward data.
public struct PetAnimationState: Equatable, Sendable {
    public private(set) var activity: CharacterActivity = .idle
    public private(set) var startedAt: Date = .distantPast
    public private(set) var expiresAt: Date?
    public private(set) var isActive = false
    private var baseline: DailyStepRecord?
    public init() {}

    #if DEBUG
    /// Visual-only preview. It never reads or mutates the game repository.
    public static func preview(_ activity: CharacterActivity, at date: Date = Date()) -> Self {
        var state = Self()
        state.isActive = true; state.activity = activity; state.startedAt = date
        state.expiresAt = activity == .touching ? date.addingTimeInterval(PetSpriteAnimation.greetingDuration) : nil
        return state
    }
    #endif

    public mutating func setActive(_ value: Bool, at date: Date) {
        guard value != isActive else { return }
        isActive = value; baseline = nil
        idle(at: date)
    }
    public mutating func observe(_ state: DailyStepState, at date: Date) {
        guard isActive else { return }
        tick(at: date)
        // Loading/restoring a saved total is not a new physical step.
        guard !state.isLoading else {
            baseline = nil
            if activity == .running { idle(at: date) }
            return
        }
        let record = DailyStepRecord(date: state.date, stepCount: state.stepCount)
        guard let previous = baseline, previous.date == record.date else {
            baseline = record
            if activity == .running { idle(at: date) }
            return
        }
        guard record.stepCount > previous.stepCount else { return }
        baseline = record
        guard activity != .touching else { return }
        if activity != .running { startedAt = date }
        activity = .running; expiresAt = date.addingTimeInterval(2)
    }
    @discardableResult
    public mutating func touch(at date: Date) -> Bool {
        tick(at: date)
        guard isActive, activity != .running, activity != .touching else { return false }
        activity = .touching; startedAt = date; expiresAt = date.addingTimeInterval(PetSpriteAnimation.greetingDuration)
        return true
    }
    public mutating func tick(at date: Date) {
        if let expiresAt, date >= expiresAt { idle(at: date) }
    }
    private mutating func idle(at date: Date) { activity = .idle; startedAt = date; expiresAt = nil }
}
