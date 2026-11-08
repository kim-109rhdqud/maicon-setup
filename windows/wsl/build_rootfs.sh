#!/usr/bin/env bash
# 리눅스(Docker 있는 PC·서버)에서 WSL 용 rootfs tar 만들기 → offline/wsl/ros2-humble-22.04.tar
#   bash build_rootfs.sh [출력 폴더]
# Windows 에서는 setup.ps1 이 이 tar 를 `wsl --import maicon-ros2 ...` 로 넣는다. (x86_64 에서 빌드할 것)
set -e
cd "$(dirname "$0")"
OUT="${1:-../offline/wsl}"
mkdir -p "$OUT"
docker build --platform linux/amd64 -t maicon-ros2-rootfs .
cid=$(docker create --platform linux/amd64 maicon-ros2-rootfs)
docker export "$cid" -o "$OUT/ros2-humble-22.04.tar"
docker rm "$cid" >/dev/null
ls -lh "$OUT/ros2-humble-22.04.tar"
echo "Windows 에서: wsl --import maicon-ros2 C:\\WSL\\maicon-ros2 ros2-humble-22.04.tar --version 2"
