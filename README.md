# Vector Breach Godot

<p>
  <img src="https://img.shields.io/badge/Status-Prototype%20%2F%20Experimental-yellow" alt="Prototype">
  <img src="https://img.shields.io/badge/Godot-4.6-blue" alt="Godot 4.6">
  <img src="https://img.shields.io/badge/tests-5%20suites-green" alt="5 test suites">
</p>

中文优先说明。This repository contains the standalone Godot migration prototype for `Vector Breach`.
> Portfolio note: this repository is a secondary Godot engineering prototype.
> For the main polished Godot project, see [BallWar](https://github.com/2002yy/BallWar).

> 作品集说明：本仓库是 Godot 工程原型辅助项目，重点展示 FPS 状态流、灰盒地图和测试意识。主展示项目请看 [BallWar](https://github.com/2002yy/BallWar)。


## 项目简介 / About

这是 `Vector Breach` 的独立 Godot 迁移仓库，当前重点是把旧实现里的关卡语义、移动手感和枪械节奏，重建成更适合持续迭代的 Godot 结构。

This is the standalone Godot migration repo for `Vector Breach`. The current focus is rebuilding level semantics, movement feel, and weapon rhythm from the older implementation into a cleaner Godot structure that is easier to extend.

当前仓库仍处于原型验证阶段，重点不是内容量，而是先把 FPS 核心状态流、地图语义和可学习枪感做扎实，并用小型自动化测试守住迭代稳定性。

This repo is still in a prototype-validation phase. The goal is not content volume yet, but a solid FPS core: state flow, level semantics, and learnable weapon feel, backed by small automated tests for iteration safety.

## 当前内容 / Current Scope

- Godot 4.6 项目骨架 / Godot 4.6 project scaffold
- 语义灰盒地图加载与构建 / Semantic graybox level loading and building
- 第一版玩家移动与碰撞校准 / First-pass player movement and collision tuning
- 双武器骨架 / Two-weapon scaffold
- 步枪：可学习的固定后坐与弹道节奏 / Rifle with learnable recoil and shot rhythm
- 手枪：半自动、副武器槽位、`1 / 2` 切枪 / Pistol with semi-auto fire and `1 / 2` weapon switching
- HUD、命中反馈、调试线与目标假人 / HUD, hit feedback, debug lines, and target dummy
- 左上角圆形战术雷达：玩家居中、随朝向旋转，所有地图统一显示半径 24 m 的局部边界、几何与目标方向 / Circular heading-up radar centered on the player, with a shared 24 m local range for nearby bounds, geometry, and objective directions on every map
- 经典 CS 风格普通跳、蹲伏胶囊与蹲跳；无二段跳、无自动翻越 / Classic CS-style jump, crouch hull, and crouch-jump; no double jump or auto-mantle
- 默认奔跑、Shift 静步、蹲伏慢行，搭配材质脚步、落地声与分层精度规则 / Default run, Shift quiet-walk, crouch movement, material footsteps, landing audio, and stance/speed accuracy bands
- 30 发完整步枪喷射轨迹，不在中途锁死 / Full 30-round rifle spray path without mid-magazine clamping
- 竞技 HUD：比分、时间、存活数、护甲、金钱、Tab 计分板、击杀信息与训练结算 / Competitive HUD with score, time, alive counts, armor, money, Tab scoreboard, kill feed, and training summary
- 头/躯干/腿命中倍率、护甲减伤、距离衰减、单层穿透、受击减速与玩家死亡 / Head/torso/leg hit groups, armor mitigation, range falloff, one-surface penetration, tagging slowdown, and player death
- T/CT 回合状态、冻结购买、胜负经济、C4 安装/拆除/爆炸及自动下一回合 / T/CT round states, freeze-time buying, win/loss economy, C4 plant/defuse/explosion, and automatic next rounds
- 中文游戏设置：鼠标灵敏度、主音量、准星间距/长度与动态准星 / Chinese settings for mouse sensitivity, master volume, crosshair gap/size, and dynamic crosshair
- 独立头盔、五类命中部位、材质/厚度穿透，以及持续 C4 安装拆除 / Separate helmet, five hit groups, material/thickness penetration, and held C4 interactions
- 刀、武器掉落拾取、HE/闪光/烟雾投掷物 / Knife, weapon drops/pickups, and HE/flash/smoke grenades
- 可调 16–40 m 的局部雷达与旋转开关 / Configurable 16–40 m local radar and rotation toggle
- 一套可 headless 运行的最小自动化测试 / A small headless regression test suite

## 目录结构 / Structure

- `project.godot`: Godot 项目入口 / Project entry
- `assets/`: 静态资源与预览图 / Static assets and preview media
- `data/levels/`: 地图 JSON 数据 / Level JSON data
- `data/weapons/`: 武器资源定义 / Weapon resource definitions
- `docs/FOUNDRY_DEPOT_DESIGN.md`: Foundry Depot 尺度、路线与验证记录 / Map scale, route, and validation record
- `scenes/`: 场景 / Scenes
- `scripts/`: 运行时代码与测试代码 / Runtime and test scripts
- `tools/run_godot_tests.ps1`: 一键运行全部 Godot 测试 / One-command Godot test runner

## 环境要求 / Requirements

- Godot `4.6.x`
- Windows PowerShell

如果 `Godot.exe` 不在系统 `PATH` 中，可以：

- 运行测试时传 `-GodotExe <你的 Godot.exe 路径>`
- 或设置环境变量 `GODOT_EXE`

If `Godot.exe` is not in your system `PATH`, either pass `-GodotExe <path>` or set the `GODOT_EXE` environment variable.

## 本地运行 / Run Locally

在 Godot 编辑器中直接打开本目录，或使用命令行：

```powershell
Godot.exe --path C:\path\to\godot
```

主场景是：

```text
res://scenes/Main.tscn
```

Open this folder directly in the Godot editor, or launch it from the command line with the command above.

## 测试 / Tests

Run all 5 headless test suites:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

If Godot is not in `PATH`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -GodotExe "C:\Program Files\Godot\Godot.exe"
```

| Test Runner | Coverage |
|---|---|
| `LevelDataLoaderTestRunner` | JSON level data validation, loader edge cases |
| `WeaponSystemTestRunner` | Weapon state boundaries, ammo, recoil |
| `GrayboxLevelTestRunner` | Level assembly, CS-scale metrics, stairs, route/spawn clearance |
| `HitFeedbackLayerTestRunner` | HUD layer behavior, hit marker |
| `MainStateFlowTestRunner` | Main menu / gameplay state transitions |

## 当前控制 / Current Controls

- `WASD`: 移动 / Move
- `Shift`: 静步 / Quiet walk
- `Space`: 跳跃 / Jump
- `Ctrl / C`: 蹲伏；蹲伏状态起跳为经典蹲跳 / Crouch; jump while crouched for a classic crouch-jump
- `Tab`: 按住显示计分板 / Hold scoreboard
- `B`: 冻结期打开购买菜单，`1–8` 购买武器、护甲、拆弹钳与投掷物 / Open the freeze-time buy menu; use `1–8` for weapons, armor, kit, and grenades
- `E`: 持续安装/拆除 C4，或拾取附近武器 / Hold to plant/defuse C4, or pick up a nearby weapon
- `鼠标左键`: 开火 / Fire
- `R`: 换弹 / Reload
- `1 / 2 / 3 / 4`: 主武器、副武器、刀、投掷物 / Primary, secondary, knife, and grenades
- `G`: 丢弃当前枪械；持刀/投掷物时丢弃 C4 / Drop the current firearm; while holding knife/grenade, drop C4
- `Esc / P`: 菜单或继续 / Pause or resume
- `F`: 全屏切换 / Toggle fullscreen
- `F3`: 显示或隐藏调试面板 / Toggle the debug panel

## Engineering Focus

```
Prototype stage — the professional value is in the structure, not the content volume.
```

- **Semantic graybox level loading**: JSON-driven level data → Godot scene assembly
- **CS-scale multilevel combat space**: 96 × 84 m Foundry Depot with three ground routes and a 4 m upper loop
- **Player collision & movement calibration**: First-pass physics tuning for FPS feel
- **Weapon state boundaries**: Magazine, fire mode, recoil pattern, reload state machine
- **Main menu / gameplay state flow**: State transitions, HUD layer management
- **Headless regression tests**: 5 test suites running via Godot `--headless` — loader, weapon, level, hit-feedback, main state flow

### Foundry Depot design record

The authoritative dimensions, route roles, vertical layout, asset-generation chain, and automated geometry invariants are recorded in [`docs/FOUNDRY_DEPOT_DESIGN.md`](docs/FOUNDRY_DEPOT_DESIGN.md).

Automated checks cover stair risers, target-edge alignment, upper headroom, route/spawn clearance, counter-strafe response, and combat-audio event wiring. The July 2026 closure pass also captured a first-person Foundry route run to verify HUD weight, weapon feedback, sustained recoil presentation, and representative peek sightlines.

## Roadmap

- [x] CS-scale multilevel Foundry Depot blockout and geometry boundaries
- [x] stair traversal feel playtest and movement polish
- [x] sustained recoil feel playtest
- [x] peek rhythm and movement polish
- [x] weapon feedback and audio
- [x] basic level demo video

### Closure evidence

- Stair/peek polish: grounded acceleration now distinguishes normal movement, release braking, and higher-authority counter-strafing; air acceleration remains intentionally bounded. Camera bob and a short landing impulse make step transitions readable without changing collision authority.
- Recoil/feedback: the existing learnable rifle pattern is now paired with view-model kick, synthesized rifle/pistol reports, a separate hit-confirmation cue, and reload/equip mechanical cues.
- Automated gate: `MainStateFlowTestRunner` covers counter-strafe/air-control boundaries and verifies shot, hit, reload, and weapon-switch audio events.
- Demo: [`assets/demo/vector-breach-foundry-demo.mp4`](assets/demo/vector-breach-foundry-demo.mp4) is a 1280x720, 30 FPS first-person route capture with HUD, weapon animation, repeated fire, and captured game audio. The matching poster is [`assets/demo/vector-breach-foundry-demo.png`](assets/demo/vector-breach-foundry-demo.png).
- Rebuild the demo with `powershell -ExecutionPolicy Bypass -File .\tools\capture_level_demo.ps1`.


## License

MIT License — see [LICENSE](LICENSE) file.
