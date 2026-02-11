# Go2 Stable Locomotion — Training Brief for Claude

## Problem

We have a Unitree Go2 robot dog for a RoboCup Rescue competition. Our previous RL policy (model_16500, trained in IsaacLab + rsl_rl) failed catastrophically in real-world and MuJoCo sim testing:

- **Epileptic jerking** — violent, rapid joint oscillations during any non-trivial movement
- **Cannot recover** from perturbations — spirals into chaotic flailing
- **Root cause**: the training over-rewarded speed (velocity tracking weight=2.0) and extreme foot clearance (20cm target), while barely penalizing jerkiness (action_rate=-0.05). The policy learned that violent aggressive movements beat obstacles faster.

## Goal

Train a **goal-directed locomotion policy** where the robot learns to traverse from a designated start point (A) to a target destination (B) with **absolute stability as the sole priority**. There are **zero rewards for speed** — the robot is incentivized purely by spatial progress toward the goal, not by how fast it gets there.

The robot must:
1. **Navigate from point A to point B** — forward progress toward a goal position is the ONLY positive incentive
2. Walk with **zero speed reward** — no velocity tracking whatsoever; the policy discovers its own minimal-energy gait speed
3. Traverse ramps and low obstacles (max 25cm height) without falling
4. Move at the **lowest possible speed** — velocity hard-capped at 0.0–0.1 m/s (near-stationary crawl)
5. Look calm and controlled at all times — like a careful cat, not an epileptic dog
6. Self-regulate speed: the only reason to move at all is the forward-progress reward, which is dominated by stability penalties; the optimal policy is the slowest stable gait that still makes forward progress

The robot does NOT need to:
- Go fast — speed is **never rewarded**, only penalized (via joint vel, energy, action rate)
- Track a commanded velocity — there is no velocity tracking reward
- Climb extreme terrain (max 25cm)
- Handle violent perturbations
- Optimize for any metric other than "reach the goal without falling or jerking"

### Why Zero Speed Reward?
Velocity tracking rewards (even at low weights) create an implicit incentive to move aggressively. The policy learns that matching the commanded velocity is worth the smoothness penalties. By removing velocity tracking entirely and replacing it with a position-based forward-progress reward, the policy has **no incentive to move fast** — it only needs to make incremental spatial progress. Combined with dominant stability penalties, this produces a self-regulating ultra-slow crawl.

## Current Setup

### Training Stack
- **Framework**: IsaacLab (Isaac Sim) + rsl_rl (PPO)
- **Sim-to-sim**: MuJoCo 3.4.0 with standalone ONNX runner
- **Real robot**: Unitree Go2 via unitree_sdk2
- **Control frequency**: 50 Hz (decimation=4, physics dt=0.005s)

### Policy Architecture
- MLP: [512, 256, 128] with ELU activation
- Input: 232 dims (3 ang_vel + 3 gravity + 3 vel_cmd + 12 joint_pos + 12 joint_vel + 12 last_action + 187 height_scan)
- Output: 12 joint positions (offset from default stance)
- Height scan: 187 points, 1.6m x 1.0m grid, 0.1m resolution

### Base Model
- `model_3400.pt` from early rough terrain training
- Can already walk — learned on flat + easy terrain (curriculum level ~5-8/20)
- Has NOT learned jerky behaviors yet — still at mild difficulty
- 232-dim observations (compatible with height scan)

### Competition Maps (OBJ files for Phase 2)
- `Maps/3D/K_Rails_Map.obj` — diagonal barriers (scale=1.0, meters)
- `Maps/3D/k_ramps.obj` — tilted ramp platforms (scale=0.01, cm units)
- Both maps: ~4.88m x 2.53m, Y=long axis, rotate_90=True for X-forward

## Training Configuration (CURRENT — velocity_stable_env_cfg.py)

### Task: `Unitree-Go2-Velocity-Stable`

### Terrain (ramps + slopes, max 25cm)
| Type | Proportion | Detail |
|------|-----------|--------|
| Flat | 25% | Stability baseline |
| Random rough | 15% | Bumps up to 6cm |
| Ascending ramps | 25% | Slopes up to 17° (~25cm rise) |
| Descending ramps | 15% | Must handle going down |
| Low steps | 10% | Grid boxes up to 25cm |
| Low rails | 10% | Barriers 5-15cm |

Curriculum enabled: starts flat, progresses to ramps.

### Speed (ABSOLUTE MINIMUM — zero speed reward)
- Forward: **0.0–0.1 m/s** (near-stationary crawl — as slow as physically stable)
- Lateral: **±0.0 m/s** (zero lateral movement)
- Yaw: **±0.2 rad/s** (minimal turning)
- **15% standing environments** (practice not falling while still)
- **No velocity tracking reward** — speed is NEVER rewarded. The only incentive to move is forward-progress (position-based). The policy will converge to the minimum-energy gait speed where the tiny progress reward outweighs movement penalties.
- Velocity commands remain in the observation space (3 dims) for deployment compatibility (teleop mode), but the training reward ignores them entirely.

### Rewards — ZERO Speed Reward, Stability DOMINATES

**Positive (goal-directed — position-based, NOT speed-based):**
| Reward | Weight | Purpose |
|--------|--------|---------|
| ~~track_lin_vel_xy~~ | ~~REMOVED~~ | ~~Was 0.3 — DELETED: no velocity tracking~~ |
| ~~track_ang_vel_z~~ | ~~REMOVED~~ | ~~Was 0.3 — DELETED: no velocity tracking~~ |
| forward_progress | **0.3** | **NEW**: reward for +X world-frame displacement per step (position-based, NOT velocity) |
| feet_air_time | **0.1** | Minimal gait encouragement |
| foot_clearance | **0.2** | 8cm target — conservative |

**Negative (DOMINANT — define the policy):**
| Penalty | Weight | Purpose |
|---------|--------|---------|
| base_lin_vel_z | **-2.0** | HARD: no vertical bouncing |
| flat_orientation | **-2.0** | HARD: stay flat/upright |
| joint_pos | **-0.7** | Stay near default stance |
| action_rate | **-0.5** | No frame-to-frame jumps |
| action_smoothness | **-0.5** | No oscillatory jitter (2nd order) |
| air_time_variance | **-0.5** | Symmetric gait |
| ang_vel_xy | **-0.3** | No roll/pitch oscillation |
| feet_slide | **-0.25** | No sliding |
| feet_stumble | **-0.3** | Don't hit obstacles |
| undesired_contacts | **-1.0** | No body dragging |
| joint_vel | **-0.002** | Calm joints |
| joint_acc | **-2e-6** | No acceleration spikes |
| joint_torques | **-2e-4** | Low torque |
| energy | **-2e-5** | Energy efficient |
| dof_pos_limits | **-10.0** | Stay in joint limits |

**Total negative budget ~-8.3 vs positive ~0.6**: the robot MUST be perfectly smooth to get any net positive reward. The only way to earn reward is to make slow, incremental forward progress without triggering any instability penalty.

**Key change from previous config**: velocity tracking rewards (`track_lin_vel_xy`, `track_ang_vel_z`) have been **completely removed**. The sole positive locomotion incentive is `forward_progress`, which rewards spatial displacement toward the goal — not speed. This means the policy has zero incentive to move fast; it will converge to the slowest gait that still yields net-positive reward after stability penalties.

### Action Settings
- `action_scale`: **0.20** (reduced from 0.25)
- `clip`: (-100, 100)

### PPO Settings (StablePPORunnerCfg)
- `init_noise_std`: **0.5** (was 1.0 — calmer exploration)
- `learning_rate`: **5e-4** (was 1e-3 — slower, more stable updates)
- `entropy_coef`: **0.008** (was 0.01 — less random)
- Network: [512, 256, 128] (unchanged)
- `max_iterations`: 50000

### Termination
- `bad_orientation`: 1.0 rad (~57°) — not too strict for model_3400
- `base_contact`: 5.0N
- Episode length: 20s

## Goal-Directed Traversal (Point A to Point B)

### Concept
Instead of rewarding the robot for matching a commanded velocity, we reward it for making **spatial progress** from a start position (A) toward a goal position (B). This is fundamentally different from velocity tracking:

| Approach | Reward Signal | Speed Incentive | Failure Mode |
|----------|--------------|-----------------|--------------|
| Velocity tracking | "Move at 0.2 m/s" | Direct — faster = more reward | Jerky aggressive movement |
| **Forward progress** | "Get closer to goal" | **None** — only position matters | None — self-regulating |

### Implementation: `forward_progress` Reward Function
A new custom reward function in `mdp/rewards.py`:

```python
def forward_progress(env: ManagerBasedRLEnv) -> torch.Tensor:
    """Reward for world-frame forward (X-axis) displacement per timestep.

    Position-based, NOT velocity-based. Rewards spatial progress toward goal,
    not speed. The robot is incentivized to move forward, but has zero reason
    to move fast — stability penalties dominate.
    """
    asset = env.scene["robot"]
    # World-frame X velocity (forward) * dt = displacement per step
    # Clamp to prevent reward from negative (backward) movement
    forward_vel = asset.data.root_lin_vel_w[:, 0]  # world X velocity
    return torch.clamp(forward_vel * env.step_dt, min=0.0)
```

**Why this works:**
- At 0.05 m/s crawl speed with dt=0.02s: `0.05 * 0.02 = 0.001` displacement per step
- With weight=0.3: `0.3 * 0.001 = 0.0003` reward per step
- Over a 20s episode (1000 steps): `~0.3` total positive reward
- Stability penalties per step are ~0.008 → the robot MUST be nearly perfect to break even
- The policy converges to the slowest gait where progress reward > movement penalties

### Observation Space (unchanged — 232 dims)
The velocity command dims (3) remain in observations for deployment compatibility. During training, commands are sampled in the range [0.0, 0.1] m/s but are **not rewarded**. The policy learns to ignore them in favor of the forward-progress signal.

In Phase 2 (competition maps), we may optionally replace velocity commands with a 2D goal-relative vector (direction + distance to goal) for true waypoint navigation. This would change obs to 231 dims (remove 3 vel_cmd, add 2 goal_vec). For now, the 232-dim space is preserved.

### Files Requiring Modification

| File | Change | Scope |
|------|--------|-------|
| `mdp/rewards.py` | Add `forward_progress()` function | New function (~15 lines) |
| `velocity_stable_env_cfg.py` | Remove `track_lin_vel_xy` and `track_ang_vel_z` rewards; add `forward_progress` reward; reduce velocity command ranges to 0.0–0.1 m/s | Reward + command config |
| `mdp/__init__.py` | Export `forward_progress` if not auto-discovered | One-line import |
| `scripts/train_stable.py` | Update comments to reflect zero-speed-reward philosophy | Comments only |

## Training Plan

### Phase 1: Goal-directed stable walking (CURRENT)
- Task: `Unitree-Go2-Velocity-Stable`
- Resume from: `model_3400.pt`
- Terrain: procedural ramps + flat (with curriculum)
- Rewards: **forward_progress ONLY** — zero velocity tracking
- Speed: hard-capped at 0.0–0.1 m/s; self-regulating via penalty dominance
- Goal: smooth traversal from spawn to terrain end, full 20s episodes, no jerking
- Success metric: robot completes episodes without termination; net positive reward; visually smooth gait at ultra-low speed
- Expected: ~5000–15000 iterations

### Phase 2: Competition maps (AFTER Phase 1 succeeds)
- Task: `Unitree-Go2-Custom-Map`
- Resume from: best Phase 1 checkpoint
- Terrain: actual competition OBJ maps (K-Rails + Ramps)
- **Keep ALL smoothness penalties and zero-speed-reward philosophy unchanged**
- Optionally add goal-relative observation (2D vector to exit point) for navigation
- Goal: traverse specific competition obstacles smoothly from entrance to exit

### Phase 3: Export and deploy
- Export: `python scripts/export_onnx.py <model.pt> exported/policy_stable.onnx`
- Test in MuJoCo: `run_policy.py` with joystick
- Verify: smooth movement, no jitter, traverses maps at ultra-low speed
- Real robot: deploy via unitree_sdk2 with identical observation pipeline

## Key Files

```
unitree_rl_lab/source/unitree_rl_lab/unitree_rl_lab/tasks/locomotion/
├── robots/go2/
│   ├── __init__.py                    # Task registration (4 tasks)
│   ├── velocity_env_cfg.py            # Flat terrain (45-dim, no height scan)
│   ├── velocity_rough_env_cfg.py      # Rough terrain (232-dim, aggressive)
│   ├── velocity_stable_env_cfg.py     # STABLE training (232-dim, THIS ONE)
│   └── custom_map_env_cfg.py          # Competition maps (for Phase 2)
├── mdp/
│   ├── rewards.py                     # Custom rewards incl. action_smoothness_l2
│   ├── custom_terrains.py             # OBJ mesh terrain loader
│   └── __init__.py
└── agents/
    └── rsl_rl_ppo_cfg.py              # PPO configs (BasePPORunnerCfg + StablePPORunnerCfg)

scripts/
├── train_stable.py                    # Phase 1 launcher (resumes from model_3400)
├── train_smooth.py                    # Old launcher (deprecated)
├── export_onnx.py                     # ONNX export without IsaacLab
├── tensorboard.sh                     # TensorBoard viewer
└── TRAINING_BRIEF.md                  # THIS FILE

exported/
├── run_policy.py                      # MuJoCo sim-to-sim with joystick
└── policy_*.onnx                      # Exported models
```

## Launch Command

```bash
conda activate isaaclab_go2
python ~/robotics/projects/Dias/scripts/train_stable.py
```

## Critical Lessons Learned

1. **action_rate penalty >= -0.3 is mandatory** — weaker allows jerky exploitation
2. **action_smoothness_l2** (penalizes `a[t]-2a[t-1]+a[t-2]`) kills oscillation
3. **Do NOT change action_scale AND termination limits AND rewards all at once** — the model can't adapt. Change one axis at a time.
4. **velocity tracking at ANY weight is dangerous** — even at 0.3, it creates an implicit speed incentive that competes with stability. Remove it entirely and use position-based progress reward instead.
5. **foot_clearance 20cm is too aggressive** — 8cm is plenty for 25cm obstacles
6. **Don't train from scratch when you have a walking base model** — resume from model_3400 (early rough terrain, knows how to walk, not yet jerky)
7. **Flat terrain models (45-dim) are incompatible with height scan models (232-dim)** — cannot mix
8. **No pre-trained Go2 rough terrain models exist publicly** — must train your own
9. **Speed kills stability** — hard-cap velocity to 0.0-0.1 m/s, not 0.5 m/s. Better yet, don't reward speed at all.
10. **sim2sim**: Use `data.sensordata` in MuJoCo, NOT `data.qpos`/`data.qvel`
11. **Height scan grid**: IsaacLab "xy" = Y outer loop, X inner loop
12. **Position-based > velocity-based rewards** — `forward_progress` (displacement per step) is self-regulating: the robot moves only as fast as the penalty budget allows. Velocity tracking rewards create a floor on speed that conflicts with stability.
13. **Let the policy find its own speed** — with zero speed reward and dominant stability penalties, the optimal gait speed emerges naturally as the minimum-energy crawl. Don't prescribe speed; let the reward structure produce it.
