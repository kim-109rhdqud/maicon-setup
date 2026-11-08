# 현장 PC 일괄 설치 (Windows 11) — 온라인 · 오프라인

현장 PC에는 Windows 11, 한글, 오피스, 크롬만 있다. 이 폴더 하나로 나머지를 맞춘다.
인터넷이 되면 `winget`으로, 안 되면 외장 드라이브의 `offline` 폴더로 설치한다.

## 파일

| 파일 | 역할 |
|---|---|
| `setup.bat` | **현장에서 우클릭 → 관리자 권한으로 실행.** `setup.ps1` 실행 |
| `setup.ps1` | 설치 본체. 온/오프라인 자동 판단, 재부팅 후 이어서 실행 |
| `packages.csv` | **설치할 프로그램 목록.** 팀원이 한 줄씩 추가 (Id = winget ID, Roles = all/desktop/laptop/wsl/manual). manual = 직접 설치, 스크립트는 확인만 |
| `requirements-common.txt` | 모든 PC Python 패키지 |
| `requirements-train.txt` | 데스크탑(학습) 추가 패키지. PyTorch는 스크립트가 cu128로 먼저 설치 |
| `wsl/install_ros2.sh` | WSL Ubuntu 안에 ROS2 Humble(RViz) 설치 (`setup.ps1`이 자동 실행) |
| `check_env.py` | 설치 확인 (desktop은 GPU 연산까지) |
| `offline-prep/` | **인터넷이 안 될 때만.** 대회 전에 설치 파일을 미리 받아 두는 도구. 온라인이면 안 봐도 됨 |

## 대회 전에 각자 (1분)

VS Code 확장·설정은 스크립트가 깔지 않고 **개인 계정 동기화**로 가져온다.

1. 자기 PC의 VS Code에서 왼쪽 아래 계정 아이콘 → GitHub(또는 Microsoft) 로그인
2. "설정 동기화 켜기(Backup and Sync Settings)" → 확장(Extensions) 항목 체크 확인

현장에서 VS Code를 켜고 같은 계정으로 로그인하면 확장·설정·단축키가 자동으로 따라온다. 대회가 끝나면 현장 PC에서 로그아웃한다.
스크립트는 팀 공통인 Python, Remote-SSH 2개만 깐다.

## 현장에서 — 이 순서대로

| 순서 | 할 일 | 방법 |
|---|---|---|
| 1 | **VS Code 설치** | https://code.visualstudio.com 에서 받아 설치 → 계정 로그인(확장·설정 동기화) |
| 2 | **Claude Desktop 설치** | https://claude.ai/download 에서 받아 설치 |
| 3 | 이 폴더를 PC로 복사 | 외장 드라이브 또는 GitHub ZIP. **ZIP은 반드시 압축을 푼 뒤 실행** (ZIP 안에서 바로 실행하면 임시 폴더에서 돌아 재부팅 후 자동 재개가 깨짐) |
| 4 | **`setup.bat` 우클릭 → 관리자 권한으로 실행** | UAC 예 → `desktop` 또는 `laptop` 입력. Git·Python·Node.js 등 자동 설치. 끝나면 결과 확인 후 아무 키나 눌러 닫기. (그냥 더블클릭해도 되지만, 그때는 관리자 창이 새로 떠서 그 창에서 진행됨) |
| 5 | 재부팅 (WSL 처음 켜는 PC만) | "지금 재부팅?" Y → 로그인하면 자동으로 이어서 설치 (UAC 예) |
| 6 | 결과 확인 | `모두 정상` 또는 `확인할 것 N건`. 로그 `setup_log.txt` |
| 7 | **Claude Code 설치** | 새 터미널에서 `npm install -g @anthropic-ai/claude-code` (4번에서 깐 Node.js 사용) |

- 1·2번은 스크립트 **앞**: VS Code가 있어야 4번에서 확장 2개가 들어감
- 7번은 스크립트 **뒤**: Node.js가 있어야 함
- 순서를 어겼으면 `setup.bat`을 한 번 더 돌리면 됨 (깔린 건 건너뜀)

| 역할 | 설치되는 것 |
|---|---|
| 공통 | Git, 7-Zip, Chrome, Python 3.10, Node.js LTS, Windows Terminal, MobaXterm, OpenSSH, venv + 공통 패키지, VS Code 확장 2개(Python·Remote-SSH) |
| 직접 설치 | VS Code, Claude Desktop, Claude Code, Foxglove (스크립트는 있는지 확인만. Foxglove 는 2.0부터 winget 배포가 없어 https://foxglove.dev/download 에서 받음) |
| + desktop | PyTorch(CUDA 12.8) + torchvision, ultralytics, onnx. NVIDIA 드라이버는 수동 |
| + WSL (기본 켜짐, `-NoWsl`로 끔) | WSL2, Ubuntu 22.04 + ROS2 Humble + RViz + foxglove-bridge. 배포판 이름 `maicon-ros2`, 사용자 `maicon`/`maicon` |

옵션: `setup.ps1 -Role laptop -NoWsl`, `-Offline E:\maicon-offline`, `-RepoUrl https://github.com/<팀>/<저장소>.git`

## 인터넷이 안 될 때 (보험) — `offline-prep/`

온라인이 확정이면 이 절은 건너뛴다. 대회 전에 인터넷 되는 Windows PC에서:

```powershell
powershell -ExecutionPolicy Bypass -File offline-prep\prepare_offline.ps1 -Out E:\maicon-offline
```

현장에서는 `setup.ps1 -Offline E:\maicon-offline` 로 실행하면 인터넷 없이 같은 결과가 나온다.

만들어지는 것 (약 5~10GB, WSL tar 포함 시 +3~4GB):

```
offline\
  winget\        App Installer msixbundle + VCLibs + UI.Xaml   (새 PC에 winget 없을 때)
  installers\    packages.csv 각 항목의 설치 파일 (winget download)
  vsix\          VS Code 확장 2개 (Python, Remote-SSH)
  wheels\        Python 패키지 (Windows x64 / Py3.10). PyTorch cu128 포함
  wsl\           ros2-humble-22.04.tar  (아래 방법으로 만든 것)
  nvidia\        RTX 5070 드라이버 exe  ← 직접 받아 넣기
  REPORT.txt     못 받은 것 목록 ← 이걸 보고 수동으로 채움
```

ROS2 포함 Ubuntu tar 만드는 법 (둘 중 하나):
- 리눅스/Docker 있는 곳: `bash offline-prep/build_rootfs.sh` → `offline/wsl/ros2-humble-22.04.tar`
- 또는 온라인으로 한 번 `setup.ps1`을 끝까지 돌린 Windows에서 `offline-prep\prepare_offline.ps1`을 실행하면 그 PC의 `maicon-ros2`를 `wsl --export`로 내보냄

## 검증 (깨끗한 Windows 11에서)

- [ ] 온라인: `setup.bat` → laptop → 재부팅 → 자동 재개 → `모두 정상`
- [ ] 온라인: desktop → `check_env.py`에서 `GPU 사용 가능` 출력 (NVIDIA GPU 있는 PC만)
- [ ] 오프라인: 네트워크 끊고 `setup.ps1 -Role laptop -Offline <폴더>` → 같은 결과
- [ ] `wsl -d maicon-ros2` → `ros2 topic list` 실행됨, `rviz2` 창 뜸
- [ ] 재부팅 후 RunOnce가 지워져 두 번 실행되지 않음
- [ ] `REPORT.txt`의 못 받은 항목을 수동으로 채웠는지

## 알려진 확인 사항


- RTX 50 시리즈는 cu128 빌드 PyTorch만 GPU를 쓴다. 오프라인 휠도 그 빌드로 받는다.
- 팀 회의에서 버전이 정해지면 `requirements-*.txt`와 `packages.csv`만 고치면 된다.
