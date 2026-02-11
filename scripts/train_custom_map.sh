#!/bin/bash
# Train Go2 policy on custom competition maps (K-Rails + Ramps OBJ meshes)
#
# Resumes from an earlier rough terrain checkpoint (model_5500.pt) with
# stronger smoothness penalties to fix jerky/unstable movements.
#
# Changes from previous training:
#   - action_rate penalty:  -0.05 → -0.5  (10x stronger)
#   - action_smoothness:    NEW at -0.5    (penalizes second-order jerk)
#   - action_scale:         0.25 → 0.15   (smaller joint movements per step)
#   - Resume from model_5500 (earlier, less specialized checkpoint)
#
# Usage:
#   bash ~/robotics/projects/Dias/scripts/train_custom_map.sh
#
# Monitor:
#   tail -f the terminal output, or:
#   tensorboard --logdir ~/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/

set -e

ISAACLAB_DIR="$HOME/robotics/projects/Dias/unitree_rl_lab"
LOAD_RUN="2026-02-07_06-49-57"
CHECKPOINT="model_5500.pt"

echo "=== Custom Map Training (Smooth v1) ==="
echo "  Task:       Unitree-Go2-Custom-Map"
echo "  Maps:       K_Rails_Map.obj + k_ramps.obj"
echo "  Resume:     $LOAD_RUN / $CHECKPOINT"
echo "  Key changes: action_rate=-0.5, smoothness=-0.5, scale=0.15"
echo "  Envs:       4096"
echo ""

eval "$(conda shell.bash hook 2>/dev/null)"
conda activate isaaclab_go2
cd "$ISAACLAB_DIR"

PYTHONUNBUFFERED=1 python -u scripts/rsl_rl/train.py \
    --task Unitree-Go2-Custom-Map \
    --num_envs 4096 \
    --resume \
    --load_run "$LOAD_RUN" \
    --checkpoint "$CHECKPOINT" \
    --headless
