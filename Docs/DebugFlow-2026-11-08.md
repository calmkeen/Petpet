# Debug 모의 계정 전체 흐름 — 2026-11-08

아이폰과 워치를 각각 새로 만든 **iPhone SE 3세대 / iOS 18.0 + Apple Watch SE 2세대 40mm / watchOS 11.0 시뮬레이터**로 페어링해 검사한다. 기존 시뮬레이터 데이터를 초기화하거나 실기기를 조회·설치하지 않는다. Mac 화면·마우스 대신 사용자가 허용한 XCTest로 조작한다.

계정·백업 서버는 `LocalDevelopmentBackend`이며 실제 Apple 인증·외부 서버 연결을 사용하지 않는다. 걸음수 센서는 시뮬레이터에서 재현할 수 없어 신규 워치의 Development 저장소에 **오늘 4,321보, 어제 2,000보** 두 기록만 준비한다. 펫·먹이·보상·계정·토큰을 임의로 주입하지 않는다. 이후 변화는 실제 앱 버튼과 WatchConnectivity를 거친다.

## 연속 검사 시나리오

| 순서 | 조작과 기대 결과 |
|---|---|
| 0. 로그인 전 | 새 워치의 우유 3개, 백업·보상 버튼 비활성. 필요한 피트니스 시스템 권한은 실제 창에서 허용 |
| 1. 로그인·최초 동기화 | 아이폰의 모의 로그인, 워치 계정 전달, 4,321보·Lv.1·우유 3개 수신. 백업 없는 복원 시도는 안내만 표시 |
| 2. 먹이·성장 | 워치에서 우유 두 번: 3→1개, Lv.2·경험치 0/4·스탯 포인트 2. 체력에 1포인트: 체력 9·잔여 1. 재실행 유지 |
| 3. 백업·중복 방지·취소 | 아이폰이 성장 상태를 수신. 첫 백업 성공 후 우유 +4·사과 +1 → 우유 5개·사과 1개. 같은 기록 재백업에도 유지. 복원 미리보기를 취소하면 적용하지 않음 |
| 4. 백업 뒤 로컬 변경 | 아이폰 앱을 닫고 워치에서 우유 5→4개·경험치 1/4, 남은 포인트를 공격력에 써 51·잔여 0 |
| 5. 다시 열기·복원·로그아웃 | 아이폰이 새 워치 상태를 수신. 이전 백업으로 복원하면 경험치 0/4·공격력 50·체력 9. 현재 우유 4개·사과 1개·스탯 포인트 0·큰 걸음수는 보존. 양쪽 로그아웃 반영 |
| 6. 로그아웃 후 돌보기 | 워치의 계정 안내·보상 버튼 비활성. 우유 4→3개·경험치 1/4로 로컬 돌보기는 계속 가능 |
| 7. 재로그인·재실행 | 같은 모의 계정과 기존 백업 유지. 미리보기 취소·앱 재실행 후 현재 워치의 우유 3개·경험치 1/4가 유지되며 자동으로 옛 백업을 덮어쓰지 않음 |
| 8. 워치에서 백업 시작 | 재로그인된 워치의 보상 버튼으로 백업을 요청. 아이폰이 현재 펫을 저장하고 완료를 돌려주며 같은 걸음수 보상을 중복 지급하지 않아 우유 3개·사과 1개를 유지 |

각 단계 뒤 화면뿐 아니라 워치 원본·아이폰 모의 서버·표시 캐시·계정·백업 확인 저널을 대조한다. 비교 결과에는 자격 증명을 포함하지 않는다. 아이폰 앱 닫기는 네트워크 차단과 다르며, 시스템의 백그라운드 전달 여부를 가정하지 않고 다시 열었을 때의 일치를 검사한다.

## 최종 결과

- **9개 UI 단계, 실패 0개.** 아이폰 4개·40mm 워치 5개의 실제 XCTest 결과 번들을 조회해 각 1개씩 통과했음을 확인했다. 로그인 전 0단계를 통과한 같은 신규 쌍에서 검사기 조정 후 1~8단계를 연속 검증했다. 최종 실행의 펫·먹이 변화는 모두 앱 UI 조작으로 만들었다.
- **공용 패키지 179개 테스트, 실패 0개.** 연속/동시 백업 요청 병합과 계정 동기화 중 복원 재전송 보존을 추가했다.
- **워치 컨트롤러 회귀 2개, 실패 0개.** 동시 4개 요청의 파일 1개 전송과 전송 실패 후 busy 해제·재시도를 확인했다.
- **Debug 아이폰·워치 테스트 빌드와 Release iOS/watchOS Simulator 빌드 성공.** Release 검사는 `/private/tmp/petpet-debug-flow-release.log`, 공용 테스트는 `/private/tmp/petpet-flow-core-all.log`, 워치 회귀는 `/private/tmp/petpet-flow-watch-backup-fixed.log`에 기록했다.
- **마지막 파일 대조 10항목 모두 일치.** 워치·아이폰의 펫·먹이·전체 준비 걸음수, 모의 서버의 펫 능력치·날짜별 걸음수, 재로그인된 워치 계정, development 태그를 확인했다. 성공 백업 3개가 모두 확인됐고, 복원 1개가 적용됐으며 대기 중 백업·복원은 0개다.

마지막 상태는 **Lv.2·경험치 1/4·공격 50·방어 0·체력 9·잔여 포인트 0·우유 3개·사과 1개**다. 워치에서 시작한 마지막 백업도 이 현재 펫을 저장했다. [단계별 값·통과 번들·최종 대조 JSON](Verification/DebugFlowSimulator-2026-11-08.json).

최종 원본 번들은 `/private/tmp/petpet-verified-debug-flow/`에 있다. 초기 검사에서 40mm 스크롤이 공격력 행을 지나쳐 멈춘 것은 프레임과 방향을 보고 느리게 스크롤하도록 보완했다. 이전 쌍에서는 그 실패 뒤 격리된 체크포인트로 재시도했으며, 최종 결과는 **별도의 새 쌍**에서 다시 수집했다. 설치 순서 검증 실패 후에는 화면의 로그아웃·재로그인으로 인증 상태를 정리하고 기존 펫·먹이로 계속 진행했다. 영구 기록은 위 JSON과 원본 화면에 남긴다.

실기기, 실제 Apple 로그인·운영 서버, 실제 센서 계측·장시간 완전 단절 상태·대용량 시스템 파일 전달의 성능을 검증한 결과는 아니다.

화면: [40mm 체력 배분](Screenshots/DebugFlow/flow-watch-level-up-and-health.png), [두 번째 백업 완료](Screenshots/DebugFlow/flow-repeat-backup-complete.png), [복원 후 현재 먹이 보존](Screenshots/DebugFlow/flow-restored-pet-kept-inventory.png), [로그아웃 뒤 워치 돌보기](Screenshots/DebugFlow/flow-watch-local-play-after-logout.png), [재로그인·재실행 후 상태](Screenshots/DebugFlow/flow-relogin-relaunch-preserved-progress.png), [워치에서 시작한 백업 완료](Screenshots/DebugFlow/flow-watch-initiated-backup.png).

## 발견·수정

- **연속 백업이 진행 작업을 교체:** 진행 중에도 다시 요청하면 두 export가 전송되고 작업 ID가 바뀌었다. 첫 await 전에 시작 상태를 예약하고 진행 중 요청을 합친다. 계정 동기화가 대기 중 복원을 재전송한 경우에도 이를 새 백업으로 교체하지 않는다. 수정 전 실패와 수정 후 회귀 검사로 확인했다. 커밋 `b0169d0`.
- **워치의 연속 탭으로 백업 파일 중복 생성:** `isBusy`를 저장소 조회 뒤에 설정해 동시 요청 4개가 모두 들어갔다. 첫 await 전에 작업 ID와 busy를 예약한다. 수정 전 파일 4개, 수정 후 1개를 확인했고 실패 뒤 busy 해제·재시도도 검사했다. 커밋 `f487ef3`.
- **성장·계정 화면의 접근성 식별자 상속:** 상위 컨테이너의 식별자가 하위 스탯 관리·배분·백업 버튼을 덮어쓰지 않도록 정리하고 레벨·포인트·능력치·로그아웃을 개별 식별한다. 전체 흐름 자동 검사가 실제 값을 확인할 수 있게 한다.
- 새 40mm 시뮬레이터의 피트니스 권한 창은 ‘허용’이 화면 아래에 있어 스크롤해야 했다. 이미 표시된 watchOS 11 시스템 창은 `simctl privacy grant motion`으로 닫히지 않았다. 최종 테스트는 해당 PetPet 권한 창을 확인하고 스크롤해 ‘허용’을 선택한다. 앱 기능의 우회나 권한 프롬프트 누락으로 처리하지 않는다.
- **검사기의 동반 앱 재설치 순서:** Xcode가 동반 앱을 재설치하면서 데이터 컨테이너를 옮겨도 이미 실행 중인 프로세스는 이전 URL에 썼다. 실제 이전 폴더의 서버 기록·완료 저널은 갱신됐지만 등록된 새 폴더는 이전 값이어서 데이터 대조에서 발견했다. 동반 앱을 먼저 실행해 페어링을 준비하고, 검사 대상 앱이 설치·실행된 뒤 동반 앱을 재시작한다. 아이폰이 활성화되기 전에 워치가 켜져 있어야 첫 watch directory도 준비된다. 재개 시 같은 바이너리를 다시 설치하지 않으며 설치 직후 LaunchServices의 일시 오류는 짧게 재시도한다. 이 조정은 테스트 드라이버에만 있다.

## 재실행

원본 데이터를 보존하려면 별도의 새 시뮬레이터 쌍을 준비한다. 아래 타입·런타임이 설치되어 있어야 한다.

```sh
xcrun simctl create 'PetPet Flow iPhone' com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation com.apple.CoreSimulator.SimRuntime.iOS-18-0
xcrun simctl create 'PetPet Flow Watch' com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-40mm-2nd-generation com.apple.CoreSimulator.SimRuntime.watchOS-11-0
xcrun simctl pair WATCH_SIMULATOR_ID PHONE_SIMULATOR_ID
xcrun simctl boot PHONE_SIMULATOR_ID
xcrun simctl boot WATCH_SIMULATOR_ID
python3 Scripts/test_debug_flow.py --phone PHONE_SIMULATOR_ID --watch WATCH_SIMULATOR_ID
```

드라이버는 두 ID가 실제로 시뮬레이터 목록에 있는지 확인한다. 기존 앱을 삭제하거나 기기를 erase하지 않는다. 첫 단계의 워치가 새 상태(Lv.1·우유 3개·소유자/백업/복원 없음)가 아니면 걸음수 준비를 거절한다. 빌드·설치·시험 로그와 xcresult, 단계별 `state-00.json`~`state-08.json`은 기본 `/private/tmp/petpet-debug-flow/`에 저장한다. 단계 시작 직전 워치 전체 상태도 `watch-before-NN.json`에 기록한다.

이미 같은 소스를 빌드했다면 `--skip-build`를 사용할 수 있다. 실패 지점의 상태를 확인한 뒤에만 `--from-stage N`으로 이어서 검사한다. 성공한 2·4·6단계를 되풀이하면 실제 먹이를 다시 소비하므로 임의로 재실행하지 않는다. 서로 다른 사전 조건의 XCTest를 한 기기에서 이름순으로 일괄 실행하지 않는다.

재개 시 `--skip-build`이면 두 앱의 선행 수동 재설치를 생략한다. Xcode는 필요한 검사 대상 설치를 수행하며, 검사기는 동반 앱이 현재 데이터 컨테이너를 사용하도록 설치 후 재시작한다. `/private/tmp/petpet-verified-debug-flow/`는 이번 최종 실행에 지정한 별도 결과 경로다.

워치 검사: `PetPet Watch AppUITests/WatchDebugFlowUITests.swift`. 아이폰 검사: `PetPetUITests/PhoneDebugFlowUITests.swift`. 이전 개별 기능 검사와 운영 연동의 한계는 [아이폰 검토](PhoneAudit-2026-11-08.md), [모의 계정](DebugTesting.md), [동기화](WatchSynchronization.md)를 따른다.

## 커밋

- `b0169d0` — 아이폰의 진행 중 백업 유지·시작 요청 병합
- `f487ef3` — 워치의 첫 await 전 백업 예약·실패 후 재시도 회귀
- `b455d7c` — 복원 재전송 중 새 백업 요청 보호 검사
- `08ed8f0` — 양쪽 앱의 연속 UI 검사·시뮬레이터 전용 드라이버·개별 상태 식별자
