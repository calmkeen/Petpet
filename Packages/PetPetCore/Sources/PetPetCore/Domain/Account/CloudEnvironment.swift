import Foundation

public enum CloudEnvironment: String, Codable, Sendable {
    case production, development

    public static var current: Self {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }

    public func storageDirectory(in root: URL) -> URL {
        self == .development ? root.appendingPathComponent("Development", isDirectory: true) : root
    }
}
