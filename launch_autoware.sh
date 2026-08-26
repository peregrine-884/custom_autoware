#!/usr/bin/env bash

set -Ee -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MAPS_DIR="${AUTOWARE_MAPS_DIR:-${HOME}/autoware_data/maps}"
LAUNCH_FILE="${AUTOWARE_LAUNCH_FILE:-autoware.launch.xml}"
SCOUT_SCRIPTS_DIR="$SCRIPT_DIR/src/launcher/autoware_launch/vehicle/external/scout_ros2/scripts"

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 1
}

choose_item() {
  local prompt="$1"
  shift
  local -a items=("$@")
  local answer index

  printf '\n%sを選択してください:\n' "$prompt"
  for index in "${!items[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${items[index]}"
  done

  while true; do
    printf '> '
    read -r answer || die "入力を読み取れませんでした"
    if [[ "$answer" =~ ^[0-9]+$ ]] &&
      ((answer >= 1 && answer <= ${#items[@]})); then
      SELECTED_ITEM="${items[answer - 1]}"
      return
    fi
    printf '1〜%dの番号を入力してください。\n' "${#items[@]}" >&2
  done
}

setup_agilex_can() {
  local can_script="$SCOUT_SCRIPTS_DIR/scout_mini_can.sh"

  [[ -x "$can_script" ]] ||
    die "SCOUT MINI CANスクリプトを実行できません: $can_script"

  printf '\nSCOUT MINI用CANをセットアップします。\n'
  "$can_script"
}

# Always use the Autoware workspace that contains this launcher.
WORKSPACE_SETUP="$SCRIPT_DIR/install/setup.bash"
[[ -f "$WORKSPACE_SETUP" ]] ||
  die "ワークスペースがビルドされていません: $WORKSPACE_SETUP
次を実行してください:
  cd $SCRIPT_DIR
  colcon build --symlink-install"

# shellcheck disable=SC1091
source "$WORKSPACE_SETUP"

command -v ros2 >/dev/null 2>&1 ||
  die "ros2が見つかりません。Autoware環境をsourceしてから実行してください"
[[ -d "$MAPS_DIR" ]] ||
  die "mapディレクトリがありません: $MAPS_DIR"

mapfile -t package_names < <(ros2 pkg list | LC_ALL=C sort)

declare -a vehicle_models=()
declare -a sensor_models=()
for package_name in "${package_names[@]}"; do
  if [[ "$package_name" == *_vehicle_description ]]; then
    model="${package_name%_description}"
    if ros2 pkg prefix "${model}_launch" >/dev/null 2>&1; then
      vehicle_models+=("$model")
    fi
  elif [[ "$package_name" == *_sensor_kit_description ]]; then
    model="${package_name%_description}"
    if ros2 pkg prefix "${model}_launch" >/dev/null 2>&1; then
      sensor_models+=("$model")
    fi
  fi
done

((${#vehicle_models[@]} > 0)) ||
  die "利用可能なvehicle modelが見つかりません。
ソースは存在しますが、ROS 2環境にインストールされていない可能性があります。
次を実行してから再度お試しください:
  cd $SCRIPT_DIR
  colcon build --symlink-install
  source install/setup.bash"
((${#sensor_models[@]} > 0)) ||
  die "利用可能なsensor modelが見つかりません。
colcon build --symlink-install を実行し、install/setup.bashをsourceしてください"

declare -a map_paths=()
while IFS= read -r -d '' lanelet_file; do
  map_dir="${lanelet_file%/*}"
  if [[ -f "$map_dir/pointcloud_map.pcd" ]]; then
    map_paths+=("$map_dir")
  fi
done < <(find "$MAPS_DIR" -type f -name lanelet2_map.osm -print0 | sort -z)

((${#map_paths[@]} > 0)) ||
  die "$MAPS_DIR 配下にlanelet2_map.osmとpointcloud_map.pcdが揃ったmapがありません"

choose_item "vehicle" "${vehicle_models[@]}"
vehicle_model="$SELECTED_ITEM"

choose_item "sensor" "${sensor_models[@]}"
sensor_model="$SELECTED_ITEM"

declare -a map_labels=()
for map_path in "${map_paths[@]}"; do
  map_labels+=("${map_path#"$MAPS_DIR"/}")
done
choose_item "map" "${map_labels[@]}"
selected_map_label="$SELECTED_ITEM"

map_path=""
for index in "${!map_labels[@]}"; do
  if [[ "${map_labels[index]}" == "$selected_map_label" ]]; then
    map_path="${map_paths[index]}"
    break
  fi
done
[[ -n "$map_path" ]] || die "選択されたmapのパスを解決できませんでした"

printf '\n以下の設定でAutowareを起動します。\n'
printf '  launch : %s\n' "$LAUNCH_FILE"
printf '  vehicle: %s\n' "$vehicle_model"
printf '  sensor : %s\n' "$sensor_model"
printf '  map    : %s\n' "$map_path"
printf '続行しますか? [Y/n] '
read -r confirmation || die "入力を読み取れませんでした"
if [[ -n "$confirmation" && ! "$confirmation" =~ ^[Yy]$ ]]; then
  printf 'キャンセルしました。\n'
  exit 0
fi

if [[ "$vehicle_model" == "agilex_vehicle" ]]; then
  setup_agilex_can
fi

exec ros2 launch autoware_launch "$LAUNCH_FILE" \
  "vehicle_model:=$vehicle_model" \
  "sensor_model:=$sensor_model" \
  "map_path:=$map_path" \
  2>&1 | tee autoware.log
