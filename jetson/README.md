# 로봇(Jetson Orin Nano) 객체 탐지 추론 환경 — DeepStream Docker 이미지

UGV 카메라(`/image_raw`, 640×480)에서 전장 객체 6종 + 지정표적 시설 3종 + 상대 UGV를 TensorRT로 빠르게 찾는 컨테이너.
`team_node.py`가 대기 단계에 띄우고, 결과를 ROS2 토픽으로 받는다.

## 폴더

| 경로 | 내용 |
|---|---|
| `deepstream/Dockerfile` | 이미지 정의. JetPack 버전은 빌드 인자 |
| `deepstream/versions.env` | JetPack 6.0 / 6.1 / 6.2 ↔ DeepStream 이미지 태그, CUDA, pyds 버전 **(빌드 전 확인)** |
| `deepstream/build.sh` | 빌드 + `docker save` → `tars/*.tar` |
| `deepstream/load.sh` | 로봇에서 `docker load` + 런타임 확인 |
| `deepstream/run.sh` | 로봇에서 수동 실행·디버깅 |
| `deepstream/entrypoint.sh` | ROS 환경 적용, YOLO 파서 없으면 컴파일 |
| `deepstream/config/yolo_pgie.txt` | nvinfer 설정 (FP16, 클래스 10) |
| `deepstream/config/labels.txt` | 클래스 10개. **학습 data.yaml 순서와 같아야 함** |
| `deepstream/detector/detector_node.py` | `/image_raw` → appsrc → nvinfer → `/detections`(vision_msgs) + `/detections_json` |
| `deepstream/scripts/build_engine.sh` | 로봇에서 ONNX → engine 한 줄 |
| `deepstream/scripts/export_onnx.py` | 데스크탑에서 .pt → DeepStream용 ONNX (공개 모델 시험 가능) |
| `deepstream/scripts/check.sh` | 컨테이너 안 환경 확인 |
| `deepstream/launch/launch_inference.py` | team_node에서 `start()/stop()/alive()` |
| `deepstream/launch/team_node_example.py` | 연결 예시 |
| `deepstream/mil_interfaces/` | 대회측 커스텀 메시지 패키지 넣는 곳 (있으면 자동 빌드) |
| `aws/` | AWS ARM 인스턴스에서 빌드하는 순서 |

## 이미지에 들어가는 것 (요청서 대조)

| 요청 | 들어감 |
|---|---|
| NGC Jetson용 DeepStream 이미지 | `deepstream-l4t` 기반 |
| ROS 2 Humble, rclpy, cv_bridge, sensor/geometry/nav_msgs | apt `ros-humble-ros-base` + 각 패키지 (+ vision_msgs) |
| `/mil/*` 메시지·서비스 타입 | `mil_interfaces/`에 패키지를 넣으면 colcon 빌드. **타입 정의를 받아야 함** |
| TensorRT, trtexec, pyds | 기반 이미지 포함 + pyds 공식 설치 스크립트(실패 시 wheel) |
| numpy, OpenCV, requests, pyyaml | numpy·requests·pyyaml은 pip, OpenCV는 시스템(`python3-opencv`, cv_bridge 충돌 방지) |
| JetPack 6.0/6.1/6.2 | `./build.sh all` → 이미지 3벌 |
| `docker save` → tar → 인터넷 없이 `docker load` | `build.sh` / `load.sh` |
| ONNX → engine 현장 한 줄 | `scripts/build_engine.sh` |
| team_node.py가 띄울 수 있는 형태 | `launch/launch_inference.py` |

## 흐름

```
[데스크탑]  학습 .pt ──export_onnx.py──▶ models/model.onnx + labels.txt ──▶ 외장 드라이브
[AWS ARM]   ./build.sh all ──▶ tars/maicon-detector-jp6.x.tar ──▶ 외장 드라이브
[로봇]      cat /etc/nv_tegra_release 로 JetPack 확인 → load.sh <맞는 tar>
            → build_engine.sh (engine 생성, 3~10분)   → team_node.py 가 launch_inference.start()
            → /detections_json 구독해서 사용
```

## 현장 순서 (로봇을 받으면)

1. `cat /etc/nv_tegra_release` → R36.3=6.0 / R36.4.0=6.1 / R36.4.3+=6.2
2. `./load.sh /media/usb/jetson/maicon-detector-jp<버전>.tar`
3. `mkdir -p ~/team/models` 에 `model.onnx`, `labels.txt` 복사
4. `./run.sh <버전> ~/team/models /app/scripts/check.sh` → TensorRT·pyds·nvinfer·GPU 전부 ok 인지
5. `./run.sh <버전> ~/team/models /app/scripts/build_engine.sh` → `model.engine` 생성
6. `./run.sh <버전> ~/team/models` 로 띄운 뒤 다른 터미널에서 `ros2 topic echo /detections_json` 으로 결과 확인
7. 되면 team_node.py 에 `launch_inference.Inference(...).start()` 연결

## 아직 모르는 것 (확인되면 고칠 곳)

| 항목 | 영향 | 고칠 곳 |
|---|---|---|
| 로봇 JetPack 버전 | 어떤 tar 를 쓸지 | 현장 1번으로 확인 |
| `versions.env` 의 이미지 태그·pyds 버전 | 빌드 성공 여부 | 빌드 전 NGC·GitHub 릴리스에서 확인 |
| team_node 가 도는 컨테이너에 Docker 소켓이 있는지 | 없으면 `launch_inference` 가 컨테이너를 못 띄움 → 경기 전에 `run.sh` 로 미리 띄워 두고 team_node 는 토픽만 구독 | 게시판 답 / 현장 |
| `/mil/oled` `/mil/gimbal` `/mil/fire` 타입 정의 | 커스텀이면 `mil_interfaces/`에 소스 필요 | 서빈 님 |
| `/mil/match` 메시지 타입 | `team_node_example.py` 는 String(JSON) 가정 | 서빈 님 |
| 탐지 결과 토픽 형식 | 지금은 `/detections`(vision_msgs) + `/detections_json`. 팀이 쓰기 편한 쪽으로 | 회의 |
| 클래스 순서 | `labels.txt` 와 학습 data.yaml 이 같아야 함 | 학습 담당 |

## 검증 결과 (2026-11-08, AWS c7g.2xlarge / Ubuntu 24.04 arm64)

| 확인 | 결과 |
|---|---|
| 세 벌 빌드 (`./build.sh 6.0 / 6.1 / 6.2`) | 전부 통과. 이미지 약 9GB, tar 3.8 / 3.4 / 3.4 GB (한 벌 15~20분) |
| `docker rmi` → `docker load` → 컨테이너 실행 | 통과 |
| 컨테이너 안 rclpy·cv_bridge·vision_msgs, ROS2 토픽, trtexec, labels.txt | ok |
| TensorRT·pyds·GPU·nvinfer | AWS에서는 "라이브러리 없음" — **정상**. JetPack 6 DeepStream 컨테이너는 CUDA·TensorRT를 호스트(Jetson)에서 마운트해 쓰므로 로봇에서 `--runtime nvidia`로 실행해야 보임 |
| YOLO 파서 | 빌드 때 컴파일 안 됨(nvcc·헤더 없음) → **로봇에서 첫 실행 때 자동 컴파일** (entrypoint). 실패해도 컨테이너는 뜸 |

로봇에서만 되는 것: GPU 추론, 속도, 메모리, 파서 컴파일, pyds import.
