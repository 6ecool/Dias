#!/usr/bin/env bash
# Dias Project Setup — RoboCup Rescue with Unitree Go2
# Usage:
#   bash setup.sh          — full install
#   bash setup.sh --check  — verify existing installation
set -euo pipefail

DIAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV_NAME="isaaclab_go2"
SDK2_INSTALL_DIR="$HOME/unitree_robotics"
ISAACLAB_DIR="$HOME/robotics/projects/IsaacLab"
ISAACSIM_DIR="$HOME/robotics/simulators/isaac-sim-standalone-5.1.0-linux-x86_64"

# ---------- colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# ================================================================
# --check mode: verify everything is installed
# ================================================================
if [[ "${1:-}" == "--check" ]]; then
    echo "========== Dias Installation Check =========="
    ERRORS=0

    # NVIDIA driver
    if nvidia-smi &>/dev/null; then
        ok "NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
    else
        fail "NVIDIA driver not found"; ((ERRORS++))
    fi

    # CUDA
    if command -v nvcc &>/dev/null; then
        ok "CUDA: $(nvcc --version | grep release | awk '{print $6}')"
    else
        warn "nvcc not in PATH (may still work via Isaac Sim bundled CUDA)"
    fi

    # conda
    if command -v conda &>/dev/null; then
        ok "conda: $(conda --version 2>&1)"
    else
        fail "conda not found"; ((ERRORS++))
    fi

    # conda env
    if conda env list 2>/dev/null | grep -q "$CONDA_ENV_NAME"; then
        ok "conda env '$CONDA_ENV_NAME' exists"
    else
        fail "conda env '$CONDA_ENV_NAME' not found"; ((ERRORS++))
    fi

    # apt packages
    for pkg in cmake libboost-all-dev libglfw3-dev libyaml-cpp-dev libfmt-dev; do
        if dpkg -s "$pkg" &>/dev/null; then
            ok "apt: $pkg"
        else
            fail "apt: $pkg not installed"; ((ERRORS++))
        fi
    done

    # git lfs
    if git lfs version &>/dev/null; then
        ok "git-lfs: $(git lfs version | awk '{print $1}')"
    else
        fail "git-lfs not installed"; ((ERRORS++))
    fi

    # Repos
    for repo in unitree_rl_lab unitree_mujoco unitree_sdk2; do
        if [[ -d "$DIAS_DIR/$repo/.git" ]]; then
            ok "repo: $repo cloned"
        else
            fail "repo: $repo not found"; ((ERRORS++))
        fi
    done

    # unitree_sdk2 build
    if [[ -f "$SDK2_INSTALL_DIR/lib/libunitree_sdk2.a" ]]; then
        ok "unitree_sdk2 installed at $SDK2_INSTALL_DIR"
    else
        fail "unitree_sdk2 not built/installed"; ((ERRORS++))
    fi

    # unitree_mujoco build
    if [[ -x "$DIAS_DIR/unitree_mujoco/simulate/build/unitree_mujoco" ]]; then
        ok "unitree_mujoco simulator built"
    else
        fail "unitree_mujoco simulator not built"; ((ERRORS++))
    fi

    # IsaacLab
    if [[ -d "$ISAACLAB_DIR" ]]; then
        ok "IsaacLab found at $ISAACLAB_DIR"
    else
        warn "IsaacLab not found at $ISAACLAB_DIR (needed for RL training)"
    fi

    # Isaac Sim
    if [[ -d "$ISAACSIM_DIR" ]]; then
        ok "Isaac Sim found at $ISAACSIM_DIR"
    else
        warn "Isaac Sim not found at $ISAACSIM_DIR (needed for RL training)"
    fi

    # Python packages in conda env
    if conda env list 2>/dev/null | grep -q "$CONDA_ENV_NAME"; then
        CONDA_PYTHON="$(conda run -n "$CONDA_ENV_NAME" which python 2>/dev/null || true)"
        if [[ -n "$CONDA_PYTHON" ]]; then
            for pypkg in mujoco isaaclab unitree_rl_lab; do
                if conda run -n "$CONDA_ENV_NAME" python -c "import $pypkg" &>/dev/null; then
                    ok "python: $pypkg importable in $CONDA_ENV_NAME"
                else
                    warn "python: $pypkg not importable in $CONDA_ENV_NAME"
                fi
            done
        fi
    fi

    echo "=========================================="
    if [[ $ERRORS -eq 0 ]]; then
        ok "All checks passed!"
    else
        fail "$ERRORS check(s) failed"
    fi
    exit $ERRORS
fi

# ================================================================
# Full installation
# ================================================================
echo "=========================================="
echo " Dias Project Setup — Unitree Go2"
echo "=========================================="
echo "Install directory: $DIAS_DIR"
echo ""

# ---------- Step 1: System dependencies ----------
echo "--- Step 1: System dependencies ---"
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    git-lfs \
    libboost-all-dev \
    libglfw3-dev \
    libyaml-cpp-dev \
    libfmt-dev

git lfs install
ok "System dependencies installed"

# ---------- Step 2: Clone repositories ----------
echo ""
echo "--- Step 2: Clone repositories ---"

if [[ ! -d "$DIAS_DIR/unitree_rl_lab/.git" ]]; then
    git clone https://github.com/6ecool/unitree_rl_lab.git "$DIAS_DIR/unitree_rl_lab"
    ok "Cloned unitree_rl_lab"
else
    ok "unitree_rl_lab already cloned"
fi

if [[ ! -d "$DIAS_DIR/unitree_mujoco/.git" ]]; then
    git clone https://github.com/6ecool/unitree_mujoco.git "$DIAS_DIR/unitree_mujoco"
    ok "Cloned unitree_mujoco"
else
    ok "unitree_mujoco already cloned"
fi

if [[ ! -d "$DIAS_DIR/unitree_sdk2/.git" ]]; then
    git clone https://github.com/unitreerobotics/unitree_sdk2.git "$DIAS_DIR/unitree_sdk2"
    ok "Cloned unitree_sdk2"
else
    ok "unitree_sdk2 already cloned"
fi

# ---------- Step 3: Build unitree_sdk2 ----------
echo ""
echo "--- Step 3: Build unitree_sdk2 ---"

if [[ -f "$SDK2_INSTALL_DIR/lib/libunitree_sdk2.a" ]]; then
    ok "unitree_sdk2 already installed at $SDK2_INSTALL_DIR"
else
    mkdir -p "$DIAS_DIR/unitree_sdk2/build"
    cd "$DIAS_DIR/unitree_sdk2/build"
    cmake .. -DCMAKE_INSTALL_PREFIX="$SDK2_INSTALL_DIR"
    make -j"$(nproc)"
    make install
    cd "$DIAS_DIR"
    ok "unitree_sdk2 built and installed to $SDK2_INSTALL_DIR"
fi

# ---------- Step 4: Build unitree_mujoco simulator ----------
echo ""
echo "--- Step 4: Build unitree_mujoco simulator ---"

if [[ -x "$DIAS_DIR/unitree_mujoco/simulate/build/unitree_mujoco" ]]; then
    ok "unitree_mujoco simulator already built"
else
    mkdir -p "$DIAS_DIR/unitree_mujoco/simulate/build"
    cd "$DIAS_DIR/unitree_mujoco/simulate/build"
    cmake .. -DCMAKE_PREFIX_PATH="$SDK2_INSTALL_DIR/lib/cmake"
    make -j"$(nproc)"
    cd "$DIAS_DIR"
    ok "unitree_mujoco simulator built"
fi

# ---------- Step 5: Conda environment + IsaacLab ----------
echo ""
echo "--- Step 5: Conda environment ---"

# Check conda is available
if ! command -v conda &>/dev/null; then
    fail "conda not found. Install Miniconda first:"
    echo "  https://docs.conda.io/en/latest/miniconda.html"
    exit 1
fi

# Initialize conda for this shell
eval "$(conda shell.bash hook)"

if conda env list 2>/dev/null | grep -q "$CONDA_ENV_NAME"; then
    ok "conda env '$CONDA_ENV_NAME' already exists"
else
    echo "Creating conda env '$CONDA_ENV_NAME' with Python 3.11..."
    conda create -y -n "$CONDA_ENV_NAME" python=3.11
    ok "conda env '$CONDA_ENV_NAME' created"
fi

conda activate "$CONDA_ENV_NAME"

# ---------- Step 6: IsaacLab ----------
echo ""
echo "--- Step 6: IsaacLab ---"

if [[ -d "$ISAACLAB_DIR" ]]; then
    ok "IsaacLab found at $ISAACLAB_DIR"
else
    echo "Cloning IsaacLab v2.3.2..."
    git clone --branch v2.3.2 https://github.com/isaac-sim/IsaacLab.git "$ISAACLAB_DIR"
    ok "IsaacLab cloned"
fi

# Check if Isaac Sim is available
if [[ ! -d "$ISAACSIM_DIR" ]]; then
    warn "Isaac Sim not found at $ISAACSIM_DIR"
    echo ""
    echo "  *** MANUAL STEP: Download Isaac Sim 5.1.0 ***"
    echo "  1. Go to https://developer.nvidia.com/isaac-sim"
    echo "  2. Download isaac-sim-standalone-5.1.0-linux-x86_64"
    echo "  3. Extract to: $ISAACSIM_DIR"
    echo "  4. Re-run this script to continue setup"
    echo ""
fi

# Link Isaac Sim into IsaacLab if not linked
if [[ -d "$ISAACSIM_DIR" && ! -L "$ISAACLAB_DIR/_isaac_sim" ]]; then
    ln -sf "$ISAACSIM_DIR" "$ISAACLAB_DIR/_isaac_sim"
    ok "Linked Isaac Sim into IsaacLab"
fi

# Install IsaacLab if not already installed
if python -c "import isaaclab" &>/dev/null; then
    ok "IsaacLab already installed in $CONDA_ENV_NAME"
else
    if [[ -d "$ISAACSIM_DIR" ]]; then
        echo "Installing IsaacLab (this takes a while)..."
        cd "$ISAACLAB_DIR"
        bash isaaclab.sh -i
        cd "$DIAS_DIR"
        ok "IsaacLab installed"
    else
        warn "Skipping IsaacLab install (Isaac Sim not available)"
    fi
fi

# ---------- Step 7: Install unitree_rl_lab ----------
echo ""
echo "--- Step 7: Install unitree_rl_lab ---"

if python -c "import unitree_rl_lab" &>/dev/null; then
    ok "unitree_rl_lab already installed in $CONDA_ENV_NAME"
else
    cd "$DIAS_DIR/unitree_rl_lab"
    bash unitree_rl_lab.sh -i
    cd "$DIAS_DIR"
    ok "unitree_rl_lab installed"
fi

# ---------- Step 8: Extra pip packages ----------
echo ""
echo "--- Step 8: Extra pip packages ---"

pip install mujoco noise opencv-python
ok "Extra pip packages installed"

# ---------- Step 9: MuJoCo pip in base env ----------
echo ""
echo "--- Step 9: MuJoCo in base conda env ---"

conda deactivate
pip install mujoco
ok "mujoco installed in base env (for terrain tools)"

# ---------- Done ----------
echo ""
echo "=========================================="
echo " Setup complete!"
echo "=========================================="
echo ""
echo "Remaining manual steps:"
echo ""
if [[ ! -d "$ISAACSIM_DIR" ]]; then
    echo "  1. Download Isaac Sim 5.1.0 from https://developer.nvidia.com/isaac-sim"
    echo "     Extract to: $ISAACSIM_DIR"
    echo ""
fi
echo "  - Go2 USD asset: place in ~/Downloads/Go2/"
echo "    (needed for Isaac Sim visualization)"
echo ""
echo "Quick start:"
echo "  # MuJoCo simulation"
echo "  cd $DIAS_DIR/unitree_mujoco/simulate/build"
echo "  ./unitree_mujoco"
echo ""
echo "  # RL training (requires Isaac Sim)"
echo "  conda activate $CONDA_ENV_NAME"
echo "  cd $DIAS_DIR/unitree_rl_lab"
echo "  python scripts/train.py --task Go2-v0 --num_envs 4096"
echo ""
echo "  # Verify installation"
echo "  bash $DIAS_DIR/setup.sh --check"
