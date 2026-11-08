#!/usr/bin/env bash
# 컨테이너 시작: ROS 환경 → YOLO 파서 없으면 컴파일 → 명령 실행
set -e
source /opt/ros/humble/setup.bash
[ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
export PATH=/usr/local/cuda/bin:$PATH

LIB=/opt/DeepStream-Yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so
if [ ! -f "$LIB" ]; then
  echo "[entrypoint] YOLO 파서 컴파일 (처음 1번, 1~3분)"
  CUDA_VER=${CUDA_VER} make -C /opt/DeepStream-Yolo/nvdsinfer_custom_impl_Yolo -j"$(nproc)"
fi
exec "$@"
