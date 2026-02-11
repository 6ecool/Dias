#!/usr/bin/env python3
"""
Export a Go2 RL checkpoint (.pt) to ONNX without needing IsaacLab/Isaac Sim.

Usage:
    conda activate isaaclab_go2
    python ~/robotics/projects/Dias/scripts/export_onnx.py <checkpoint_path> [output_path]

Examples:
    python scripts/export_onnx.py logs/rsl_rl/unitree_go2_velocity_rough/2026-02-06_14-17-40/model_300.pt
    python scripts/export_onnx.py /full/path/to/model_300.pt exported/policy_300.onnx
"""

import sys
import os
import torch
import torch.nn as nn

# Network architecture (must match training config)
OBS_DIM = 232       # 3+3+3+12+12+12+187 (with height scan)
ACTION_DIM = 12     # 12 joint positions
HIDDEN_DIMS = [512, 256, 128]
ACTIVATION = nn.ELU


def build_actor(obs_dim, action_dim, hidden_dims, activation):
    """Reconstruct the actor MLP matching rsl_rl ActorCritic."""
    layers = []
    in_dim = obs_dim
    for h in hidden_dims:
        layers.append(nn.Linear(in_dim, h))
        layers.append(activation())
        in_dim = h
    layers.append(nn.Linear(in_dim, action_dim))
    return nn.Sequential(*layers)


def main():
    if len(sys.argv) < 2:
        print("Usage: python export_onnx.py <checkpoint.pt> [output.onnx]")
        sys.exit(1)

    checkpoint_path = sys.argv[1]
    if not os.path.exists(checkpoint_path):
        print(f"ERROR: Checkpoint not found: {checkpoint_path}")
        sys.exit(1)

    # Default output path
    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        basename = os.path.splitext(os.path.basename(checkpoint_path))[0]
        output_path = os.path.expanduser(f"~/robotics/projects/Dias/exported/policy_{basename.replace('model_', '')}.onnx")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    print(f"Loading checkpoint: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=True)

    # Extract model state dict
    if "model_state_dict" in checkpoint:
        state_dict = checkpoint["model_state_dict"]
    else:
        state_dict = checkpoint

    # Filter actor weights only
    actor_state = {}
    for key, val in state_dict.items():
        if key.startswith("actor."):
            actor_key = key[len("actor."):]
            actor_state[actor_key] = val

    if not actor_state:
        print("ERROR: No 'actor.*' keys found in checkpoint.")
        print(f"Available keys: {list(state_dict.keys())[:20]}")
        sys.exit(1)

    # Detect dimensions from weights
    first_weight = actor_state["0.weight"]
    last_key = sorted([k for k in actor_state if k.endswith(".weight")])[-1]
    last_weight = actor_state[last_key]

    detected_obs = first_weight.shape[1]
    detected_act = last_weight.shape[0]
    detected_hidden = []
    for k in sorted(actor_state.keys()):
        if k.endswith(".weight"):
            detected_hidden.append(actor_state[k].shape[0])
    detected_hidden = detected_hidden[:-1]  # remove output layer

    print(f"Detected: obs={detected_obs}, act={detected_act}, hidden={detected_hidden}")

    # Build and load actor
    actor = build_actor(detected_obs, detected_act, detected_hidden, ACTIVATION)
    actor.load_state_dict(actor_state)
    actor.eval()

    # Export to ONNX
    dummy_input = torch.randn(1, detected_obs)
    torch.onnx.export(
        actor,
        dummy_input,
        output_path,
        input_names=["obs"],
        output_names=["actions"],
        opset_version=11,
        dynamic_axes={"obs": {0: "batch"}, "actions": {0: "batch"}},
    )

    # Verify
    import onnxruntime as ort
    sess = ort.InferenceSession(output_path)
    test_input = dummy_input.numpy()
    result = sess.run(None, {"obs": test_input})
    print(f"Exported: {output_path}")
    print(f"  Size: {os.path.getsize(output_path) / 1024:.1f} KB")
    print(f"  Input:  obs [{detected_obs}]")
    print(f"  Output: actions [{detected_act}]")
    print(f"  Test output range: [{result[0].min():.3f}, {result[0].max():.3f}]")
    print("OK")


if __name__ == "__main__":
    main()
