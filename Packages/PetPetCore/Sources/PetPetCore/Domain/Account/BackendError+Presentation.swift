import Foundation

extension BackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configurationMissing, .invalidServerURL: "계정 연결 설정이 아직 완료되지 않았어요."
        case .authenticationRequired: "아이폰에서 Apple로 로그인해 주세요."
        case .invalidAppleCredential: "Apple 로그인 응답을 확인하지 못했어요. 다시 로그인해 주세요."
        case .appleLoginUnavailable: "서버의 Apple 로그인 연결이 아직 준비되지 않았어요."
        case .noBackup: "저장된 백업이 없어요. 먼저 워치 기록을 백업해 주세요."
        case .environmentMismatch: "아이폰과 워치의 개발 모드가 달라요. 두 앱을 같은 구성으로 설치해 주세요."
        case .sessionChanged: "로그인 계정이 바뀌었어요. 다시 시도해 주세요."
        case .accountMismatch: "다른 계정의 워치 기록이에요. 기존 계정으로 로그인하거나 서버 복원으로 계정을 전환해 주세요."
        case .localStateChanged: "워치의 펫 상태가 바뀌었어요. 최신 상태를 불러온 뒤 다시 복원해 주세요."
        case .watchUnavailable: "아이폰과 워치에서 PetPet을 열고 연결을 확인해 주세요."
        case .storage: "기록을 저장하지 못했어요. 기기 잠금과 저장 공간을 확인해 주세요."
        case .invalidResponse: "서버 기록을 확인하지 못했어요. 다시 시도해 주세요."
        case .unsupportedMate: "이 펫은 아직 이 앱에서 복원할 수 없어요."
        case .operationExpired: "이 작업을 계속할 수 없어요. 새로 백업하거나 복원해 주세요."
        case .transferTooLarge: "기록이 너무 커서 전송하지 못했어요."
        case .http(401), .http(403): "서버 로그인에 실패했어요. 계정을 다시 확인해 주세요."
        case .http, .network: "서버에 연결하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요."
        }
    }
}
