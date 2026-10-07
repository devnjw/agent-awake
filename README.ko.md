# AgentAwake

MacBook의 덮개를 닫아도 로컬 에이전트 작업이 이어지도록
돕는 macOS 메뉴 막대 앱입니다. 기본 화면에는 **Keep awake** 토글 하나가 있습니다.

[다운로드](https://github.com/devnjw/agent-awake/releases/tag/v0.2.0) ·
[English](README.md) · [개발·배포](docs/DEVELOPMENT.md) · [MIT 라이선스](LICENSE)

## 설치

**macOS 14 이상 · Apple Silicon / Intel 공용 · 관리자 helper 설치 없음**

1. [AgentAwake-0.2.0-universal.dmg](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/AgentAwake-0.2.0-universal.dmg)를 받습니다.
2. 열어서 **AgentAwake.app**을 **Applications** 폴더로 드래그합니다.
3. Applications에서 실행한 뒤 디스크 이미지를 추출하고 충전기를 연결합니다.
4. 메뉴 막대의 번개 아이콘을 누르고 **Keep awake**를 켭니다.

[ZIP 파일](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/AgentAwake-0.2.0-universal.zip)도
제공합니다. 압축을 풀어 앱을 Applications로 옮기면 됩니다.

배포 파일은 **Developer ID 서명은 포함하지만 Apple 공증은 포함하지 않습니다.**
macOS가 실행을 막으면 [Apple 안내](https://support.apple.com/102445)의 앱별
‘확인 없이 열기 / Open Anyway’ 절차를 확인하세요. 조직에서 관리하는 Mac은
이를 제한할 수 있습니다. 신뢰할 수 있는 파일만 설치하고 Gatekeeper 전체를
비활성화하지 마세요.

덮개 제어에 비공개 macOS API를 사용하는 초기 버전입니다. 긴 작업 전에
덮개를 짧게 닫았다 열어 **본인 Mac에서 실제로 작업이 계속되는지** 확인하세요.
유지 요청이 성공했다는 사실만으로 덮개를 닫았을 때의 동작을 보장하지 않습니다.

## 사용

**⋯** 메뉴에서 화면 끄기(**Turn off displays**), 전원 조건(**Only when plugged in**),
종료 시간(**Stop after**), 로그인 실행(**Launch at login**), 도움말, 종료를 선택합니다.
1·2·4·8시간 또는 직접 끌 때까지 유지할 수 있습니다.
실행 중 시간을 바꾸면 그 시점부터 다시 시작되며, 남은 시간도 설정 메뉴에 표시됩니다.

- **Only when plugged in**은 기본으로 체크되어 있습니다. 충전기를 빼면
  일시 정지하고 다시 연결하면 켜 둔 세션을 재개합니다. 체크를 해제하면
  배터리에서도 유지합니다. 전원 조건은 저장되며, 변경해도 종료 시간은 그대로입니다.
- **Turn off displays**는 외부 모니터를 포함한 모든 화면을 끕니다.
  키보드·마우스·트랙패드 입력으로 다시 켜집니다. 화면을 끈 동안에도 작업을
  이어가려면 Keep awake를 켜 두세요. 기존 macOS 잠금·암호 설정은 그대로 적용됩니다.
- macOS가 심각한 온도 상태를 보고하면 멈췄다가 상태가 안정되면 재개합니다.
- 종료하거나 시간이 끝나면 요청을 해제합니다. 앱은 로그인 실행을 포함해
  항상 Keep awake가 꺼진 상태에서 시작합니다.
- 배터리가 100%이거나 최적화 충전으로 충전이 멈춰 있어도 외부 전원이면 동작합니다.
- 배터리 허용 모드는 배터리를 소모하며, 배터리 소진으로 인한 잠자기·종료를 막지는 못합니다.

Codex 외의 로컬 작업에도 적용됩니다. 네트워크 단절, 에이전트의 승인 대기,
다른 앱 자체의 오류는 직접 확인해야 합니다. 서버·분석 수집·에이전트 내용 접근은 없습니다.

통풍되는 단단한 표면에서 사용하고, 깨어 있는 MacBook을 가방에 넣지 마세요.
다른 덮개·절전 제어 앱과 동시에 사용하지 않는 편이 좋습니다.

## 호환성 확인

충전기를 연결하고 Keep awake를 켠 뒤 진행 상태가 기록되는 간단한 로컬 작업을
실행하세요. 덮개를 30초 닫았다 열고 작업이 계속 진행됐는지 확인합니다.
그다음 Keep awake를 끄고 평소처럼 잠자기가 동작하는지 확인하세요.
Mac 모델, 외부 화면 구성, macOS 버전에 따라 결과가 달라질 수 있습니다.

macOS 14 이상을 대상으로 빌드하며, 개발 중 실기 검증은 Apple Silicon /
macOS 26.6.2에서 진행했습니다. Intel 바이너리도 포함하고 CI에서 Intel 빌드를
검사합니다. 물리적인 덮개 닫힘·충전기 분리·로그인 재실행은 실기 확인이 필요합니다.

## 문제 해결과 삭제

**토글이 켜져 있는데 작업이 멈춰요:** 전원 조건과 일시 정지 안내를 확인하고
짧은 덮개 시험을 해보세요. 다른 앱의 승인 대기·연결 오류는 별도로 해결해야 합니다.

**Monitor 오류가 나요:** 앱을 종료하고 다시 여세요. UI와 감시 프로세스를
동시에 강제 종료한 뒤 잠자기가 이상하면 Mac을 재시동하세요.
시스템의 영구 `pmset` 설정은 수정하지 않습니다.

**삭제:** ⋯ 메뉴에서 Launch at login을 끄고 앱을 종료한 뒤 Applications의
AgentAwake를 휴지통으로 옮깁니다. 종료 후에는
`~/Library/Application Support/AgentAwake`의 잠금 파일 디렉토리도 지워도 됩니다.
전원 조건은 앱의 로컬 환경설정에 저장합니다. 관리자 서비스는 설치하지 않습니다.

## 소스에서 빌드

macOS와 Swift 6 이상이 포함된 Xcode 또는 Command Line Tools가 필요합니다.

```sh
git clone https://github.com/devnjw/agent-awake.git
cd agent-awake
make test
make build
open dist/AgentAwake.app
```

[개발·배포 안내](docs/DEVELOPMENT.md)에 공용 바이너리 패키징, 서명, 공증,
실기 검사와 구현 한계를 정리했습니다. 릴리스의
[SHA256SUMS.txt](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/SHA256SUMS.txt)로
다운로드 파일의 SHA256을 확인할 수 있습니다.
