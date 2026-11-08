#!/usr/bin/env bash
# AWS ARM64(Graviton) Ubuntu 22.04 인스턴스에서 1번: Docker 설치 + 저장소 받기
#   curl -sSL <raw 주소>/bootstrap_arm.sh | bash     또는 파일 복사 후  bash bootstrap_arm.sh
set -euo pipefail
[ "$(uname -m)" = "aarch64" ] || { echo "ARM64 인스턴스가 아님: $(uname -m) — t4g/c7g/m7g 계열을 쓸 것"; exit 1; }
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
df -h / | tail -1 | awk '{print "디스크 남은 용량: " $4 "  (세 벌 빌드 + tar 면 100GB 이상 권장)"}'
echo "완료. 로그아웃 후 다시 접속(docker 그룹 적용) → git clone <maicon-setup> → cd maicon-setup/jetson/deepstream → ./build.sh 6.1"
