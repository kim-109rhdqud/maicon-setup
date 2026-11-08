#!/usr/bin/env python3
"""데스크탑에서: 학습한 YOLO(.pt) → DeepStream-Yolo 형식 ONNX. 공개 모델로 시험하려면 -w yolo11n.pt

    pip install ultralytics onnx onnxslim        # 데스크탑 (setup.ps1 의 desktop 역할이면 이미 있음)
    python export_onnx.py -w runs/train/best.pt --out ../models
    python export_onnx.py -w yolo11n.pt          # 공개 모델 시험용 (자동 다운로드)

DeepStream-Yolo 의 export 스크립트를 받아서 실행한다 (일반 ultralytics export 와 출력 형식이 달라서 그쪽 걸 써야 함).
결과: <out>/model.onnx, <out>/labels.txt
"""
import argparse
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

RAW = "https://raw.githubusercontent.com/marcoslucianops/DeepStream-Yolo/master/utils/"
SCRIPTS = {"yolo11": "export_yolo11.py", "yolov8": "export_yoloV8.py", "yolov5": "export_yoloV5.py",
           "yolov9": "export_yoloV9.py", "yolov10": "export_yoloV10.py"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-w", "--weights", required=True, help=".pt 파일 (없으면 ultralytics 가 공개 모델 다운로드)")
    ap.add_argument("--out", default="models")
    ap.add_argument("--family", default="", help="yolo11 / yolov8 … (비우면 파일 이름으로 추정)")
    ap.add_argument("--size", type=int, default=640)
    a = ap.parse_args()

    fam = a.family or next((k for k in SCRIPTS if k in Path(a.weights).name.lower()), "yolo11")
    script = Path(__file__).with_name(SCRIPTS[fam])
    if not script.exists():
        print("export 스크립트 받는 중:", RAW + SCRIPTS[fam])
        urllib.request.urlretrieve(RAW + SCRIPTS[fam], script)

    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable, str(script), "-w", a.weights, "-s", str(a.size), "--simplify", "--dynamic"]
    print(" ".join(cmd))
    subprocess.run(cmd, check=True)

    onnx = Path(a.weights).with_suffix(".onnx")
    if not onnx.exists():
        cands = sorted(Path(".").glob("*.onnx"), key=lambda p: p.stat().st_mtime)
        onnx = cands[-1] if cands else None
    if not onnx:
        sys.exit("ONNX 파일을 못 찾음")
    shutil.copy(onnx, out / "model.onnx")
    labels = Path("labels.txt")
    if labels.exists():
        shutil.copy(labels, out / "labels.txt")  # export 스크립트가 .pt 의 클래스 이름으로 만들어 줌
    print(f"\n완료: {out/'model.onnx'}  (+ labels.txt)")
    print("다음: 이 폴더를 로봇 ~/team/models 로 복사 → 로봇에서 build_engine.sh")
    print("주의: 클래스 수가 yolo_pgie.txt 의 num-detected-classes 와 같아야 함 (지금 10)")


if __name__ == "__main__":
    main()
