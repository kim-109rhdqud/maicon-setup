#!/usr/bin/env bash
# 컨테이너 시작: ROS 환경 → YOLO 파서 없으면 컴파일(로봇에서만 가능) → 명령 실행
source /opt/ros/humble/setup.bash
[ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
export PATH=/usr/local/cuda/bin:$PATH

LIB=/opt/DeepStream-Yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so
if [ ! -f "$LIB" ]; then
  if [ -f /usr/include/aarch64-linux-gnu/NvInfer.h ] || [ -f /usr/include/NvInfer.h ] || ls /usr/local/cuda*/include/cuda.h >/dev/null 2>&1; then
    echo "[entrypoint] YOLO 파서 컴파일 (처음 1번, 1~3분)"
    if ! CUDA_VER=${CUDA_VER} make -C /opt/DeepStream-Yolo/nvdsinfer_custom_impl_Yolo -j"$(nproc)" >/tmp/yolo_parser_build.log 2>&1; then
      echo "[entrypoint] !!! YOLO 파서 컴파일 실패 — /tmp/yolo_parser_build.log 확인. 추론(nvinfer)은 동작하지 않음"
    fi
  else
    echo "[entrypoint] TensorRT/CUDA 헤더 없음 → 파서 컴파일 건너뜀 (Jetson 에서 --runtime nvidia 로 실행하면 호스트 것이 마운트됨)"
  fi
fi
exec "$@"
