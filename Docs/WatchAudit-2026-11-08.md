# 워치 중심 Android 비교·회귀 검토 — 2026-11-08

비교 기준은 Android `Chaeros/StepMate`의 `main`, **`4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`**이다. 이번 검토에서도 동일한 HEAD임을 확인했다. Android 소스와 현재 Swift 구현을 대조하고, 문제가 재현되는 테스트를 추가한 뒤 수정했다. **이번 작업은 시뮬레이터만 사용했다. 실기기 조회·빌드·설치·실행은 하지 않았다.**

## 비교 범위

| 영역 | 비교·검토한 내용 | 결과 |
|---|---|---|
| 홈·걸음수 | 날짜별 누적, 자정·시간대 전환, 센서 실패·재연결, 저장 복구 | 누적 병합 정책 유지. 같은 날 센서 재시도 버그 수정 |
| 펫·성장 | 신규 능력치, 먹이별 경험치, 레벨·스탯 포인트, 터치·호감도, 공복·기분 | Android 규칙과 일치. 작은 워치 성장 화면 보완 |
| 먹이·보상 | 신규 우유 3개, 1,000보당 우유, 하루 사과, 백업 성공 후 지급 | 기존 구현 유지. 모의 백업 반복 시 중복 보상 없음 확인 |
| 애니메이션 | 시간대별 배경, 달리기·인사, 화면 이탈·비활성 재생 제어 | 기존 네이티브 프레임 재생 유지. 작은 홈 화면 높이 조정 |
| 스트릭 | 워치 로컬 기록, 월·윤년·날짜 경계, 1보 기준 연속 일수, 날짜 조회 | 기존 계산 유지. watchOS 11 선택 화면 이동 보완 |
| 계정·닉네임 | 입력 규칙, 중복 검사, 계정 변경, 인증 만료 전파 | 만료된 세션의 화면·워치 반영 경로 수정. 긴 이름 줄 수 제한 |
| 백업·복원·동기화 | 아이폰 경유 전송, 성공 확인, 원래 날짜 보상, 중복·계정·환경 검사 | 기존 원자 저장·멱등성 테스트 통과. 모의 백업 UI 재검증 |
| 슈팅 | 적·아이템, 공격력·체력, 세 보스 임계값·타이머, 결과·랭킹 | 공격력 0 규칙과 큰 복원 능력치 처리 수정 |
| 별계단 | 목숨·콤보, 계단 생성, 구간별 시간, 일시정지·재개 | 시스템 시계 변경에 영향받지 않는 경과 시간 사용 |
| 랭킹 | 두 게임 계약, 로컬 최고 기록, 계정별 결과 표시 | 계정 변경 시 이전 랭킹·진행 요청 제거 |
| 음성·AI | 시스템 입력, SSE, 반복 질문, 취소·늦은 응답, 아이폰 중계 | 반복 사용·취소 경합·실제 URLSession 스트림 처리 수정 |
| Android 설정 | `feature_setting`의 `SettingScreen` | 소스에는 배경·화면 이동만 있는 자리 표시자. 별도 설정 기능 누락으로 보지 않음 |

현재 Android의 주요 클라이언트 기능에 대응하는 구현은 있다. Apple 로그인·서버 운영 검증과 플랫폼별 센서·음성 입력 차이는 별도 확인이 필요하다. 세부 규칙은 [대응표](AndroidParity.md), [먹이·성장](FeedingAndGrowth.md), [게임·대화](GamesAndChat.md)를 따른다.

## 수정한 문제

1. **다섯 번째 AI 질문이 거절됨.** 아이폰 중계가 완료된 작업도 동시 요청 4개 제한에 포함했다. 진행 중인 작업만 세고 완료 작업은 최대 8개로 정리한다. 워치도 완료 응답을 받으면 중계 작업을 해제한다.
2. **채팅 취소 순서와 늦은 콜백 경합.** 취소가 시작보다 먼저 도착하면 뒤늦은 요청이 살아났고, 취소된 작업의 콜백이 같은 ID의 새 작업을 실패시킬 수 있었다. 제한된 취소 이력과 작업별 generation을 검사한다. 계정이 입력 도중 바뀐 시스템 입력 결과도 버린다.
3. **걸음수 재시도가 실시간 구독을 복구하지 않음.** 같은 날짜이면 기록만 다시 읽던 경로를 수정해 종료된 센서 구독도 재시작한다. 홈 오류 안내를 재시도 버튼으로 바꾸고, 저장된 걸음수와 이전 구독의 늦은 응답 방지는 유지했다.
4. **큰 복원 능력치로 슈팅 화면이 충돌하거나 체력이 부정확해짐.** `Int64.max`를 Double로 바꾼 뒤 Int로 표시하는 경로를 없앴다. 체력·피해·회복은 Int64로 유지하고 상한 덧셈의 오버플로도 피한다. Android처럼 공격력 0은 일반 적과 앞의 두 보스에 피해 0이다. 외계인·지휘관의 최소 피해 규칙은 유지한다.
5. **이전 계정 랭킹 잔류와 시계 변경에 따른 별계단 시간 오차.** 계정 변경 시 랭킹 요청·결과를 정리하고 로컬 게임 기록은 유지한다. 별계단의 경과 시간은 `systemUptime`으로 측정한다.
6. **운영 URLSession SSE 경로에서 토큰이 사라짐.** 로컬 URLProtocol을 통한 네이티브 전송 회귀 테스트에서 기존 줄 변환 경로가 `metadata/token/token/done` 중 `done`만 전달하는 것을 재현했다. 바이트 단위로 빈 줄과 CRLF/LF/CR을 보존해 이벤트를 나누고, 분할된 한글·이모지 UTF-8, BOM, 마지막 개행 없는 응답을 처리한다. 잘못된 MIME·UTF-8과 32KB 초과 줄은 거절하고, 종료 시 URLSession 작업도 취소한다. 모의 백엔드만으로는 드러나지 않았던 문제다.
7. **랭킹·AI에서 인증이 만료되어도 로그인 표시가 남음.** refresh 실패로 BackendClient 세션이 사라진 경우 아이폰 계정 모델을 다시 읽고 워치에도 계정 상태를 전달한다. 저장 오류만으로 로그아웃을 추정하지 않는다.
8. **40mm 화면 잘림과 날짜 선택 후 복귀 문제.** 오류가 있는 작은 홈에서 펫 높이·간격을 줄이고, 성장 버튼이 화면 안에 들도록 배치했다. 계정 이름은 두 줄로 제한했다. watchOS 11에서 기본 Picker가 뒤로 가기 없는 선택 목록으로 열리는 현상을 관찰해, 날짜·연도·월을 명시적인 NavigationLink 목록으로 바꾸고 선택 시 `dismiss()`하도록 했다.

## 검증 결과와 한계

- **PetPetCore 169개 테스트, 실패 0개.** 이번에 11개 회귀 테스트를 추가했다. 반복 질문, 취소 선도착·이전 작업 콜백, 센서 재구독, 큰 체력·공격력 0, 네이티브 SSE·Unicode·잘못된 MIME·라인 제한, 스트림 인증 만료를 포함한다. 기존 날짜·성장·먹이·저장·백업·복원·계정·환경 분리 테스트도 통과했다.
- **Debug 전체 iOS/watchOS Simulator 빌드**, **Release 전체 iOS/watchOS Simulator 빌드** 및 마지막 날짜 선택 수정이 포함된 **Release watchOS Simulator 빌드** 성공. 실행용 Debug는 로컬 ad hoc 서명을 사용했다.
- Release 아이폰·워치 실행 파일에서 개발용 서버 주소와 모의 AI 응답 문자열이 포함되지 않음을 확인했다. 40mm와 46mm 워치 시뮬레이터에 마지막 수정 Debug 빌드도 업데이트했다.
- **SE 2세대 40mm / watchOS 11.0 시뮬레이터:** 홈 오류·크라운 안내와 성장 버튼이 잘리지 않음을 확인했다. 우유 3개에서 2개를 먹여 레벨 2·스탯 포인트 2가 되고, 체력에 1포인트를 써 체력 9·잔여 1포인트가 되는 것을 확인했다. 앱 업데이트·재실행 뒤에도 유지됐다. 로컬 스트릭·월별 캘린더와 기존 Picker의 복귀 문제를 확인했다.
- **Series 11 46mm / watchOS 26.5 + iPhone 17 Pro / iOS 26.5 페어링 시뮬레이터:** 크라운 페이지·계정·백업 관리에 접근하고 모의 백업 완료 안내를 확인했다. 같은 날짜·기록을 두 번 백업한 뒤 두 번째에는 먹이 보상이 추가되지 않았고 대기 중 백업이 남지 않았다. 두 게임·랭킹·모의 AI 입력의 앞선 UI 검증은 [게임·대화](GamesAndChat.md)에 기록돼 있다.
- **입력 도구로 남았던 검증은 아래 XCTest 후속 검증으로 확인했다.** 초기 컴퓨터 조작에서는 보조 화면 좌표 오류로 날짜·연월 선택과 40mm 플레이를 완료하지 못했으며, 사용자가 명시적으로 요청한 XCTest 자동 UI 테스트로 전환했다.
- 실기기의 센서·받아쓰기·무선 연결, 실제 Apple 인증, 운영 서버의 백업·복원·랭킹·AI는 이번 검증 범위에 포함하지 않는다. 인증 만료 전파는 회귀 테스트·코드 검토·빌드로 확인했으며 운영 서버로 만료를 재현한 것은 아니다.

```sh
swift test --package-path Packages/PetPetCore --scratch-path /private/tmp/petpet-daily-step-tests
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/petpet-streak-release -jobs 2 CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PetPet.xcodeproj -scheme 'PetPet Watch App' -configuration Release -destination 'generic/platform=watchOS Simulator' -derivedDataPath /private/tmp/petpet-streak-release -jobs 2 CODE_SIGNING_ALLOWED=NO build
```

## 40mm 날짜·게임 후속 UI 검증

대상은 기존 **Apple Watch SE 2세대 40mm / watchOS 11.0 시뮬레이터**, 논리 화면 크기는 **162×197pt**다. 시뮬레이터를 새로 만들거나 기기를 지우지 않고 Debug 앱을 업데이트했다. 테스트는 시뮬레이터 내부에 직접 입력을 보내며 Mac 화면 좌표·마우스나 창 이동을 사용하지 않는다. 날짜·게임은 로그인 없이 동작하므로 페어링되지 않은 이 시뮬레이터에서 로컬 동작을 검증했다.

발견·수정한 앱 문제는 두 가지다.

1. **슈팅 시작 버튼 하단 잘림:** 기존 버튼 프레임이 `(9.5, 168, 143, 45)`로 화면 하단 197pt보다 16pt 벗어났다. 두 게임의 시작 설명을 ScrollView로 바꾸고 간격을 줄여, 최고 기록이나 긴 능력치가 있어도 끝까지 스크롤하고 시작 버튼 전체에 접근할 수 있게 했다.
2. **복귀 후 새 게임이 일시정지 상태로 시작:** 시작 화면에서 홈으로 나갔다 돌아오면 두 게임 모두 `paused`가 true로 남았다. 새 게임을 시작하는 버튼에서 이를 초기화했다. 시작 직후 ‘계속하기’가 나타나던 실패를 두 게임 모두에서 재현한 뒤 수정했다. 진행 중 게임의 일시정지·재개 정책은 유지한다.

슈팅 영역에는 현재 좌우 위치를 접근성 값으로 제공하고, 일시정지 버튼에 식별자를 부여했다. 이 값으로 실제 크라운·드래그 입력에 따른 위치 변화를 검사한다. 테스트는 게임 속도·목숨·센서 기록을 바꾸지 않는다.

| XCTest | 확인한 결과 |
|---|---|
| `testDateSelectionReturnsToCalendar` | 연도·월 목록 선택 후 자동 복귀, 2026년 2월의 28일 상한, 28일 선택 반영, 목록을 다시 열어 기본 뒤로 버튼으로 취소해도 28일 유지 |
| `testYearAndMonthSelectionReturnAndRespectLeapDay` | 2024년 2월 29일 선택·복귀, 2025년으로 변경 후 선택 날짜 1일 초기화·28일 상한 |
| `testShootingStartPauseFinishReplayAndSavedBest` | 시작 버튼 전체 표시, 시작 전 백그라운드 왕복, 실제 크라운·드래그 이동, 일시정지·재개, 종료 확인, 결과·다시 하기, 앱 재실행 후 최고 기록과 시작 버튼 유지 |
| `testStairsControlsTimeoutResultAndReplay` | 시작 전 백그라운드 왕복, 좌우 버튼 전체 표시·일시정지 중 비활성, 안내 방향 입력으로 1계단·1콤보, 자연 시간 초과 결과·로컬 저장, 다시 하기·명시적 종료 |

최종 동일 빌드의 **4개 UI 검사 일괄 실행, 실패 0개**를 확인했다. 후속 수정이 포함된 **Debug 테스트 빌드와 Release watchOS Simulator 빌드도 성공**했다. 공용 패키지는 변경하지 않았으며 위의 169개 테스트와 UI 테스트 수를 합산하지 않는다. 결과 번들은 `/private/tmp/petpet-small-watch-final.xcresult`, 실행 로그는 `/private/tmp/petpet-small-watch-final.log`다.

테스트 탐색은 크라운으로 루트 페이지를 바꾸고, 세부 목록은 행을 건너뛰지 않는 짧은 세로 드래그로 찾는다. 현재 화면의 기본 뒤로 버튼을 지정하며, 가상화된 결과 목록의 ‘다시 하기’는 스크롤한 뒤 확인한다. 테스트 코드: [WatchSmallScreenUITests.swift](../PetPet%20Watch%20AppUITests/WatchSmallScreenUITests.swift).

```sh
xcodebuild -project PetPet.xcodeproj -scheme 'PetPet Watch App' -configuration Debug -destination 'platform=watchOS Simulator,id=B2F4C50E-D489-48CF-B593-BFE304DD42F2,arch=arm64' -derivedDataPath /private/tmp/petpet-streak-build -jobs 2 -parallel-testing-enabled NO -only-testing:'PetPet Watch AppUITests/WatchSmallScreenUITests' -resultBundlePath /private/tmp/petpet-small-watch-result.xcresult CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
xcrun xcresulttool export attachments --path /private/tmp/petpet-small-watch-result.xcresult --output-path /private/tmp/petpet-small-watch-attachments
```

같은 결과 번들 경로가 이미 있으면 다른 경로를 사용한다. 명령의 시뮬레이터 ID는 로컬 환경에 맞춰 바꾼다. 세 보스를 끝까지 플레이하거나 실제 하드웨어의 성능·배터리를 검증한 것은 아니다. 게임 규칙·보스 진행은 기존 공용 테스트를 따르며, 운영 랭킹 서버는 이번 범위에 포함하지 않았다.

통과한 게임 실행의 원본 화면: [슈팅 시작·최고 기록](Screenshots/Watch40mm/shooting-ready.png), [슈팅 일시정지](Screenshots/Watch40mm/shooting-paused.png), [별계단 조작 버튼](Screenshots/Watch40mm/stairs-paused.png), [별계단 시간 초과 결과](Screenshots/Watch40mm/stairs-result.png).

## 수정 커밋

- `ea1ecb6` — 완료 채팅 정리·취소 경합 차단
- `1a3fc42` — 센서 구독 재시도 복구
- `ad62052` — 큰 게임 능력치·계정별 랭킹·경과 시간
- `af7fff4` — 네이티브 SSE 이벤트 경계 보존
- `c910240` — 인증 만료를 아이폰·워치 계정에 전파
- `63239c2` — 작은 워치 배치·명시적 날짜 선택 복귀
- `c207902` — 40mm 날짜·게임 UI 회귀 테스트 추가
- `f47c515` — 40mm 게임 시작 화면 스크롤·백그라운드 복귀 후 시작 상태 수정 및 UI 검증 보완

참조: [Android 기준 소스](https://github.com/Chaeros/StepMate/tree/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3), [Apple AsyncBytes의 URLSession 작업](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes/task). SSE 문제는 Apple 문서의 일반 보장으로 추정한 것이 아니라 로컬 네이티브 전송 테스트에서 재현한 결과다.
