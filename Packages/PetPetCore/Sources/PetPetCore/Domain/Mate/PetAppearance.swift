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
    public static let greetingFrameCount = 12
    public static let greetingFrameInterval: TimeInterval = 0.1
    public static let greetingDuration: TimeInterval = 1.2
    public let activity: CharacterActivity
    public init(_ activity: CharacterActivity) { self.activity = activity }
    public var frameInterval: TimeInterval { activity == .touching ? Self.greetingFrameInterval : 0.2 }
    public var isAnimated: Bool { activity == .running || activity == .touching }
    public var posterImageName: String { imageName(elapsed: activity == .touching ? 0.5 : 0) }
    public func imageName(elapsed: TimeInterval) -> String {
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        switch activity {
        case .running:
            let frame = Int((elapsed.truncatingRemainder(dividingBy: 0.8) / 0.2 + 1e-9).rounded(.down))
            return "stepmate_fox_run_\(min(frame, 3) + 1)"
        case .touching:
            let frame = min(Int(min(elapsed / Self.greetingFrameInterval + 1e-9, Double(Self.greetingFrameCount - 1)).rounded(.down)), Self.greetingFrameCount - 1)
            return String(format: "stepmate_fox_greeting_v2_%02d", frame)
        case .idle, .stopped: return "stepmate_fox_greeting_v2_00"
        }
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
