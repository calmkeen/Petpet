# 아이폰 앱과 워치 동기화 검토 — 2026-11-08

Android 기준은 `Chaeros/StepMate`의 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`이다. GitHub에서 현재 main과 같은 커밋인지 확인하고 `mobile`의 로그인·홈·스트릭·워치 설치 안내와 실제 API 계약을 비교했다. 이번 작업은 시뮬레이터에서만 수행한다. Mac 화면 좌표·마우스나 창 이동 대신 사용자가 허용한 XCTest를 사용한다.

## Android와의 대응

| Android mobile의 실제 구현 | 아이폰 대응과 검토 결과 |
|---|---|
| 로그인과 refresh·세션 만료 처리 | Apple/Debug 모의 계정 유지. 스트릭·펫 조회를 포함한 모든 인증 요청의 세션 무효화가 계정 화면과 워치까지 전달되도록 공통 알림을 추가 |
| `/api/v1/usermates/{selectedMateId}`로 서버 펫 표시 | 워치 수신 기록이 없어도 로그인 후 서버 펫을 조회. 계정별 표시 캐시와 오류·재시도 추가 |
| 레벨·경험치·기분·호감도·공격·방어·체력 | 워치 기록을 우선 표시하고, 서버 데이터이면 ‘서버 백업 기록’과 조회 시각으로 구분. 서버가 저장하지 않는 스탯 포인트는 추정하지 않음 |
| 최근 365일 스트릭, 마지막 백업일 기준 연속 일수 | 기존 기준 유지. 조회 실패 시 캐시 보존, 캐시 저장 실패 시에도 새 서버 결과 표시, 자정·시간대 변경 시 히트맵 날짜 갱신 |
| 워치 연결·설치 안내와 수동 갱신 | 로그인 없이 열리는 Watch 앱 페어링·설치 안내 추가. 홈을 당기거나 ‘지금 동기화’로 워치·서버 펫·스트릭을 갱신 |
| 하단 순위·AI·내 정보 버튼 | Android 해당 버튼은 안내용 자리 표시자. iOS에는 이미 실제 랭킹·AI·계정 화면이 있으므로 이를 검토하고 유지 |
| Google 로그인·Play Store 원격 설치 | iOS의 Apple/모의 로그인과 Watch 앱 설치 안내로 대응. Google 설정이나 존재하지 않는 App Store 링크를 추가하지 않음 |

워치의 현재 상태가 원본이다. 서버 펫 조회는 표시만 하며 워치에 복원하지 않는다. 서버의 날짜별 과거 기록을 오늘의 실시간 걸음수로 표시하거나 보유 먹이를 추정하지 않는다. 워치 기록이 있으면 로그인 여부와 관계없이 우선 표시한다.

## 수정한 문제

1. **워치 전환 중 새 수동 동기화가 막힘:** 이전 워치의 미완료 요청이 전역 busy 상태를 잡고 있었다. 워치 변경 시 요청 ID를 교체하고 새 요청을 허용한다. 이전 요청의 늦은 실패가 새 워치의 성공 상태를 훼손하지 않도록 검사한다. 회귀 테스트에서 기존 실패를 재현했다.
2. **조회 경로에 따른 로그아웃 표시 차이:** 랭킹·AI만 개별적으로 인증 만료를 알리던 경로를 BackendClient의 공통 무효화 알림으로 통합한다. 병렬 요청도 한 번만 알리고 일시적인 500 오류는 로그아웃으로 처리하지 않는다. 알림은 자격 증명 저장 작업 밖에서 실행하며 UI는 현재 세션을 다시 읽는다.
3. **스트릭 오류 시 기록 유실 표시:** 404에서 마지막 정상 기록을 지우던 처리를 없앴다. 서버 조회와 로컬 캐시 쓰기를 구분해 저장 오류가 새 결과를 숨기지 않도록 했다. 갱신 제한은 단조 증가 시계를 쓰며 날짜가 바뀌면 제한을 건너뛴다.
4. **AI 응답 중단이 랭킹 요청까지 취소:** 채팅 취소를 별도 메서드로 분리했다. 진행 중인 응답이 없는데 화면을 나가는 것만으로 ‘응답 중단’ 오류를 만들지 않는다. 게임·대화 화면의 탐색 막대를 명시적으로 표시해 뒤로 가기를 제공한다.
5. **Debug/Release 표시용 데이터 혼합:** 계정·백업과 달리 홈 표시용 스냅샷에는 환경 구분이 없었다. development는 버전 2와 환경 태그를 쓰고 production은 기존 버전 1과 호환된다. 반대 환경의 수신·캐시는 표시하지 않으며 같은 테스트/정식 앱을 설치하도록 안내한다. 기존 개발용 송신 파일의 ID와 순번은 새 형식으로 이어진다. 오래된 개발용 수신 캐시는 새 태그가 있는 워치 응답을 받을 때 다시 표시한다.
6. **자동 검사에서 먹이 버튼 식별자 가려짐:** 상위 VStack/ScrollView의 접근성 식별자가 하위 버튼·수량에 상속되는 것을 실제 XCTest 계층에서 확인했다. 불필요한 상위 식별자를 없애고 개별 버튼·수량·계정 이름을 식별한다. 게임 규칙과 입력 동작은 바꾸지 않는다.
7. **작은 아이폰에서 키보드와 전송 버튼 접근:** AI 입력에 키보드 ‘완료’와 스크롤로 닫기를 제공하고 전송 시 포커스를 해제한다. iOS 18의 TextView와 최신 런타임의 TextField 접근성 차이는 테스트에서 함께 지원한다. 스크롤 중 내용이 상태 표시줄과 겹치던 홈은 화면 경계에서 자른다. 마지막 SE 캡처에서 상태 표시줄 아래로 잘리는 것을 확인했다.

서버 펫 캐시는 `server-pet-v1.json`에 계정 ID·펫·조회 시각을 원자 저장한다. 계정 변경·로그아웃 시 메모리 표시를 비우며 다른 계정 캐시는 반환하지 않는다. API 응답의 소유자·날짜·능력치 범위를 검증한다. Debug 파일은 기존과 같이 `Development/` 안에 저장한다.

## 검증

- 공용 패키지 **177개 테스트 통과**. 서버 펫 API·소유자/수치/날짜 검증·계정별 캐시·공통 인증 무효화, 워치 전환의 요청 경합, 환경 분리·기존 파일 갱신을 추가로 검사했다.
- 아이폰 화면 모델 **6개 테스트 통과**. 서버 표시와 워치 우선순위, 오프라인 캐시·계정 분리·로그아웃, 스트릭 404·캐시 저장 실패·날짜 변경, 채팅 취소와 랭킹의 독립성을 검사했다.
- **iPhone 17 Pro / iOS 26.5: UI 3개 통과.** 연결·설치 안내와 홈 복귀, 모의 AI 질문·응답과 뒤로 가기, 짧은 닉네임 검증·변경·재실행 유지, 워치 모의 백업 성공·복원 미리보기·취소·적용 완료를 검사했다.
- **Series 11 46mm / watchOS 26.5: UI 1개 통과.** 실제 먹이 버튼으로 우유 7개에서 6개로 감소, 재실행 후 아이폰의 변경한 닉네임과 같은 이름 표시를 확인했다.
- **iPhone SE 3세대 / iOS 18.0: 최종 UI 2개 통과.** 작은 화면의 연결 안내·AI 입력·키보드 ‘완료’·응답·뒤로 가기와 워치 없는 서버 펫 표시를 검사했다. 독립 시뮬레이터에 자격 증명·워치 캐시를 복사하지 않고 모의 백업의 펫·기록만 준비했다. 앞선 실패는 런타임별 입력 접근성 유형과 키보드 중 스크롤에서 발생했고 최종 수정 후 같은 시뮬레이터에서 통과했다.
- **실제 저장 값 대조 모두 일치.** 워치 원본·송신본·아이폰 수신본의 펫·먹이·걸음수, 아이폰 모의 프로필과 워치 닉네임을 비교했다. 우유 6개·경험치 1/2, 기존 테스트 기록 2026-11-07의 4,321보·11-08의 0보가 일치했다. 같은 날짜의 추가 백업 후 우유는 6개를 유지했고 대기 중 백업·복원도 없었다. [민감 정보 없는 검증 결과](Verification/PhoneSynchronizationSimulator-2026-11-08.json).
- **Debug 테스트 빌드와 마지막 수정 포함 Release iOS/watchOS Simulator 빌드 성공.** 기존 실기기나 실제 운영 서버에 설치·전송하지 않았다.

결과 번들은 `/private/tmp/petpet-streak-build/Logs/Test/` 아래 `Test-PetPet-2026.11.08_18-29-54-+0900.xcresult`(아이폰 3 UI+6 모델), `Test-PetPet Watch App-2026.11.08_18-28-13-+0900.xcresult`(워치 UI), `Test-PetPet-2026.11.08_18-35-10-+0900.xcresult`(SE 최종 2 UI)다. 워치 먹이 검사 후의 새 닉네임 변경도 저장 값 대조에서 다시 확인했다.

확인한 원본 화면: [아이폰 워치 펫·먹이](Screenshots/PhoneAudit/phone-synced-watch-pet.png), [복원 미리보기](Screenshots/PhoneAudit/phone-restore-preview.png), [복원 완료](Screenshots/PhoneAudit/phone-watch-restore-complete.png), [SE 설치 안내](Screenshots/PhoneAudit/phone-watch-setup-se.png), [SE 서버 펫](Screenshots/PhoneAudit/phone-server-pet-without-watch.png), [SE 랭킹·AI 응답](Screenshots/PhoneAudit/phone-mock-ai-se.png), [워치 먹이 사용](Screenshots/PhoneAudit/watch-fed-milk.png), [워치 닉네임](Screenshots/PhoneAudit/watch-synced-phone-nickname.png).

운영 Apple 인증·실제 서버·실기기 센서/무선 성능은 이번 검증 범위에 포함하지 않는다. Debug 로그인·백업·랭킹·AI는 아이폰 내부 모의 백엔드를 사용한다.

## 재실행

```sh
swift test --package-path Packages/PetPetCore --scratch-path /private/tmp/petpet-daily-step-tests
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'platform=iOS Simulator,id=PHONE_SIMULATOR_ID,arch=arm64' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 -parallel-testing-enabled NO -only-testing:PetPetTests/PhonePresentationTests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

`PhoneAuditUITests`의 연결 안내·AI·닉네임 검사는 독립적으로 실행할 수 있다. `testPairedWatchBackupAndRestoreRoundTrip`은 페어링된 시뮬레이터와 열린 워치 앱, `testServerPetWithoutWatch`는 워치 캐시가 없는 독립 시뮬레이터와 모의 서버 백업이 필요하다. 운영 자격 증명을 테스트에 복사하지 않는다.

```sh
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'platform=iOS Simulator,id=PAIRED_PHONE_SIMULATOR_ID,arch=arm64' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 -parallel-testing-enabled NO -only-testing:PetPetUITests/PhoneAuditUITests/testConnectionGuideAndExtrasReturnHome -only-testing:PetPetUITests/PhoneAuditUITests/testNicknameValidationPersistsAcrossRelaunch -only-testing:PetPetUITests/PhoneAuditUITests/testPairedWatchBackupAndRestoreRoundTrip CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
xcodebuild -project PetPet.xcodeproj -scheme 'PetPet Watch App' -configuration Debug -destination 'platform=watchOS Simulator,id=PAIRED_WATCH_SIMULATOR_ID,arch=arm64' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 -parallel-testing-enabled NO -only-testing:'PetPet Watch AppUITests/WatchPhoneSyncUITests' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'platform=iOS Simulator,id=UNPAIRED_SE_SIMULATOR_ID,arch=arm64' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 -parallel-testing-enabled NO -only-testing:PetPetUITests/PhoneAuditUITests/testConnectionGuideAndExtrasReturnHome -only-testing:PetPetUITests/PhoneAuditUITests/testServerPetWithoutWatch CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

워치 UI 검사는 우유가 한 개 이상 있고 아이폰에서 `Phone…` 형태의 검사용 닉네임을 저장한 상태를 사용한다. 서로 다른 사전 조건의 UI 검사들을 한 기기에서 일괄 실행하지 않고 위와 같이 선택한다. 아이폰 26.5 검사는 작은 화면 후속 수정 전의 통과 결과이며, 키보드·클리핑 수정은 SE의 마지막 실행과 마지막 Release 빌드에서 검증했다.

## 수정 커밋

- `f768df1` — 워치 전환 중 수신 요청 분리
- `86c994f` — 서버 펫 조회·계정별 캐시·공통 인증 만료 알림
- `01b42b3` — 아이폰 기능 보완·표시 데이터 환경 구분·회귀 검사
- `2066a7f` — 작은 아이폰의 키보드 완료·스크롤 상태 표시줄 겹침 보완

참조: [Android mobile 기준 소스](https://github.com/Chaeros/StepMate/tree/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/mobile), [Apple의 워치 앱 설치 안내](https://support.apple.com/en-us/109023), [동기화 구조](WatchSynchronization.md), [개발용 모의 계정](DebugTesting.md).
