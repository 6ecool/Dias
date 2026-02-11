#!/bin/bash
# Run policy in MuJoCo on competition map with joystick
#
# Usage:
#   ./scripts/run_mujoco.sh                  # K-Rails zone (default)
#   ./scripts/run_mujoco.sh ramps            # Ramps zone
#   ./scripts/run_mujoco.sh pallets          # Pallets zone
#   ./scripts/run_mujoco.sh flat             # Flat ground
#   ./scripts/run_mujoco.sh krails /path/to/other_policy.onnx
#
# Controls:
#   Joystick: Left stick = move, Right stick = yaw
#   Keyboard: W/S = forward/back, A/D = strafe, Q/E = turn

set -e

ZONE="${1:-krails}"
POLICY="${2:-$HOME/robotics/projects/Dias/exported/policy.onnx}"
SCENE="$HOME/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_competition.xml"
SCRIPT="$HOME/robotics/projects/Dias/unitree_mujoco/simulate_python/run_policy.py"

echo "=== MuJoCo Go2 Competition Runner ==="
echo "  Policy: $POLICY"
echo "  Scene:  competition (3 zones)"
echo "  Zone:   $ZONE"
echo ""
echo "  Controls:"
echo "    Left stick  = move (forward/back/strafe)"
echo "    Right stick = yaw (turn)"
echo "    Keyboard:   WASD + QE"
echo ""

cd "$HOME/robotics/projects/Dias/unitree_mujoco/simulate_python"
python3 run_policy.py --policy "$POLICY" --scene "$SCENE" --zone "$ZONE"
