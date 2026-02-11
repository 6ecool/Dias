#!/bin/bash
# =============================================================================
# NVIDIA Brev Setup — полная установка среды для Go2 RL тренировки
# =============================================================================
#
# NVIDIA Brev — облачная GPU платформа с предустановленными:
#   - NVIDIA драйверами + CUDA
#   - Python + pip
#   - Docker
#   - Jupyter
#
# Этот скрипт устанавливает ВСЁ остальное:
#   - Miniconda + conda env (Python 3.11)
#   - IsaacSim 5.1.0 (pip)
#   - IsaacLab v2.3.2 (из исходников)
#   - unitree_rl_lab (наш RL фреймворк)
#   - Dias проект (карты, скрипты, конфиги)
#   - Все зависимости (trimesh, tensorboard, onnx, etc.)
#
# Использование:
#   # 1. Создай Brev instance с GPU (A100/H100/L40S)
#   # 2. Подключись по SSH или через Brev CLI
#   # 3. Запусти:
#   bash setup_brev.sh
#
#   # После установки:
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
echo "  NVIDIA Brev Setup — Go2 RL Training"
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

if ! nvidia-smi &>/dev/null; then
    fail "NVIDIA GPU not found. Select a GPU instance on Brev."
fi
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
ok "GPU: $GPU_NAME ($GPU_MEM), Driver: $DRIVER"

AVAIL_GB=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAIL_GB" -lt 25 ]; then
    warn "Low disk: ${AVAIL_GB}GB free (need ~25GB). May fail during IsaacSim install."
else
    ok "Disk: ${AVAIL_GB}GB available"
fi

# =============================================================================
# Step 1: System dependencies
# =============================================================================
info "Step 1: System dependencies..."

# Brev instances typically have most tools, but ensure key ones exist
if command -v sudo &>/dev/null; then
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y -qq \
        build-essential cmake git git-lfs wget curl unzip \
        libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
        2>/dev/null || true
else
    # Some Brev containers run as root
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq \
        build-essential cmake git git-lfs wget curl unzip \
        libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
        2>/dev/null || true
fi

git lfs install --skip-repo > /dev/null 2>&1 || true
ok "System dependencies installed"

# =============================================================================
# Step 2: Miniconda
# =============================================================================
info "Step 2: Miniconda..."

# Check multiple possible conda locations (Brev may pre-install)
CONDA_SH=""
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    CONDA_SH="$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    CONDA_SH="/opt/conda/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    CONDA_SH="$HOME/anaconda3/etc/profile.d/conda.sh"
fi

if [ -n "$CONDA_SH" ]; then
    source "$CONDA_SH"
    ok "Conda found: $CONDA_SH"
elif command -v conda &>/dev/null; then
    ok "Conda in PATH"
else
    info "Installing Miniconda..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    rm /tmp/miniconda.sh
    CONDA_SH="$HOME/miniconda3/etc/profile.d/conda.sh"
    source "$CONDA_SH"
    "$HOME/miniconda3/bin/conda" init bash > /dev/null 2>&1
    ok "Miniconda installed"
fi

# =============================================================================
# Step 3: Clone IsaacLab
# =============================================================================
info "Step 3: IsaacLab ($ISAACLAB_TAG)..."

mkdir -p "$(dirname "$ISAACLAB_DIR")"

if [ -d "$ISAACLAB_DIR/.git" ]; then
    ok "IsaacLab already cloned"
else
    info "Cloning IsaacLab $ISAACLAB_TAG (shallow)..."
    git clone --depth 1 --branch "$ISAACLAB_TAG" \
        https://github.com/isaac-sim/IsaacLab.git "$ISAACLAB_DIR"
    ok "IsaacLab cloned"
fi

# =============================================================================
# Step 4: Conda environment
# =============================================================================
info "Step 4: Conda environment ($CONDA_ENV)..."

if conda env list 2>/dev/null | grep -qw "$CONDA_ENV"; then
    ok "Conda env '$CONDA_ENV' exists"
else
    info "Creating conda env (Python 3.11)..."
    cd "$ISAACLAB_DIR"
    conda env create -y --file environment.yml -n "$CONDA_ENV"
    ok "Conda env created"
fi

conda activate "$CONDA_ENV"
ok "Activated: $CONDA_ENV ($(python --version 2>&1))"

# =============================================================================
# Step 5: IsaacSim 5.1.0 (pip)
# =============================================================================
info "Step 5: IsaacSim 5.1.0..."

if python -c "import isaacsim" &>/dev/null; then
    ok "IsaacSim already installed"
else
    info "Installing IsaacSim via pip (~15GB download, please wait)..."
    pip install --upgrade pip > /dev/null 2>&1

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
# Step 6: IsaacLab from source
# =============================================================================
info "Step 6: IsaacLab source install..."

if python -c "import isaaclab" &>/dev/null; then
    ok "IsaacLab already installed: $(python -c 'import isaaclab; print(isaaclab.__version__)' 2>/dev/null)"
else
    info "Installing IsaacLab + rsl_rl (takes a few minutes)..."
    cd "$ISAACLAB_DIR"
    bash isaaclab.sh -i rsl_rl
    ok "IsaacLab installed"
fi

# =============================================================================
# Step 7: Clone Dias + unitree_rl_lab
# =============================================================================
info "Step 7: Project repos..."

mkdir -p "$(dirname "$DIAS_DIR")"

if [ -d "$DIAS_DIR/.git" ]; then
    info "Dias repo exists, pulling..."
    cd "$DIAS_DIR" && git pull --ff-only 2>/dev/null || true
    ok "Dias updated"
else
    git clone https://github.com/6ecool/Dias.git "$DIAS_DIR"
    ok "Dias cloned"
fi

if [ -d "$DIAS_DIR/unitree_rl_lab/.git" ]; then
    info "unitree_rl_lab exists, pulling..."
    cd "$DIAS_DIR/unitree_rl_lab" && git pull --ff-only 2>/dev/null || true
    ok "unitree_rl_lab updated"
else
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
    export ISAACLAB_PATH="$ISAACLAB_DIR"
    bash unitree_rl_lab.sh -i
    ok "unitree_rl_lab installed"
fi

# =============================================================================
# Step 9: Extra dependencies
# =============================================================================
info "Step 9: Extra packages..."

pip install -q trimesh tensorboard onnx onnxruntime psutil noise 2>/dev/null
ok "Extra packages done"

# =============================================================================
# Step 10: Download pre-trained flat model from HuggingFace (optional)
# =============================================================================
info "Step 10: Pre-trained flat model (reference)..."

HF_MODEL_DIR="$DIAS_DIR/pretrained/velocity_flat"
if [ -f "$HF_MODEL_DIR/model_500.pt" ]; then
    ok "Flat model already downloaded"
else
    info "Downloading diasAiMaster/unitree-go2-velocity-flat from HuggingFace..."
    pip install -q huggingface_hub 2>/dev/null
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='diasAiMaster/unitree-go2-velocity-flat',
    local_dir='$HF_MODEL_DIR',
    allow_patterns=['*.pt', '*.onnx*', '*.yaml', 'README.md'],
)
print('Downloaded')
" 2>/dev/null && ok "Flat model downloaded to $HF_MODEL_DIR" || warn "Could not download flat model (not critical)"
fi

# =============================================================================
# Step 11: Verify
# =============================================================================
echo ""
info "Step 11: Final verification..."
echo ""

ERRORS=0

# PyTorch + CUDA
if python -c "import torch; assert torch.cuda.is_available()" &>/dev/null; then
    TORCH_VER=$(python -c "import torch; print(torch.__version__)")
    GPU=$(python -c "import torch; print(torch.cuda.get_device_name(0))")
    ok "PyTorch $TORCH_VER | GPU: $GPU"
else
    warn "PyTorch CUDA not available!"; ((ERRORS++))
fi

# IsaacSim
python -c "import isaacsim" &>/dev/null && ok "isaacsim" || { warn "isaacsim"; ((ERRORS++)); }

# IsaacLab
python -c "import isaaclab" &>/dev/null && ok "isaaclab: $(python -c 'import isaaclab; print(isaaclab.__version__)' 2>/dev/null)" || { warn "isaaclab"; ((ERRORS++)); }

# RSL-RL
python -c "import rsl_rl" &>/dev/null && ok "rsl_rl" || { warn "rsl_rl"; ((ERRORS++)); }

# unitree_rl_lab
python -c "import unitree_rl_lab" &>/dev/null && ok "unitree_rl_lab" || { warn "unitree_rl_lab"; ((ERRORS++)); }

# trimesh
python -c "import trimesh" &>/dev/null && ok "trimesh" || { warn "trimesh"; ((ERRORS++)); }

# Maps
if [ -f "$DIAS_DIR/Maps/3D/realnaya_huinya.obj" ]; then
    ok "Competition map found"
else
    warn "Map not found: $DIAS_DIR/Maps/3D/realnaya_huinya.obj"
    echo -e "     ${YELLOW}Copy manually: scp -r Maps/ user@brev:$DIAS_DIR/Maps/${NC}"
    ((ERRORS++))
fi

# Task registration
if python -c "
import gymnasium as gym
import unitree_rl_lab.tasks
ids = [s.id for s in gym.registry.values()]
assert 'Unitree-Go2-Curriculum-Phase1' in ids
assert 'Unitree-Go2-Curriculum-Phase2' in ids
assert 'Unitree-Go2-Curriculum-Phase3' in ids
" &>/dev/null; then
    ok "Curriculum tasks registered (Phase1/2/3)"
else
    warn "Tasks not registered — check if code is pushed to git"; ((ERRORS++))
fi

echo ""
echo "=============================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}SETUP COMPLETE — ALL CHECKS PASSED${NC}"
else
    echo -e "  ${YELLOW}SETUP DONE — $ERRORS warning(s)${NC}"
fi
echo "=============================================="
echo ""
echo "  Training commands:"
echo ""
echo "    conda activate $CONDA_ENV"
echo ""
echo "    # Phase 1: flat terrain, from scratch (~30 min)"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh --phase 1"
echo ""
echo "    # Phase 2: terrain (resume from Phase 1)"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh --phase 2 --load_run <phase1_dir>"
echo ""
echo "    # Phase 3: competition map (resume from Phase 2)"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh --phase 3 --load_run <phase2_dir>"
echo ""
echo "    # Or ALL phases automatically:"
echo "    bash $DIAS_DIR/scripts/train_curriculum.sh"
echo ""
echo "    # Monitor:"
echo "    tensorboard --logdir $DIAS_DIR/unitree_rl_lab/logs/rsl_rl/ --bind_all"
echo ""
echo "=============================================="
