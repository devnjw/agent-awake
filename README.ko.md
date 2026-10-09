# AgentAwake

MacBook 덮개를 닫아도 Codex와 로컬 에이전트 작업을 이어가세요.

**[Apple Silicon 다운로드](https://github.com/devnjw/agent-awake/releases/download/v0.3.1/AgentAwake-0.3.1-arm64.dmg)** · [English](README.md)

macOS 14 이상 · Apple Silicon (M 시리즈)

## 시작하기

1. DMG를 열고 **AgentAwake.app**을 **Applications**로 드래그합니다.
2. 앱을 실행하고 메뉴 막대의 **⚡**를 누릅니다.
3. **Keep awake**를 켭니다. 기본은 충전기 연결 시에만 동작합니다.

## 설정 · ⋯

| 옵션 | 기능 |
| --- | --- |
| **Only when plugged in** | 해제하면 배터리에서도 유지합니다. 선택은 저장됩니다. |
| **Turn off displays** | 모든 화면을 끕니다. 키보드·마우스·트랙패드 입력으로 다시 켜집니다. |
| **Stop after** | 직접 끌 때까지 또는 1 / 2 / 4 / 8시간 유지합니다. |
| **Launch at login** | 로그인할 때 앱을 엽니다. Keep awake는 꺼진 상태로 시작합니다. |

초기 버전으로 Developer ID 서명은 포함하지만 Apple 공증은 없습니다([최초 실행 안내](https://support.apple.com/102445)). 덮개 제어에 비공개 macOS API를 사용하므로, 긴 작업 전에 짧게 확인하세요. 통풍되는 표면에서 사용하세요.

[도움말·문제 해결](docs/GUIDE.ko.md) · [소스에서 빌드](docs/DEVELOPMENT.md) · [MIT 라이선스](LICENSE)
