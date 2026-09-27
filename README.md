# Caffeine

SwiftUI와 IOKit으로 만든 macOS 메뉴바 절전 방지 앱입니다. 외부 라이브러리나 `caffeinate` 하위 프로세스 없이 macOS 전원 관리 API를 직접 사용합니다.

## 기능

- 화면 켜짐 유지 또는 시스템 유휴 절전 방지
- 15분, 30분, 1시간, 2시간, 무제한 프리셋
- 메뉴바에 남은 시간 또는 감시 중인 PID 표시
- 지정한 PID가 종료되면 절전 방지 해제
- AC 전원 연결 중에만 동작하는 옵션
- 배터리 사용 중 잔량이 20% 이하가 되면 자동 해제
- 로그인 시 자동 실행 설정 (`SMAppService`)

메뉴에서 `Cmd + T`로 절전 방지를 켜거나 끄고, `Cmd + Q`로 앱을 종료할 수 있습니다. 시간 프리셋을 선택하면 기존 PID 감시는 해제됩니다. 모드 변경에 실패하면 절전 방지를 해제하고 오류를 표시합니다.

## 요구 사항

- Apple Silicon Mac — 제공되는 빌드 스크립트는 `arm64`를 대상으로 합니다.
- macOS 13 이상
- Swift 5.9 이상과 macOS SDK를 제공하는 Xcode 또는 Command Line Tools

## 빌드 및 실행

```bash
git clone https://github.com/Felix0708/Caffeinate.git
cd Caffeinate
./scripts/build_app.sh
open Caffeine.app
```

빌드 스크립트는 로컬 앱 번들을 생성하고 ad-hoc 서명을 적용합니다. Developer ID 서명이나 Apple 공증을 수행하지 않습니다. 빌드된 앱은 저장소에 포함하지 않습니다.

응용 프로그램 폴더에 설치하려면 다음을 실행합니다.

```bash
./scripts/install.sh
```

설치 스크립트는 다시 빌드한 뒤 실행 중인 `Caffeine`을 종료하고 `/Applications/Caffeine.app`을 교체합니다. 해당 폴더에 쓰기 권한이 없으면 `~/Applications`에 설치합니다. 설치 후 직접 앱을 실행하세요.

## 검사

```bash
bash scripts/check_app_state.sh
```

실제 `AppState`와 테스트용 전원 관리 객체를 함께 컴파일하여 다음을 검사합니다.

- PID 감시에서 타이머로 전환할 때 감시 상태 정리
- 모드 변경 및 활성화 실패 후 비활성 상태와 오류 메시지 유지
- AC 전원과 배터리 조건에 따른 활성화 거부
- 잘못된 PID와 켜기/끄기 동작

회귀 검사와 로컬 앱 빌드·서명 검증은 완료했습니다. 실제 화면 절전, 배터리 전환, 로그인 자동 실행의 UI 및 하드웨어 동작은 별도 확인이 필요합니다. 메모리 사용량이나 다른 앱과의 성능 비교는 측정하지 않았습니다.

## 구현과 범위

| 파일 | 역할 |
| --- | --- |
| `Sources/Caffeine/CaffeineApp.swift` | 메뉴바 UI와 PID 입력 |
| `Sources/Caffeine/AppState.swift` | 활성 상태, 타이머, 감시 및 보호 조건 |
| `Sources/Caffeine/PowerManager.swift` | IOKit assertion, 전원 정보, PID 생존 확인 |
| `Tests/AppStateCheck.swift` | 상태 전환 회귀 검사 |
| `scripts/` | 빌드, 설치, 검사, 아이콘 생성 |

화면 모드는 `PreventUserIdleDisplaySleep`, 시스템 모드는 `PreventUserIdleSystemSleep` assertion을 사용합니다. 배터리 정보는 `IOPowerSources`에서 읽고, 프로세스 생존 여부는 `kill(pid, 0)`으로 확인합니다.

- 활성 상태에서 타이머·PID·전원 조건을 1초 주기로 확인합니다. 타이머는 tick마다 감소하므로 시스템 잠자기나 이벤트 처리 지연 후 정확한 종료 시각을 보장하지 않습니다.
- AC 전원 옵션은 앱의 실행 조건이며, `caffeinate -s`와 동일한 assertion을 사용하지 않습니다.
- `caffeinate`의 디스크 절전 방지(`-m`), 사용자 활성 선언(`-u`), 명령 실행 및 CLI 동기화 기능은 구현하지 않았습니다.
- 덮개 닫힘이나 사용자가 직접 요청한 잠자기를 막는 기능은 제공하지 않습니다.
- 모드·시간·보호 옵션은 앱을 다시 실행하면 초기값으로 돌아갑니다. 로그인 자동 실행 여부는 macOS에서 읽습니다.
