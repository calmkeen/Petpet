# PetPet — iOS·watchOS

워치의 걸음수로 펫을 키우는 StepMate의 Apple 클라이언트다. Android의 기능·게임 규칙·서버 계약을 기준으로 구현하며, 플랫폼별 UI와 센서·통신 어댑터는 분리한다.

원작 프로젝트는 [@Chaeros](https://github.com/Chaeros)가 만들었다. 직접 반려동물을 기르기 어려워도 동물을 좋아하는 사람들이 워치에서 펫을 키울 수 있도록 하는 것이 프로젝트의 목적이다.

**Android 개발자에게 공유할 때는 [개발 공유 안내](Docs/Collaboration/README.md)부터 읽는다.** 현재 반영 상태, 구조 대응표, 데이터 소유권과 서버 작업을 한곳에서 확인할 수 있다.

| 문서 | 내용 |
|---|---|
| [개발 공유 안내](Docs/Collaboration/README.md) | 현재 상태·플랫폼별 구조·데이터 흐름·남은 과제 |
| [선행 개발과 기능 인계](Docs/Collaboration/FeatureHandoff.md) | iOS에서 먼저 구현한 기능을 Android에 전달하는 절차, 꾸미기 예시 |
| [기능 공유 양식](Docs/Collaboration/FeatureTemplate.md) | 새 기능마다 복사해 쓰는 동작·계약·검증 기록 |
| [Apple 구조](Docs/Architecture.md) | 실제 디렉터리와 의존성 조립 |
| [Android 기능 대응](Docs/AndroidParity.md) | 기존 Android 기능과 Apple 측 구현 위치 |
| [API 대응](Docs/APIParity-2026-11-13.md) | Swagger 경로의 사용·미사용과 화면 출력 |
| [Apple 로그인 서버 요청](Docs/AppleSignInServer.md) | 서버에 추가할 인증 계약과 기존 Android 호환 범위 |

## 기능별 상세 문서

- [하루 걸음수·저장·복구](Docs/DailySteps.md), [먹이·성장·보상](Docs/FeedingAndGrowth.md), [스트릭·닉네임](Docs/StreakAndNickname.md)
- [폰·워치 동기화](Docs/WatchSynchronization.md), [계정·백업·복원](Docs/AccountAndBackup.md), [워치 단독 연결](Docs/WatchStandalone-2026-11-12.md)
- [게임·랭킹·AI](Docs/GamesAndChat.md), [별계단 반응 보완](Docs/StarStairFeedback-2026-11-14.md)
- [Android 원본 이미지](Docs/AndroidMedia.md), [부드러운 인사·GIF](Docs/SmoothPetAnimation.md), [네이티브 달리기·인사](Docs/NativePetAnimations.md)
- [워치 대응 검토](Docs/WatchAudit-2026-11-08.md), [아이폰 검토](Docs/PhoneAudit-2026-11-08.md), [전체 흐름 검증 기록](Docs/FullFlow-2026-11-13.md)

## 실행 환경과 빌드

최소 대상은 iOS 18 / watchOS 11이다. 최근 빌드 확인 환경은 Xcode 27.2다. `PetPet.xcodeproj`를 열며, 공용 로직은 로컬 패키지 `Packages/PetPetCore`를 참조한다.

```sh
xcodebuild -project PetPet.xcodeproj -scheme PetPet \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

`PetPet` scheme은 포함된 워치 앱도 함께 빌드한다. Release 확인은 configuration을 Release로 바꾼다. 기본 개발 작업은 빌드 확인까지만 수행한다. 시뮬레이터 부팅·앱 실행·XCTest 실행은 별도로 요청받은 검토에서 수행한다. 이전 문서의 실행 명령은 과거 검증의 재현 절차다.

Debug는 무료 개발용 모의 계정·기기 내부 모의 백엔드를 사용한다. 운영 로그인·서버 연동 성공을 뜻하지 않는다. [Debug 안내](Docs/DebugTesting.md).

## 브랜치

`main`은 릴리스, `develop`은 통합, `feature/*`는 최신 develop에서 분기한 독립 작업이다. 기능 PR은 develop을 대상으로 한다. [저장소 지침](AGENTS.md)을 따른다.

현재 작업의 기준과 독립 브랜치 상태는 [개발 공유 안내](Docs/Collaboration/README.md#현재-공유-기준)에 기록한다. 한 feature에 다른 미통합 기능을 함께 넣지 않는다.
