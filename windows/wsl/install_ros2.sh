#!/usr/bin/env bash
# WSL Ubuntu 22.04 안에 ROS2 Humble(RViz 포함) 설치. root 로 실행 (setup.ps1 이 자동으로 부름)
#   wsl -d Ubuntu-22.04 -u root -- bash install_ros2.sh
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y locales curl gnupg lsb-release software-properties-common
locale-gen en_US.UTF-8 ko_KR.UTF-8
add-apt-repository -y universe
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
  > /etc/apt/sources.list.d/ros2.list
apt-get update
apt-get install -y ros-humble-desktop ros-dev-tools ros-humble-foxglove-bridge ros-humble-cv-bridge \
                   python3-pip python3-colcon-common-extensions git
# 기본 사용자 (없으면 만듦)
if ! id maicon >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo maicon && echo "maicon:maicon" | chpasswd
fi
printf '[boot]\nsystemd=true\n[user]\ndefault=maicon\n' > /etc/wsl.conf
grep -q "ros/humble/setup.bash" /home/maicon/.bashrc || cat >> /home/maicon/.bashrc <<'B'
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
B
echo "ROS2 Humble 설치 완료. 로그인: maicon / maicon"
