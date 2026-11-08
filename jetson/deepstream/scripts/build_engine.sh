#!/usr/bin/env bash
# 로봇에서: ONNX → TensorRT 엔진 (한 줄). 경기 전에 미리 돌려 두면 첫 실행이 느리지 않다.
#   컨테이너 밖:  ./run.sh 6.1 ~/team/models /app/scripts/build_engine.sh
#   컨테이너 안:  /app/scripts/build_engine.sh [onnx] [engine] [fp16|fp32|int8]
# 기본: /models/model.onnx → /models/model.engine, FP16
set -euo pipefail
ONNX="${1:-${MODEL_DIR:-/models}/model.onnx}"
ENGINE="${2:-${ONNX%.onnx}.engine}"
PREC="${3:-fp16}"
TRTEXEC=$(command -v trtexec || ls /usr/src/tensorrt/bin/trtexec 2>/dev/null || true)
[ -n "$TRTEXEC" ] || { echo "trtexec 없음 (TensorRT 미설치?)"; exit 1; }
[ -f "$ONNX" ] || { echo "ONNX 없음: $ONNX"; exit 1; }
case "$PREC" in fp16) FLAG=--fp16;; int8) FLAG=--int8;; *) FLAG="";; esac
echo "ONNX: $ONNX → $ENGINE ($PREC)  — Orin Nano 에서 3~10분"
"$TRTEXEC" --onnx="$ONNX" --saveEngine="$ENGINE" $FLAG --memPoolSize=workspace:2048 --skipInference 2>&1 | tail -5
ls -lh "$ENGINE"
echo "완료. yolo_pgie.txt 의 model-engine-file 이 이 경로인지 확인: $ENGINE"
