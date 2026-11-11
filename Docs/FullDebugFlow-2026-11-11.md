# 아이폰·워치 Debug 전체 흐름 최종 점검

## 범위

아이폰·워치 UI를 정리한 현재 소스를 별도의 새 시뮬레이터 페어에서 검사했다. 계정·백업·랭킹·AI는 `LocalDevelopmentBackend`를 사용하며 Apple 인증이나 운영 서버를 호출하지 않는다. Mac의 주 화면·마우스·창 이동 없이 CLI와 XCTest로 실행했다.

- Xcode 27.2 (27B52)
- iPhone SE 3세대 / iOS 18.0: `62CC3FF5-FBE5-44D0-93A6-A10DA462ED7E`
- Apple Watch SE 2세대 40mm / watchOS 11.0: `A9079E67-24A1-43C4-A431-48DAAB3E59C8`
- 페어: `E41F3EC6-2278-464E-8F3E-6F010FBC25C0`
- 실행 원본: `/private/tmp/petpet-final-20261111/verified/`

센서의 실제 걸음 측정은 시뮬레이터로 검증할 수 없어 새 워치의 Development 저장소에 2026-11-11의 4,321보와 2026-11-10의 2,000보만 준비했다. 로그인·펫·먹이·점수·보상·백업·복원은 파일에 주입하지 않고 실제 앱 UI와 WatchConnectivity를 거쳤다. 슈팅 체력을 늘리는 설정도 사용하지 않았다.

## 검사 흐름

| 순서 | 확인 사항 |
| --- | --- |
| 로그인 전 | 초기 우유 3개, 보상 비활성, 피트니스 권한 허용 |
| 로그인 | 아이폰 모의 로그인 → 워치 계정 전파 → 오늘 4,321보·Lv.1·우유 3개 수신, 백업 없는 복원 안내 |
| 먹이·성장 | 우유 3→1개, Lv.2·경험치 0·스탯 포인트 2, 체력 배분 후 체력 9·포인트 1, 재실행 유지 |
| 백업·보상 | 아이폰 백업 후 우유 5개·사과 1개, 같은 기록 재백업 시 중복 지급 없음, 복원 미리보기 취소 |
| 백업 후 변화 | 아이폰을 닫고 워치에서 우유 5→4개·경험치 1, 공격 50→51·포인트 0 |
| 복원 | 아이폰이 현재 워치 상태를 다시 수신, 이전 펫으로 복원 시 경험치 0·공격 50, 현재 먹이 4개·사과 1개·포인트 0 보존 |
| 로그아웃·재로그인 | 워치 로그아웃 전파, 로그인 없이 우유 4→3개·경험치 1로 돌보기 계속 가능, 재로그인·재실행 시 로컬 진행 유지 |
| 워치 백업 | 워치에서 현재 펫의 백업 요청, 아이폰 저장과 워치 완료 확인, 같은 걸음수 보상 중복 없음 |
| 슈팅 | 이동·일시정지·종료·결과 제출·다시 하기·재실행 후 최고 기록 |
| 별계단 | 정답 1계단·일시정지·시간 초과·결과 제출, 독립 랭킹 진입·새로고침 |
| 아이폰 랭킹 | 워치에서 제출한 두 게임 기록 표시·게임 전환 |
| 워치 AI | 시스템 입력 후 6회 반복 완료, 긴 응답 중단, 입력 재활성화, 화면 복귀 후 초기화 |
| 계정 경계 | 로그아웃 뒤 로컬 게임 저장·AI 로그인 안내, 재로그인 뒤 랭킹 복구·AI 6회 재사용 |
| 아이폰 AI | 반복 응답 2회, 긴 질문 미리보기·응답 중단·입력 재사용 |

검사기 `Scripts/test_full_debug_flow.py`는 앞의 계정·성장·백업 9단계와 게임·랭킹·AI 13단계를 연결한다. 각 XCTest 결과 번들에서 선택한 검사 1건의 성공과 실패·건너뛰기 0건, 대상 시뮬레이터 UDID를 확인한다. 마지막에는 워치 원본·아이폰 수신 스냅샷·모의 서버의 펫·먹이·걸음·게임 기록 및 백업 확인 저널을 비교한다. 결과에 인증 토큰을 기록하지 않는다.

## 최종 결과

| 검증 | 통과 | 결과 |
| --- | ---: | --- |
| 연속 UI 흐름 | 22단계 | 워치 13·아이폰 9 실행, 19개 테스트 메서드. 최종 채택 실행의 실패·건너뛰기 0건 |
| 첫 입력 안내 회귀 | 1개 | 별도 워치에서 안내가 실제로 표시됨을 확인, 오디오 공유 거절·안내 닫힘·시스템 입력·AI 응답 6회 성공 |
| 공용 로직 | 180개 | 성장·보상·저장·동기화·계정·백업·게임·AI 관련 전체 패키지 회귀, 실패 0건 |
| 앱 모델 | 22개 | 워치 백업 6·활동 수명 2·대화/랭킹/게임 8, 아이폰 표시 모델 6, 실패·건너뛰기 0건 |
| 빌드 | 모두 성공 | 아이폰·워치 Debug 테스트 빌드, 아이폰·포함된 워치 앱 Release Simulator 빌드 |

이번 기능 점검에서 추가 제품 오류는 발견하지 않았다. 변경 사항은 현재 UI와 첫 실행 시스템 안내에 맞춘 검사기 수정 및 연속 실행·결과 대조 도구다. 초기 진단 실패와 수정 후 채택한 통과 실행을 검증 JSON에서 구분했다.

최종 페어의 원본 저장값은 다음과 같다.

- Lv.2·경험치 1/4·공격 50·방어 0·체력 9·스탯 포인트 0
- 우유 3개·사과 1개, 11월 11일 4,321보·11월 10일 2,000보
- 백업 적용 3건·복원 적용 1건, 대기 중 백업·복원 0건
- 슈팅 최고 점수 5점·별계단 1계단/콤보 1, 모의 서버의 게임 점수와 일치
- 아이폰 수신 펫·먹이·걸음 기록이 워치와 일치하며, 모의 서버 펫 능력치·걸음 기록도 현재 워치와 일치

슈팅 콤보는 기존 API 계약상 로컬 기록이며 서버 비교는 점수만 한다. 별계단은 점수와 콤보를 함께 비교한다. 계정은 양쪽 모두 `개발 테스트 계정`으로 복구됐다.

첫 입력·모델 회귀는 앞선 진단용 쌍(`8F26631E-6E43-4D1E-BCC9-D84F20C8CD61` / `0A5BC441-A9DE-4956-8E8A-D443F870E610`)에서 별도로 실행했다. 입력 안내의 실제 거절 로그와 펫·먹이 불변을 확인한 뒤 해당 쌍을 종료했고, 최종 페어의 데이터 일치도 다시 확인했다.

화면 검사용 큰 글씨 실행 인자가 Debug 바이너리에는 있고 Release에는 없음을 아이폰·워치 각각 확인했다. 현재 Swift 5 구성의 Release 빌드는 성공했으며 기존 `WatchConnectivityTransport`의 Swift 6 액터 격리 경고는 남아 있다. Swift 6 언어 모드 전환은 이번 기능 검증 범위에 포함하지 않았다.

## 화면과 실행 기록

- [로그인·최초 동기화](Screenshots/FullDebugFlow/journey-01-flow-login-and-first-sync.png), [워치 체력 배분](Screenshots/FullDebugFlow/journey-02-flow-watch-level-up-and-health.png)
- [두 번째 백업 완료](Screenshots/FullDebugFlow/journey-03-flow-repeat-backup-complete.png), [복원 후 먹이 보존](Screenshots/FullDebugFlow/journey-05-flow-restored-pet-kept-inventory.png)
- [재로그인·재실행](Screenshots/FullDebugFlow/journey-07-flow-relogin-relaunch-preserved-progress.png), [워치에서 시작한 백업](Screenshots/FullDebugFlow/journey-08-flow-watch-initiated-backup.png)
- [슈팅 결과 제출](Screenshots/FullDebugFlow/games-01-games-shooting-submitted.png), [별계단 결과 제출](Screenshots/FullDebugFlow/games-02-games-stairs-submitted.png)
- [워치 랭킹 새로고침](Screenshots/FullDebugFlow/games-03-games-ranking-refresh-button.png), [아이폰의 워치 게임 기록](Screenshots/FullDebugFlow/games-04-games-phone-watch-rankings.png)
- [워치 AI 6번째 응답](Screenshots/FullDebugFlow/games-05-games-chat-answer-6.png), [응답 중단](Screenshots/FullDebugFlow/games-06-games-chat-cancelled.png)
- [로그아웃 AI 안내](Screenshots/FullDebugFlow/games-08-games-logged-out-chat-guard.png), [재로그인 후 AI 재사용](Screenshots/FullDebugFlow/games-11-games-chat-answer-6.png), [아이폰 긴 질문 중단](Screenshots/FullDebugFlow/games-12-games-phone-chat-cancelled.png)
- [별도 첫 입력 회귀의 6번째 응답](Screenshots/FullDebugFlow/first-use-watch-ai-answer-6.png)
- [단계별 네이티브 결과와 최종 상태](Verification/FullDebugFlowSimulator-2026-11-11.json)

## 검사기 수정

이전 성장 검사기는 스탯 포인트가 레벨과 함께 화면에 생성된다고 가정했다. 새 40mm 목록에서는 해당 행이 아래에 있어 첫 실행이 멈췄다. 당시 저장값은 정상적으로 Lv.2·우유 1개였다. 포인트와 능력치 행을 스크롤해 확인하고, 행이 지연 생성되는 동안에도 스크롤 방향을 유지하도록 고쳤다. 아이폰 검사도 바뀐 홈 배치에서 위아래 항목을 찾아간 뒤 값을 읽는다.

먹이를 이미 소비한 첫 쌍을 억지로 초기화하거나 다시 먹이지 않고, 위의 새 페어에서 최종 흐름을 처음부터 다시 실행했다. 첫 진단용 쌍은 종료 상태로 보존했다. 제품 데이터·성장 규칙을 변경한 수정은 아니다.

새 워치에서 첫 시스템 입력을 열 때 선택적인 ‘Siri 및 받아쓰기 기능 향상’ 안내가 늦게 나타났다. 즉시 `exists`만 확인하던 검사기가 이를 놓쳐 입력창 종료를 기다리다 중단됐다. 알려진 안내 제목이 나타날 때까지 기다리고 ‘지금 안 함’을 스크롤해 선택한 뒤 닫힘을 확인하도록 고쳤다. 중단된 입력 단계부터 같은 페어에서 이어서 실행한다. 워치의 실제 받아쓰기 품질을 검증하는 대신, 받아쓰기를 중지하고 시스템 손글씨 입력 모드에 XCTest 문자열을 넣어 앱의 전송·응답 흐름을 검사한다.

## 재실행

새 시뮬레이터 쌍을 생성·페어링·부팅한 뒤 실행한다. 아래 명령에 기록된 ID는 이번 최종 실행에서 이미 먹이와 보상을 사용한 기기이므로, 처음부터 재실행할 때는 새 ID와 새 결과 디렉터리를 사용한다.

```sh
python3 -B Scripts/test_full_debug_flow.py \
  --phone NEW_PHONE_SIMULATOR_ID \
  --watch NEW_WATCH_SIMULATOR_ID \
  --build /private/tmp/petpet-watch-ux-272 \
  --artifacts /private/tmp/petpet-next-full-flow
```

중간 실패 시 `Scripts/test_debug_flow.py` 또는 `Scripts/test_games_flow.py`의 `--from-stage`로 정확한 단계부터 이어간다. 이미 성공한 먹이 소비·능력치 배분·복원을 반복하면 상태가 달라지므로 먼저 저장값을 확인해야 한다. 앞부분을 완료한 뒤 `--from-part games --skip-build`, 모든 UI 단계를 완료한 뒤 `--from-part verify`로 집계만 재실행할 수 있다.

이번 결과는 Debug 모의 계정과 시뮬레이터의 기능 검증이다. 실제 센서·마이크 인식 품질·무선 환경·운영 Apple 로그인 및 운영 서버를 검증한 결과는 아니다.

검사기 수정은 `9549b43`(스크롤과 지연 생성 행), `070d7d7`(연속 실행·네이티브 결과·최종 상태 대조), `93b1e43`(첫 입력의 늦은 시스템 안내 처리)로 나눠 커밋했다.
