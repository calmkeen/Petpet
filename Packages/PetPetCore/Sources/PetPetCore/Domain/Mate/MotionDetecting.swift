@MainActor
public protocol MotionDetecting: AnyObject {
    func start(onMovement: @escaping @MainActor (Bool) -> Void)
    func stop()
}
