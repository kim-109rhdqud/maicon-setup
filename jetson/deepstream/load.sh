#!/usr/bin/env bash
# 로봇(현장)에서: 외장 드라이브의 tar 를 불러와 확인. 인터넷 불필요.
#   ./load.sh /media/usb/tars/maicon-detector-jp6.1.tar
set -euo pipefail
TAR="${1:?tar 파일 경로}"
echo "L4T: $(head -1 /etc/nv_tegra_release 2>/dev/null || echo '모름 (Jetson 아님?)')"
[ -f "$TAR.sha256" ] && (cd "$(dirname "$TAR")" && sha256sum -c "$(basename "$TAR").sha256")
docker load -i "$TAR"
docker image ls maicon-detector
echo "nvidia 런타임: $(docker info --format '{{json .Runtimes}}' | grep -o nvidia || echo '없음 → sudo apt install nvidia-container-toolkit 또는 /etc/docker/daemon.json 확인')"
