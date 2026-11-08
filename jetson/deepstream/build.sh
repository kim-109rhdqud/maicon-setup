#!/usr/bin/env bash
# 이미지 빌드 + tar 저장.  ARM64 리눅스(AWS Graviton 등)에서 실행. x86 이면 buildx 로 에뮬레이션(느림).
#   ./build.sh 6.1            # JetPack 6.1 용
#   ./build.sh all            # 6.0 6.1 6.2 세 벌
#   SAVE=0 ./build.sh 6.1     # tar 저장 생략
# 결과: 이미지 maicon-detector:jp<버전>, 파일 tars/maicon-detector-jp<버전>.tar
set -euo pipefail
cd "$(dirname "$0")"
source versions.env
SAVE="${SAVE:-1}"

build_one() {
  local jp="$1"
  local key="JP${jp/./}"
  local image="${key}_DS_IMAGE"
  local cuda="${key}_CUDA_VER"
  local pyds="${key}_PYDS_VER"
  local wheel="${key}_PYDS_WHEEL"
  local tag="maicon-detector:jp${jp}"
  echo "=== JetPack ${jp}: base ${!image}, CUDA ${!cuda}, pyds ${!pyds}"
  local args=(--build-arg "DS_IMAGE=${!image}" --build-arg "JETPACK=${jp}" --build-arg "CUDA_VER=${!cuda}"
              --build-arg "PYDS_VER=${!pyds}" --build-arg "PYDS_WHEEL=${!wheel}" -t "$tag" .)
  if [ "$(uname -m)" = "aarch64" ]; then
    docker build "${args[@]}"
  else
    echo "x86 호스트 → buildx 에뮬레이션 (매우 느림). 처음이면: docker run --privileged --rm tonistiigi/binfmt --install arm64"
    docker buildx build --platform linux/arm64 --load "${args[@]}"
  fi
  docker image inspect "$tag" --format '이미지 {{.RepoTags}} {{.Architecture}} {{printf "%.1f" (divf .Size 1073741824)}} GB'
  if [ "$SAVE" = 1 ]; then
    mkdir -p tars
    local out="tars/maicon-detector-jp${jp}.tar"
    echo "저장: $out"
    docker save -o "$out" "$tag"
    sha256sum "$out" > "$out.sha256"
    ls -lh "$out"
  fi
}

case "${1:-}" in
  6.0|6.1|6.2) build_one "$1" ;;
  all) for v in 6.0 6.1 6.2; do build_one "$v"; done ;;
  *) echo "사용법: $0 {6.0|6.1|6.2|all}"; exit 1 ;;
esac
