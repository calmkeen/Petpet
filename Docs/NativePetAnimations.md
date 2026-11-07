# 달리기·인사 v3와 네이티브 재생

시뮬레이터보다 실기기의 인사 동작이 덜 부드럽다는 피드백 뒤, 달리기와 인사를 모두 새로 만들고 재생기를 교체했다. 사용자의 후속 요청에 따라 **이번 버전은 시뮬레이터에서만 빌드·설치·검증했다.** 실기기를 깨우거나 설치하지 않았다.

## 동작과 에셋

| 동작 | 프레임 | 재생 |
|---|---|---|
| 달리기 | 생성한 16개 중간 자세 | 15fps 텍스처 순환, 새 걸음 후 기존 2초 유지 정책 |
| 인사 | 생성한 16개 중간 자세 | 약 1.067초 한 번 재생. 첫·끝·기본 자세 동일 |

기존 캐릭터를 참조해 built-in `image_gen.imagegen`으로 두 시트를 생성했다. 고정된 녹색 기술 배경은 패킹 때 제거하고, 눈 위치·눈 사이 거리와 공통 화면 여백을 맞춰 256×336 투명 PNG로 변환했다. 원본·v2 파일은 보존했다.

- [달리기 GIF](../Artwork/Generated/fox-running-v3.gif) · [인사 GIF](../Artwork/Generated/fox-greeting-v3.gif)
- [생성 프롬프트와 참조 이미지](../Artwork/Generated/fox-animations-v3.prompts.json)
- [달리기 생성 소스](../Artwork/Generated/fox-running-v3-source.png) · [인사 생성 소스](../Artwork/Generated/fox-greeting-v3-source.png)
- 양쪽 앱의 `Assets.xcassets/PetAnimationsV3/stepmate_fox_running_v3_00…15` 및 `stepmate_fox_greeting_v3_00…15`에 실제 프레임을 저장한다.

```sh
swift Scripts/preparePetAnimationsV3.swift
swift Scripts/verifyPetAnimationsV3.swift
```

## 워치 재생

`WatchPetRenderer`가 32개 텍스처를 먼저 로드한다. `WatchPetScene`의 고정 크기 스프라이트 한 개가 `SKAction.animate`로 텍스처를 바꾸며, `SpriteView`에 30fps 업데이트를 요청한다. 텍스처 동작은 15fps이므로 목표 주기에서는 한 자세를 두 번의 업데이트 동안 표시한다. 매 프레임 SwiftUI `Image`를 다시 만드는 경로를 제거했다.

`PetPlaybackRequest`는 동작·시작 시각·재생 여부만 비교한다. 걸음수 증가로 종료 시간이 연장돼도 같은 달리기를 처음부터 다시 시작하지 않는다. 다른 화면·백그라운드·저휘도·동작 줄이기에서는 재생을 멈추고 정지 자세를 표시한다. 텍스처 준비 전에도 기본 이미지를 표시한다.

watchOS의 `SpriteView`는 투명도 옵션을 받는 초기화 경로를 지원하지 않는다. 장면 크기가 뷰 크기로 바뀔 때 캐릭터를 다시 맞추고, 부모와 동일한 배경 이미지의 투영을 스프라이트 아래에 그려 검은 여백·잘림을 방지한다. 홈의 배경 좌표계와 실제 캐릭터 영역을 사용하며, 배경 갱신이 동작을 재시작하지 않는다.

아이폰의 `NativePhonePetSprite`는 미리 디코딩한 16개 이미지를 UIKit `UIImageView.animationImages`로 재생한다. SwiftUI는 제스처가 시작·종료되거나 접근성 상태가 바뀔 때만 새 명령을 보낸다. 폰의 인사는 기존처럼 화면 반응이며 워치 호감도를 변경하지 않는다.

## Debug 미리보기

워치의 **계정과 백업 → 백업 관리 → 캐릭터 동작 테스트**에서 달리기와 인사를 자동으로 번갈아 본다. 미리보기는 게임 저장소·실제 걸음수·호감도를 변경하지 않는다. 화면 비활성화·이탈 시 중단한다. 동작 줄이기가 켜져 있으면 이유와 정지 자세를 표시한다.

시뮬레이터에서 다음 인자로 미리보기만 직접 실행할 수도 있다. 이 경로와 메뉴·미리보기 상태 팩토리는 Debug 전용이다.

```sh
xcrun simctl launch --terminate-running-process '<watch simulator ID>' com.calmkeen.PetPet.watchkitapp --pet-animation-preview
```

Debug의 `Development/animation-renderer-debug.json`은 모드·텍스처 준비 여부·장면 업데이트 주기·최대 간격·장면/스프라이트 크기만 기록한다. 계정·걸음수·펫 수치는 포함하지 않고 파일 쓰기는 렌더 루프 밖에서 수행한다. Release에서는 측정·기록 코드를 제외한다. 이전 `animation-debug.json`은 접근성·화면 상태 플래그를 유지한다.

## 검증 기록

- 공용 테스트 **132개** 통과. 16프레임 순환·인사 종료·접근성 정지 자세, 걸음수 연장 중 재생 명령 동일성, 새 제스처의 새 시작, 저장소와 독립적인 미리보기를 검증했다.
- 64개 PNG 사본의 크기·투명 여백·녹색 번짐 제거·양쪽 일치, 인사 시작/끝 일치, 두 GIF의 16프레임 구성을 검사했다.
- Debug·Release 전체 iOS/watchOS **시뮬레이터 빌드**를 확인했다. 처음 실행에서 확인한 캐릭터 잘림을 수정한 뒤, 워치 시뮬레이터에서 두 동작의 전신·배경 표시를 직접 확인했다.
- Series 11 46mm / watchOS 26.5 시뮬레이터에서 두 모드 모두 텍스처 준비 완료, 약 **30회/초의 SpriteKit 업데이트**, 약 **33.33ms 최대 업데이트 간격**을 기록했다. 각 샘플은 약 0.767초다. 이것은 시뮬레이터의 짧은 장면 업데이트 측정이며 실기기 화면 표시 FPS나 장시간 성능 보장은 아니다. [측정 JSON](Verification/NativePetAnimationsSimulator-2026-11-08.json).
- 아이폰 시뮬레이터 앱 설치·실행과 새 재생기의 빌드는 완료했다. 추가 UI 조작은 컴퓨터 조작 도구의 메뉴 요소 ID 오류로 완료하지 못했다. 실기기의 재생 품질은 이번 범위에서 검증하지 않았다.

공식 근거: [watchOS 지원 SpriteView 초기화](https://developer.apple.com/documentation/spritekit/spriteview/init(scene:transition:ispaused:preferredframespersecond:)), [텍스처 사전 로드](https://developer.apple.com/documentation/spritekit/sktexture), [네이티브 텍스처 애니메이션](https://developer.apple.com/documentation/spritekit/skaction/animate(with:timeperframe:)), [UIImageView 애니메이션](https://developer.apple.com/documentation/uikit/uiimageview/startanimating()).
