#!/bin/bash
# Launch TensorBoard for all training runs
#
# Usage:
#   bash ~/robotics/projects/Dias/scripts/tensorboard.sh

eval "$(conda shell.bash hook 2>/dev/null)"
conda activate isaaclab_go2

tensorboard \
    --logdir ~/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/ \
    --port 6006 \
    --bind_all
