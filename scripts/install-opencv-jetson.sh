#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="${OPENCV_VERSION:-4.10.0}"
WORKSPACE="${OPENCV_WORKSPACE:-${HOME}/Downloads/workspace}"
OPENCV_SOURCE="${WORKSPACE}/opencv-${VERSION}"
CONTRIB_SOURCE="${WORKSPACE}/opencv_contrib-${VERSION}"
BUILD_DIR="${OPENCV_SOURCE}/release"
INSTALL_PREFIX="${OPENCV_INSTALL_PREFIX:-/usr/local}"
CUDA_ARCH_BIN="8.7"
JOBS="${JOBS:-4}"

trap 'echo "Error: line ${LINENO}: command failed." >&2' ERR

if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "ERROR: this installer is intended for Jetson ARM64 (aarch64)." >&2
    exit 1
fi

if ! [[ $JOBS =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: JOBS must be a positive integer: $JOBS" >&2
    exit 1
fi

echo "===================================="
echo " OpenCV ${VERSION} Jetson installer"
echo "===================================="
echo "Source directory : ${WORKSPACE}"
echo "Install prefix   : ${INSTALL_PREFIX}"
echo "CUDA architecture: ${CUDA_ARCH_BIN}"
echo "Build jobs       : ${JOBS}"
echo

while true; do
    read -r -p "既存のAPT版OpenCVを削除しますか？ [yes/no]: " remove_old

    case "$remove_old" in
    yes)
        echo
        echo "削除予定パッケージをシミュレーションします。"
        echo "ROS 2、JetPackなどが含まれていないことを確認してください。"
        echo
        sudo apt-get --simulate purge 'libopencv*'
        echo
        read -r -p "上記のパッケージを実際に削除しますか？ [yes/no]: " confirm
        if [[ $confirm == "yes" ]]; then
            sudo apt-get -y purge 'libopencv*'
            sudo apt-get -y autoremove
        else
            echo "既存OpenCVの削除を中止します。"
        fi
        break
        ;;
    no)
        echo "既存OpenCVを残します。"
        break
        ;;
    *)
        echo "yes または no を入力してください。"
        ;;
    esac
done

sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    curl \
    git \
    libavcodec-dev \
    libavformat-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer1.0-dev \
    libgtk2.0-dev \
    libjpeg-dev \
    libpng-dev \
    libswscale-dev \
    libtbb-dev \
    libtiff-dev \
    libv4l-dev \
    pkg-config \
    python3-dev \
    python3-numpy \
    qv4l2 \
    unzip \
    v4l-utils

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

rm -rf -- "$OPENCV_SOURCE" "$CONTRIB_SOURCE"
rm -f -- "opencv-${VERSION}.zip" "opencv_contrib-${VERSION}.zip"

curl --fail --location \
    "https://github.com/opencv/opencv/archive/${VERSION}.zip" \
    --output "opencv-${VERSION}.zip"
curl --fail --location \
    "https://github.com/opencv/opencv_contrib/archive/${VERSION}.zip" \
    --output "opencv_contrib-${VERSION}.zip"

unzip -q "opencv-${VERSION}.zip"
unzip -q "opencv_contrib-${VERSION}.zip"
rm -f -- "opencv-${VERSION}.zip" "opencv_contrib-${VERSION}.zip"

normalize_bbox_file="${OPENCV_SOURCE}/modules/dnn/src/cuda4dnn/primitives/normalize_bbox.hpp"
region_file="${OPENCV_SOURCE}/modules/dnn/src/cuda4dnn/primitives/region.hpp"

sed -i \
    's/if (weight != 1\.0)/if (weight != static_cast<T>(1.0f))/' \
    "$normalize_bbox_file"
sed -i \
    's/if (nms_iou_threshold > 0)/if (nms_iou_threshold > static_cast<T>(0.0f))/' \
    "$region_file"

grep -Fq 'weight != static_cast<T>(1.0f)' "$normalize_bbox_file"
grep -Fq 'nms_iou_threshold > static_cast<T>(0.0f)' "$region_file"

rm -rf -- "$BUILD_DIR"

cmake \
    -S "$OPENCV_SOURCE" \
    -B "$BUILD_DIR" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -D OPENCV_EXTRA_MODULES_PATH="${CONTRIB_SOURCE}/modules" \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    -D WITH_CUDA=ON \
    -D WITH_CUDNN=ON \
    -D WITH_CUBLAS=ON \
    -D OPENCV_DNN_CUDA=ON \
    -D CUDA_ARCH_BIN="$CUDA_ARCH_BIN" \
    -D CUDA_ARCH_PTX="" \
    -D ENABLE_FAST_MATH=ON \
    -D CUDA_FAST_MATH=ON \
    -D WITH_GSTREAMER=ON \
    -D WITH_LIBV4L=ON \
    -D WITH_TBB=ON \
    -D BUILD_opencv_python3=ON \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_EXAMPLES=OFF \
    -D BUILD_JAVA=OFF

cmake --build "$BUILD_DIR" --parallel "$JOBS"
sudo cmake --install "$BUILD_DIR"
sudo ldconfig

if [[ ! -f "${INSTALL_PREFIX}/include/opencv4/opencv2/ximgproc/segmentation.hpp" ]]; then
    echo "ERROR: ximgproc/segmentation.hpp が見つかりません。" >&2
    exit 1
fi

if ! find "${INSTALL_PREFIX}/lib" \
    -maxdepth 1 \
    -name 'libopencv_ximgproc.so*' \
    -print \
    -quit | grep -q .; then
    echo "ERROR: libopencv_ximgproc.so が見つかりません。" >&2
    exit 1
fi

echo
echo "OpenCV pkg-config:"
PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion opencv4

echo
echo "Python OpenCV:"
python3 - <<'PY'
import cv2

print("OpenCV version:", cv2.__version__)
print("cv2 path:", cv2.__file__)
print("CUDA devices:", cv2.cuda.getCudaEnabledDeviceCount())
PY

echo
echo "OpenCV ${VERSION} installation completed."
echo "Export these variables before building Autoware:"
echo "  export OpenCV_DIR=${INSTALL_PREFIX}/lib/cmake/opencv4"
echo "  export PKG_CONFIG_PATH=${INSTALL_PREFIX}/lib/pkgconfig:\${PKG_CONFIG_PATH:-}"
echo "  export LD_LIBRARY_PATH=${INSTALL_PREFIX}/lib:\${LD_LIBRARY_PATH:-}"
