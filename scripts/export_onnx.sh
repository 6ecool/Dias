#!/bin/bash
# Export a training checkpoint to ONNX for deployment (MuJoCo sim or real Go2)
#
# Usage:
#   ./scripts/export_onnx.sh                    # exports latest checkpoint
#   ./scripts/export_onnx.sh 5500               # exports model_5500.pt
#   ./scripts/export_onnx.sh 5500 my_run_name   # exports from specific run

set -e

ITER="${1:-latest}"
RUN_DIR="${2:-2026-02-07_11-24-58}"
BASE_DIR="$HOME/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/unitree_go2_velocity_rough/$RUN_DIR"

if [ ! -d "$BASE_DIR" ]; then
    echo "ERROR: Run directory not found: $BASE_DIR"
    echo "Available runs:"
    ls "$HOME/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/unitree_go2_velocity_rough/"
    exit 1
fi

# Find checkpoint
if [ "$ITER" = "latest" ]; then
    CKPT=$(ls "$BASE_DIR"/model_*.pt 2>/dev/null | sort -t_ -k2 -n | tail -1)
    if [ -z "$CKPT" ]; then
        echo "ERROR: No checkpoints found in $BASE_DIR"
        exit 1
    fi
    ITER=$(basename "$CKPT" | sed 's/model_\(.*\)\.pt/\1/')
else
    CKPT="$BASE_DIR/model_${ITER}.pt"
    if [ ! -f "$CKPT" ]; then
        echo "ERROR: Checkpoint not found: $CKPT"
        echo "Available checkpoints:"
        ls "$BASE_DIR"/model_*.pt | sort -t_ -k2 -n
        exit 1
    fi
fi

OUT_DIR="$BASE_DIR/exported"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/policy_${ITER}.onnx"

echo "=== Exporting checkpoint ==="
echo "  Checkpoint: $CKPT"
echo "  Output:     $OUT_FILE"

# Use the conda env with torch
source activate isaaclab_go2 2>/dev/null || conda activate isaaclab_go2 2>/dev/null || true

python3 -c "
import torch
import torch.nn as nn

class PolicyNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.actor = nn.Sequential(
            nn.Linear(232, 512), nn.ELU(),
            nn.Linear(512, 256), nn.ELU(),
            nn.Linear(256, 128), nn.ELU(),
            nn.Linear(128, 12),
        )
    def forward(self, x):
        return self.actor(x)

model = PolicyNet()
ckpt = torch.load('$CKPT', map_location='cpu', weights_only=False)
actor_state = {k: v for k, v in ckpt['model_state_dict'].items() if k.startswith('actor.')}
model.load_state_dict(actor_state)
model.eval()

dummy = torch.randn(1, 232)
torch.onnx.export(model, dummy, '$OUT_FILE', input_names=['obs'], output_names=['action'], opset_version=11)
print(f'Exported iter {ckpt[\"iter\"]} -> $OUT_FILE')
"

echo ""
echo "=== Done! ==="
echo "To test in MuJoCo:"
echo "  cd ~/robotics/projects/Dias/unitree_mujoco/simulate_python"
echo "  python run_policy.py --policy $OUT_FILE --zone krails"
