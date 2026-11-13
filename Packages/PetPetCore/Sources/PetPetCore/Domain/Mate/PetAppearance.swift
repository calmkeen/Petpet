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
public struct PetFrameBlend: Equatable, Sendable {
    public let fromIndex: Int
    public let toIndex: Int
    public let amount: Float
}

public struct PetSpriteAnimation: Sendable {
    public static let greetingFrameCount = 16
    public static let greetingFrameInterval: TimeInterval = 1.0 / 15
    public static let greetingDuration: TimeInterval = 16.0 / 15
    public let activity: CharacterActivity
    public let characterID: String
    public let motionID: String
    public init(_ activity: CharacterActivity, characterID: String = PetCustomization.default.characterID, motionID: String? = nil) {
        self.activity = activity
        let character = PetCustomizationCatalog.character(id: characterID)
        self.characterID = character.id
        let defaultMotion = activity == .running ? "running" : activity == .touching ? "greeting" : "idle"
        self.motionID = character.motion(id: motionID ?? defaultMotion).id
    }
    public var clip: PetMotionClip { PetCustomizationCatalog.character(id: characterID).motion(id: motionID) }
    public var frameInterval: TimeInterval { clip.frameInterval }
    public var frameNames: [String] { clip.frames }
    public var cycleDuration: TimeInterval { clip.duration }
    public var isAnimated: Bool { frameNames.count > 1 }
    public var posterImageName: String { frameNames[clip.posterIndex] }
    /// Interpolate aligned source frames at the renderer's cadence. Mixing
    /// premultiplied pixels preserves an opaque body and soft moving edges.
    public func blend(elapsed: TimeInterval) -> PetFrameBlend {
        guard isAnimated else { return PetFrameBlend(fromIndex: 0, toIndex: 0, amount: 0) }
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let position = clip.loops
            ? time.truncatingRemainder(dividingBy: cycleDuration) / frameInterval
            : min(time / frameInterval, Double(frameNames.count - 1))
        let lower = min(Int(position.rounded(.down)), frameNames.count - 1)
        let upper = clip.loops ? (lower + 1) % frameNames.count : min(lower + 1, frameNames.count - 1)
        return PetFrameBlend(fromIndex: lower, toIndex: upper,
                             amount: lower == upper ? 0 : Float(max(0, min(1, position - Double(lower)))))
    }
    public func imageName(elapsed: TimeInterval) -> String {
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        if clip.loops {
            let frame = Int((elapsed.truncatingRemainder(dividingBy: cycleDuration) / frameInterval + 1e-9).rounded(.down))
            return frameNames[min(frame, frameNames.count - 1)]
        }
        let frame = Int(min(elapsed / frameInterval + 1e-9, Double(frameNames.count - 1)).rounded(.down))
        return frameNames[frame]
    }
}

/// A step update may extend expiry without restarting an already playing clip.
public struct PetPlaybackRequest: Equatable, Sendable {
    public let activity: CharacterActivity
    public let startedAt: Date
    public let isPlaying: Bool
    public let characterID: String
    public let motionID: String
    public var animation: PetSpriteAnimation { PetSpriteAnimation(activity, characterID: characterID, motionID: motionID) }
    public init(state: PetAnimationState, suppressed: Bool, characterID: String = PetCustomization.default.characterID, motionID: String? = nil) {
        activity = state.activity; startedAt = state.startedAt
        let animation = PetSpriteAnimation(state.activity, characterID: characterID, motionID: motionID)
        self.characterID = animation.characterID; self.motionID = animation.motionID
        isPlaying = state.isActive && animation.isAnimated && !suppressed
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

    /// Visual-only preview, also used by the customization screen in Release.
    /// It never reads or mutates the game repository.
    public static func preview(_ activity: CharacterActivity, at date: Date = Date()) -> Self {
        var state = Self()
        state.isActive = true; state.activity = activity; state.startedAt = date
        state.expiresAt = activity == .touching ? date.addingTimeInterval(PetSpriteAnimation.greetingDuration) : nil
        return state
    }

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
    public mutating func touch(at date: Date, duration: TimeInterval = PetSpriteAnimation.greetingDuration) -> Bool {
        tick(at: date)
        guard isActive, activity != .running, activity != .touching else { return false }
        activity = .touching; startedAt = date; expiresAt = date.addingTimeInterval(duration)
        return true
    }
    public mutating func tick(at date: Date) {
        if let expiresAt, date >= expiresAt { idle(at: date) }
    }
    private mutating func idle(at date: Date) { activity = .idle; startedAt = date; expiresAt = nil }
}
