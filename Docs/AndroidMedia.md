# Android 이미지·펫 프레임 재사용

원본은 `Chaeros/StepMate`의 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`에 있는 `app/src/main/res/drawable`이다. 이 커밋에는 펫 GIF가 없으며 연속 PNG를 표시하는 방식이다. iOS·watchOS도 같은 프레임을 로컬 에셋으로 재생한다.

**현재 동작:** 달리기·인사를 각각 16프레임으로 만들고 워치 SpriteKit·아이폰 UIKit 재생기로 옮겼다. 원본을 참조한 별도 생성 에셋을 사용한다. [현재 구현·GIF 미리보기·검증](NativePetAnimations.md). 아래는 최초 원본 이식 당시의 규칙과 기록이다.

## 적용한 이미지

| 원본 | 사용 위치 |
|---|---|
| `snowfox_baby_sitting.png` | 워치 홈·아이폰 펫 장면의 기본 자세 |
| `snowfox_baby_run1`–`run4.png` | 워치 걸음수 증가에 따른 달리기 |
| `snowfox_baby_happy1`·`happy2.png` | 워치 쓰다듬기·아이폰 인사 반응 |
| `north_pole_background_dawn/default/sunset/night.png` | 양쪽 앱의 시간대별 펫 배경 |
| `milk_normal1`·`apple_normal1.png` | 워치의 기존 먹이 이미지와 아이폰 먹이 카드 |

워치에 11개, 아이폰에 9개의 원본 사본을 `Assets.xcassets/StepMate`로 추가했다. 이름은 `stepmate_`로 시작하므로 기존 에셋과 충돌하지 않는다. 모든 사본은 원본 PNG 바이트를 유지한다. 원본 경로·커밋·Git blob·SHA256·크기는 [에셋 명세](AndroidMediaManifest.json)에 기록했다. 워치에 이미 있던 우유·사과 이미지도 같은 원본과 일치한다.

고기 그림은 해당 Android drawable에 없으므로 기존 시스템 아이콘을 사용한다. 게임에는 이후 원본 이미지·애니메이션 프레임 33개를 추가했다. 해시·패킹·사용 경로는 [게임과 대화](GamesAndChat.md)를 따른다. 기존 에셋도 삭제하지 않았다.

## 워치 동작

- 현재 날짜의 걸음수가 새로 증가하면 1→2→3→4 프레임을 200ms 간격으로 반복한다. 새 증가가 없으면 2초 후 기본 자세로 돌아간다. 추가 가속도계 구독 없이 기존 걸음수 상태를 사용한다.
- 앱 시작·저장 복구·백그라운드 복귀·날짜 변경의 초기 합계는 기준값으로만 사용한다. 옛 기록을 새 걸음으로 간주해 달리지 않는다.
- 가만히 있을 때 펫을 누르면 행복 1→2→1 프레임을 각각 300ms 표시한다. 달리기·행복 반응 중의 연속 탭은 받지 않는 Android 동작을 따른다. 수락한 탭은 기존 워치 `.touch` 저장 경로로 전달한다.
- 홈을 벗어나거나 scene이 비활성화되거나 Always On의 저휘도 상태가 되면 재생 상태와 완료 작업을 중단한다. 돌아올 때 현재 걸음수를 다시 기준값으로 잡는다. 센서 집계 자체는 기존 루트가 계속 관리한다.
- ‘동작 줄이기’에서는 프레임 재생을 멈추고 정지 프레임을 표시한다. 터치에 따른 기존 펫 규칙은 유지한다.
- 배경은 Android와 같이 07시 새벽, 08–16시 낮, 17시 노을, 18–06시 밤이다. 현재 기기의 시간대와 분 단위 타임라인으로 갱신한다. 밤에는 흰 글자, 나머지는 검은 글자를 사용한다.

`PetAnimationState`는 화면용 임시 상태이며 걸음수·먹이·보상 파일에 쓰지 않는다. `PetSpriteAnimation`은 원본 프레임 순서를 결정한다. `CharacterActivityViewModel`은 상태 발행과 취소 가능한 짧은 완료 작업만 담당한다. `WatchPetSpriteView`의 SwiftUI `TimelineView`는 필요할 때만 프레임을 갱신한다. GIF 디코더·웹 뷰·외부 이미지 다운로드 라이브러리를 추가하지 않았다.

## 아이폰 동작

펫 카드는 같은 원본 펫·시간대 배경을 표시하며 **펫에게 인사하기**를 누르면 행복 프레임을 잠깐 재생한다. 이 인사는 화면 반응만 제공하며 워치의 호감도·보상·걸음수를 변경하지 않는다. 우유·사과는 실제 Android 먹이 그림을 표시한다. 로그인이나 운영 API 없이도 이미지와 반응을 사용할 수 있다.

## 검증

- 공용 테스트 **129개** 통과. 이번 6개는 시간대 경계, 현지 시간대, 프레임 순서·간격·반복, 시계 역행, 저장 복구와 새 걸음 구분, 2초 만료·연장, 중복 터치 제한, 화면 복귀 시 기준값을 검증한다.
- 20개 새 사본의 SHA256·Git blob을 Android 고정 커밋과 비교해 모두 일치함을 확인했다. 두 타깃에서 이미지 이름 중복이 없고, Debug·Release 시뮬레이터와 무료 Personal Team 실기기 Debug 서명 빌드가 통과했다.
- 2026-11-08 시뮬레이터에서 워치 홈의 원본 펫·밤 배경·흰 글자와 아이폰의 펫 장면·우유·사과 이미지가 표시되는 것을 확인했다. 아이폰 인사 버튼은 접근성 트리에 노출되고 조작했다. 짧은 반응 전체를 화면 녹화로 검증한 것은 아니며, 프레임 순서와 시간 규칙은 공용 테스트로 검증했다.
- 워치 자동 터치에는 기존 컴퓨터 조작 도구의 창 좌표 문제가 있어 실기기에서의 걷기·쓰다듬기 재생은 별도 확인 항목이다. 실제 워치에 테스트 걸음수를 주입하지 않았다.
- 2026-11-08 00:18 iPhone 13 mini·Series 10 모두 새 이미지와 반응을 포함한 Debug 앱 설치를 완료했다. 기존 앱을 삭제하지 않았다.

근거: [Android 펫 프레임 재생](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_stepcounter/presentation/component/MateMovingImage.kt), [Android 시간대 규칙](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/common/util/TimeUtils.kt), [Apple의 타임라인과 일시정지](https://developer.apple.com/documentation/watchos-apps/updating-watchos-apps-with-timelines).
