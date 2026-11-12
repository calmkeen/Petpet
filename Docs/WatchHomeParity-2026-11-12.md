# 원본에 맞춘 워치 홈과 메인 구성

## 원본 확인

사용자가 지적한 차이를 Android 코드와 공유 Figma에서 다시 확인했다. 앞선 점검은 기능·데이터·작은 화면의 조작을 중심으로 했으며, 홈의 화면 구성까지 같다는 검증은 아니었다.

- Android 기준: `Chaeros/StepMate`의 `main` = `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3` (2026-11-12 재확인)
- [Android 홈](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_stepcounter/presentation/TodayStepsScreen.kt): 전체 배경 위에 시간·중앙 펫·걸음수, 좌우 화살표
- [Android 메인 이동](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/presentation/MainScreen.kt): 홈 → 상태 → 게임 → 스트릭 → 음성의 5개 페이지
- [Android 상태](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_statistics/presentation/StatisticsScreen.kt): 펫과 능력치, 먹이·스탯 배분을 같은 상태 화면에 묶음
- [Figma 홈 프레임](https://www.figma.com/design/93gFgiYFvhiyTo4DfyyD6q/chearo-watch-app?node-id=166-3), [상태 프레임](https://www.figma.com/design/93gFgiYFvhiyTo4DfyyD6q/chearo-watch-app?node-id=166-6)

Figma는 편집 가능한 세부 UI 레이어보다 화면 캡처와 설명을 모은 자료다. 해당 프레임의 디자인 컨텍스트와 실제 렌더를 확인하고 Android 코드의 배치와 함께 사용했다. 홈 프레임의 디자인 좌표는 311×311이며, 문서에 보관한 내보내기 이미지는 438×438px다. Figma 캡처를 앱 배경으로 넣지 않고 기존 배경 이미지·펫 렌더러·실제 데이터로 재구성했다.

## 바꾼 구성

| 구분 | 이전 | 변경 후 |
| --- | --- | --- |
| 홈 | 작은 펫·걸음수의 가로 배치, 레벨·기분, 성장·먹이 버튼, 이동 설명 | 전체 배경, 커진 중앙 펫, 펫 아래 걸음수, 양옆 화살표 |
| 펫 터치 영역 | 64×64pt | 40mm에서 74×128pt. 이미지는 넓게 표시하고 화살표와 터치 영역을 분리 |
| 메인 페이지 | 홈·성장·먹이·스트릭·게임·대화·계정의 7개 | 홈·상태·게임·스트릭·음성의 5개 |
| 먹이·스탯 | 별도 먹이 페이지, 성장 개요 후 상세 | 상태 화면 안에서 각각의 편집 목록으로 진입 |
| 상태 | 텍스트 중심 성장 개요 | 원본처럼 왼쪽 펫·레벨·경험치, 오른쪽 능력치 패널 |
| 계정·백업 | 별도 메인 페이지 | 스트릭 상세 안의 계정·백업 진입점 |

홈의 오른쪽 화살표는 상태, 왼쪽 화살표는 마지막 음성 페이지로 이동한다. 기존 크라운 이동도 유지한다. 펫 터치·달리기·인사와 성장·먹이·백업 로직은 기존 구현을 사용한다.

watchOS 기본 시계는 상단 시스템 위치에 유지하고 중앙에 시계를 중복 표시하지 않는다. 페이지 표시는 크라운에 맞춘 watchOS의 세로 표시를 사용한다. Android의 작은 화살표·상하 탭 대신 44pt 터치 영역과 편집용 기본 목록을 사용하며, 게임·달력·시스템 음성 입력의 기존 기능은 유지한다. 화면 형태와 입력 방식의 차이를 문서화하며 픽셀 단위의 완전 동일 화면으로 표현하지 않는다.

## 검증 방법

실제 기기는 사용하지 않았다. 주 화면의 창·마우스를 이동하지 않고 기존 전용 iPhone SE / iOS 18.0 + Apple Watch SE 2세대 40mm / watchOS 11.0 페어에서 XCTest로 확인했다.

- 아이폰: `62CC3FF5-FBE5-44D0-93A6-A10DA462ED7E`
- 워치: `A9079E67-24A1-43C4-A431-48DAAB3E59C8`
- 원본 실행 기록: `/private/tmp/petpet-home-parity-20261112/`

`--watch-ui-day`, `--watch-ui-night`는 Debug에서 배경 시간대만 바꾼다. 시스템 시각, 걸음수, 기분 계산, 저장 파일과 계정은 바꾸지 않는다. 큰 글씨는 기존 `--watch-ui-large-text`를 사용한다.

검사기는 홈 4종(낮·밤 × 기본·큰 글씨), 5개 페이지와 상태 상세 진입, 기본·큰 글씨의 개요와 상세 화면을 확인했다. 홈에 성장·먹이 버튼이 없고 펫이 중앙을 차지하며, 양옆 버튼과 펫 터치 영역이 겹치지 않는지 측정했다. 먹이 주기·스탯 배분·백업·복원·닉네임 변경은 실행하지 않았다.

```sh
xcodebuild -project PetPet.xcodeproj -scheme 'PetPet Watch App' \
  -configuration Debug \
  -destination 'platform=watchOS Simulator,id=A9079E67-24A1-43C4-A431-48DAAB3E59C8,arch=arm64' \
  -derivedDataPath /private/tmp/petpet-watch-ux-272 \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
python3 -B Scripts/test_watch_home_parity.py \
  --phone 62CC3FF5-FBE5-44D0-93A6-A10DA462ED7E \
  --watch A9079E67-24A1-43C4-A431-48DAAB3E59C8 \
  --build /private/tmp/petpet-watch-ux-272 \
  --artifacts /private/tmp/petpet-next-home-parity
```

## 화면 비교

- [Figma 기준 홈](Screenshots/WatchHomeParity/figma-home-reference.png)
- [낮 홈](Screenshots/WatchHomeParity/parity-day-normal-home.png), [밤 홈](Screenshots/WatchHomeParity/parity-night-normal-home.png)
- [큰 글씨 낮 홈](Screenshots/WatchHomeParity/parity-day-large-home.png), [큰 글씨 밤 홈](Screenshots/WatchHomeParity/parity-night-large-home.png)
- [상태 화면](Screenshots/WatchHomeParity/parity-status-page.png), [큰 글씨 상태](Screenshots/WatchHomeParity/ux-large-status.png)
- [큰 글씨 먹이](Screenshots/WatchHomeParity/ux-large-food-detail.png), [큰 글씨 달력](Screenshots/WatchHomeParity/ux-large-calendar.png), [큰 글씨 닉네임](Screenshots/WatchHomeParity/ux-large-nickname.png)

## UI 검증 결과

최종 채택한 native XCTest 실행 9개가 모두 통과했다. 각 xcresult의 실제 성공·실패·건너뜀 수와 기기 ID를 확인했다. 렌더는 324×394px, 좌표 기준 화면은 162×197pt다.

| 검사 | 성공 실행 수 | 확인한 내용 |
| --- | ---: | --- |
| 낮·밤 홈 × 기본·큰 글씨 | 4 | 중앙 펫, 성장·먹이 바로가기 제거, 걸음수, 화살표, 왼쪽 이동 |
| 5개 페이지와 상태 상세 | 1 | 먹이·스탯, 게임 목록, 스트릭, 계정·백업, 음성 진입과 복귀 |
| 개요 × 기본·큰 글씨 | 2 | 크라운으로 5개 페이지 이동, 걸음수 오류 안내, 버튼 크기·화면 경계 |
| 상세 × 기본·큰 글씨 | 2 | 스탯·먹이·보상·월 선택·이전/다음·닉네임 버튼 크기·화면 경계 |

40mm 홈의 화살표는 각각 44×44pt, 펫 터치 영역은 74×128pt이며 서로 겹치지 않았다. 상태의 먹이·스탯 버튼은 각각 64×44pt다. 나머지 측정한 액션도 최소 44pt를 충족했다.

중간 검사에서는 고정 크라운 회전량이 상태 페이지를 건너뛰거나 너무 작아 이동하지 않는 경우가 있었다. 현재 페이지를 확인하고 필요하면 반대 방향으로 회전하도록 검사기를 수정했다. 상세 목록 끝에서 watchOS의 가장자리 축소 효과가 44pt 버튼을 43.915pt로 표시한 검사도 실패했다. 목록 안쪽으로 스크롤한 뒤 측정하도록 수정했으며, 44pt 최소 기준을 완화하지 않았다. 최종 결과와 이 중간 실패는 [검증 JSON](Verification/WatchHomeParitySimulator-2026-11-12.json)에 구분해 기록한다.

이번 변경·검증 범위는 워치 홈, 상태 화면과 메인 페이지 묶음이다. 게임·대화·스트릭 상세와 아이폰 전체의 디자인을 Figma와 픽셀 단위로 일치시킨 검증은 아니다. 로그인부터 백업까지의 전체 기능 실행 결과는 기존 [11월 11일 Debug 전체 흐름](FullDebugFlow-2026-11-11.md)에 별도로 남아 있다.

## 빌드와 데이터 보존

Xcode 27.2 (27B52)에서 Debug `build-for-testing`과 아이폰·워치 Release 시뮬레이터 빌드가 모두 성공했다. 빌드는 `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`로 실행했다. 낮·밤 강제 표시 인수는 Debug 실행 파일에만 있으며 Release 워치 실행 파일에는 포함되지 않음을 확인했다.

검사 전후 파일을 읽어 펫의 레벨 2·경험치 1·공격 50·방어 0·체력 9·스탯 포인트 0, 우유 3개·사과 1개, 터치 수와 보상 수령 내역, 계정과 기존 걸음 기록의 보존을 확인했다. 백업 3건·복원 1건의 ID 집합이 같고 대기 작업은 0건이다. 백업 ID는 Set 저장이므로 배열에 기록된 순서보다 ID 집합을 비교했다. 마지막 활동 시각은 앱 실행에 따라 갱신된다.

기분은 `HAPPY → HUNGRY`로 바뀌었다. 마지막 먹이 시각은 2026-11-11 13:55:34 KST로 같고, 최종 검사 때 실제 24.26시간이 지나 기존 24시간 공복 규칙이 적용됐다. 테스트로 먹이·기분·시스템 시간을 재설정하지 않았다. 아이폰에 저장된 워치 스냅샷의 펫·먹이·걸음 기록도 최종 워치 저장값과 일치했다.

구현은 `c406e83`, 검사 경로는 `4642828`, 목록 측정 보완은 `b3bac0e`에 커밋했다. 실제 xcresult 경로, 9개 실행의 기기 정보와 측정값, 33개 native 화면 캡처와 Figma 기준 이미지 정보는 [검증 JSON](Verification/WatchHomeParitySimulator-2026-11-12.json)에 남겼다.
