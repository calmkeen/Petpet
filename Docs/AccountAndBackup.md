# Apple 로그인과 서버 백업·복원

기준은 Android [StepMate `4e2b5e5`](https://github.com/Chaeros/StepMate/tree/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3)와 서버 [StepMate_SpringBoot `bcdcefbb`](https://github.com/Chaeros/StepMate_SpringBoot/tree/bcdcefbb226951785e09a82c30ab473ef77e39da)다. 서버 코드는 읽기 전용으로 확인했으며 변경하지 않았다.

## iOS 로그인 설정

iOS는 Apple 기본 `SignInWithAppleButton`과 AuthenticationServices를 사용한다. Google SDK·iOS Google Client ID·Web Client ID·Google 복귀 URL scheme은 제거했다. Android의 기존 Google 인증 API 계약은 공용 클라이언트와 회귀 테스트에 남아 있지만 iOS 화면에서는 호출하지 않는다.

실제 로그인을 연결하려면 다음이 필요하다.

1. Apple Developer Program 팀의 앱 ID **`com.calmkeen.PetPet`**에 Sign in with Apple을 활성화하고 서명 프로파일을 갱신한다. 프로젝트의 `PetPet.entitlements`와 iPhone 타깃 Debug/Release에 capability를 연결했다. 무료 Personal Team은 이 기능을 지원하지 않는다. [Apple 지원 표](https://developer.apple.com/help/account/reference/supported-capabilities-ios/).
2. 서버에 **`POST /api/v1/auth/apple`**과 Apple 증명 검증·공용 계정 조회를 추가한다. 이 경로는 이번에 정의한 계약이며 기존 서버에는 없다. [서버 변경 명세](AppleSignInServer.md)에 요청·응답과 수정 파일·이행 순서를 정리했다.
3. 서버의 Apple Team ID·Key ID·`.p8` 키를 준비한다. 개인 키와 client secret은 서버에만 둔다. 앱은 Bundle ID를 사용하는 네이티브 인증이며 별도 Google OAuth 설정이 필요하지 않다.
4. `PetPet-Info.plist`의 `PetPetAPIBaseURL`을 확인한다. 현재 기본값은 Android 문서의 `https://www.stepmatecp.com/`이며 운영 주소는 소유자 확인이 필요하다.
5. 새 프로파일로 빌드한 iPhone의 **계정 · 서버 백업**에서 Apple로 로그인한다. 워치에는 계정 표시 정보만 전달한다.

인증 요청마다 별도의 nonce·state를 만들고, SHA256 nonce와 state를 Apple 요청에 넣는다. 콜백의 state·유효 시간을 확인한 뒤 identityToken·authorizationCode·rawNonce를 서버에 한 번 교환한다. 서버가 검증하고 내부 userId와 PetPet 토큰 쌍을 반환해야 로그인으로 저장한다. Apple API가 404/405/501이면 서버 연결이 아직 준비되지 않았다고 안내한다.

처음에만 오는 이름은 서버 교환이 완료될 때까지 앱 UserDefaults의 `PetPet.apple.pendingNames.v1`에 잠시 보관한다. token·code·nonce는 여기에 저장하지 않는다. Keychain에는 PetPet 세션과 Apple 제공자·사용자 식별자를 저장한다. 앱 실행·복귀와 Apple credential 철회 알림에서 기기 상태를 확인하며, 철회·계정 변경이 확인되면 해당 세션을 로그아웃하고 워치에도 알린다. 일시적인 상태 조회 오류만으로 세션을 지우지 않는다.

공식 안내: [Apple 인증 흐름](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple), [서버 검증과 기기 credential 상태](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).

## 사용자 흐름

- iPhone에서 로그인하면 계정 표시 정보만 워치로 전송한다. 로그인 자체가 기존 워치 기록을 자동으로 덮어쓰거나 업로드하지 않는다.
- iPhone의 **워치 기록 백업**, 워치의 네 번째 Crown 섹션 또는 먹이 화면의 **서버 백업·보상 받기**로 백업한다. 현재 기록을 로컬에 저장한 뒤 워치가 전체 보관 기록 중 미백업 날짜와 마지막 백업 날짜의 최신 합계를 추출한다. iPhone 홈의 최대 7일 캐시를 백업 원본으로 사용하지 않는다.
- 서버 저장 성공을 iPhone에 먼저 기록하고 워치에 확인 메시지를 보낸다. 워치는 이 확인을 받은 뒤 해당 백업의 날짜·걸음수에 대해 우유와 사과를 지급한다. 실패한 백업과 센서 갱신에는 보상을 지급하지 않는다.
- iPhone의 **서버 기록 불러오기**는 워치의 현재 상태와 서버 기록을 조회해 미리보기를 보여준다. 사용자가 **이 기록으로 복원**을 누른 경우에만 워치에 적용한다. 조회 이후 펫 상태가 바뀌면 복원을 거절하고 다시 조회하도록 안내한다.
- 같은 계정의 걸음수는 날짜별 큰 값을 유지한다. 다른 계정으로 복원할 때는 이전 계정의 로컬 상태를 별도로 보관한다. 다른 계정의 기존 워치 상태를 바로 백업하는 동작은 거절한다.

로그인과 HTTP 요청은 iPhone이 담당한다. 워치가 단독으로 셀룰러/Wi-Fi에 연결되어 있어도 iPhone을 거치지 않고 서버에 백업하지 않는다. 백업 파일과 확인 메시지는 WatchConnectivity가 적절한 시점에 전달하므로 완료가 지연될 수 있다. 복원 미리보기에는 두 앱을 열어 직접 연결할 수 있는 상태가 필요하다.

## 서버 계약

| 동작 | 요청 |
|---|---|
| Apple 로그인 — 새 서버 계약 | `POST /api/v1/auth/apple`, identityToken·authorizationCode·rawNonce·userIdentifier·선택적 name |
| 세션 갱신 | `POST /api/v1/auth/refresh`, `{"refreshToken":"…"}`. 404/405에서만 `/api/v1/refresh` 재시도 |
| 백업 | `POST /api/v1/backup`, Bearer access token |
| 펫 복원 | `GET /api/v1/usermates/1`, Bearer access token |
| 걸음수 복원 | `GET /api/v1/stepcounts/me`, Bearer access token |

백업의 `userMateId`는 서버 행 ID가 아니라 **카탈로그 mate ID 1**이다. 날짜는 `yyyy-MM-dd`, 걸음수는 정수, `lastFedAt`은 Android와 같은 시간대 없는 LocalDateTime 표현이다. 실제 서버의 로그인 응답에는 선택된 mate와 신규 사용자 여부가 없으므로 기본 mate 1을 사용한다. 복원 응답의 두 userId와 로그인 계정이 일치하는지 검증한다.

401/403이면 refresh를 한 번 공유해 실행하고 원래 요청을 한 번 재시도한다. 회전된 refresh token도 저장한다. refresh의 401/403은 세션을 만료시키고, 일시적인 네트워크·서버 오류는 자격 증명을 지우지 않는다. 로그아웃이나 계정 변경 중 도착한 이전 요청이 세션을 되살리지 못하도록 검사한다.

**서버가 저장하지 않는 항목:** 먹이 수량, 미사용 스탯 포인트, 로컬 보상 지급 내역, 터치 중간 횟수. 복원할 때 같은 계정의 이 로컬 값을 보존한다. 새 기기에서 서버만으로 이 값을 복구할 수는 없다. 다른 계정에 기록이 없으면 먹이·포인트를 새로 지급하지 않는다. 서버의 `userfoods` 등 별도 API를 이번 백업 DTO에 임의로 추가하지 않았다.

## 저장과 중단 복구

| 위치 | 저장 내용 |
|---|---|
| iPhone Keychain | 서버 주소에 연결된 BackendSession. `AfterFirstUnlockThisDeviceOnly`, iCloud 동기화 안 함 |
| Watch `Application Support/PetPet/game-state-v1.json` | 펫·먹이·걸음수·보상 내역·백업 대기·계정별 보관 상태를 하나로 원자적 저장 |
| iPhone `cloud-receipts-v1.json` | 성공한 서버 백업, 워치 확인 여부, 송신 순번, 확인 전 복원 명령 |
| 양쪽 `CloudInbox`, `CloudOutbox` | 전체 기록 전송용 파일. 처리 완료 후 수신 파일 삭제 |

최초 실행 시 기존 `step-history-v1.json`과 `pet-progress-v1.json`을 통합 저장소로 옮긴다. 기존 파일은 변경하지 않고 이전 버전의 복구 사본으로 남긴다. 새 파일이 존재하면서 손상된 경우 오래된 사본으로 조용히 되돌리지 않고 저장 오류를 표시한다. 기존 기록과 먹이를 지우거나 신규 지급을 반복하지 않는다.

백업·복원 명령에는 operation ID와 워치 저장소 ID가 있다. 백업 순번이 오래된 파일은 재업로드하지 않으며, 이미 처리한 성공 확인은 보상을 중복 지급하지 않는다. iPhone 재실행 시 확인 전 성공 메시지와 복원 명령을 재전송한다. 워치는 복원 적용 후 확인을 보내며 동일 명령을 다시 적용하지 않는다. 자정 뒤에 도착한 성공 메시지는 내보낸 당시 날짜와 시간대의 걸음수에만 보상을 준다.

파일은 16 MiB 이하, 작은 제어 메시지는 60,000바이트 이하로 제한한다. WCSession 파일 콜백이 반환하면 시스템이 파일을 삭제하므로 콜백 안에서 먼저 앱 수신함으로 이동한다. 이동 직후 앱이 종료된 경우 다음 활성화에서 수신함을 다시 처리한다. 인증 토큰은 워치 전송·일반 JSON 파일·로그에 넣지 않는다.

## 검증 범위

공용 패키지 86개 테스트가 통과한다. Apple 교환 요청 형식·필수 응답·미구현 경로·state와 유효 시간·기존 Keychain 표현 호환·refresh 후 Apple 식별 유지·로그아웃 경합을 포함한다. 기존 동시 refresh, 백업·복원·이관·중복 보상·역순·중단 복구 테스트도 통과한다. HTTP는 주입한 모의 서버 응답을 사용했다.

2026-11-07 Apple 전환 검증: iPhone·Watch 전체 Debug/Release 시뮬레이터 빌드와 서명을 생략한 실기기용 아키텍처 컴파일이 통과했다. 기본 서명한 iPhone 시뮬레이터에서 Google 버튼이 사라지고 Apple 기본 버튼이 표시되는 것, 로그인 전 서버 백업·복원 버튼이 비활성화된 것을 확인했다. 기존 걸음수·펫·먹이 화면과 워치 연결도 유지됐다. 실제 Apple 인증 화면에서 계정을 인증하거나 운영 서버로 자격 증명을 전송하지 않았다.

앞선 백업 연동 단계에서는 워치 Crown의 네 번째 계정·백업 섹션과 저장소 이관을 확인했다. 사용자가 승인한 워치 시뮬레이터 피트니스 권한을 허용했으며 실제 워치 설정은 변경하지 않았다. 기존 시뮬레이터 걸음수·펫·먹이·지급 내역·터치 횟수와 보존된 이전 파일을 비교했다.

현재 실기기 프로파일은 Sign In with Apple capability와 `com.apple.developer.applesignin` entitlement를 포함하지 않아 Apple 로그인 추가 후 서명 빌드는 실패한다. 이를 제거해서 설치한 것을 로그인 검증으로 취급하지 않는다. 서버 구현·Apple 개발자 팀/프로파일 설정 후 실제 Apple 계정 로그인과 운영 백업·복원을 별도로 확인해야 한다. 이번 변경은 실기기에 설치하지 않았다.

```sh
swift test --package-path Packages/PetPetCore
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
