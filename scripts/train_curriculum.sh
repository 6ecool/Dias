#!/bin/bash
# 3-Phase Curriculum Training for Go2 Competition Map
#
# Phase 1: Flat + mild terrain — learn smooth forward gait (from scratch)
# Phase 2: Ramps + K-rails — terrain handling (resume from Phase 1)
# Phase 3: 100% realnaya_huinya.obj — competition map (resume from Phase 2)
#
# Usage:
#   # Run all 3 phases sequentially:
#   bash ~/robotics/projects/Dias/scripts/train_curriculum.sh
#
#   # Run a specific phase:
#   bash ~/robotics/projects/Dias/scripts/train_curriculum.sh --phase 1
#   bash ~/robotics/projects/Dias/scripts/train_curriculum.sh --phase 2 --load_run <phase1_run>
#   bash ~/robotics/projects/Dias/scripts/train_curriculum.sh --phase 3 --load_run <phase2_run>
#
# Monitor:
#   tensorboard --logdir ~/robotics/projects/Dias/unitree_rl_lab/logs/rsl_rl/

set -e

ISAACLAB_DIR="$HOME/robotics/projects/Dias/unitree_rl_lab"
PHASE=""
LOAD_RUN=""
CHECKPOINT=""
NUM_ENVS_P1=8192
NUM_ENVS_P2=8192
NUM_ENVS_P3=4096

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --phase) PHASE="$2"; shift 2 ;;
        --load_run) LOAD_RUN="$2"; shift 2 ;;
        --checkpoint) CHECKPOINT="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Initialize conda
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate isaaclab_go2
cd "$ISAACLAB_DIR"

run_phase1() {
    echo "============================================"
    echo "  PHASE 1: Robust Forward Locomotion"
    echo "  Terrain: flat + mild rough + gentle slopes"
    echo "  From scratch (no resume)"
    echo "  Envs: $NUM_ENVS_P1"
    echo "============================================"
    PYTHONUNBUFFERED=1 python -u scripts/rsl_rl/train.py \
        --task Unitree-Go2-Curriculum-Phase1 \
        --num_envs "$NUM_ENVS_P1" \
        --headless
}

run_phase2() {
    local load_run="$1"
    local checkpoint="${2:-model_5000.pt}"
    echo "============================================"
    echo "  PHASE 2: Terrain Handling"
    echo "  Terrain: ramps + K-rails + boxes"
    echo "  Resume: $load_run / $checkpoint"
    echo "  Envs: $NUM_ENVS_P2"
    echo "============================================"
    PYTHONUNBUFFERED=1 python -u scripts/rsl_rl/train.py \
        --task Unitree-Go2-Curriculum-Phase2 \
        --num_envs "$NUM_ENVS_P2" \
        --resume \
        --load_run "$load_run" \
        --checkpoint "$checkpoint" \
        --headless
}

run_phase3() {
    local load_run="$1"
    local checkpoint="${2:-model_5000.pt}"
    echo "============================================"
    echo "  PHASE 3: Competition Map Fine-Tuning"
    echo "  Terrain: 100% realnaya_huinya.obj"
    echo "  Resume: $load_run / $checkpoint"
    echo "  Envs: $NUM_ENVS_P3"
    echo "============================================"
    PYTHONUNBUFFERED=1 python -u scripts/rsl_rl/train.py \
        --task Unitree-Go2-Curriculum-Phase3 \
        --num_envs "$NUM_ENVS_P3" \
        --resume \
        --load_run "$load_run" \
        --checkpoint "$checkpoint" \
        --headless
}

if [ -n "$PHASE" ]; then
    # Run specific phase
    case $PHASE in
        1) run_phase1 ;;
        2)
            if [ -z "$LOAD_RUN" ]; then
                echo "ERROR: Phase 2 requires --load_run <phase1_run_dir>"
                exit 1
            fi
            run_phase2 "$LOAD_RUN" "${CHECKPOINT:-model_5000.pt}"
            ;;
        3)
            if [ -z "$LOAD_RUN" ]; then
                echo "ERROR: Phase 3 requires --load_run <phase2_run_dir>"
                exit 1
            fi
            run_phase3 "$LOAD_RUN" "${CHECKPOINT:-model_5000.pt}"
            ;;
        *) echo "Invalid phase: $PHASE (use 1, 2, or 3)"; exit 1 ;;
    esac
else
    # Run all phases sequentially
    echo "Running all 3 phases sequentially..."
    echo ""

    # Phase 1 — from scratch
    run_phase1

    # Find the latest Phase 1 run
    P1_DIR="$ISAACLAB_DIR/logs/rsl_rl/unitree_go2_curriculum_phase1"
    P1_RUN=$(ls -t "$P1_DIR" | head -1)
    echo ""
    echo "Phase 1 complete. Run: $P1_RUN"
    echo ""

    # Phase 2 — resume from Phase 1
    run_phase2 "$P1_RUN" "model_5000.pt"

    # Find the latest Phase 2 run
    P2_DIR="$ISAACLAB_DIR/logs/rsl_rl/unitree_go2_curriculum_phase2"
    P2_RUN=$(ls -t "$P2_DIR" | head -1)
    echo ""
    echo "Phase 2 complete. Run: $P2_RUN"
    echo ""

    # Phase 3 — resume from Phase 2
    run_phase3 "$P2_RUN" "model_5000.pt"

    echo ""
    echo "============================================"
    echo "  ALL 3 PHASES COMPLETE!"
    echo "  Export best checkpoint to ONNX and test"
    echo "============================================"
fi
