import Foundation

public enum NicknameRules {
    /// Kotlin/Java use UTF-16 length. Preserve the exact spelling and spaces
    /// sent by Android; do not silently trim or case-fold a nickname.
    public static func validate(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf16.count >= 2 else {
            throw BackendError.nicknameTooShort
        }
        // The server's JPA nickname column uses the default VARCHAR(255).
        guard value.utf16.count <= 255 else { throw BackendError.nicknameTooLong }
    }
}

struct NicknameResponse: Decodable {
    let duplicated: Bool
    let nickname: String
}
struct AccountProfileResponse: Decodable { let nickname: String?; let pictureUrl: String? }

extension BackendSession {
    func replacingNickname(_ nickname: String) -> BackendSession {
        BackendSession(accountID: accountID, serverOrigin: serverOrigin, accessToken: accessToken,
                       refreshToken: refreshToken, email: email, name: name, nickname: nickname,
                       selectedMateID: selectedMateID, isNewUser: isNewUser,
                       identityProvider: identityProvider, providerSubject: providerSubject)
    }
}
