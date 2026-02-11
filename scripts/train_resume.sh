#!/bin/bash
# Resume training from model_10700 with tuned config:
#   - base_contact threshold: 1.0 -> 10.0
#   - terrain: boxes_high 20% -> boxes_mid 10% + boxes_high 10%
#   - terrain rows: 10 -> 20 (finer curriculum)
#   - curriculum demotion: OR -> AND (softer demotion)
cd /home/robotics-1/robotics/projects/Dias/unitree_rl_lab
conda activate isaaclab_go2
./unitree_rl_lab.sh -t --task Unitree-Go2-Velocity-Rough \
  --resume --load_run 2026-02-08_14-46-19 --checkpoint model_10700.pt
