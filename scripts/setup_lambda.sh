#!/bin/bash
# =============================================================================
# Cloud GPU Setup — полная установка среды для тренировки Go2 с нуля
# =============================================================================
#
# Работает на: Lambda Labs, Vast.ai, RunPod, любой Ubuntu 22.04+ с NVIDIA GPU
#
# Что делает:
#   1. Устанавливает Miniconda
#   2. Клонирует IsaacLab (v2.3.2)
#   3. Создает conda env через isaaclab.sh
#   4. Устанавливает IsaacSim 5.1.0 (pip)
#   5. Устанавливает IsaacLab из исходников
#   6. Клонирует Dias + unitree_rl_lab
#   7. Устанавливает unitree_rl_lab + зависимости
#   8. Верифицирует всё
#
# Использование:
#   # Вариант 1: Свежая машина (всё с нуля)
#   curl -sL https://raw.githubusercontent.com/6ecool/Dias/master/scripts/setup_lambda.sh | bash
#
#   # Вариант 2: Скопировать файл и запустить
#   scp scripts/setup_lambda.sh user@cloud-gpu:~/
#   ssh user@cloud-gpu "bash ~/setup_lambda.sh"
#
# После установки:
#   source ~/.bashrc
#   conda activate isaaclab_go2
#   bash ~/robotics/projects/Dias/scripts/train_curriculum.sh --phase 1
#
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

CONDA_ENV="isaaclab_go2"
DIAS_DIR="$HOME/robotics/projects/Dias"
ISAACLAB_DIR="$HOME/robotics/projects/IsaacLab"
ISAACLAB_TAG="v2.3.2"

echo ""
echo "=============================================="
echo "  Cloud GPU Setup — Go2 RL Training"
echo "=============================================="
echo "  Target: $DIAS_DIR"
echo "  IsaacLab: $ISAACLAB_TAG"
echo "  Conda env: $CONDA_ENV"
echo "=============================================="
echo ""

# =============================================================================
# Step 0: Pre-flight checks
# =============================================================================
info "Step 0: Pre-flight checks..."

# Check NVIDIA GPU
if ! nvidia-smi &>/dev/null; then
    fail "NVIDIA GPU not found. Need a GPU machine (A100/H100/RTX)."
fi
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
ok "GPU: $GPU_NAME ($GPU_MEM), Driver: $DRIVER"

# Check disk space (need ~30GB: IsaacSim ~15GB, IsaacLab ~2GB, conda ~5GB, rest ~5GB)
AVAIL_GB=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAIL_GB" -lt 30 ]; then
    warn "Only ${AVAIL_GB}GB free disk space. Need ~30GB. Proceeding anyway..."
else
    ok "Disk: ${AVAIL_GB}GB available"
fi

# =============================================================================
# Step 1: System dependencies
# =============================================================================
info "Step 1: System dependencies..."

sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential \
    cmake \
    git \
    git-lfs \
    wget \
    curl \
    unzip \
    libgl1-mesa-glx \
    libglib2.0-0 \
    > /dev/null 2>&1

git lfs install --skip-repo > /dev/null 2>&1
ok "System dependencies installed"

# =============================================================================
# Step 2: Miniconda
# =============================================================================
info "Step 2: Miniconda..."

if command -v conda &>/dev/null; then
    ok "Conda already installed"
else
    info "Installing Miniconda..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    rm /tmp/miniconda.sh

    # Init for current shell and future shells
    "$HOME/miniconda3/bin/conda" init bash > /dev/null 2>&1
    ok "Miniconda installed at $HOME/miniconda3"
fi

# Source conda for this script
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    source "/opt/conda/etc/profile.d/conda.sh"
else
    fail "Cannot find conda.sh. Check conda installation."
fi

# =============================================================================
# Step 3: Clone IsaacLab
# =============================================================================
info "Step 3: IsaacLab ($ISAACLAB_TAG)..."

mkdir -p "$(dirname "$ISAACLAB_DIR")"

if [ -d "$ISAACLAB_DIR/.git" ]; then
    ok "IsaacLab already cloned at $ISAACLAB_DIR"
else
    info "Cloning IsaacLab $ISAACLAB_TAG..."
    git clone --depth 1 --branch "$ISAACLAB_TAG" \
        https://github.com/isaac-sim/IsaacLab.git "$ISAACLAB_DIR"
    ok "IsaacLab cloned"
fi

# =============================================================================
# Step 4: Create conda environment
# =============================================================================
info "Step 4: Conda environment ($CONDA_ENV)..."

if conda env list 2>/dev/null | grep -qw "$CONDA_ENV"; then
    ok "Conda env '$CONDA_ENV' already exists"
else
    info "Creating conda env from IsaacLab environment.yml..."
    cd "$ISAACLAB_DIR"
    conda env create -y --file environment.yml -n "$CONDA_ENV"
    ok "Conda env '$CONDA_ENV' created (Python 3.11)"
fi

conda activate "$CONDA_ENV"
ok "Activated conda env: $CONDA_ENV"

# =============================================================================
# Step 5: Install IsaacSim 5.1.0 (pip-based)
# =============================================================================
info "Step 5: IsaacSim 5.1.0 (pip)..."

if python -c "import isaacsim" &>/dev/null; then
    ISAACSIM_VER=$(python -c "from importlib.metadata import version; print(version('isaacsim'))" 2>/dev/null || echo "unknown")
    ok "IsaacSim already installed: $ISAACSIM_VER"
else
    info "Installing IsaacSim 5.1.0 via pip (this downloads ~15GB, be patient)..."
    pip install --upgrade pip > /dev/null

    # Core IsaacSim packages needed for RL training (headless)
    pip install \
        isaacsim==5.1.0.0 \
        isaacsim-rl==5.1.0.0 \
        isaacsim-replicator==5.1.0.0 \
        isaacsim-extscache-physics==5.1.0.0 \
        isaacsim-extscache-kit-sdk==5.1.0.0 \
        isaacsim-extscache-kit==5.1.0.0 \
        isaacsim-app==5.1.0.0 \
        --extra-index-url https://pypi.nvidia.com

    ok "IsaacSim 5.1.0 installed"
fi

# =============================================================================
# Step 6: Install IsaacLab from source
# =============================================================================
info "Step 6: IsaacLab from source..."

if python -c "import isaaclab" &>/dev/null; then
    ISAACLAB_VER=$(python -c "import isaaclab; print(isaaclab.__version__)" 2>/dev/null || echo "unknown")
    ok "IsaacLab already installed: $ISAACLAB_VER"
else
    info "Installing IsaacLab (all source packages + rsl_rl framework)..."
    cd "$ISAACLAB_DIR"

    # IsaacLab install: installs PyTorch, all source packages, RL frameworks
    bash isaaclab.sh -i rsl_rl

    ok "IsaacLab installed"
fi

# =============================================================================
# Step 7: Clone project repos
# =============================================================================
info "Step 7: Project repos (Dias + unitree_rl_lab)..."

mkdir -p "$DIAS_DIR"

# Clone Dias (main project — maps, scripts, configs)
if [ -d "$DIAS_DIR/.git" ]; then
    info "Dias repo exists, pulling latest..."
    cd "$DIAS_DIR" && git pull --ff-only 2>/dev/null || true
    ok "Dias repo updated"
else
    info "Cloning Dias repo..."
    git clone https://github.com/6ecool/Dias.git "$DIAS_DIR"
    ok "Dias cloned"
fi

# Clone unitree_rl_lab (RL training framework)
if [ -d "$DIAS_DIR/unitree_rl_lab/.git" ]; then
    info "unitree_rl_lab exists, pulling latest..."
    cd "$DIAS_DIR/unitree_rl_lab" && git pull --ff-only 2>/dev/null || true
    ok "unitree_rl_lab updated"
else
    info "Cloning unitree_rl_lab..."
    git clone https://github.com/6ecool/unitree_rl_lab.git "$DIAS_DIR/unitree_rl_lab"
    ok "unitree_rl_lab cloned"
fi

# =============================================================================
# Step 8: Install unitree_rl_lab
# =============================================================================
info "Step 8: unitree_rl_lab..."

if python -c "import unitree_rl_lab" &>/dev/null; then
    ok "unitree_rl_lab already installed"
else
    cd "$DIAS_DIR/unitree_rl_lab"

    # Set ISAACLAB_PATH so unitree_rl_lab.sh can find IsaacLab
    export ISAACLAB_PATH="$ISAACLAB_DIR"

    # Install via the project's installer (sets up conda hooks too)
    bash unitree_rl_lab.sh -i

    ok "unitree_rl_lab installed"
fi

# =============================================================================
# Step 9: Extra pip packages
# =============================================================================
info "Step 9: Extra dependencies..."

pip install -q \
    trimesh \
    tensorboard \
    onnx \
    onnxruntime \
    psutil \
    noise \
    2>/dev/null

ok "Extra packages installed"

# =============================================================================
# Step 10: Verify installation
# =============================================================================
info "Step 10: Verifying installation..."
echo ""

ERRORS=0

# GPU check
if python -c "import torch; assert torch.cuda.is_available()" &>/dev/null; then
    TORCH_VER=$(python -c "import torch; print(torch.__version__)")
    CUDA_AVAIL=$(python -c "import torch; print(torch.cuda.get_device_name(0))")
    ok "PyTorch: $TORCH_VER | CUDA GPU: $CUDA_AVAIL"
else
    fail "PyTorch CUDA not available!"
fi

# IsaacSim
if python -c "import isaacsim" &>/dev/null; then
    ok "IsaacSim importable"
else
    warn "IsaacSim not importable"; ((ERRORS++))
fi

# IsaacLab
if python -c "import isaaclab; print(isaaclab.__version__)" &>/dev/null; then
    ok "IsaacLab: $(python -c 'import isaaclab; print(isaaclab.__version__)')"
else
    warn "IsaacLab not importable"; ((ERRORS++))
fi

# IsaacLab RL
if python -c "import isaaclab_rl" &>/dev/null; then
    ok "isaaclab_rl importable"
else
    warn "isaaclab_rl not importable"; ((ERRORS++))
fi

# IsaacLab Tasks
if python -c "import isaaclab_tasks" &>/dev/null; then
    ok "isaaclab_tasks importable"
else
    warn "isaaclab_tasks not importable"; ((ERRORS++))
fi

# RSL-RL
if python -c "import rsl_rl" &>/dev/null; then
    ok "rsl_rl importable"
else
    warn "rsl_rl not importable"; ((ERRORS++))
fi

# unitree_rl_lab
if python -c "import unitree_rl_lab" &>/dev/null; then
    ok "unitree_rl_lab importable"
else
    warn "unitree_rl_lab not importable"; ((ERRORS++))
fi

# trimesh
if python -c "import trimesh" &>/dev/null; then
    ok "trimesh importable"
else
    warn "trimesh not importable"; ((ERRORS++))
fi

# Maps
if [ -f "$DIAS_DIR/Maps/3D/realnaya_huinya.obj" ]; then
    ok "Competition map: realnaya_huinya.obj found"
else
    warn "Competition map not found at $DIAS_DIR/Maps/3D/realnaya_huinya.obj"
    echo "     You need to copy the Maps directory manually:"
    echo "     scp -r Maps/ user@cloud-gpu:$DIAS_DIR/Maps/"
    ((ERRORS++))
fi

# Task registration check
if python -c "
import gymnasium as gym
import unitree_rl_lab.tasks  # noqa: registers tasks
env_ids = [s.id for s in gym.registry.values()]
assert 'Unitree-Go2-Curriculum-Phase1' in env_ids, 'Phase1 not registered'
assert 'Unitree-Go2-Curriculum-Phase2' in env_ids, 'Phase2 not registered'
assert 'Unitree-Go2-Curriculum-Phase3' in env_ids, 'Phase3 not registered'
print('OK')
" &>/dev/null; then
    ok "Curriculum tasks registered (Phase1, Phase2, Phase3)"
else
    warn "Curriculum tasks not registered. Check unitree_rl_lab code."
    ((ERRORS++))
fi

echo ""
echo "=============================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}ALL CHECKS PASSED!${NC}"
else
    echo -e "  ${YELLOW}$ERRORS warning(s) — see above${NC}"
fi
echo "=============================================="
echo ""
echo "  Quick start:"
echo ""
echo "    # Activate environment"
echo "    conda activate $CONDA_ENV"
echo ""
echo "    # Train Phase 1 (from scratch, ~5000 iterations)"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh --phase 1"
echo ""
echo "    # Or run all 3 phases automatically"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh"
echo ""
echo "    # Monitor training"
echo "    tensorboard --logdir $DIAS_DIR/unitree_rl_lab/logs/rsl_rl/ --bind_all"
echo ""
echo "  Files to copy manually (if not in git):"
echo "    scp -r Maps/ user@cloud:$DIAS_DIR/Maps/"
echo ""
echo "=============================================="
