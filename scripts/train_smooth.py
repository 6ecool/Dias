#!/usr/bin/env python3
"""
Launch stable/smooth custom map training from model_5500.

Run from the isaaclab_go2 conda environment:
    conda activate isaaclab_go2
    python ~/robotics/projects/Dias/scripts/train_smooth.py

Changes vs previous training:
    - action_rate:       -0.05 → -0.5  (10x stronger)
    - action_smoothness: NEW at -0.5   (second-order jerk penalty)
    - action_scale:      0.25 → 0.15  (smaller joint movements)
    - track_lin_vel_xy:  2.0 → 1.0    (speed not priority)
    - base_lin_vel_z:    -0.3 → -1.0  (no vertical bounce)
    - orientation:       -0.1 → -0.5  (stay flat)
    - Resume from model_5500 (earlier checkpoint)
"""

import os
import subprocess
import sys

ISAACLAB_DIR = os.path.expanduser("~/robotics/projects/Dias/unitree_rl_lab")
LOAD_RUN = "2026-02-07_06-49-57"
CHECKPOINT = "model_5500.pt"
TASK = "Unitree-Go2-Custom-Map"
NUM_ENVS = 4096

def main():
    # Verify we're in the right directory / env
    checkpoint_path = os.path.join(
        ISAACLAB_DIR, "logs", "rsl_rl", "unitree_go2_custom_map",
        LOAD_RUN, CHECKPOINT
    )
    if not os.path.exists(checkpoint_path):
        print(f"ERROR: Checkpoint not found at {checkpoint_path}")
        print("Make sure the symlink exists. Run:")
        print(f"  ln -s {ISAACLAB_DIR}/logs/rsl_rl/unitree_go2_velocity_rough/{LOAD_RUN} "
              f"{ISAACLAB_DIR}/logs/rsl_rl/unitree_go2_custom_map/{LOAD_RUN}")
        sys.exit(1)

    print("=== Custom Map Training (Smooth v1) ===")
    print(f"  Task:       {TASK}")
    print(f"  Resume:     {LOAD_RUN} / {CHECKPOINT}")
    print(f"  Envs:       {NUM_ENVS}")
    print(f"  Key:        action_rate=-0.5, smoothness=-0.5, scale=0.15")
    print(f"              vel_track=1.0, orientation=-0.5, vel=0.1-0.35 m/s")
    print()

    cmd = [
        sys.executable, "-u", "scripts/rsl_rl/train.py",
        "--task", TASK,
        "--num_envs", str(NUM_ENVS),
        "--resume",
        "--load_run", LOAD_RUN,
        "--checkpoint", CHECKPOINT,
        "--headless",
    ]

    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"

    print(f"Running: {' '.join(cmd)}")
    print(f"CWD:     {ISAACLAB_DIR}")
    print()

    result = subprocess.run(cmd, cwd=ISAACLAB_DIR, env=env)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
