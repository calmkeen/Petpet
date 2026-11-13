import Foundation

public struct RankingPageRequest: Codable, Equatable, Sendable {
    public let page: Int
    public let size: Int
    public init(page: Int = 1, size: Int = 5) { self.page = page; self.size = size }
    public func validate() throws {
        guard (1...10_000).contains(page), (1...10).contains(size) else { throw BackendError.invalidResponse }
    }
    public var query: [URLQueryItem] { [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "size", value: String(size))] }
}
public struct StepRankEntry: Codable, Equatable, Sendable {
    public let rank: Int64
    public let userId: Int64
    public let nickname: String
    public let totalStepCount: Int64
}
public struct StepRankingPage: Codable, Equatable, Sendable {
    public let page: Int
    public let size: Int
    public let totalUsers: Int64
    public let rankings: [StepRankEntry]
    public var hasNext: Bool { Int64(page) * Int64(size) < totalUsers }
}
public struct GameRankingPage: Codable, Equatable, Sendable {
    public let game: MiniGame
    public let request: RankingPageRequest
    public let entries: [GameRankEntry]
    public var hasNext: Bool { entries.count == request.size }
}

/// A small avatar also fits the bounded WatchConnectivity feature envelope.
public struct RepresentativeImage: Codable, Equatable, Sendable {
    public static let maximumBytes = 32_000
    public let data: Data
    public init(data: Data) throws { self.data = data; try validate() }
    private enum CodingKeys: String, CodingKey { case data }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(data: values.decode(Data.self, forKey: .data))
    }
    public var mimeType: String { data.starts(with: [0xFF, 0xD8, 0xFF]) ? "image/jpeg" : "image/png" }
    public var filename: String { mimeType == "image/jpeg" ? "profile.jpg" : "profile.png" }
    public func validate() throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw BackendError.transferTooLarge }
        guard data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [137,80,78,71,13,10,26,10]) else { throw BackendError.invalidResponse }
    }
    public func multipart(boundary: String) throws -> Data {
        try validate()
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); return body
    }
    public static func fromMultipart(_ body: Data, contentType: String) throws -> Self {
        guard let marker = contentType.range(of: "boundary="), contentType.hasPrefix("multipart/form-data;") else { throw BackendError.invalidResponse }
        let boundary = String(contentType[marker.upperBound...])
        guard !boundary.isEmpty, boundary.count <= 100,
              let headerEnd = body.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: body[..<headerEnd.lowerBound], encoding: .utf8),
              header.hasPrefix("--\(boundary)\r\n"), header.contains("name=\"image\"; filename=\"profile."),
              body.suffix(boundary.utf8.count + 8) == Data("\r\n--\(boundary)--\r\n".utf8) else { throw BackendError.invalidResponse }
        let end = body.index(body.endIndex, offsetBy: -(boundary.utf8.count + 8))
        guard headerEnd.upperBound <= end else { throw BackendError.invalidResponse }
        let image = try Self(data: Data(body[headerEnd.upperBound..<end]))
        guard header.contains("Content-Type: \(image.mimeType)") else { throw BackendError.invalidResponse }
        return image
    }
}
public struct AccountProfileDetails: Codable, Equatable, Sendable {
    public let nickname: String?
    public let pictureURL: URL?
    public let preview: RepresentativeImage?
    public init(nickname: String?, pictureURL: URL?, preview: RepresentativeImage? = nil) {
        self.nickname = nickname; self.pictureURL = pictureURL; self.preview = preview
    }
    public static func imageURL(_ value: String?) throws -> URL? {
        guard let value, !value.isEmpty else { return nil }
        guard value.utf8.count <= 4096, let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw BackendError.invalidResponse }
        return url
    }
}
