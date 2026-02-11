#!/bin/bash
# Train Go2 policy on competition final map (realnaya_huinya.obj)
#
# Snake/zigzag path: 5.28m × 2.72m × 0.75m walls, 3-4 turns
# Resumes from model_16500 (best rough terrain — height scan + obstacle handling)
# Traversal-dominated rewards: robot MUST make forward X progress
#
# Usage:
#   bash ~/robotics/projects/Dias/scripts/train_competition_final.sh
#
# Monitor:
#   tensorboard --logdir ~/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/

set -e

ISAACLAB_DIR="$HOME/robotics/projects/Dias/unitree_rl_lab"
LOAD_RUN="2026-02-08_19-48-15"
CHECKPOINT="model_16500.pt"

echo "=== Competition Final Training ==="
echo "  Task:       Unitree-Go2-Competition-Final"
echo "  Map:        realnaya_huinya.obj (5.28m zigzag, 0.75m walls)"
echo "  Resume:     $LOAD_RUN / $CHECKPOINT"
echo "  Rewards:    traversal=1.5, completion=3.0, goal_prox=0.5, vel=0.5"
echo "  Commands:   vx=(0.15,0.4), vy=(-0.2,0.2), vyaw=(-1.0,1.0)"
echo "  Episodes:   60s"
echo "  Envs:       4096"
echo ""

# Initialize conda
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate isaaclab_go2
cd "$ISAACLAB_DIR"

PYTHONUNBUFFERED=1 python -u scripts/rsl_rl/train.py \
    --task Unitree-Go2-Competition-Final \
    --num_envs 4096 \
    --resume \
    --load_run "$LOAD_RUN" \
    --checkpoint "$CHECKPOINT" \
    --headless
