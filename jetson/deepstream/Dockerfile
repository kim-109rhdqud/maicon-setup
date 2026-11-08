# UGV(Jetson Orin Nano) 객체 탐지 추론 이미지 — DeepStream + ROS2 Humble + pyds
#
# 빌드는 build.sh 로 (JetPack 버전에 맞는 ARG 를 versions.env 에서 읽어 넣어 줌):
#   ./build.sh 6.1          # JetPack 6.1 용 1벌
#   ./build.sh all          # 6.0 / 6.1 / 6.2 세 벌
#
# 들어가는 것
#   기반      NGC deepstream-l4t (TensorRT, trtexec, CUDA, GStreamer 포함)
#   ROS2      Humble ros-base + rclpy, cv_bridge, sensor/geometry/nav/vision_msgs
#   추론      pyds (DeepStream Python 바인딩), DeepStream-Yolo 파서
#   파이썬    numpy, 시스템 OpenCV(python3-opencv), requests, pyyaml
#   대회측    mil_interfaces/ 에 패키지가 있으면 colcon 빌드해 포함
#   앱        /app (detector 노드, 설정, 스크립트)

ARG DS_IMAGE=nvcr.io/nvidia/deepstream-l4t:7.1-samples-multiarch
FROM ${DS_IMAGE}

ARG JETPACK=6.1
ARG CUDA_VER=12.6
ARG PYDS_VER=1.2.0
ARG PYDS_WHEEL=
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    ROS_DISTRO=humble \
    JETPACK=${JETPACK} \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------- 기본 도구 + GStreamer 파이썬
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release software-properties-common locales \
        git build-essential cmake pkg-config \
        python3 python3-pip python3-dev python3-numpy python3-opencv \
        python3-gi python3-gst-1.0 gir1.2-gst-plugins-base-1.0 \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libglib2.0-dev \
        libcairo2-dev libgirepository1.0-dev python3-gi-cairo \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------- ROS2 Humble
RUN add-apt-repository -y universe \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
         -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
         http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
         > /etc/apt/sources.list.d/ros2.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        ros-humble-ros-base \
        ros-humble-cv-bridge \
        ros-humble-sensor-msgs ros-humble-geometry-msgs ros-humble-nav-msgs \
        ros-humble-vision-msgs ros-humble-std-srvs \
        python3-colcon-common-extensions python3-rosdep \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------- pyds (DeepStream Python 바인딩)
# 1순위: DeepStream 컨테이너에 들어 있는 공식 설치 스크립트 / 2순위: GitHub 릴리스 wheel
RUN set -e; ok=0; \
    DS_DIR=/opt/nvidia/deepstream/deepstream; \
    if [ -x "$DS_DIR/user_deepstream_python_apps_install.sh" ]; then \
        bash "$DS_DIR/user_deepstream_python_apps_install.sh" -v ${PYDS_VER} && ok=1 || echo "공식 설치 스크립트 실패"; \
    fi; \
    if [ "$ok" = 0 ] && [ -n "${PYDS_WHEEL}" ]; then \
        pip3 install --no-cache-dir "${PYDS_WHEEL}" && ok=1 || echo "wheel 설치 실패"; \
    fi; \
    # import 는 Jetson 전용 라이브러리(libnvbufsurface 등, 실행 시 호스트에서 마운트)가 필요해 빌드 서버에서는 안 됨 → 설치 여부만 확인
    python3 -c "import importlib.util as u; s=u.find_spec('pyds'); assert s, 'pyds 없음'; print('pyds 설치됨:', s.origin)" \
        || { echo "!!! pyds 설치 실패 — versions.env 의 PYDS_VER/PYDS_WHEEL 확인"; exit 1; }

# ---------------------------------------------------------------- DeepStream-Yolo 파서 (YOLOv5~11 출력 해석)
# nvcc 가 이미지에 있으면 빌드 때 컴파일, 없으면(호스트 CUDA 마운트 방식) 로봇에서 첫 실행 때 컴파일
RUN git clone --depth 1 https://github.com/marcoslucianops/DeepStream-Yolo /opt/DeepStream-Yolo \
    && cd /opt/DeepStream-Yolo \
    && if command -v nvcc >/dev/null 2>&1 || [ -x /usr/local/cuda/bin/nvcc ]; then \
         export PATH=/usr/local/cuda/bin:$PATH; \
         CUDA_VER=${CUDA_VER} make -C nvdsinfer_custom_impl_Yolo -j"$(nproc)" \
         && echo "YOLO 파서 빌드 완료"; \
       else \
         echo "!!! nvcc 없음 — YOLO 파서는 로봇에서 첫 실행 때 컴파일됨 (entrypoint)"; \
       fi

# ---------------------------------------------------------------- 파이썬 패키지
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# ---------------------------------------------------------------- 대회측 인터페이스 (있을 때만 빌드)
COPY mil_interfaces/ /ws/src/
RUN source /opt/ros/humble/setup.bash \
    && if ls /ws/src/*/package.xml >/dev/null 2>&1; then \
         cd /ws && colcon build --symlink-install && echo "mil_interfaces 빌드 완료"; \
       else \
         echo "mil_interfaces 없음 — 표준 타입만 사용"; mkdir -p /ws/install; \
       fi

# ---------------------------------------------------------------- 앱
COPY config/   /app/config/
COPY detector/ /app/detector/
COPY scripts/  /app/scripts/
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /app/scripts/*.sh \
    && mkdir -p /models \
    && cp /app/config/labels.txt /models/labels.txt

ENV CUDA_VER=${CUDA_VER} \
    MODEL_DIR=/models \
    PGIE_CONFIG=/app/config/yolo_pgie.txt \
    IMAGE_TOPIC=/image_raw \
    DETECTIONS_TOPIC=/detections

WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["python3", "/app/detector/detector_node.py"]
