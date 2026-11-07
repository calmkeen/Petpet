# Android 기능 대응표

기준 저장소: [Chaeros/StepMate](https://github.com/Chaeros/StepMate)

분석 기준: `main`, 커밋 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`. 아래 Android 항목은 소스에 구현된 경로를 기준으로 하며, 서버의 실제 운영 결과를 검증했다는 의미는 아니다.

| Android 기능 | 확인한 구현 | Apple 측 현재 상태 / 후속 위치 |
|---|---|---|
| 워치 홈·걸음수 | `feature_stepcounter`, 자정 리셋·센서 재시작 복구·일일 기록 | 오늘 자정 기준 집계·저장 복원·자정/시간대 전환·최근 기록 복구 구현 |
| 펫 이미지·움직임 | `MateMovingImage`, 시간대별 배경 | 고정 이미지 유지. 반응 초안과 Motion 어댑터 분리 |
| 펫 능력치·터치 | `feature_statistics`, 스탯 배분·50회 터치 호감도·공복/활동 상태 | 레벨·경험치·스탯 배분·호감도·기분과 영구 저장 구현 |
| 먹이·보상 | `feature_userfoods`, `StepStreakViewModel.grantBackupRewards` | 먹이 소비·신규 우유 3개·1,000걸음당 우유·일일 사과·중복 방지 구현. 현재 로컬 저장 뒤 수령 |
| 스트릭·닉네임 | `feature_stepstreak`와 서버 API | 후속 `Features/Streak` 및 기능별 Data |
| 로그인·세션 | `feature_auth`, Google ID Token 교환·refresh·세션 만료 처리 | 후속 `Features/Auth`, Keychain·인증 API 어댑터 |
| 백업·복원 | `feature_backup`, Room 데이터와 메타데이터 | 걸음수·펫·먹이·보상 내역 로컬 저장 구현. 서버 백업·복원은 미구현 |
| 지구를 지켜라 | `feature_game1`, 펫 스탯을 사용하는 슈팅·스테이지·랭킹 | 후속 게임 도메인 엔진과 watchOS 렌더러 |
| 별계단 훈련 | `feature_game2`, 계단 게임·점수·랭킹 | 후속 게임 도메인 엔진과 watchOS 렌더러 |
| 음성·AI 대화 | `feature_voice`, 음성 입력과 스트리밍 클라이언트 | 후속 음성 권한·녹음/인식·스트리밍 어댑터 |
| 폰 보조 앱 | `mobile`, 로그인·홈·스트릭·워치 설치/연동 | WatchConnectivity로 걸음수·펫·먹이 수신·캐시·재연결·수동 갱신 구현. 로그인·서버 스트릭은 후속 |

## 호환 기준

- 앱 이름·Xcode 타깃·Bundle ID는 PetPet의 기존 값을 사용한다. Android 패키지 이름을 Apple Bundle ID로 복사하지 않는다.
- iOS 18 / watchOS 11 최소 버전을 유지한다. 구조 정비를 위해 사용자 기기나 Xcode 버전 업그레이드를 요구하지 않는다.
- Android의 `Long` 식별자·능력치는 공용 모델에서 `Int64`로 다룬다. `PetStatistic` ID 1~6, `PetMood`의 HAPPY/SAD/HUNGRY 값은 원본 의미를 유지한다.
- 서버와 공통 계정 사용은 기본 방향이다. 인증 audience·iOS OAuth 설정·서버 DTO·날짜 표현은 인증 이식 단계에서 맞춘다. Android 빌드 설정의 비밀 값이나 클라이언트 키를 소스에 복사하지 않는다.
- Google Credential Manager, Wearable Data Layer, Room, Samsung Health SDK, Android 음성 입력 UI는 Apple에서 직접 사용할 수 없다. 해당 기능은 Apple용 어댑터와 UI로 구현한다.
- 실제 규칙은 README나 화면 이름보다 위 기준 커밋의 코드가 우선한다. 원본 버그까지 동등하게 재현하지 않으며, 의도된 규칙과 버그가 갈리는 경우 이 대응표에 결정과 차이를 남긴다.

## 하루 걸음수의 플랫폼 차이

Android의 부팅 이후 센서 원시 누적값·offset 보정은 Apple에 복사하지 않는다. CoreMotion은 요청한 시작 날짜부터의 누적 합계를 제공하므로 자정 구간 조회와 실시간 값을 최댓값으로 병합한다. 재실행·센서 재연결 시 중복 합산을 방지하고, 저장된 오늘 기록보다 작은 일시적인 응답은 기록을 줄이지 않는다.

날짜별 저장·앱 재실행 복구·자정 초기화는 같은 사용자 동작을 제공한다. 백그라운드에서는 앱의 지속 실행을 가정하지 않고 복귀 시 시스템 기록으로 보정한다. CoreMotion의 과거 조회 한계는 최근 약 7일이며, 기존 로컬 기록은 이 범위 이후에도 유지한다. [자세한 구현·검증 기준](DailySteps.md).

## 먹이·성장과 보상의 차이

게임 수치와 지급량은 Android와 동일하다. Android는 서버 백업 성공 뒤 지급하며, Apple 앱은 서버 연결 전까지 명시적인 로컬 저장·수령 버튼을 사용한다. 펫·먹이·지급 내역은 하나의 원자적 파일 저장으로 처리하여 Android의 개별 저장 사이 중단으로 인한 중복 지급·먹이 유실을 방지한다. 공복과 미접속이 동시에 성립하면 HUNGRY를 우선한다. 자세한 원본 경로와 규칙·결정은 [먹이·성장·보상](FeedingAndGrowth.md)을 따른다.
