#!/bin/bash
# Export a portable MuJoCo deployment package
# Everything needed to run the Go2 policy on another machine
#
# Usage:
#   bash ~/robotics/projects/Dias/scripts/export_mujoco_package.sh [output_dir]
#
# Dependencies on target machine: mujoco, onnxruntime, numpy, pygame

set -e

OUT="${1:-$HOME/robotics/projects/Dias/mujoco_deploy_package}"

echo "=== Exporting MuJoCo Deploy Package ==="
echo "  Output: $OUT"
echo ""

rm -rf "$OUT"
mkdir -p "$OUT"

# --- Robot XML + meshes ---
mkdir -p "$OUT/unitree_robots/go2/assets"
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/go2.xml "$OUT/unitree_robots/go2/"
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene.xml "$OUT/unitree_robots/go2/"
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_k_ramps.xml "$OUT/unitree_robots/go2/"
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_competition.xml "$OUT/unitree_robots/go2/"
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_terrain.xml "$OUT/unitree_robots/go2/" 2>/dev/null || true
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_krails.xml "$OUT/unitree_robots/go2/" 2>/dev/null || true
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_ramps.xml "$OUT/unitree_robots/go2/" 2>/dev/null || true
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/scene_pallets.xml "$OUT/unitree_robots/go2/" 2>/dev/null || true

# Robot body meshes
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/assets/*.obj "$OUT/unitree_robots/go2/assets/"

# K-ramps meshes (referenced by scene_k_ramps.xml)
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/k_ramps_Body29.obj "$OUT/unitree_robots/go2/" 2>/dev/null || true
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/k_ramps_Body53.obj "$OUT/unitree_robots/go2/" 2>/dev/null || true

# Height field textures
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/height_field.png "$OUT/unitree_robots/go2/" 2>/dev/null || true
cp ~/robotics/projects/Dias/unitree_mujoco/unitree_robots/go2/unitree_hfield.png "$OUT/unitree_robots/go2/" 2>/dev/null || true

# --- Python runner ---
mkdir -p "$OUT/simulate_python"
cp ~/robotics/projects/Dias/unitree_mujoco/simulate_python/run_policy.py "$OUT/simulate_python/"

# --- Competition map OBJs ---
mkdir -p "$OUT/Maps/3D"
cp ~/robotics/projects/Dias/Maps/3D/K_Rails_Map.obj "$OUT/Maps/3D/" 2>/dev/null || true
cp ~/robotics/projects/Dias/Maps/3D/K_Rails_Map.mtl "$OUT/Maps/3D/" 2>/dev/null || true
cp ~/robotics/projects/Dias/Maps/3D/k_ramps.obj "$OUT/Maps/3D/" 2>/dev/null || true
cp ~/robotics/projects/Dias/Maps/3D/k_ramps.mtl "$OUT/Maps/3D/" 2>/dev/null || true

# --- Exported policies ---
mkdir -p "$OUT/policies"
cp ~/robotics/projects/Dias/exported/policy_16500.onnx "$OUT/policies/" 2>/dev/null || true
cp ~/robotics/projects/Dias/exported/velocity_stable_6600/policy.onnx "$OUT/policies/policy_velocity_stable_6600.onnx" 2>/dev/null || true
# Copy latest ramps traverse if it exists
LATEST_RAMPS=$(ls -t ~/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/unitree_go2_ramps_traverse/*/model_*.pt 2>/dev/null | head -1)
if [ -n "$LATEST_RAMPS" ]; then
    echo "  Latest ramps checkpoint: $LATEST_RAMPS"
    echo "  (Export to ONNX separately with scripts/export_onnx.py)"
fi

# --- Export script ---
cp ~/robotics/projects/Dias/scripts/export_onnx.py "$OUT/"

# --- README ---
cat > "$OUT/README.txt" << 'READMEEOF'
MuJoCo Go2 Deploy Package
==========================

Requirements:
  pip install mujoco onnxruntime numpy pygame

Run:
  cd simulate_python
  python run_policy.py --policy ../policies/policy_16500.onnx --scene ../unitree_robots/go2/scene_k_ramps.xml --zone flat

Scenes:
  scene.xml            - flat ground
  scene_k_ramps.xml    - ramps obstacle course
  scene_competition.xml - full 3-zone competition map
  scene_krails.xml     - K-Rails obstacle

Policies:
  policy_16500.onnx                - best rough terrain model
  policy_velocity_stable_6600.onnx - stable locomotion model

Export new policy from checkpoint:
  python export_onnx.py <path/to/model_XXXX.pt> policies/my_policy.onnx
READMEEOF

# --- Show result ---
echo ""
echo "=== Package contents ==="
find "$OUT" -type f | sort | while read f; do
    SIZE=$(du -h "$f" | cut -f1)
    echo "  $SIZE  ${f#$OUT/}"
done

TOTAL=$(du -sh "$OUT" | cut -f1)
echo ""
echo "=== Done! Total size: $TOTAL ==="
echo "  Copy '$OUT' to another machine and follow README.txt"
