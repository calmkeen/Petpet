import Foundation

/// Separate cosmetics from the game aggregate and server backup contract.
public actor FilePetCustomizationRepository: PetCustomizationRepository {
    private struct Document: Codable { let version: Int; let selection: PetCustomization }
    private let fileURL: URL
    private var cached: PetCustomization?

    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> PetCustomization {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cached = .default; return .default
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 4_096 else { throw PetCustomizationError.storage }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1 else { throw PetCustomizationError.unsupportedVersion(document.version) }
            try document.selection.validate()
            cached = document.selection
            return document.selection
        } catch let error as PetCustomizationError { throw error }
        catch { throw PetCustomizationError.storage }
    }
    public func save(_ selection: PetCustomization) throws {
        // A damaged/newer document must not be silently overwritten.
        _ = try load()
        try selection.validate()
        do {
            let data = try JSONEncoder().encode(Document(version: 1, selection: selection))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            cached = selection
        } catch { throw PetCustomizationError.storage }
    }
}
