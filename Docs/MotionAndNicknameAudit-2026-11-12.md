# 홈 동작·닉네임과 Android 기능 재점검

## 이번에 고친 부분

홈 캐릭터와 터치 버튼의 수명을 분리했다. 캐릭터를 비활성화되는 버튼의 label에 넣는 대신, 캐릭터는 독립적으로 렌더링하고 같은 위치의 투명한 버튼이 입력만 받는다. 저장 성공·인사 완료까지의 중복 입력 방지와 50회마다 애정도 +1 규칙은 유지한다.

16개 원본 프레임이 모두 다른 동작인지 파일과 화면을 확인했다. 인사는 시작·끝 이미지가 같아 15개 고유 PNG, 달리기는 16개 고유 PNG다. 실제 홈과 미리보기의 재생을 따로 측정했다. 보완 과정의 홈은 **2개 원본 프레임·3회 갱신**에 그쳤지만, 렌더링을 분리한 최종 홈은 **16개 원본 프레임·34회 갱신·30회 중간 보간**을 기록했다. 미리보기도 달리기·인사 각각 16개를 사용했다. 이것은 짧은 시뮬레이터 장면 측정이며 실기기의 표시 FPS 보장은 아니다.

원본을 약 15Hz로 교체하는 대신, SpriteKit의 30Hz 갱신마다 인접 프레임의 premultiplied 색상·알파를 보간한다. 두 스프라이트를 반투명하게 겹치지 않아 몸통의 불투명도를 유지한다. 텍스처·셰이더는 재사용하고 화면 이탈·저휘도·동작 줄이기에서는 기존처럼 정지한다. [Apple SKShader](https://developer.apple.com/documentation/spritekit/skshader), [SKUniform](https://developer.apple.com/documentation/spritekit/skuniform)과 설치된 WatchSimulator SDK의 지원 API를 확인했다.

사용자 요청대로 홈 안내·VoiceOver 값·스탯 상세의 **중간 쓰다듬기 횟수 표시를 제거**했다. 내부 횟수 저장과 애정도 지급은 유지한다. 애정도 +1 성공과 저장 오류 안내만 잠시 표시한다. 이전 화면 검사 전용 `--watch-ui-hold-touch-feedback`도 제거했다.

닉네임 API·중복 검사·변경·영구 저장은 이미 있었지만, 스트릭 상세 아래나 계정 화면까지 들어가야 했다. 이제 크라운으로 **스트릭 → 닉네임 변경**에 바로 진입한다. 현재 이름도 버튼에 표시한다. 로그인하지 않았으면 같은 위치에서 **로그인 · 계정**으로 안내한다. 40mm 기본·큰 글씨에서 월별 기록과 닉네임 버튼 모두 134×44pt이고 화면 안에 들어왔다. Android 스트릭에 있는 앱 버전 정보도 상세 아래에 추가했다.

## Android와 대조한 범위

GitHub의 Android `main`을 다시 읽었으며 기준은 여전히 `4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3`다.

| 원본 기능 | Apple 측 경로·결과 |
| --- | --- |
| 홈·시간대 배경·달리기·인사 | 홈의 배경·중앙 펫·걸음수 유지. 실제 홈 재생과 미리보기를 분리 측정하고 보완 |
| 50회 터치 애정도·성장·먹이·스탯 | 기존 규칙과 저장 유지. 중간 횟수의 화면 노출만 사용자 요청으로 제거 |
| 월별 기록·날짜·연속 일수 | 스트릭 → 월별 걸음 기록. 기존 날짜 선택·복귀 구현과 회귀 테스트 유지 |
| 닉네임 | 스트릭에서 바로 진입. 실제 시스템 입력·중복 확인·제출·재실행을 모의 계정으로 검증 |
| 백업·보상·최근 백업 시간 | 스트릭 상세/계정·백업/먹이 화면에 기존 경로 존재. 변경하지 않음 |
| 두 게임·최고 기록·랭킹 | 게임 → 게임 선택/랭킹에 기존 구현 존재. 이번에는 소스·공용 회귀로 재대조 |
| 음성 입력·AI 대화·취소 | 음성 → AI 대화 열기에 기존 구현 존재. 이번에는 소스·공용 회귀로 재대조 |
| 폰 로그인·로그아웃·설치 안내·기록·펫 표시 | 기존 계정·워치 연결·홈 경로 존재. 워치 닉네임 변경의 폰 모의 저장 결과를 대조 |
| 버전 확인 | Android 스트릭의 버전 표시를 Apple 스트릭 상세에도 추가 |

Android의 [메인 이동](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/presentation/MainScreen.kt), [스트릭 화면](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_stepstreak/presentation/StepStreakScreen.kt), [스트릭·닉네임 ViewModel](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/app/src/main/java/com/chaeros/stepmate/feature_stepstreak/presentation/StepStreakViewModel.kt), [폰 홈](https://github.com/Chaeros/StepMate/blob/4e2b5e54902efd9630dc5fe7595ca0fb2656d0e3/mobile/src/main/java/com/chaeros/stepmate/mobile/feature_home/presentation/MobileHomeScreen.kt)을 확인했다. Android의 설정 화면과 폰 하단의 자리 표시자는 실제 동작 기능으로 세지 않았다.

새로 발견한 주요 로컬 게임 기능의 누락은 없었다. 닉네임은 미구현이 아니라 접근성이 낮은 경로를 개선한 것이다. 기능 이름이 존재하는 것과 모든 운영 연동이 끝난 것은 구분한다. **운영 Apple 로그인·서버 연동 성공은 아직 검증하지 않았고**, 공개 Swagger에 없는 Apple 인증 경로는 기존 [서버 계약](AppleSignInServer.md)의 작업 범위다. 현재 서버 작업은 iPhone을 중계하므로 Android처럼 워치가 서버에 직접 요청하는 단독 네트워크 동작까지 동일하지 않다. 이는 현재 앱 구조의 차이이며 watchOS에서 불가능하다는 뜻은 아니다.

## 실제 검증

Xcode 27.2 (27B52), 기존 전용 40mm Apple Watch SE 2세대/watchOS 11.0과 iPhone SE 3세대/iOS 18.0 시뮬레이터 페어를 사용했다. 실제 기기와 Mac의 창·마우스는 조작하지 않았다.

- 공용 패키지 전체 **183개**, 워치 저장·대기·계정 모델 **10개** 통과.
- 최종 채택한 native UI 실행 **5개**: 카운트 없는 실제 홈 터치, 달리기·인사 미리보기, 일반/큰 글씨 닉네임 바로가기, 실제 워치 닉네임 입력·변경·재실행.
- Debug 테스트 빌드와 아이폰·워치 Release 시뮬레이터 빌드 통과.
- 워치의 변경된 이름과 폰 모의 백엔드의 저장 이름이 같고, 워치 재실행 후에도 유지됐다. 운영 서버로 닉네임을 변경하지 않았다.
- 펫 수치·먹이·걸음수·보상·백업/복원 ID 집합을 보존했다. 이번 실제 UI 터치 3회는 내부 카운트에 정상 저장되며 화면에는 노출하지 않는다.

전체 기능을 이번에 모두 UI로 다시 실행한 것은 아니다. 게임·백업·대화의 이전 실행 결과는 [11월 11일 전체 흐름](FullDebugFlow-2026-11-11.md), 상세 기능 비교는 [Android 대응표](AndroidParity.md)를 함께 따른다. 원본 로그는 `/private/tmp/petpet-motion-profile-20261112/`, 기기 정보·실제 프레임 이름·보간 횟수·데이터 대조와 xcresult 경로는 [검증 JSON](Verification/MotionAndNicknameSimulator-2026-11-12.json)에 기록했다.

[카운트 없는 홈](Screenshots/MotionNickname/motion-home-without-count.png) · [닉네임 바로가기](Screenshots/MotionNickname/profile-shortcut.png) · [큰 글씨](Screenshots/MotionNickname/profile-shortcut-large.png)

구현·회귀 검사 커밋: `ed8e049`.
