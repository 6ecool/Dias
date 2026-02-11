#!/bin/bash
# Train ramps traverse: goal-directed traversal on competition ramps map
# Resumes from best rough terrain model (model_16500) for terrain handling
#
# Usage:
#   bash ~/robotics/projects/Dias/scripts/train_ramps_traverse.sh

set -e

cd ~/robotics/projects/Dias/unitree_rl_lab

# Best rough terrain checkpoint — can walk + handle terrain
LOAD_RUN="2026-02-07_01-04-19"
CHECKPOINT="model_3400.pt"

echo "=== Ramps Traverse Training ==="
echo "  Task:       Unitree-Go2-Ramps-Traverse"
echo "  Resume:     $LOAD_RUN / $CHECKPOINT"
echo "  Terrain:    Built-in ramps (ascending/descending slopes + steps)"
echo "  Episodes:   60 seconds"
echo "  Reward:     forward_progress (no velocity tracking)"
echo "  Envs:       4096"
echo ""

source activate isaaclab_go2 2>/dev/null || conda activate isaaclab_go2 2>/dev/null || true

python -u scripts/rsl_rl/train.py \
    --task Unitree-Go2-Ramps-Traverse \
    --num_envs 4096 \
    --resume \
    --load_run "$LOAD_RUN" \
    --checkpoint "$CHECKPOINT" \
    --headless
