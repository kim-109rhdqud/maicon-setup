# 대회측 메시지·서비스 타입 (/mil/oled, /mil/gimbal, /mil/fire)

주최측이 커스텀 ROS2 인터페이스 패키지를 쓰면 그 소스를 이 폴더에 넣는다 (예: `mil_msgs/`).
빌드 때 이 폴더에 `package.xml` 이 있는 패키지가 있으면 colcon 으로 빌드해 이미지에 포함한다.
표준 타입(std_msgs 등)만 쓰면 아무것도 넣지 않아도 된다.

→ 사전교육 자료나 로봇의 `ros2 interface show <타입>` 으로 확인해서 채울 것.
