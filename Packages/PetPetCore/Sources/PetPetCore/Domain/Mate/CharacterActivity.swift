/// Animation state is independent of the pet's persisted mood.
public enum CharacterActivity: Equatable, Sendable {
    case running
    case stopped
    case touching
    case idle
}
