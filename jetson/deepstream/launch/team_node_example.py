#!/usr/bin/env python3
"""team_node.py 에 추론 컨테이너를 붙이는 최소 예시 (통합 담당 참고용).

- 대기(standby) 신호: 추론 시작
- /detections_json 구독: 탐지 결과 받기
- stop 신호: 추론 종료
실제 team_node 의 step() 은 0.1초 안에 끝나야 하므로 start()/stop() 은 스레드에서 부른다.
"""
import json
import os
import sys
import threading

import rclpy
from rclpy.node import Node
from std_msgs.msg import String

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from launch_inference import Inference  # noqa: E402


class TeamNodeExample(Node):
    def __init__(self):
        super().__init__("team_node_example")
        self.inference = Inference(jetpack=os.environ.get("JETPACK", "6.1"),
                                   models=os.path.expanduser("~/team/models"))
        self.latest = []
        # [확인 필요] /mil/match 의 실제 메시지 타입. 여기서는 JSON 문자열(String)이라고 가정
        self.create_subscription(String, "/mil/match", self.on_match, 10)
        self.create_subscription(String, "/detections_json", self.on_detections, 10)
        self.create_timer(0.1, self.step)

    def on_match(self, msg):
        try:
            cmd = json.loads(msg.data).get("cmd", "")
        except Exception:
            cmd = msg.data
        if cmd == "standby":
            threading.Thread(target=self.inference.start, daemon=True).start()
        elif cmd == "stop":
            threading.Thread(target=self.inference.stop, daemon=True).start()

    def on_detections(self, msg):
        self.latest = json.loads(msg.data)["dets"]      # [{"cls":"tank","conf":0.9,"x1":..,"y1":..,"x2":..,"y2":..}]

    def step(self):
        # 0.1초 안에 끝나는 가벼운 일만. 예: 가장 확신도 높은 탐지 로그
        if self.latest:
            best = max(self.latest, key=lambda d: d["conf"])
            self.get_logger().info(f"{best['cls']} {best['conf']:.2f}", throttle_duration_sec=2.0)


def main():
    rclpy.init()
    node = TeamNodeExample()
    try:
        rclpy.spin(node)
    finally:
        node.inference.stop()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
