# 로봇(Jetson) 추론 환경 — 준비 중

UGV(Jetson Orin Nano)에서 객체 인식 추론을 돌릴 환경. 로봇 JetPack 버전과 경기 컨테이너 GPU 연결 여부(주최측 답변 대기)에 따라 구성이 정해진다.

계획
1. 기본: TensorRT + Python 추론 스크립트 (JetPack 기본 포함분만 사용) + ONNX → engine 변환 한 줄 스크립트
2. 추가: DeepStream Docker 이미지 (JetPack 버전 확정 후 그 버전 1개)
