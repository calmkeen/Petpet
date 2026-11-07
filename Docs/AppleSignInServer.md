# Apple 로그인 서버 변경 명세

iOS 클라이언트는 Apple 로그인으로 전환했다. **아래 Apple API는 iOS가 구현한 새 계약이며 현재 서버에 배포된 API라는 뜻이 아니다.** 서버 저장소는 변경하지 않았다.

이 문서는 실제 Apple 인증을 사용하는 **Release** 서버 계약이다. 기본 Debug의 모의 로그인·로컬 백업에는 서버 변경이 필요하지 않다. [무료 개발 모드](DebugTesting.md).

확인한 서버 기준: [StepMate_SpringBoot `bcdcefbb`](https://github.com/Chaeros/StepMate_SpringBoot/tree/bcdcefbb226951785e09a82c30ab473ef77e39da). 실제 수정 전 최신 브랜치와 비교한다. Android의 기존 Google 로그인·계정·백업은 유지한다.

## 1. 추가할 API

`POST /api/v1/auth/apple`, `Content-Type: application/json`, 로그인 전 요청이므로 PetPet Bearer 토큰은 보내지 않는다.

```json
{
  "identityToken": "<Apple identity JWT>",
  "authorizationCode": "<Apple one-time authorization code>",
  "rawNonce": "<64 lowercase hexadecimal characters>",
  "userIdentifier": "<ASAuthorizationAppleIDCredential.user>",
  "name": "<optional first-authorization display name>"
}
```

- iOS는 매 요청마다 CSPRNG로 32바이트 nonce와 별도의 state를 생성한다. `SHA256(rawNonce)`의 소문자 64자리 hex를 Apple 요청의 `nonce`에 넣고, 원문 `rawNonce`를 이 API에 보낸다.
- `state`는 Apple 콜백에서 iOS가 검증한다. iOS는 다른 요청의 state, 5분 이상 지난 콜백, 누락된 token/code를 거절한다. 서버는 아래의 서명·nonce·code 검증을 별도로 수행해야 한다.
- `userIdentifier`는 서버가 검증한 JWT의 `sub`와 반드시 일치해야 한다. 이 문자열이나 본문 `name`만으로 사용자를 인증하지 않는다.
- `name`은 최초 Apple 동의 때만 받을 수 있는 표시용 정보다. 생략될 수 있으며 신원·권한 판단에 사용하지 않는다. 이메일은 본문에서 받지 않고 검증한 Apple 토큰에서 읽는다.

성공 응답: `200 OK`, `Cache-Control: no-store`. 기존 PetPet 세션과 같은 형식으로 발급한다.

```json
{
  "userId": "7",
  "accessToken": "<PetPet access token>",
  "refreshToken": "<PetPet refresh token>",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "refreshExpiresIn": 2592000,
  "email": "<optional verified email or Apple relay email>",
  "name": "<optional display name>",
  "nickname": "<optional PetPet nickname>",
  "selectedMateId": 1,
  "isNewUser": false
}
```

위 만료 시간은 형식 예시이며 운영 정책값을 반환한다. **`userId`는 기존 `users.id`**다. Apple sub나 Google ID를 넣지 않는다. iOS는 `userId`, access/refresh token 중 하나라도 없으면 로그인 성공으로 저장하지 않는다. `selectedMateId` 생략 시 기존과 같이 카탈로그 mate 1을 사용한다.

| 상태 | 의미 / iOS 처리 |
|---|---|
| 400 | 본문 필드·형식 오류. 로그인 실패, 새 인증 필요 |
| 401 / 403 | 인증 증명 검증 실패. 로그인 실패 |
| 404 / 405 / 501 | Apple API 미구현·미지원 안내. Google API로 우회하지 않음 |
| 429 / 5xx / 네트워크 실패 | 실패 안내. 같은 일회용 code를 자동 재전송하지 않음 |

## 2. Apple 증명 검증

신규 `AppleIdTokenVerifierClient` / `AppleAuthService` / `AppleLoginRequest`를 추가한다.

1. Apple JWKS `https://appleid.apple.com/auth/keys`의 신뢰할 수 있는 키로 JWT 서명을 검증한다. 검증 라이브러리에 허용 알고리즘을 고정하고, 알 수 없는 `kid`일 때 키 목록을 제한적으로 갱신한다. 단순 Base64 디코딩이나 `alg=none`을 인증으로 취급하지 않는다.
2. `iss == https://appleid.apple.com`, `aud == com.calmkeen.PetPet`, `exp`, 합리적인 `iat`, 비어 있지 않은 `sub`를 검사한다. 네이티브 iOS의 client ID는 Bundle ID다.
3. JWT `nonce == lowercaseHex(SHA256(UTF8(rawNonce)))`를 검증한다. JWT의 `sub`와 본문의 `userIdentifier`도 비교한다.
4. `https://appleid.apple.com/auth/token`에 `grant_type=authorization_code`, `client_id`, 서버에서 만든 `client_secret`, `code`를 보내 일회용 code를 교환한다. 교환 결과의 id_token도 검증하고 최초 토큰과 같은 `sub`·audience의 인증인지 확인한다. 이 절차를 생략하면 같은 identity token/body의 재사용을 차단할 수 없다.
5. 검증 실패·만료·code 재사용에는 PetPet 세션을 발급하지 않는다. 성공한 nonce/code 증명은 한 번만 소비하도록 동시 요청과 재전송을 처리한다. Apple 교환 타임아웃을 성공으로 간주하지 않는다.
6. 검증한 `(APPLE, sub)`로 내부 사용자를 조회하거나 생성하고, 기본 mate 1과 기존 정책의 닉네임을 할당한다. 그 뒤 공용 세션 발급기로 PetPet 토큰 쌍을 발급한다.

Apple refresh token은 필요하면 서버에서 암호화해 보관하고 철회·연결 상태 확인에 사용한다. **iOS에 반환하는 refreshToken은 기존 PetPet refresh token**이다. Apple refresh token, `.p8` 키, client secret을 앱·워치로 전달하지 않는다. 요청 본문·identityToken·authorizationCode·rawNonce·토큰 교환 응답을 로그에 남기지 않는다.

공식 근거: [사용자 검증](https://developer.apple.com/documentation/signinwithapple/verifying-a-user), [Apple 토큰 교환](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), [nonce](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce).

## 3. 기존 코드에서 함께 수정할 부분

| 현재 파일 / 동작 | 필요한 변경 |
|---|---|
| `domain/auth/presentation/AuthController.java` | Apple 핸들러 추가. Google 핸들러와 기존 경로 별칭은 유지 |
| `domain/auth/service/GoogleAuthService.java` | 세션 발급·refresh를 공용 서비스로 분리. 현재 refresh도 `user.getGoogleId()`로 access/refresh를 만들므로 Apple 사용자에게 그대로 재사용할 수 없음 |
| `domain/auth/infrastructure/jwt/JwtTokenProvider.java` | 새 토큰의 principal을 내부 사용자 ID로 표현. Google/Apple 모두 같은 사용자 ID 정책 사용 |
| `global/security/JwtAuthenticationFilter.java` | 검증된 내부 ID를 담는 principal/resolver 도입. 기존 Google sub 토큰과의 이행 처리 필요 |
| `global/security/AuthenticatedUserProvider.java` | 현재 `getAuthenticatedGoogleId()`가 authentication name을 그대로 반환함. 내부 userId 기반 조회로 바꾸고 호출부를 함께 이행 |
| `domain/user/domain/User.java`, `UserRepository` | Google ID 필수 조건과 이메일에 의한 계정 식별을 분리. 외부 인증 식별자 테이블 도입 |
| `BackupService`, `StepCountService`, `UserMateService` 및 사용자·스트릭·랭킹·음성 서비스 | 인증 principal을 Google ID로 가정하는 `findByGoogleId` 조회를 공용 내부 사용자 조회로 변경 |
| `RefreshTokenSession` | 기존 user FK·회전·재사용 검사 유지. Apple 철회 시 해당 인증의 세션을 구분하려면 외부 인증 FK/제공자 정보도 기록 |
| `SecurityConfig.java` | 현재 `/api/v1/auth/**`가 이미 공개 경로라 새 로그인 경로도 포함됨. 백업·복원 API까지 공개하지 않음 |
| `domain/user/service/dto/MyUserResponse.java` | 기존 Google 사용자의 `googleId` 응답 호환은 유지하되 Apple 사용자에게 Google ID를 강제하지 않음 |

현재 `User.googleId`는 `nullable=false, unique=true`, `User.email`도 필수·고유다. Apple sub를 `google_id`에 억지로 넣는 방식으로 해결하지 않는다. 현재 Google 로그인에는 `findByEmail` 뒤 `syncProfile`로 Google ID를 덮어쓰는 경로도 있으므로, Apple 로그인만 추가해도 이메일이 같으면 의도치 않은 계정 연결이 생길 수 있다. Google 쪽도 제공자 식별자를 우선하도록 함께 정리한다.

권장 인증 식별자 구조:

```text
external_identities
  id
  user_id             -> users.id, 기존 펫·걸음수 FK와 같은 사용자
  provider            GOOGLE | APPLE
  subject             검증한 제공자 sub
  email               nullable, 프로필 정보
  email_verified      nullable
  unique(provider, subject)
```

`users.google_id`는 기존 사용자 backfill 뒤 nullable로 바꾸거나 이후 이행에서 제거한다. 이메일은 선택적 연락처/프로필로 다루고 전역 고유 식별자에서 분리한다. Apple의 가려진 이메일·누락된 이메일을 허용하며, 이메일 일치만으로 계정을 자동 병합하지 않는다.

## 4. 기존 Android 계정과 토큰을 유지하는 이행

1. 외부 인증 테이블을 추가하고 기존 `users.google_id`를 `(GOOGLE, subject, 기존 user_id)`로 backfill한다. `users.id`, 펫·걸음수·먹이 등 데이터 FK는 유지한다.
2. 새 access token에는 `ver: 2`, `uid: <users.id>`와 내부 ID 기반 subject를 넣고 공용 resolver가 이를 사용하게 한다. **Google sub도 숫자일 수 있으므로 숫자인지로 신·구 토큰을 구분하지 않는다.**
3. 서명·타입·만료가 검증된 기존 버전 access token만 legacy Google sub 경로로 해석해 기존 사용자로 연결한다. refresh는 `RefreshTokenSession.user`를 기준으로 새 버전 토큰을 발급한다. refresh 회전과 재사용 감지는 유지한다.
4. Google 로그인 응답의 기존 필드·별칭을 유지하고 Android 회귀 테스트를 통과시킨 뒤 Apple 핸들러를 연다. iOS의 기존 백업·복원 요청 DTO는 변경하지 않는다.

새 Apple 로그인은 연결된 외부 인증이 없으면 **새 PetPet 계정**이다. 기존 Google 계정의 데이터를 자동으로 가져오지 않는다. 현재 iOS 화면에는 계정 병합·연결 UI를 구현하지 않았다.

기존 Android 계정과 연결하는 기능이 필요하면 별도 `POST /api/v1/auth/apple/link`를 설계한다. 이미 로그인한 기존 PetPet 계정의 Bearer 증명과 새 Apple 인증 증명을 **둘 다** 검증해야 한다. Apple 식별자가 이미 다른 user_id에 연결되어 있으면 409로 거절하고, 두 계정의 데이터 병합은 별도의 명시적인 절차로 처리한다. 연결 성공 시 기존 user_id를 유지해야 기존 백업을 볼 수 있다. 이 경로는 이번 iOS 로그인 API와 별개의 후속 계약이다.

## 5. 서버·Apple 개발자 설정

- Apple Developer Program 팀에서 Bundle ID `com.calmkeen.PetPet`에 Sign in with Apple을 활성화하고 프로비저닝 프로파일을 갱신한다. iOS 프로젝트에는 `PetPet.entitlements`와 타깃 capability를 추가했다. [Apple 지원 capability 표](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)상 무료 Apple Developer/Personal Team에는 이 기능이 없다.
- 서버에 Apple Team ID, Key ID, Sign in with Apple `.p8` 개인 키, 허용 client ID를 설정한다. `.p8`은 secret store에서 공급한다. Apple token endpoint용 client secret은 서버가 ES256 JWT로 생성·회전한다. 네이티브 앱에는 개인 키나 Google OAuth Client ID가 필요하지 않다.
- 서버에서 Apple 인증 철회/계정 변경 알림을 검증해 외부 인증과 관련 세션에 반영한다. 클라이언트는 앱 실행·복귀와 credential revoked 알림에서 기기 credential 상태를 확인하지만, 서버 세션의 철회를 대신하지 않는다. [계정 변경 처리](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts).
- 앱 탈퇴를 구현할 때 Apple 연결 해제·관련 서버 토큰 철회와 데이터 처리도 함께 연결한다. 일반 로그아웃은 현재 기기의 PetPet 세션만 지운다.

## 6. 서버 인수 테스트

- 올바른 Apple token/code/nonce → 기존 내부 사용자 또는 신규 사용자와 PetPet 토큰 쌍 반환.
- 잘못된 서명·issuer·audience·nonce·sub·만료·재사용 code → 세션 미발급. 동일 증명의 동시 요청에서 중복 계정·세션 생성 방지.
- 첫 로그인 이름·relay 이메일, 다음 로그인 name 누락, email 누락 → 기존 프로필 유실·이메일 자동 연결 없음.
- Apple 사용자로 refresh 회전, 백업 POST, 펫·걸음수 복원 GET 성공. 다른 user_id 데이터는 조회·수정 불가.
- 기존 Android Google 로그인·구버전 access/refresh token·백업·복원 성공. 기존 사용자 ID와 데이터 FK 유지.
- 철회 알림·연결 충돌·일시적인 Apple 키 서버/토큰 교환 장애 처리. 원본 토큰·code·nonce가 로그에 없음.

iOS는 모의 HTTP 응답으로 요청 형식·미구현 경로·refresh·세션 경합을 검증했다. 운영 서버에 이 변경을 적용하거나 실제 Apple 계정으로 end-to-end 검증한 상태는 아니다.
