# 별계단 정답 동작·시간 초과 진동

develop `33b9945`에서 `feature/star-stair-feedback`을 새로 만들어 꾸미기와 분리해 개발했다. 이후 2026-11-14 두 feature를 develop에 함께 통합했다. [통합 기록](Integration-2026-11-14.md). Android 비교 기준은 `Chaeros/StepMate`의 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`다.

## 변경한 동작

Android `HeavenStairsGameScreen`의 정답 반응과 실패 피드백을 따른다.

| 상황 | 이번 동작 |
|---|---|
| 왼쪽 정답 | left_running1 80ms → left_running2 100ms → 기본 자세 |
| 오른쪽 정답 | right_running1 80ms → right_running2 100ms → 기본 자세 |
| 빠른 다음 정답 | 앞선 반응을 취소하고 새 방향으로 시작. 늦은 이전 작업은 현재 자세를 바꾸지 않음 |
| 오답 | 목숨 감소에 대응하는 실패 햅틱 1회, 기본 자세 |
| 타이머 시간 초과 | 타이머에서 발생해도 실패 햅틱 1회. 마지막 목숨까지 포함 |
| 입력 직전 만료 확인 | 만료 이벤트만 처리하고 그 탭을 추가 정답/오답으로 처리하지 않음 |
| 수동 종료 | 새 실패 이벤트·진동을 만들지 않음 |
| 일시정지·비활성화·저휘도·화면 이탈·재시작 | 진행 중 반응 취소·기본 자세 복귀 |
| 동작 줄이기 | 정답 프레임 재생 억제. 실패 이벤트는 유지 |

watchOS 햅틱은 `.failure`를 사용한다. 원본과 발생 조건을 맞춘 것이며 진동 장치의 파형을 복제하지 않는다. 점수·콤보·목숨·제한 시간·계단 생성·서버 기록 계약은 변경하지 않았다.

## 구현 경계

- 공용 `StarStairGame.input` / `advance`는 실제로 처리한 동작에 대해 선택적 `StarStairFeedback`을 반환한다. 정답 방향·오답·시간 초과를 표시 문자열과 분리한다. 종료 후 입력/타이머에는 이벤트가 없다.
- View는 타이머와 입력 직전 검사 모두에서 그 이벤트를 동일하게 전달한다. `StarStairReactionModel`이 방향별 이미지·취소 토큰·실패 햅틱을 담당한다. 최종 시간 초과의 이벤트는 결과 화면으로 이동하기 전에 처리한다.
- 반응은 저장되지 않는 화면 상태다. 서버에 애니메이션 이벤트를 보내거나 성장 펫의 능력치를 변경하지 않는다.

## 원본 리소스

원본 4개는 `Artwork/AndroidStarStairFeedbackSources.json`의 고정 커밋·Git blob 해시로 검증했다. 워치 리소스는 기존 게임 아트와 같은 방식으로 긴 변을 512px 이하로 줄이고 원본 종횡비를 유지한다.

```sh
python3 Scripts/importAndroidGameArtwork.py \
  /path/to/pinned/android/pngs Artwork/AndroidStarStairFeedbackSources.json
```

원본 PNG 파일 이름은 `snowfox_baby_left_running1/2.png`, `snowfox_baby_right_running1/2.png`다. 앱 Asset 이름에는 `stepmate_game_` 접두사를 붙인다. 기존 33개 게임 리소스의 기본 import 방식도 유지한다.

## 빌드와 이후 검토

사용자 요청에 따라 **빌드까지만** 확인한다. Core 테스트 타깃에는 정답 방향·연속 오답·마지막 목숨의 시간 초과·수동 종료·유효하지 않은 시간 증가에 대한 회귀 5건을 추가해 컴파일한다. 테스트를 실행한 결과로 계산하지 않는다.

아이폰과 내장 워치 앱은 Xcode 27.2 / arm64 generic iOS Simulator에서 Debug/Release로 빌드한다. 시뮬레이터 부팅·앱 설치/실행·실제 기기 조작은 하지 않는다. 빌드 로그는 `/private/tmp/petpet-stair-feedback-core-build.log`, `/private/tmp/petpet-stair-feedback-build/`에 둔다.

별도 시뮬레이터 검토 시 양쪽 방향·빠른 연속 입력·만료 직전 입력·3번째 시간 초과·수동 종료·재시작·접근성·화면 이탈을 확인한다. 실제 진동 감각은 빌드나 코드 검토로 확인한 것으로 표시하지 않는다.

공유할 구조와 선행 개발 방법은 [Android·iOS 공유 안내](Collaboration/README.md)와 [기능 인계](Collaboration/FeatureHandoff.md)에 정리했다.

최종 결과: 공용 모듈·테스트 타깃 컴파일과 아이폰/내장 워치의 Debug·Release 빌드 모두 성공했다. 새 회귀 5건의 실행 수는 **0**이다. 시뮬레이터 부팅·앱 설치/실행·실제 진동 확인은 수행하지 않았다. 구현 커밋은 `0f4a7e1`이며 [검증 기록](Verification/StarStairFeedback-2026-11-14.json)에 코드·원본 리소스·빌드 범위를 남겼다.
