"""설치 확인. setup.ps1 마지막에 자동 실행. 직접 실행: python check_env.py desktop"""
import importlib
import sys

role = sys.argv[1] if len(sys.argv) > 1 else "laptop"
ok = True


def check(mod, label=None):
    global ok
    try:
        m = importlib.import_module(mod)
        print(f"  [OK] {label or mod} {getattr(m, '__version__', '')}")
        return m
    except Exception as e:
        ok = False
        print(f"  [X]  {label or mod}: {e}")


print(f"Python {sys.version.split()[0]}")
for mod in ["requests", "yaml", "numpy", "cv2"]:
    check(mod)

if role == "desktop":
    torch = check("torch")
    if torch:
        if torch.cuda.is_available():
            name = torch.cuda.get_device_name(0)
            x = torch.ones(2, device="cuda") * 2   # 실제 GPU 연산까지 확인 (RTX 50 호환 문제는 여기서 드러남)
            print(f"  [OK] GPU 사용 가능: {name}, 연산 결과 {x.tolist()}")
        else:
            ok = False
            print("  [X]  GPU 를 못 찾음 -> 드라이버 설치 확인, torch 가 CUDA 12.8(cu128) 빌드인지 확인")
    check("ultralytics")
    check("onnx")

print("\n결과:", "모두 정상" if ok else "문제 있음 (위 [X] 항목 확인)")
sys.exit(0 if ok else 1)
