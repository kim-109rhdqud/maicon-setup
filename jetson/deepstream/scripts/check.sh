#!/usr/bin/env bash
# 컨테이너 안에서 환경 확인 (로봇에서 docker load 후 1번)
#   ./run.sh 6.1 ~/team/models /app/scripts/check.sh
source /opt/ros/humble/setup.bash 2>/dev/null
echo "JetPack(빌드 기준): ${JETPACK}   L4T(호스트): $(cat /etc/nv_tegra_release 2>/dev/null | head -1 || echo '-')"
echo -n "TensorRT: "; python3 -c "import tensorrt as t; print(t.__version__)" 2>&1 | tail -1
echo -n "trtexec:  "; (command -v trtexec || ls /usr/src/tensorrt/bin/trtexec) 2>&1 | tail -1
echo -n "pyds:     "; python3 -c "import pyds; print('ok')" 2>&1 | tail -1
echo -n "GStreamer nvinfer: "; gst-inspect-1.0 nvinfer >/dev/null 2>&1 && echo ok || echo "없음 (--runtime nvidia 로 실행했는지 확인)"
echo -n "YOLO 파서: "; ls /opt/DeepStream-Yolo/nvdsinfer_custom_impl_Yolo/*.so 2>/dev/null || echo "없음 (첫 실행 때 컴파일됨)"
echo -n "rclpy:    "; python3 -c "import rclpy, cv_bridge, vision_msgs; print('ok')" 2>&1 | tail -1
echo -n "GPU:      "; python3 -c "import ctypes; ctypes.CDLL('libcuda.so.1'); print('libcuda ok')" 2>&1 | tail -1
echo -n "모델:     "; ls ${MODEL_DIR:-/models} 2>/dev/null | tr '\n' ' '; echo
echo -n "ROS 토픽: "; timeout 3 ros2 topic list 2>/dev/null | tr '\n' ' ' || echo "(host 네트워크·ROS_DOMAIN_ID 확인)"; echo
