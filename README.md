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
- 一套可 headless 运行的最小自动化测试 / A small headless regression test suite

## 目录结构 / Structure

- `project.godot`: Godot 项目入口 / Project entry
- `assets/`: 静态资源与预览图 / Static assets and preview media
- `data/levels/`: 地图 JSON 数据 / Level JSON data
- `data/weapons/`: 武器资源定义 / Weapon resource definitions
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
| `GrayboxLevelTestRunner` | Level assembly, collision integrity |
| `HitFeedbackLayerTestRunner` | HUD layer behavior, hit marker |
| `MainStateFlowTestRunner` | Main menu / gameplay state transitions |

## 当前控制 / Current Controls

- `WASD`: 移动 / Move
- `Shift`: 冲刺 / Sprint
- `Space`: 跳跃 / Jump
- `鼠标左键`: 开火 / Fire
- `R`: 换弹 / Reload
- `1 / 2`: 切枪 / Switch weapons
- `Esc / P`: 菜单或继续 / Pause or resume
- `F`: 全屏切换 / Toggle fullscreen
- `F3`: 显示或隐藏调试面板 / Toggle the debug panel

## Engineering Focus

```
Prototype stage — the professional value is in the structure, not the content volume.
```

- **Semantic graybox level loading**: JSON-driven level data → Godot scene assembly
- **Player collision & movement calibration**: First-pass physics tuning for FPS feel
- **Weapon state boundaries**: Magazine, fire mode, recoil pattern, reload state machine
- **Main menu / gameplay state flow**: State transitions, HUD layer management
- **Headless regression tests**: 5 test suites running via Godot `--headless` — loader, weapon, level, hit-feedback, main state flow

### What is not yet covered

Stair and ramp traversal, peek rhythm, and sustained recoil feel still require editor-side tuning and human playtesting.

## Roadmap

- [ ] stair and ramp traversal tuning
- [ ] sustained recoil feel playtest
- [ ] peek rhythm and movement polish
- [ ] weapon feedback and audio
- [ ] basic level demo video


## License

MIT License — see [LICENSE](LICENSE) file.
