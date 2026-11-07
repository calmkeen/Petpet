import Foundation

public struct UserProfile: Codable, Equatable, Sendable {
    public var email: String
    public var displayName: String
    public var description: String
    public var selectedPetID: Int64

    public init(email: String, displayName: String, description: String, selectedPetID: Int64) {
        self.email = email
        self.displayName = displayName
        self.description = description
        self.selectedPetID = selectedPetID
    }
}
