#!/usr/bin/env python3
"""
Phase 1: Train Go2 goal-directed stable walking policy.

Zero speed reward. Forward progress only. Stability dominates.

Resumes from model_3400 (early rough terrain — knows how to walk,
hasn't learned jerky behaviors yet). Retrains with:
  - forward_progress reward (position-based, NOT velocity)
  - NO velocity tracking reward
  - Speed hard-capped at 0.0-0.1 m/s
  - Dominant smoothness/stability penalties

Usage:
    conda activate isaaclab_go2
    python ~/robotics/projects/Dias/scripts/train_stable.py
"""

import os
import subprocess
import sys

ISAACLAB_DIR = os.path.expanduser("~/robotics/projects/Dias/unitree_rl_lab")
TASK = "Unitree-Go2-Velocity-Stable"
NUM_ENVS = 4096
LOAD_RUN = "2026-02-07_01-04-19"
CHECKPOINT = "model_3400.pt"


def main():
    # Verify checkpoint exists
    checkpoint_path = os.path.join(
        ISAACLAB_DIR, "logs", "rsl_rl", "unitree_go2_velocity_stable",
        LOAD_RUN, CHECKPOINT
    )
    if not os.path.exists(checkpoint_path):
        print(f"ERROR: Checkpoint not found: {checkpoint_path}")
        sys.exit(1)

    print("=== Phase 1: Goal-Directed Stable Walking ===")
    print(f"  Task:       {TASK}")
    print(f"  Resume:     {LOAD_RUN} / {CHECKPOINT}")
    print(f"  Envs:       {NUM_ENVS}")
    print(f"  Speed:      0.0-0.1 m/s (NOT rewarded)")
    print(f"  Rewards:    forward_progress=0.3 (position-based)")
    print(f"              NO velocity tracking (removed)")
    print(f"  Penalties:  action_rate=-0.5, smoothness=-0.5, orientation=-2.0")
    print(f"  PPO:        noise=0.5, lr=5e-4, entropy=0.008")
    print(f"  Goal:       A-to-B traversal, zero speed reward, ultra-stable")
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
