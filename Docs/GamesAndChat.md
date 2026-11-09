# 게임·랭킹·음성 AI 대화

Android `Chaeros/StepMate`의 `main` 커밋 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`을 기준으로 남은 주요 기능을 이식했다. 이번 변경은 **시뮬레이터에서만** 빌드·설치·검증했다.

## 사용 경로

- 워치 크라운 페이지: 홈 → 성장 → 먹이 → 스트릭 → **펫과 놀기** → **펫과 대화** → 계정과 백업.
- **펫과 놀기 → 게임 선택**에서 두 게임과 각 TOP 10을 연다. 시작 화면에 저장된 최고 기록을 표시한다.
- 슈팅은 크라운·좌우 드래그, 별계단은 크라운·방향 버튼으로 조작한다.
- 상단 버튼으로 일시정지하거나 종료한다. 종료를 확인하면 현재 기록으로 결과·랭킹을 연다. 화면 비활성화·저휘도에서는 멈추고 사용자가 계속하기를 눌러 재개한다.
- 40mm에서도 시작 설명·능력치·최고 기록을 스크롤해 시작 버튼 전체에 접근할 수 있다. 시작 화면에서 앱을 나갔다 돌아와도 새 게임은 정상 플레이 상태로 시작한다. 슈팅 영역은 접근성으로 현재 좌우 위치도 읽어 준다.
- **펫과 대화 → AI 대화 열기**에서 시스템 받아쓰기 또는 키보드로 질문을 작성한다. 내용을 확인·수정한 뒤 전송한다.
- 아이폰 홈 **게임 랭킹 · AI 대화**에서 워치가 제출한 랭킹과 AI 대화를 사용한다. 게임은 워치에서 실행한다.

## 지구를 지켜라

펫 공격력·체력을 복사해 시작하고 기본 0.4초 간격으로 레이저를 자동 발사한다. 게임의 피해는 육성 펫의 체력을 소비하지 않는다. 체력은 Int64로 유지해 큰 복원 값의 정밀도 손실·표시 변환 충돌을 피한다. Android처럼 공격력이 0이면 일반 적과 앞의 두 보스에는 피해를 주지 않는다. Android에서 방어력 인자는 실제 피해 계산에 사용되지 않아 같은 정책을 유지했다.

현재 콤보는 점수·체력 아래에 표시한다. 시작 체력이 0이면 체력을 임의로 늘리지 않고 Android처럼 즉시 0점 결과를 전달하며, 다시 시작해도 같은 규칙을 적용한다.

| 항목 | 규칙 |
|---|---|
| 일반 적 점수 | 운석 1 · 유성 2 · 우주 쓰레기 3 · 외계인 10 |
| 아이템 | 공격 속도 ×1.2 · 공격력 ×1.2 · 체력 +20(시작 체력 상한) · 일반 적/탄환 제거 |
| 콤보 | 처치 시 증가, 피해 시 초기화. 원본 경로와 같이 100단위 공격 속도 증가 |
| 1단계 보스 | 100점 · HP 5,000 · 30초 · 보상 100점 |
| 2단계 보스 | 450점 · HP 100,000 · 입장 후 30초 · 보상 200점 |
| 3단계 지휘관 | 1,100점 · HP 300,000 · 60초 · 보상 250점/콤보 +10 |
| 지휘관 패턴 | HP 70%/35%에서 단계 전환, 방어력 24/12/0, 원형·조준 탄환과 외계인 소환 |

SpriteKit 노드를 재사용하고 원본 뒤돌아 달리기 6프레임, 운석·유성·쓰레기·보스 프레임을 네이티브 액션으로 재생한다. 논리 좌표계를 화면에 투영하며 터치 입력 영역을 SpriteKit 뷰와 분리한다. 렌더러는 30fps를 요청하고 엔진은 고정 60Hz로 진행한다. 원본의 디스플레이 갱신 횟수에 따른 속도 차이는 재현하지 않는다. 큰 시간 간격은 한 번에 0.25초까지만 처리한다.

## 별계단 훈련

목숨 3개, 정답 시 계단 수·콤보 +1, 오답·시간 초과 시 목숨 -1과 콤보 초기화다. 실패 후 다음 계단은 유지된다. 같은 방향은 최대 4회, 과거·미래 계단은 각각 4개를 유지한다. 입력 직전에도 경과 시간을 반영한다. 시스템 시각 변경과 무관한 `systemUptime`을 사용한다. 30Hz 갱신 작업은 실제 플레이 중에만 실행하고 일시정지·결과·화면 이탈에서 취소한다.

| 계단 수 | 한 계단 제한 시간 |
|---|---|
| 0~19 | 1.5초 |
| 20~49 | 1.2초 |
| 50~99 | 1.0초 |
| 100~199 | 0.8초 |
| 200 이상 | 0.65초 |

## 기록과 랭킹

게임별 최고 점수와 별계단 최대 콤보를 워치의 `minigame-records-v1.json`에 원자적으로 저장한다. Debug는 `Application Support/PetPet/Development/`, Release는 기존 루트를 사용한다. 기존 펫·걸음수 백업 계약에 게임 필드를 임의 추가하지 않는다. 로그인·서버 실패 시 로컬 기록을 유지하고 결과 화면에서 재시도할 수 있다. 자동 백그라운드 제출 큐는 사용하지 않는다.

| API | 메서드·본문 |
|---|---|
| `/api/v1/shooting-game/rank/score` | POST `{ "score": 42 }` |
| `/api/v1/shooting-game/rank/position` | POST 동일 본문 |
| `/api/v1/shooting-game/rank/top10` | GET |
| `/api/v1/star-stair-game/rank/score` | POST `{ "maxStep": 42, "maxCombo": 12 }` |
| `/api/v1/star-stair-game/rank/position` | POST 동일 본문 |
| `/api/v1/star-stair-game/rank/top10` | GET |

기존 `BackendClient`의 인증·공유 refresh·계정 epoch 검사를 재사용한다. 워치는 토큰 없이 `WatchFeatureClient → WatchConnectivityTransport → PhoneFeatureCoordinator`를 통해 아이폰에 요청한다. 요청 ID·계정·개발 환경을 확인하고 응답은 60KB로 제한한다. 양쪽 계정 변경 시 진행 작업과 이전 랭킹을 정리한다. refresh 실패로 인증이 사라지면 아이폰 계정 화면과 워치 상태에도 반영한다.

## 음성·AI 스트리밍

워치의 마이크 버튼은 WatchKit의 시스템 텍스트 입력 UI를 호출한다. 시스템이 받아쓰기·키보드를 제공하며 앱이 녹음 파일을 만들거나 상시 마이크를 구독하지 않는다. 아이폰에서도 키보드의 받아쓰기를 사용할 수 있다.

Android와 같은 `POST /api/v1/ai/chat/stream`, JSON `{ "question": "..." }`, Bearer 인증, `Accept: text/event-stream`을 사용한다. iPhone URLSession이 SSE를 읽고 워치는 0.3초마다 누적 텍스트를 요청한다. `metadata/context/token/done/error`, 여러 줄 data, 주석, 마지막 빈 줄 없는 종료를 처리한다. 질문은 2,000자/8KB, 답변은 UTF-8 24KB, 요청 전체 시간은 120초로 제한한다.

네이티브 URLSession 경로는 바이트 단위로 SSE 빈 줄·CRLF/LF/CR을 보존하고 UTF-8이 완성된 줄에서만 디코딩한다. 잘못된 MIME·UTF-8·32KB 초과 줄을 거절하며 종료 시 네트워크 작업을 취소한다. 로컬 URLProtocol로 분할된 한글·이모지와 실제 이벤트 전달을 검증한다. 완료 작업을 동시 요청 제한에 포함하지 않고 워치가 수신을 마치면 정리한다. 취소가 시작보다 먼저 도착하거나 이전 작업의 응답이 늦어져도 새 작업을 변경하지 않는다.

화면 이탈·백그라운드·사용자 중단·계정 변경은 요청을 취소하고 로그아웃 후 늦은 토큰을 폐기한다. 질문·답변은 파일로 저장하지 않고 화면과 제한된 진행 중 작업에만 유지한다.

## Debug와 서버 설정

Debug의 영구 모의 백엔드는 모의 상대 3명과 현재 계정의 최고 기록으로 랭킹을 구성하며 닉네임 변경을 반영한다. AI는 `[개발용 모의 응답]`을 여러 토큰으로 전달한다. 이 경로는 외부 서버나 AI에 연결하지 않으며 Release에 포함하지 않는다.

운영 API는 기존 Android 경로·본문을 사용한다. 서버는 [Apple 로그인 명세](AppleSignInServer.md)로 발급한 내부 계정 토큰으로 랭킹·AI에도 접근할 수 있어야 한다. 서버 배포·운영 계정 검증은 수행하지 않았다. AI 제공자 키를 앱에 넣지 않는다.

## 검증

- 공용 테스트 **180개** 통과: 시간·목숨·생성 규칙, 슈팅 30/60fps 동일 진행·아이템·보스 3종 도달, 큰 복원 능력치·공격력/체력 0, 영구 최고 기록, 두 게임 API 계약, refresh·로그아웃 경합, 네이티브 SSE·모의 랭킹·반복 대화·취소 경합·환경/요청 경계.
- Debug·Release 전체 iOS/watchOS 시뮬레이터 빌드 통과. 실행용 Debug는 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`로 로컬 서명했다. 서명 없는 시뮬 실행에서 발생한 Keychain 오류의 해결을 확인했다.
- Series 11 46mm / watchOS 26.5 시뮬레이터: 페이지·게임 선택, 별계단 시작·정답 1계단/1콤보·시간 초과·계단 배치·결과, 슈팅 터치 이동·자동 발사·점수·일시정지·종료 확인·최고 기록 유지·TOP 10 확인.
- 워치 시스템 키보드로 `안녕`을 전송해 `AI 응답 완료`와 전체 모의 답변 확인.
- iPhone 17 Pro / iOS 26.5 시뮬레이터: 워치의 3점/4위와 닉네임, `Hello` 질문의 모의 AI 응답 완료 확인.
- 실제 기기·마이크로 말한 받아쓰기·운영 Apple 계정 및 운영 랭킹/AI 서버는 이번 검증에 포함하지 않았다.

후속 [워치 중심 전체 검토](WatchAudit-2026-11-08.md)에 40mm/watchOS 11의 실제 XCTest 플레이·재시작·최고 기록 유지, 시작 화면 잘림과 복귀 후 일시정지 시작 버그 수정, 검증 화면을 기록했다.

[Debug 게임·랭킹·AI 전체 흐름 검토](GamesAudit-2026-11-09.md)에는 40mm 워치 중심의 모의 계정 로그인·두 게임·랭킹·AI 연속 질문과 중단·로그아웃·재로그인, 아이폰 랭킹과 대화 검증을 기록했다. 워치 대화 입력 해제·계정별 점수 보호, 작은 화면의 랭킹 새로고침, 아이폰 긴 질문 입력 행의 높이를 보완했다. 재실행은 `Scripts/test_games_flow.py`를 사용한다.

```sh
swift test --package-path Packages/PetPetCore
python3 Scripts/importAndroidGameArtwork.py /path/to/pinned/android/pngs
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

이미지와 Git blob SHA는 [매니페스트](../Artwork/AndroidGameSources.json)에 기록했다. 스크립트는 33개 원본 해시를 확인하고 긴 변을 최대 512px로 패킹한다.

근거: [Android 슈팅](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_game1/presentation/FoxGameScreen.kt), [별계단](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_game2/presentation/domain/logic/HeavenStairsEngine.kt), [SSE 클라이언트](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_voice/data/remote/AiChatStreamClient.kt), [Apple 시스템 입력](https://developer.apple.com/documentation/watchkit/wkinterfacecontroller/presenttextinputcontroller(withsuggestions:allowedinputmode:completion:)), [URLSession 스트리밍](https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:)).
