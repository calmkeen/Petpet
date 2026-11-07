# 먹이·성장·걸음수 보상

Android 기준은 [StepMate `4e2b5e5`](https://github.com/Chaeros/StepMate/tree/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3)다. `FoodTypeEnum`, `UserFoodsViewModel`, `UserMateRepository.gainStat`, `StatisticsViewModel`, `StepStreakViewModel.grantBackupRewards`, `MainActivity.grantStarterMilkToNewUser`를 확인했다.

## 같은 게임 규칙

| 항목 | 규칙 |
|---|---|
| 첫 로컬 사용자 | 레벨 1, 경험치·호감도·스탯 포인트 0, 공격력 50, 방어력 0, 체력 8, HAPPY, 우유 3개 |
| 먹이 | 우유(ID 1) 경험치 +1, 사과(ID 2) +3, 고기(ID 3) +5 |
| 소비 | 보유 먹이 1개를 소비하고 경험치를 적용. 빈 항목 제거. 기분 HAPPY와 마지막 식사 시각 갱신 |
| 레벨업 | 현재 레벨 × 2 경험치를 차감, 레벨 +1, 스탯 포인트 +2. 남은 경험치를 보존하고 추가 레벨업 반복 |
| 스탯 배분 | 포인트 1개로 선택한 공격력·방어력·체력 +1 |
| 쓰다듬기 | 홈의 펫을 누른 누적 횟수 50마다 호감도 +1. 중간 횟수도 저장 |
| 공복·미접속 | 식사 후 24시간이면 HUNGRY. 24시간 미접속이면 SAD. 식사하면 HAPPY |
| 걸음수 보상 | 오늘 걸음수 / 1,000의 정수 몫만큼 우유. 이전에 받은 몫을 제외한 차이만 지급 |
| 일일 보상 | 보상 받기에 성공한 날 사과 1개. 1,000걸음 미만이어도 지급 |

Android의 Debug 테스트 데이터(사과 1개 등)는 실제 신규 사용자 지급과 구분하여 복사하지 않았다. 고기는 카탈로그·소비 규칙을 지원하지만 이 단계의 걸음수 보상으로 지급하지 않는다. Android에도 고기 이미지 파일이 없어 watchOS 기본 기호를 대체 표시한다. 우유·사과 이미지는 위 커밋의 원본 리소스를 사용한다.

## 보상 시점의 플랫폼 차이

Android는 센서 이벤트마다 자동 지급하지 않고 **서버 백업 성공 후** 보상을 준다. 현재 Apple 앱에는 인증·서버 백업이 없으므로 먹이 화면의 **기록 저장·보상 받기**가 로컬 저장 성공 뒤 같은 지급 규칙을 실행한다. 서버 백업을 수행하거나 성공했다고 표시하지 않는다. 서버 연동 시 이 트리거를 백업 성공 뒤로 옮길 수 있다.

버튼은 현재 표시된 오늘 기록을 저장하고 저장소의 최댓값을 다시 읽는다. 저장 실패·저장 도중 날짜 변경 시 지급하지 않는다. 이후 걸음수가 다음 1,000단위를 넘으면 추가분을 받을 수 있다. 과거 기록을 복구하는 작업에는 보상을 붙이지 않는다.

## 저장과 화면

- 홈의 성장·먹이 버튼으로 각 화면을 열고, 목록은 세로로 스크롤하거나 Digital Crown으로 읽는다. 기본 뒤로 가기로 홈에 돌아온다. 화면 이동 중에도 하루 걸음수 추적을 유지한다.
- `PetProgressViewModel`은 화면 상태와 동작을 담당하고, 규칙은 공용 `PetPetCore`에 둔다.
- `FilePetProgressRepository`는 `Application Support/PetPet/pet-progress-v1.json`에 펫·먹이·터치 횟수·활동 시각·날짜별 지급 내역을 한 번에 원자적으로 저장한다. 기존 `step-history-v1.json`은 계속 사용한다.
- 저장이 실패하면 메모리 상태도 이전 상태를 유지한다. 재시도 시 소비·성장 또는 보상이 정확히 한 번 적용된다. actor가 연속 명령을 직렬화하고, UI는 저장 중 버튼을 잠근다.
- 재실행이나 일시적으로 감소한 센서 값은 지급 내역을 초기화하지 않는다. 날짜별 내역을 보존해 날짜·시간대를 되돌려도 같은 날짜의 보상을 다시 주지 않는다.
- 손상되었거나 알 수 없는 버전의 파일은 덮어쓰지 않고 오류와 재시도를 표시한다. 앱 데이터를 삭제하거나 초기 먹이를 다시 주는 방식으로 오류를 숨기지 않는다.
- 공복 여부는 앱 복귀 시와 활성 상태에서 10분마다 확인한다. 동시에 공복·미접속인 경우 HUNGRY를 우선한다. Android의 비동기 상태 갱신 순서에 따른 경쟁과, 미접속 검사 전에 활동 시각을 덮어쓰는 문제는 재현하지 않는다.
- iPhone 표시와 WatchConnectivity, 로그인·서버 백업은 다음 단계다.

## 검증

Swift Package 테스트는 기존 걸음수 24개에 먹이·성장·저장·보상 테스트 18개를 더한 42개다. 경험치 경계·복수 레벨업·스탯 배분·50회 터치·24시간 경계, 동시 소비·동시 수령, 앱 재시작, 낮아진 걸음수, 날짜 재방문, 파일 손상·저장 실패 후 재시도, 과거 기록 제외를 검증한다.

```sh
swift test --package-path Packages/PetPetCore
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PetPet.xcodeproj -scheme PetPet -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

실기기 확인: 먹이 화면에서 우유를 먹여 경험치 증가와 수량 감소를 확인하고, 레벨업 후 성장 화면에서 스탯을 배분한다. 보상 버튼으로 받은 뒤 앱을 재실행해 수량·경험치·지급 내역이 유지되는지 확인한다. 당일 다음 1,000걸음 전에는 같은 우유 보상을 재지급하지 않아야 한다.
