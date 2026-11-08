#!/usr/bin/env bash
# 로봇에서 추론 컨테이너 실행 (team_node 가 launch_inference.py 로 부르는 것과 같은 내용)
#   ./run.sh 6.1 ~/team/models            # 모델 폴더: model.onnx (+ model.engine, labels.txt)
#   ./run.sh 6.1 ~/team/models bash       # 안에 들어가서 확인
set -euo pipefail
JP="${1:?JetPack 버전 (6.0|6.1|6.2)}"; MODELS="${2:?모델 폴더}"; shift 2
docker rm -f maicon-detector >/dev/null 2>&1 || true
exec docker run --rm -it --name maicon-detector \
  --runtime nvidia --network host --ipc host \
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" -e IMAGE_TOPIC="${IMAGE_TOPIC:-/image_raw}" \
  -v "$(realpath "$MODELS")":/models \
  -v "$HOME/team":/team \
  "maicon-detector:jp${JP}" "$@"
