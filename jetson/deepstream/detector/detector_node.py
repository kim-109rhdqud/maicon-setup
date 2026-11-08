#!/usr/bin/env python3
"""/image_raw → DeepStream(nvinfer) → /detections (vision_msgs/Detection2DArray) + /detections_json

구조
  rclpy 구독(sensor_msgs/Image 640x480) → numpy RGB → GStreamer appsrc
  → nvvideoconvert → nvstreammux → nvinfer(YOLO, TensorRT) → probe 에서 결과 꺼냄 → ROS 발행

환경변수 (run.sh / launch_inference.py 가 넣어 줌)
  IMAGE_TOPIC=/image_raw   DETECTIONS_TOPIC=/detections   PGIE_CONFIG=/app/config/yolo_pgie.txt
  MODEL_DIR=/models        FRAME_W=640 FRAME_H=480         MAX_FPS=15

결과 메시지
  vision_msgs/Detection2DArray: results[0].hypothesis.class_id = 클래스 이름, score = 확신도, bbox = 중심·크기(픽셀)
  std_msgs/String (JSON): {"stamp":..., "dets":[{"cls":"tank","conf":0.91,"x1":..,"y1":..,"x2":..,"y2":..}]}
"""
import json
import os
import sys
import threading
import time

import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib  # noqa: E402

import numpy as np  # noqa: E402
import pyds  # noqa: E402
import rclpy  # noqa: E402
from cv_bridge import CvBridge  # noqa: E402
from rclpy.node import Node  # noqa: E402
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy  # noqa: E402
from sensor_msgs.msg import Image  # noqa: E402
from std_msgs.msg import String  # noqa: E402
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose  # noqa: E402

W = int(os.environ.get("FRAME_W", 640))
H = int(os.environ.get("FRAME_H", 480))
MAX_FPS = int(os.environ.get("MAX_FPS", 15))
PGIE_CONFIG = os.environ.get("PGIE_CONFIG", "/app/config/yolo_pgie.txt")
MODEL_DIR = os.environ.get("MODEL_DIR", "/models")


def load_labels():
    p = os.path.join(MODEL_DIR, "labels.txt")
    try:
        with open(p, encoding="utf-8") as f:
            return [l.strip() for l in f if l.strip()]
    except Exception:
        return []


class Detector(Node):
    def __init__(self):
        super().__init__("maicon_detector")
        self.bridge = CvBridge()
        self.labels = load_labels()
        self.frames_in = self.frames_out = 0
        self._last_pts = 0
        self._min_dt = 1.0 / MAX_FPS

        qos = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST, depth=1)
        self.sub = self.create_subscription(Image, os.environ.get("IMAGE_TOPIC", "/image_raw"), self.on_image, qos)
        topic = os.environ.get("DETECTIONS_TOPIC", "/detections")
        self.pub = self.create_publisher(Detection2DArray, topic, 10)
        self.pub_json = self.create_publisher(String, topic + "_json", 10)
        self.create_timer(5.0, self.report)

        Gst.init(None)
        self.pipeline = self._build_pipeline()
        self.appsrc = self.pipeline.get_by_name("src")
        pad = self.pipeline.get_by_name("pgie").get_static_pad("src")
        pad.add_probe(Gst.PadProbeType.BUFFER, self._on_inferred, None)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_bus)
        self.pipeline.set_state(Gst.State.PLAYING)
        self.get_logger().info(f"pipeline PLAYING  config={PGIE_CONFIG}  labels={len(self.labels)}")

    # ------------------------------------------------------------ GStreamer
    def _build_pipeline(self):
        desc = (
            f"appsrc name=src is-live=true format=time do-timestamp=true block=false max-bytes=0 "
            f"caps=video/x-raw,format=RGB,width={W},height={H},framerate={MAX_FPS}/1 "
            f"! queue leaky=downstream max-size-buffers=1 "
            f"! nvvideoconvert ! video/x-raw(memory:NVMM),format=NV12 "
            f"! m.sink_0 nvstreammux name=m batch-size=1 width={W} height={H} live-source=1 batched-push-timeout=40000 "
            f"! nvinfer name=pgie config-file-path={PGIE_CONFIG} "
            f"! fakesink name=sink sync=false async=false"
        )
        return Gst.parse_launch(desc)

    def _on_bus(self, bus, msg):
        t = msg.type
        if t == Gst.MessageType.ERROR:
            err, dbg = msg.parse_error()
            self.get_logger().error(f"GStreamer: {err} / {dbg}")
        elif t == Gst.MessageType.WARNING:
            w, _ = msg.parse_warning()
            self.get_logger().warning(f"GStreamer: {w}")

    # ------------------------------------------------------------ ROS → appsrc
    def on_image(self, msg: Image):
        now = time.monotonic()
        if now - self._last_pts < self._min_dt:
            return  # 추론 속도보다 빨리 오는 프레임은 버림
        self._last_pts = now
        try:
            rgb = self.bridge.imgmsg_to_cv2(msg, desired_encoding="rgb8")
            if rgb.shape[1] != W or rgb.shape[0] != H:
                import cv2
                rgb = cv2.resize(rgb, (W, H))
            data = np.ascontiguousarray(rgb).tobytes()
            buf = Gst.Buffer.new_wrapped(data)
            self._stamp = msg.header.stamp
            self.appsrc.emit("push-buffer", buf)
            self.frames_in += 1
        except Exception as e:
            self.get_logger().error(f"frame push failed: {e}")

    # ------------------------------------------------------------ nvinfer → ROS
    def _on_inferred(self, pad, info, _):
        buf = info.get_buffer()
        if not buf:
            return Gst.PadProbeReturn.OK
        try:
            batch = pyds.gst_buffer_get_nvds_batch_meta(hash(buf))
            l_frame = batch.frame_meta_list
            while l_frame is not None:
                frame = pyds.NvDsFrameMeta.cast(l_frame.data)
                dets = []
                l_obj = frame.obj_meta_list
                while l_obj is not None:
                    o = pyds.NvDsObjectMeta.cast(l_obj.data)
                    r = o.rect_params
                    name = self.labels[o.class_id] if o.class_id < len(self.labels) else str(o.class_id)
                    dets.append((name, float(o.confidence), float(r.left), float(r.top),
                                 float(r.width), float(r.height)))
                    l_obj = l_obj.next
                self._publish(dets)
                l_frame = l_frame.next
        except Exception as e:
            self.get_logger().error(f"probe failed: {e}")
        return Gst.PadProbeReturn.OK

    def _publish(self, dets):
        arr = Detection2DArray()
        arr.header.stamp = getattr(self, "_stamp", None) or self.get_clock().now().to_msg()
        arr.header.frame_id = "camera"
        js = []
        for name, conf, left, top, w, h in dets:
            d = Detection2D()
            d.header = arr.header
            d.bbox.center.position.x = left + w / 2
            d.bbox.center.position.y = top + h / 2
            d.bbox.size_x = w
            d.bbox.size_y = h
            hyp = ObjectHypothesisWithPose()
            hyp.hypothesis.class_id = name
            hyp.hypothesis.score = conf
            d.results.append(hyp)
            d.id = name
            arr.detections.append(d)
            js.append({"cls": name, "conf": round(conf, 3), "x1": round(left), "y1": round(top),
                       "x2": round(left + w), "y2": round(top + h)})
        self.pub.publish(arr)
        self.pub_json.publish(String(data=json.dumps(
            {"stamp": arr.header.stamp.sec + arr.header.stamp.nanosec * 1e-9, "dets": js})))
        self.frames_out += 1

    def report(self):
        self.get_logger().info(f"frames in={self.frames_in} inferred={self.frames_out}")

    def destroy_node(self):
        try:
            self.appsrc.emit("end-of-stream")
            self.pipeline.set_state(Gst.State.NULL)
        except Exception:
            pass
        super().destroy_node()


def main():
    rclpy.init()
    node = Detector()
    loop = GLib.MainLoop()
    threading.Thread(target=loop.run, daemon=True).start()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        loop.quit()
        rclpy.shutdown()


if __name__ == "__main__":
    sys.exit(main())
