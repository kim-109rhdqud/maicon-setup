"""team_node.py 에서 추론 컨테이너를 띄우고 끄는 모듈.

    from launch_inference import Inference
    inf = Inference(jetpack="6.1", models="/home/ugv/team/models")
    inf.start()      # 대기(standby) 단계에 호출. 이미 떠 있으면 정리하고 다시 띄움
    inf.alive()      # 살아 있나
    inf.stop()       # stop 신호에 호출

동작 방식 (순서대로 시도)
  1. docker 가 보이면: 기존 maicon-detector 컨테이너 제거 → docker run (GPU, host 네트워크)
  2. docker 가 안 보이고 이 환경에 pyds 가 있으면: detector_node.py 를 서브프로세스로 직접 실행
  3. 둘 다 안 되면: 경고만 남기고 넘어감 (경기 코드가 죽으면 안 됨)

team_node 가 비정상 종료 후 재시작(최대 3회)돼도 1번에서 남은 컨테이너를 먼저 지우므로 충돌하지 않는다.
"""
import logging
import os
import shutil
import subprocess
import time

log = logging.getLogger("inference")
NAME = "maicon-detector"
HERE = os.path.dirname(os.path.abspath(__file__))


class Inference:
    def __init__(self, jetpack="6.1", models=None, image=None, ros_domain_id=None,
                 image_topic="/image_raw", detections_topic="/detections"):
        self.image = image or f"maicon-detector:jp{jetpack}"
        self.models = os.path.abspath(models or os.path.expanduser("~/team/models"))
        self.domain = str(ros_domain_id if ros_domain_id is not None else os.environ.get("ROS_DOMAIN_ID", "0"))
        self.image_topic = image_topic
        self.detections_topic = detections_topic
        self.mode = None
        self._proc = None

    # ------------------------------------------------------------------ 공개
    def start(self):
        try:
            if self._docker_ok():
                return self._start_docker()
            if self._local_ok():
                return self._start_local()
            log.warning("추론을 띄울 방법이 없음: docker 소켓도 pyds 도 없음. 탐지 없이 진행")
            self.mode = None
            return False
        except Exception as e:
            log.error("추론 시작 실패: %s", e)
            return False

    def alive(self):
        try:
            if self.mode == "docker":
                out = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", NAME],
                                     capture_output=True, text=True, timeout=5).stdout.strip()
                return out == "true"
            if self.mode == "local":
                return self._proc is not None and self._proc.poll() is None
        except Exception:
            pass
        return False

    def stop(self):
        try:
            if self.mode == "docker":
                subprocess.run(["docker", "rm", "-f", NAME], capture_output=True, timeout=20)
            elif self.mode == "local" and self._proc:
                self._proc.terminate()
                try:
                    self._proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
        except Exception as e:
            log.warning("추론 종료 중 오류: %s", e)
        self.mode = None

    # ------------------------------------------------------------------ 내부
    @staticmethod
    def _docker_ok():
        if not shutil.which("docker"):
            return False
        try:
            return subprocess.run(["docker", "info"], capture_output=True, timeout=10).returncode == 0
        except Exception:
            return False

    @staticmethod
    def _local_ok():
        try:
            import pyds  # noqa: F401
            return True
        except Exception:
            return False

    def _start_docker(self):
        subprocess.run(["docker", "rm", "-f", NAME], capture_output=True, timeout=20)  # 남은 것 정리
        have = subprocess.run(["docker", "image", "inspect", self.image], capture_output=True).returncode == 0
        if not have:
            log.error("이미지 없음: %s  (load.sh 로 먼저 불러올 것)", self.image)
            return False
        cmd = ["docker", "run", "-d", "--rm", "--name", NAME,
               "--runtime", "nvidia", "--network", "host", "--ipc", "host",
               "-e", f"ROS_DOMAIN_ID={self.domain}",
               "-e", f"IMAGE_TOPIC={self.image_topic}", "-e", f"DETECTIONS_TOPIC={self.detections_topic}",
               "-v", f"{self.models}:/models", self.image]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            log.error("docker run 실패: %s", r.stderr.strip())
            return False
        self.mode = "docker"
        time.sleep(1.0)
        log.info("추론 컨테이너 시작 (%s, 모델 %s)", self.image, self.models)
        return self.alive()

    def _start_local(self):
        env = dict(os.environ, ROS_DOMAIN_ID=self.domain, MODEL_DIR=self.models,
                   IMAGE_TOPIC=self.image_topic, DETECTIONS_TOPIC=self.detections_topic,
                   PGIE_CONFIG=os.path.join(HERE, "..", "config", "yolo_pgie.txt"))
        script = os.path.join(HERE, "..", "detector", "detector_node.py")
        self._proc = subprocess.Popen(["python3", script], env=env)
        self.mode = "local"
        log.info("추론 노드 직접 실행 (pid %s)", self._proc.pid)
        return True
