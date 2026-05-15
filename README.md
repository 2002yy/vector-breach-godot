# Vector Breach Godot

中文优先说明。This repository contains the standalone Godot migration prototype for `Vector Breach`.

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

运行全部测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

如果 Godot 不在 `PATH`：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -GodotExe "C:\Program Files\Godot\Godot.exe"
```

当前会依次运行这些测试场景：

- `LevelDataLoaderTestRunner`
- `WeaponSystemTestRunner`
- `GrayboxLevelTestRunner`
- `HitFeedbackLayerTestRunner`
- `MainStateFlowTestRunner`

These suites cover loader validation, weapon-state boundaries, graybox level integration, hit-feedback UI behavior, and main menu/state flow.

## 当前控制 / Current Controls

- `WASD`: 移动 / Move
- `Shift`: 冲刺 / Sprint
- `Space`: 跳跃 / Jump
- `鼠标左键`: 开火 / Fire
- `R`: 换弹 / Reload
- `1 / 2`: 切枪 / Switch weapons
- `P`: 菜单或继续 / Pause or resume
- `F`: 全屏切换 / Toggle fullscreen
- `Esc`: 释放鼠标或退出全屏 / Release mouse or exit fullscreen

## 当前定位 / Project Status

这是一个偏原型验证阶段的 Godot 迁移仓库，重点是：

- 把旧实现里的关卡语义、移动手感和枪械节奏迁移到 Godot
- 保持结构清晰，方便继续扩展
- 用最小但持续可跑的测试守住核心状态流

This is a prototype-focused migration repo. The priorities are:

- Preserving level semantics, movement feel, and weapon rhythm in Godot
- Keeping the project structure clean and easy to extend
- Using small but repeatable tests to protect core gameplay state flows

还没有覆盖所有“手感”验证。像楼梯与坡道 traversal、peek 节奏、压枪体感，仍然需要编辑器内和真人手测补充验证。

Not every feel-related case is covered yet. Stairs, ramps, peek rhythm, and recoil feel still need editor-side and human playtesting.
