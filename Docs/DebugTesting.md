# 무료 계정으로 아이폰·워치 테스트

기본 **Debug 구성**은 Apple 인증이나 운영 서버를 사용하지 않는 개발용 모드다. 실제 기기의 걸음수·펫·먹이 기능과 WatchConnectivity는 그대로 사용하고, 로그인·백업 서버만 아이폰 안의 모의 구현으로 대체한다. 개인 Apple Developer Program 결제나 Google OAuth ID가 필요하지 않다.

## 실행 방법

1. Xcode에서 `PetPet` scheme의 Run → Build Configuration을 **Debug**로 선택한다. 기존 Bundle ID와 Personal Team을 사용한다.
2. 페어링된 워치와 아이폰에 Debug 앱을 모두 설치한다. 기기 앱 이름은 **PetPet Debug**다. 같은 Bundle ID이므로 별도 앱으로 신규 등록하거나 기존 앱을 지울 필요가 없다.
3. 두 기기에서 앱을 열고, 아이폰의 **계정 · 서버 백업 → 개발용 계정으로 로그인**을 누른다. Apple 로그인 창은 뜨지 않는다.
4. 워치에 **개발 테스트 계정** 또는 변경한 닉네임이 표시되면 아이폰의 **워치 기록 모의 백업** 또는 워치의 **모의 백업·보상 받기**를 누른다. 전체 기록을 아이폰으로 보내 저장하고 워치가 테스트 보상을 받는다. 전달 시점은 WatchConnectivity 상태에 따라 지연될 수 있다.
5. 아이폰에서 **모의 백업 불러오기**를 누르면 저장된 기록을 미리 볼 수 있다. **이 기록으로 복원**을 눌러야 개발용 워치 상태에 적용한다. 백업이 없으면 먼저 백업하라는 안내를 표시한다.

로그아웃·재로그인은 같은 테스트 계정을 사용한다. 앱을 재실행해도 모의 백업을 유지하며, 같은 날 같은 걸음수에 보상을 중복 지급하지 않는다. 모의 백업은 이 아이폰에 저장되므로 다른 기기나 클라우드에 보관되는 데이터가 아니며 앱 삭제 시 함께 삭제된다.

워치의 네 번째 크라운 페이지는 **스트릭**이며 월별 로컬 기록과 날짜별 걸음수를 조회한다. 계정·백업은 다섯 번째 페이지다. 양쪽 **닉네임 변경**은 같은 모의 프로필을 사용한다. `사용중닉네임`·`StepMate`는 중복 테스트 값이며, 다른 이름으로 변경하면 재로그인·refresh·재실행 뒤에도 유지한다. 아이폰 스트릭 히트맵은 모의 백업한 기록을 표시한다. [사용법·규칙·최신 검증](StreakAndNickname.md).

**로그인 없이도 계속 개발할 수 있다.** 아이폰 홈의 워치 상태 수신과 워치의 걸음수 집계·먹이 소비·성장·스탯 배분은 로그인과 독립적이다. 로그인이 실패하면 홈으로 돌아가 이 기능을 테스트할 수 있다.

## Debug와 Release의 차이

| 항목 | Debug | Release |
|---|---|---|
| 로그인 | 로컬 모의 계정 | Apple 기본 로그인 |
| 백업 | 아이폰 안의 파일 | 운영 API |
| Apple entitlement | 빈 값 — 무료 Personal Team 서명 가능 | `PetPet.entitlements`의 Sign in with Apple |
| 앱 내 저장 위치 | `Application Support/PetPet/Development/` | `Application Support/PetPet/` |
| Keychain 세션 | `https://debug.petpet.invalid/` 전용 service | 운영 서버 주소 전용 service |
| 워치 전송 환경 | development, 프로토콜 버전 2 | production, 프로토콜 버전 1 |

Debug는 최초 실행 때 기존 워치의 **현재 펫·먹이·걸음수·지급 내역**을 개발용 저장소로 복사한다. 기존 계정 소유권·대기 중 백업·복원 명령은 복사하지 않고 새 저장소 ID를 발급한다. 이전 파일은 수정하지 않는다. 개발용 저장소가 이미 있으면 재실행 때 다시 덮어쓰지 않는다.

모의 보상·먹이 사용·복원은 개발용 복사본에만 적용된다. Release로 전환하면 기존 원본을 사용하며, 개발용 변경분은 자동 이관하지 않는다. Debug/Release가 섞인 두 기기 사이의 인증·백업·복원은 환경 검증으로 거절한다. 이전 앱도 개발용 프로토콜 버전 2를 거절하므로 모의 계정이 기존 저장소에 연결되지 않는다.

## 구현과 데이터 위치

- `LocalDevelopmentBackend`는 `BackendHTTPTransport`를 구현하는 actor다. URLSession이나 외부 서버 연결 코드가 없으며 `.invalid` 개발용 주소 외의 요청을 거절한다. 모의 로그인 진입점은 이 구체적인 전송 객체에서만 사용할 수 있다.
- 모의 구현과 로그인 메서드·버튼은 `#if DEBUG` 안에 있다. Release에는 모의 전송 클래스나 로그인 메서드가 포함되지 않는다.
- 모의 access/refresh는 실제 Apple 또는 운영 API 토큰이 아니다. 기존 `BackendClient`의 인증·refresh·서버 DTO를 거쳐 저장·복원 흐름을 검증한다.
- `Development/mock-backend-v1.json`에는 모의 서버의 펫·전체 날짜별 기록을 원자적으로 저장한다. 증분 업로드는 기존 날짜 기록을 유지하고 같은 날짜는 큰 값을 보존한다.
- `Development/game-state-v1.json`은 워치의 개발용 상태, `Development/cloud-receipts-v1.json`은 아이폰의 성공 확인·중복 방지 저널이다. 표시용 스냅샷과 송신 순번도 개발용 폴더에 둔다.
- 백업 파일의 환경 태그를 검사한 뒤 처리하며, 반대 환경의 파일은 해당 환경 수신함에 보관한다. 제어 메시지·복원 대상 조회도 환경을 확인한다.
- 두 앱이 열려 있으면 제어 메시지와 60,000바이트 이하 기록을 즉시 전달한다. 백그라운드 user-info/file 대기열도 유지하며, 중복 수신은 operation ID와 저장소 ID로 처리한다. 큰 전체 기록은 파일 전송을 사용한다.

## 검증

공용 패키지 테스트 **129개**가 통과했다. 개발 모드 관련 테스트는 운영 네트워크 경로 거절, 재실행 후 모의 백업·닉네임 복구, 증분·낮은 걸음수 병합, 빈 백업 안내, refresh 회전, 저장 실패 후 재시도·손상 보존, 기존 계정/먹이/보상 원본 보존, 레거시 파일 복사, Debug/Release 메시지·파일·복원 대상 차단, 완료 후 지연된 중복 요청의 재처리 방지를 검증한다. [스트릭·닉네임](StreakAndNickname.md)과 [원본 이미지·펫 재생](AndroidMedia.md) 검증도 기록했다.

현재 Personal Team으로 아이폰·watchOS Debug 서명 빌드를 통과했고, 서명된 실행 파일에 Apple 로그인 entitlement가 없는 것을 확인했다. Release 시뮬레이터 빌드와 실행 파일의 모의 백엔드·로그인 진입점 제외도 확인했다.

2026-11-07 실기기: iPhone 13 mini와 Series 10에 앱 삭제 없이 설치했다. 사용자가 양쪽의 **개발 테스트 계정** 표시를 확인했다. 실제 워치의 기존 걸음수·펫 파일과 아이폰의 기존 수신 캐시는 설치 전 사본과 바이트 단위로 일치했고, 양쪽에 별도 Development 저장소가 생성됐다. 설치 뒤 워치 자동 실행 명령은 무선 터널 연결 오류를 반환했지만, 이후 사용자가 워치 앱을 열어 양쪽 로그인을 확인했다. 실기기의 모의 백업·복원 완료는 별도 수동 검증 항목이다.

전송 지연 개선을 포함한 최종 아이폰 업데이트도 완료했다. 워치의 마지막 업데이트는 일시적인 무선 터널 오류 이후 Xcode 기기 목록을 갱신하고 CoreDevice 식별자로 재시도해 설치 완료를 확인했다.

페어링된 시뮬레이터: 개발용 버튼 로그인, 앱 재실행 후 계정 유지, 워치 전체 기록 전송, 모의 저장, 워치 테스트 보상 확인, 복원 미리보기와 적용·완료 응답을 확인했다. 워치 저장소의 완료된 백업/복원과 아이폰의 미확인 복원 대기열 해소도 검사했다. 시뮬레이터에 있던 테스트 기록만 사용했으며 실기기에 임의 걸음수를 주입하지 않았다.

```sh
swift test --package-path Packages/PetPetCore
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Apple 계정의 실제 인증과 운영 서버 연동은 이 모드로 검증한 범위에 포함되지 않는다. Release 준비 사항은 [Apple 로그인 설정](AccountAndBackup.md)과 [서버 변경 명세](AppleSignInServer.md)를 따른다.
