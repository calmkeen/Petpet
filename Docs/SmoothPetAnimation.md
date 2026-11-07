# 인사 애니메이션 v2

실기기에서 첫 버전이 ‘이미지가 바뀌는 느낌’이라는 피드백을 받아 수정했다. 이전 두 그림은 자세·비율 차이가 컸고, 300ms 간격의 1→2→1 전환만으로는 연속 동작을 만들기 어려웠다.

## 현재 재생

- **12프레임, 프레임당 100ms, 총 1.2초**로 손을 올리고 흔든 뒤 내린다. 이는 재생 요청 간격이며 실기기 표시 주기를 측정한 값은 아니다.
- 256×336 투명 PNG를 눈 위치와 공통 배율로 정렬한다. 앞발 영역의 변화 때문에 몸 전체가 이동하지 않게 바운딩 박스 대신 눈을 기준으로 맞춘다.
- 기본 자세와 인사의 첫 프레임은 같다. 마지막 프레임도 첫 프레임을 사용해 정지 상태로 돌아갈 때 자세·색이 바뀌지 않게 했다.
- 워치와 아이폰은 같은 프레임·시간 규칙을 사용한다. 인사 중 중복 탭 제한도 1.2초에 맞췄다. 수락한 워치 터치의 호감도 규칙·저장 경로는 유지한다.
- ‘동작 줄이기’에서는 인사 중간 자세를 정지 표시한다. AOD 저휘도·비활성화·다른 섹션의 재생 중단 정책을 유지한다.

## 생성·재현

Android 원본 흰여우·손 인사 그림을 참조해 built-in `image_gen.imagegen`으로 중간 자세를 생성했다. 이 프레임은 원본 사본과 구분한 생성 에셋이며, 원본 파일과 기존 출처 명세도 보존했다.

- [사용한 프롬프트·생성 방식](../Artwork/Generated/fox-greeting-v2.prompts.md)
- [선택한 생성 소스](../Artwork/Generated/fox-greeting-v2-source.png)
- [GIF 미리보기](../Artwork/Generated/fox-greeting-v2.gif)
- 워치·아이폰 에셋: 각 타깃 `Assets.xcassets/GreetingV2/stepmate_fox_greeting_v2_00…11.imageset`

`Scripts/prepareGreetingAnimation.swift`는 시트의 알파 잔여물을 제거하고 4×3 셀을 분리·정렬한다. 소스는 수정하지 않으며, 투명 PNG와 GIF 미리보기를 출력한다. 미리보기의 어두운 바탕과 루프 사이 정지 시간은 검토용이고 앱 PNG는 투명하다.

```sh
swift Scripts/prepareGreetingAnimation.swift
swift Scripts/verifyGreetingAnimation.swift
```

## 검증

- 공용 테스트 **130개** 통과. 12개 프레임 순서·100ms 전환·마지막 프레임 유지·1.2초 종료·접근성 정지 자세를 포함한다.
- 패킹 검사로 양쪽의 24개 PNG가 동일하고 크기·투명 여백·캐릭터 영역을 유지하는지 확인했다. 첫·마지막 PNG의 바이트 일치와 GIF의 12프레임도 검사했다.
- iPhone·watchOS Debug 시뮬레이터, 무료 Personal Team 실기기 Debug 서명, Release 시뮬레이터 빌드 통과. 워치 시뮬레이터에서 새 기본 프레임이 배경 위에 정상 크기로 표시되는 것을 확인했다.
- 2026-11-08 00:35 iPhone 13 mini·Series 10 업데이트 설치 완료. 워치 자동 실행은 무선 연결의 20초 시간 초과로 완료되지 않았다. 실기기의 새 동작이 얼마나 부드러운지는 사용자 확인을 요청했다.

Debug는 `Development/animation-debug.json`에 동작 줄이기·저휘도·활성 scene·홈 선택의 4개 불리언만 기록한다. 매 프레임 저장하지 않고 걸음수·계정·펫 수치는 포함하지 않는다. Release에서는 기록하지 않는다. 사용자의 접근성 설정은 자동으로 바꾸지 않는다.

이번 실기기 조회에서는 해당 파일을 읽지 못했으므로 현재 ‘동작 줄이기’ 설정이 켜져 있는지는 확인하지 못했다. 파일이 없다는 이유로 설정을 추정하지 않는다.

패킹에는 Apple CoreGraphics·ImageIO를 사용한다. 참고: [CGImage 영역 추출](https://developer.apple.com/documentation/coregraphics/cgimage/cropping(to:)), [watchOS 타임라인](https://developer.apple.com/documentation/watchos-apps/updating-watchos-apps-with-timelines).
