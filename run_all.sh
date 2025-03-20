#!/bin/bash

# ========================
# ROS2 Startup Script
# - Static TF Publishing
# - Launching rqt_runtime_monitor
# - Launching Autoware (with logs)
# ========================

# Function to stop all background jobs on exit
cleanup() {
  echo "Stopping all background jobs..."
  for pid in "${pids[@]}"; do
    kill "$pid"
  done
  exit
}

# Trap SIGINT (Ctrl+C) and call cleanup
trap cleanup SIGINT

# Array to store process IDs
pids=()

# ------------------------
# Static TF Publishing
# ------------------------

# map → odom
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom &
pids+=($!)

# odom → base_link
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom base_link &
pids+=($!)

# ------------------------
# Launch rqt_runtime_monitor
# ------------------------

ros2 run rqt_runtime_monitor rqt_runtime_monitor &
pids+=($!)

# ------------------------
# Launch Autoware (Foreground Execution)
# ------------------------

ros2 launch autoware_launch autoware.launch.xml \
  vehicle_model:=beamng_vehicle \
  sensor_model:=beamng_sensor_kit \
  map_path:=/home/apollo-22/Documents/autoware/autoware_map/c1/scenario_02

# Wait for all background jobs to complete
wait
