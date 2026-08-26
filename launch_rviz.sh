#!/usr/bin/env bash

set -Ee -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_SETUP="$SCRIPT_DIR/install/setup.bash"

die() {
  printf 'エラー: %s\n' "$*" >&2
  exit 1
}

[[ -f "$WORKSPACE_SETUP" ]] ||
  die "ワークスペースがビルドされていません: $WORKSPACE_SETUP"

# shellcheck disable=SC1091
source "$WORKSPACE_SETUP"

command -v ros2 >/dev/null 2>&1 ||
  die "ros2が見つかりません"
command -v rviz2 >/dev/null 2>&1 ||
  die "rviz2が見つかりません"

AUTOWARE_SHARE="$(ros2 pkg prefix --share autoware_launch 2>/dev/null)" ||
  die "autoware_launchパッケージが見つかりません"

RVIZ_CONFIG="${1:-$AUTOWARE_SHARE/rviz/autoware.rviz}"
SPLASH_IMAGE="$AUTOWARE_SHARE/rviz/image/autoware.png"

[[ -f "$RVIZ_CONFIG" ]] ||
  die "RViz設定ファイルが見つかりません: $RVIZ_CONFIG"

printf 'Autoware RVizだけを起動します。\n'
printf '  config: %s\n' "$RVIZ_CONFIG"

if [[ -f "$SPLASH_IMAGE" ]]; then
  exec rviz2 -d "$RVIZ_CONFIG" -s "$SPLASH_IMAGE"
else
  exec rviz2 -d "$RVIZ_CONFIG"
fi
