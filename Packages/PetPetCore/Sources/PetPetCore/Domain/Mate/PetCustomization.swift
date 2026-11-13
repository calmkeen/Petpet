import Foundation

/// Cosmetic selection only. It never changes mate IDs, progression or rewards.
/// Keep unknown, well-formed IDs so an older companion can safely show defaults.
public struct PetCustomization: Codable, Equatable, Sendable {
    public var characterID: String
    public var backgroundID: String
    public static let `default` = Self(characterID: "snow-fox", backgroundID: "automatic")

    public init(characterID: String, backgroundID: String) {
        self.characterID = characterID; self.backgroundID = backgroundID
    }
    public var character: PetCharacterDefinition { PetCustomizationCatalog.character(id: characterID) }
    public func background(at date: Date, automaticPeriod: PetDaylightPeriod? = nil) -> PetBackgroundAppearance {
        PetCustomizationCatalog.background(id: backgroundID).resolve(at: date, automaticPeriod: automaticPeriod)
    }
    public func validate() throws {
        for value in [characterID, backgroundID] {
            guard !value.isEmpty, value.utf8.count <= 64,
                  value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
                throw PetCustomizationError.invalidSelection
            }
        }
    }
}

public struct PetMotionClip: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let frames: [String]
    public let frameInterval: TimeInterval
    public let loops: Bool
    public let posterIndex: Int
    public var duration: TimeInterval { Double(frames.count) * frameInterval }
}

public struct PetCharacterDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let canvasWidth: Double
    public let canvasHeight: Double
    public let motions: [PetMotionClip]
    public func motion(id: String) -> PetMotionClip {
        motions.first { $0.id == id } ?? motions[0]
    }
}

public struct PetBackgroundAppearance: Equatable, Sendable {
    public let imageName: String
    public let usesLightText: Bool
}

public struct PetBackgroundDefinition: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    /// nil follows the clock; a name can reference any future bundled scenery.
    public let imageName: String?
    public let usesLightText: Bool
    public var isAutomatic: Bool { imageName == nil }
    public func resolve(at date: Date, automaticPeriod: PetDaylightPeriod? = nil) -> PetBackgroundAppearance {
        if let imageName { return PetBackgroundAppearance(imageName: imageName, usesLightText: usesLightText) }
        let value = automaticPeriod ?? PetDaylightPeriod(date: date)
        return PetBackgroundAppearance(imageName: value.backgroundImageName, usesLightText: value.usesLightText)
    }
}

/// Register bundled artwork here; selection screens and renderers share it.
/// Every character supplies an idle pose and default running/greeting clips.
public enum PetCustomizationCatalog {
    public static let characters: [PetCharacterDefinition] = [
        PetCharacterDefinition(id: "snow-fox", name: "눈여우", detail: "함께 걷는 하얀 친구",
            canvasWidth: 256, canvasHeight: 336, motions: [
                PetMotionClip(id: "idle", name: "쉬기", frames: ["stepmate_fox_greeting_v3_00"], frameInterval: 1, loops: false, posterIndex: 0),
                PetMotionClip(id: "greeting", name: "인사", frames: frames("greeting"), frameInterval: 1.0 / 15, loops: false, posterIndex: 8),
                PetMotionClip(id: "running", name: "달리기", frames: frames("running"), frameInterval: 1.0 / 15, loops: true, posterIndex: 0)
            ])
    ]
    public static let backgrounds: [PetBackgroundDefinition] = [
        .init(id: "automatic", name: "시간대에 맞추기", symbol: "clock", imageName: nil, usesLightText: false),
        .init(id: "dawn", name: "새벽", symbol: "sunrise", imageName: "stepmate_background_dawn", usesLightText: false),
        .init(id: "day", name: "낮", symbol: "sun.max", imageName: "stepmate_background_day", usesLightText: false),
        .init(id: "sunset", name: "노을", symbol: "sunset", imageName: "stepmate_background_sunset", usesLightText: false),
        .init(id: "night", name: "밤", symbol: "moon.stars", imageName: "stepmate_background_night", usesLightText: true)
    ]
    public static func character(id: String) -> PetCharacterDefinition {
        characters.first { $0.id == id } ?? characters[0]
    }
    public static func background(id: String) -> PetBackgroundDefinition {
        backgrounds.first { $0.id == id } ?? backgrounds[0]
    }
    private static func frames(_ motion: String) -> [String] {
        (0..<16).map { String(format: "stepmate_fox_\(motion)_v3_%02d", $0) }
    }
}

public enum PetCustomizationError: Error, Equatable {
    case invalidSelection, unsupportedVersion(Int), storage
}

public protocol PetCustomizationRepository: Sendable {
    func load() async throws -> PetCustomization
    func save(_ selection: PetCustomization) async throws
}
