# WSL 용 Ubuntu 22.04 + ROS2 Humble rootfs 를 리눅스에서 만들기 위한 이미지 (build_rootfs.sh 가 씀)
FROM ubuntu:22.04
COPY install_ros2.sh /tmp/install_ros2.sh
RUN bash /tmp/install_ros2.sh && rm /tmp/install_ros2.sh && apt-get clean && rm -rf /var/lib/apt/lists/*
