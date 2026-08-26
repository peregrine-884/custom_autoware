# Jetson AGX Orin セットアップ手順

この手順では、NVIDIA Jetson AGX Orin上に本Autowareフォークをネイティブ環境で
インストールし、ビルドします。対象環境はUbuntu 22.04（`aarch64`）および
ROS 2 Humbleです。

JetPackがインストール済みで、JetPackに含まれるCUDA、cuDNN、TensorRTが正常に
動作していることを前提とします。AutowareのAnsible Playbookで、これらの
Jetson専用パッケージを置き換えないようにしてください。

## 1. Jetson環境の確認

システムへ変更を加える前に、次のコマンドを実行します。

```bash
uname -m
. /etc/os-release && echo "$PRETTY_NAME"
nvcc --version
dpkg-query -W 'nvidia-jetpack' 'libnvinfer*' 2>/dev/null | head
```

`aarch64`、Ubuntu 22.04、およびインストール済みのCUDA/TensorRTパッケージが
表示されることを確認してください。不足している場合は、先にJetPack環境を
修復します。

## 2. リポジトリの取得

すでにリポジトリを取得済みの場合、この手順は不要です。

```bash
git clone --branch agile-x \
  https://github.com/peregrine-884/custom_autoware.git
cd custom_autoware
```

以降のコマンドは、特記がない限りリポジトリのルートで実行します。

## 3. Autoware開発環境のインストール

Ansibleと、このリポジトリで使用するAnsible Collectionをインストールします。

```bash
bash ansible/scripts/install-ansible.sh
export PATH="$HOME/.local/bin:$PATH"
ansible-galaxy collection install -f \
  -r ansible-galaxy-requirements.yaml
```

開発環境用Playbookを実行します。CUDAとTensorRTはJetPackが管理するため、
該当するロールをスキップします。`spconv_is_jetson=true`を指定すると、
ARMサーバー用ではなくJetson用のspconvパッケージが選択されます。

```bash
ansible-playbook autoware.dev_env.install_dev_env \
  --ask-become-pass \
  --skip-tags cuda,tensorrt \
  -e spconv_is_jetson=true
```

このリポジトリが指定するCUDA/TensorRTと、使用中のJetPackとの互換性を確認せずに
`--skip-tags cuda,tensorrt`を外さないでください。

Playbookの完了後、新しいターミナルを開くか、現在のシェルを再読み込みします。

```bash
source "$HOME/.bashrc"
source /opt/ros/humble/setup.bash
```

必要なツールを確認します。

```bash
ansible --version
ros2 --help >/dev/null
vcs --help >/dev/null
colcon --help >/dev/null
```

## 4. ソースリポジトリの取得

```bash
mkdir -p src
vcs import src < repositories/autoware.repos
```

取得処理が中断された場合は、再実行する前に`vcs status src`で状態を確認します。
ローカル変更がある場合は、`src`を削除しないでください。

## 5. ROS依存パッケージのインストール

UbuntuとROSの既存パッケージを更新し、インポートした各パッケージで宣言されている
依存関係を`rosdep`でインストールします。

```bash
sudo apt-get update
sudo apt-get upgrade

source /opt/ros/humble/setup.bash
rosdep update
rosdep install -y \
  --from-paths src \
  --ignore-src \
  --rosdistro humble
```

`apt-get upgrade`を承認する前に、表示される更新対象を確認してください。カーネル、
JetPack、CUDA、NVIDIA関連パッケージが更新された場合はJetsonを再起動します。

## 6. 任意: CUDA対応OpenCV 4.10のインストール

使用するセンサーまたはPerceptionパッケージがOpenCV contribモジュールや
CUDA対応OpenCVを必要としない場合、Ubuntu標準のOpenCVを使用できます。
必要な場合は、Jetson向けのソースインストーラーを実行します。

```bash
./scripts/install-opencv-jetson.sh
```

デフォルトでは4並列でビルドします。メモリ不足になる場合は並列数を減らします。

```bash
JOBS=2 ./scripts/install-opencv-jetson.sh
```

インストーラーは、APT版OpenCVを削除する前に削除シミュレーションと確認を行います。
削除対象にROS 2、JetPack、その他必要なパッケージが含まれる場合は`no`を選択して
ください。

インストール後、カスタムOpenCVのパスを設定します。

```bash
export OpenCV_DIR=/usr/local/lib/cmake/opencv4
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}
export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}
```

## 7. Autowareのビルド

Jetsonのメモリ不足を避けるため、パッケージ単位とコンパイラーの両方で並列数を
制限します。空きメモリを確認してから、必要に応じて値を増やしてください。

```bash
source /opt/ros/humble/setup.bash

export OpenCV_DIR=/usr/local/lib/cmake/opencv4
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}
export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}
export CMAKE_BUILD_PARALLEL_LEVEL=4

colcon build \
  --symlink-install \
  --parallel-workers 2 \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=Release \
    -DOpenCV_DIR="$OpenCV_DIR"
```

手順6の`/usr/local`版OpenCVをインストールしていない場合は、3つのOpenCV環境変数と
`-DOpenCV_DIR=...`を省略してください。

## 8. ビルド結果の確認と起動

```bash
source install/setup.bash
ros2 pkg prefix autoware_launch
ros2 pkg prefix agilex_vehicle_launch
```

`lanelet2_map.osm`と`pointcloud_map.pcd`を含む地図を
`$HOME/autoware_data/maps`以下に配置して起動します。

```bash
./launch_autoware.sh
```

別の地図ディレクトリを使用する場合は、次のように指定します。

```bash
AUTOWARE_MAPS_DIR=/path/to/maps ./launch_autoware.sh
```

ビルド後にRVizだけを起動する場合は、次のコマンドを使用します。

```bash
./launch_rviz.sh
```

## トラブルシューティング

### ビルドが強制終了する、またはJetsonが応答しなくなる

並列数を減らして再度ビルドします。

```bash
export CMAKE_BUILD_PARALLEL_LEVEL=2
colcon build --symlink-install --parallel-workers 1 \
  --cmake-args -DCMAKE_BUILD_TYPE=Release
```

### CMakeが意図しないOpenCVを検出する

```bash
pkg-config --modversion opencv4
python3 -c 'import cv2; print(cv2.__version__, cv2.__file__)'
find /usr/local/lib/cmake/opencv4 -maxdepth 1 -type f -print
```

確認後、問題が発生したパッケージのビルドディレクトリだけを削除して再ビルドします。
未コミットの作業がある場合、ワークスペース全体を削除しないでください。

### 起動エラーを確認する

`launch_autoware.sh`は、実行したディレクトリに`autoware.log`を出力します。
警告やプロセス異常は、次のコマンドで確認できます。

```bash
./check_log.sh autoware.log
```
