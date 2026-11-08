# AWS에서 이미지 빌드 + tar 만들기 (현서)

GPU 없는 ARM 서버에서 **빌드가 되는지**와 **tar 저장·불러오기**까지 확인한다. 실제 추론은 로봇에서.

## 1. 인스턴스

| 항목 | 값 |
|---|---|
| AMI | Ubuntu Server 22.04 LTS **(64-bit Arm)** |
| 타입 | `c7g.2xlarge` (8코어, 빌드 빠름) 또는 `t4g.xlarge` (싸지만 느림) |
| 디스크 | gp3 **120GB** (이미지 1벌 약 9GB, tar 1벌 약 3.5GB — 실측) |
| 보안 그룹 | SSH(22)만 |

비용 감각: c7g.2xlarge 시간당 약 0.3~0.4달러. 빌드 끝나면 **중지(stop)** 또는 종료.

## 2. 준비 (한 번)

```bash
ssh -i key.pem ubuntu@<IP>
bash <(curl -sSL https://raw.githubusercontent.com/kim-109rhdqud/maicon-setup/main/jetson/aws/bootstrap_arm.sh)
exit   # docker 그룹 적용하려고 재접속
ssh -i key.pem ubuntu@<IP>
git clone https://github.com/kim-109rhdqud/maicon-setup.git
cd maicon-setup/jetson/deepstream
```

NGC 이미지는 보통 로그인 없이 받아진다. 거부되면 `docker login nvcr.io` (아이디 `$oauthtoken`, 비밀번호 = NGC API 키).

## 3. 빌드

```bash
./build.sh 6.1            # 먼저 1벌로 Dockerfile 이 통과하는지 확인 (30분~1시간)
./build.sh all            # 통과하면 세 벌 (tars/ 에 tar 3개)
ls -lh tars/
```

`screen` 이나 `tmux` 안에서 돌리면 SSH 끊겨도 계속된다.

## 4. 불러오기 확인 (요청서의 "docker load 로 설치되는지")

```bash
docker rmi maicon-detector:jp6.1
docker load -i tars/maicon-detector-jp6.1.tar
docker run --rm maicon-detector:jp6.1 /app/scripts/check.sh    # GPU 없는 서버라 TensorRT·pyds·GPU·nvinfer 는 "없음"이 정상 (Jetson 호스트 마운트)
docker run --rm maicon-detector:jp6.1 python3 -c "import pyds, rclpy, cv_bridge, vision_msgs; print('imports ok')"
```

## 5. tar 내려받기

```bash
# 내 PC 에서
scp -i key.pem ubuntu@<IP>:~/maicon-setup/jetson/deepstream/tars/*.tar* ./
```
tar 1벌 약 3.5GB, 세 벌 10GB 안팎. S3 를 거치면 끊겨도 이어받기 쉽다: `aws s3 cp tars/ s3://<버킷>/ --recursive`.

## 6. 외장 드라이브 구성

```
maicon-offline/
  jetson/
    maicon-detector-jp6.0.tar  (+ .sha256)
    maicon-detector-jp6.1.tar
    maicon-detector-jp6.2.tar
    load.sh  run.sh  (deepstream 폴더에서 복사)
  models/
    model.onnx  labels.txt      (export_onnx.py 결과)
```

## 막혔을 때

| 증상 | 대처 |
|---|---|
| NGC 이미지 pull 실패 (manifest unknown) | `versions.env` 의 태그가 없음 → NGC 태그 목록에서 맞는 걸로 수정 |
| pyds 설치 실패 | `versions.env` 의 PYDS_VER / PYDS_WHEEL 을 deepstream_python_apps 릴리스에서 확인해 수정 |
| YOLO 파서 "nvcc 없음" 로그 | 정상. 로봇에서 첫 실행 때 컴파일됨 |
| ROS apt 키 오류 | `curl ... ros.key` 줄의 주소 접근 확인 (인스턴스 인터넷) |
| 디스크 부족 | `docker system prune -a` 후 재시도, 또는 볼륨 확장 |
